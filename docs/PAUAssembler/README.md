# PAU Assembler

`PAUAssembler` deploys and fully wires **one or more PAU stacks that share a single `ALMProxy`** in one transaction, plus any number of `AdministeredAgent` allocators, transfers administrative rights to caller-supplied admins, and renounces every role it held during setup. After the call returns the assembler holds **no** privileged role on any deployed contract.

It generalises [`DefaultPAUAssembler`](../DefaultPAUAssembler/README.md) (one proxy / one controller) to the multi-stack case: a shared proxy fronts several Controllers, each bound to its own AccessControls/RateLimits pair, cross-referenced by caller-supplied `id`s.

Implementation version: `1.0.0` (`VERSION`).

## Dependencies

The assembler is constructed with two underlying factories and calls into them at deploy time:

| Constructor argument        | Type                            | Role                                                                           |
| --------------------------- | ------------------------------- | ------------------------------------------------------------------------------ |
| `pauFactory_`               | `IPAUFactoryLike`               | Deploys the shared ALMProxy and each AccessControls / RateLimits / Controller. |
| `administeredAgentFactory_` | `IAdministeredAgentFactoryLike` | Deploys each `AdministeredAgent` allocator.                                    |

Both must be non-zero (`ZeroPAUFactory` / `ZeroAdministeredAgentFactory`). The PAU factory points its deployed Controllers at a shared **Beacon**; integrations must be registered on that Beacon _before_ they can be passed to `deploy` (see [Preconditions](#preconditions--behavior)).

> **Auditor note — dependency status.** The assembler has **no compile-time dependency** on the underlying contracts: `src/` interacts with them solely through the inline `*Like` adapter interfaces, so the production bytecode imports neither repository. Integration tests fork the target chain and call canonical on-chain `PAUFactory` and `AdministeredAgentFactory` deployments, which avoids pulling those repositories in as submodules.

## Entry point

```solidity
function deploy(
    ControllerConfig[]        memory controllerConfigs,
    RateLimitsConfig[]        memory rateLimitsConfigs,
    AccessControlsConfig[]    memory accessControlsConfigs,
    AdministeredAgentConfig[] memory allocatorAgentConfigs,
    ALMProxyConfig            memory almProxyConfig
)
    external
    returns (
        address          proxy,
        address[] memory controllers,
        address[] memory accessControls,
        address[] memory rateLimits,
        address[] memory allocatorAgents
    );
```

There is a single deploy path. It always deploys exactly **one** shared `ALMProxy` (via `deployALMProxy`) and grants **every** Controller `CONTROLLER` on it — the role that gates `doCall`.

## Cross-referencing by `id`

AccessControls and RateLimits are addressable within a single `deploy` call by a caller-supplied `bytes32 id`:

- Each `AccessControlsConfig.id` / `RateLimitsConfig.id` must be **unique within its own set** (`DuplicateAccessControlsId` / `DuplicateRateLimitsId`).
- A `ControllerConfig` names the `accessControlsId` and `rateLimitsId` it binds to; an `AdministeredAgentConfig` names the `accessControlsId` it is granted the allocator role on. Unknown ids revert (`InvalidAccessControlsId` / `InvalidRateLimitsId`).
- The two id-spaces are **independent** — the same `bytes32` value may be used as both an AccessControls id and a RateLimits id without collision (they are namespaced internally).

`id`s are resolved through **transient storage** (`tload`/`tstore`) scoped to the call. They have no meaning outside the transaction: they are not stored, not emitted as a mapping, and a deployed component is referenced only by the address returned in the result arrays / `Deployment` event.

> **Reviewer note — transient cleanup is load-bearing.** The final step zeroes every id slot it set. Without this, a second `deploy` **in the same transaction** would observe stale slots and falsely revert with `Duplicate…Id`. Keys are recomputed from the configs (rather than tracked in a memory array) to stay within the stack limit, since the contract is compiled without via-IR. A reverting `deploy` needs no cleanup — transient storage is discarded when the transaction unwinds.

## Runtime model

Identical in spirit to `DefaultPAUAssembler`, applied per stack. The assembler separates **who may administer a stack** from **who may drive allocator actions**:

| Layer           | Who                                            | Role on AccessControls               | How they act                                                                            |
| --------------- | ---------------------------------------------- | ------------------------------------ | --------------------------------------------------------------------------------------- |
| Stack admin     | addresses in each component's `admins`         | `DEFAULT_ADMIN_ROLE` (per component) | govern AccessControls, the shared ALMProxy, RateLimits, and (indirectly) the Controller |
| Allocator agent | each deployed `AdministeredAgent` contract     | `ALLOCATOR_ROLE`                     | holds the on-chain allocator identity for its referenced AccessControls                 |
| Actor           | addresses in `allocatorAgentConfigs[i].actors` | none on the PAU stack                | call into a Controller (or other targets) via `AdministeredAgent.call` / `batchCall`    |

`ALLOCATOR_ROLE` is granted to the **agent contract address**, not to the actor EOAs. Actors operate the stack by routing calls through their agent; only addresses listed as `actors` on that agent may do so (`NotActor` otherwise).

Rate limits, proxy funding, and other runtime policy are **not** configured by the assembler — admins set those after deploy.

## Deploy flow

1. **Allocate return arrays** sized to each config array.
2. **Deploy the shared ALMProxy** (administered by the assembler initially) and grant `DEFAULT_ADMIN_ROLE` on it from `almProxyConfig.admins`.
3. **Deploy each AccessControls** — one per `accessControlsConfigs` entry (administered by the assembler initially), index it by `id` (duplicate-checked), and grant `DEFAULT_ADMIN_ROLE` from its `admins`.
4. **Deploy each RateLimits** — one per `rateLimitsConfigs` entry (administered by the assembler initially), index it by `id` (duplicate-checked), and grant `DEFAULT_ADMIN_ROLE` from its `admins`.
5. **Deploy each Controller** — resolve its referenced AccessControls and RateLimits by `id` (revert on unknown), deploy the Controller wired to that pair and the shared proxy, register integrations (`updateIntegrations`, **skipped** when empty), then grant the Controller `CONTROLLER` on the **shared proxy** and on **its** RateLimits.
6. **Deploy and configure each allocator agent** — deploy an `AdministeredAgent` (with the assembler as constructor admin), add `admins`, `actors`, `grantors`, `revokers` in order, grant it `ALLOCATOR_ROLE` on its referenced AccessControls (revert on unknown), then remove the assembler as an agent admin.
7. **Renounce** — the assembler revokes its own `DEFAULT_ADMIN_ROLE` on every AccessControls, every RateLimits, and the shared proxy.
8. **Clear transient storage** — zero every AccessControls/RateLimits id slot set in steps 3–4.

A `Deployment` event is emitted with every deployed address and the full configuration.

## Resulting permission layout

After a successful deploy:

| Contract               | Role                  | Holders                                            |
| ---------------------- | --------------------- | -------------------------------------------------- |
| **shared ALMProxy**    | `DEFAULT_ADMIN_ROLE`  | `almProxyConfig.admins`                            |
| **shared ALMProxy**    | `CONTROLLER`          | **every** deployed Controller                      |
| each AccessControls    | `DEFAULT_ADMIN_ROLE`  | that config's `admins`                             |
| each AccessControls    | `ALLOCATOR_ROLE`      | each agent whose `accessControlsId` references it  |
| each RateLimits        | `DEFAULT_ADMIN_ROLE`  | that config's `admins`                             |
| each RateLimits        | `CONTROLLER`          | each Controller whose `rateLimitsId` references it |
| each AdministeredAgent | admin                 | per-agent `allocatorAgentConfigs[i].admins`        |
| each AdministeredAgent | actor/grantor/revoker | per-agent `actors` / `grantors` / `revokers`       |
| **the assembler**      | —                     | **nothing** (all bootstrap roles renounced)        |

> **Note.** A Controller has no roles of its own — admin actions on it are authorized against `DEFAULT_ADMIN_ROLE` on its AccessControls. Holders of that AccessControls' admins therefore also effectively govern the Controller.

Post-deploy invariants checked by `PAUAssembler.t.sol`:

- The assembler holds `DEFAULT_ADMIN_ROLE` on the proxy, every AccessControls, and every RateLimits — **false**; and `CONTROLLER` on the proxy — **false**.
- The assembler is an admin on any deployed agent — **false** (removed during step 6).
- `DEFAULT_ADMIN_ROLE` and `ALLOCATOR_ROLE` member counts on each AccessControls equal exactly the configured counts (nothing stray lingers).
- Each Controller's `proxy`, `accessControls`, and `rateLimits` reference the contracts it was bound to; cross-stack RateLimits are **not** granted to the wrong Controller.
- A second `deploy` reusing the same `id`s in a later transaction succeeds (transient state cleared).

## Configuration reference

### `ALMProxyConfig`

| Field    | Meaning                                                                                                                                    |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `admins` | `DEFAULT_ADMIN_ROLE` holders on the shared ALMProxy. **Must be non-empty** (`NoDefaultAdmins`); every entry non-zero (`ZeroDefaultAdmin`). |

### `AccessControlsConfig[]` / `RateLimitsConfig[]`

One entry per AccessControls / RateLimits deployed.

| Field    | Meaning                                                                                                                                                                     |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`     | Call-scoped identifier used by `ControllerConfig` (and, for AccessControls, `AdministeredAgentConfig`) to reference this component. Unique within its set (`Duplicate…Id`). |
| `admins` | `DEFAULT_ADMIN_ROLE` holders on the component. **Must be non-empty** (`NoDefaultAdmins`); every entry non-zero (`ZeroDefaultAdmin`).                                        |

### `ControllerConfig[]`

One entry per Controller. Each Controller is wired to the shared proxy and the referenced AccessControls/RateLimits pair.

| Field              | Meaning                                                                                                    |
| ------------------ | ---------------------------------------------------------------------------------------------------------- |
| `accessControlsId` | `id` of the AccessControls to bind to (must exist — `InvalidAccessControlsId`).                            |
| `rateLimitsId`     | `id` of the RateLimits to bind to (must exist — `InvalidRateLimitsId`).                                    |
| `integrationIds`   | Passed to `Controller.updateIntegrations`; each id must be Beacon-registered. May be empty (call skipped). |

Multiple Controllers may reference the **same** AccessControls and/or RateLimits id.

### `AdministeredAgentConfig[]`

One entry per allocator agent. The array length determines how many `AdministeredAgent` contracts deploy; each receives `ALLOCATOR_ROLE` on its referenced AccessControls.

| Field              | Meaning                                                                                                |
| ------------------ | ------------------------------------------------------------------------------------------------------ |
| `accessControlsId` | `id` of the AccessControls to grant `ALLOCATOR_ROLE` on (must exist — `InvalidAccessControlsId`).      |
| `admins`           | Agent admins (must be non-empty per entry — `NoAgentAdmins`).                                          |
| `actors`           | May execute `call` / `batchCall` / `sendValue` on the agent.                                           |
| `grantors`         | May add actors on the agent (may be empty).                                                            |
| `revokers`         | May remove actors on the agent (may be empty). Agent-level revokers only — not ALMProxy freezer roles. |

## Preconditions & behavior

- **Each `admins` array must be non-empty.** The proxy, every AccessControls, every RateLimits, and each agent must have at least one admin (`NoDefaultAdmins` / `NoAgentAdmins`).
- **No zero admins** on the proxy / AccessControls / RateLimits (`ZeroDefaultAdmin`).
- **`id`s must be unique within their set** (`DuplicateAccessControlsId` / `DuplicateRateLimitsId`) and every referenced `id` must exist (`InvalidAccessControlsId` / `InvalidRateLimitsId`).
- **Integrations must be pre-registered on the Beacon.** Unknown ids revert. **Empty `integrationIds`** is supported — the `updateIntegrations` call is skipped (the Controller reverts on an empty array), so a Controller can be deployed bare and configured later by an admin.
- **Empty `grantors` / `revokers` / `actors`** arrays are supported on an agent (subject to the agent still having at least one admin).
- **Empty config arrays are supported** where they make sense — e.g. a deploy with only `almProxyConfig` produces a bare shared proxy with no stacks. A Controller or agent that references an `id` belonging to an empty set reverts with `Invalid…Id`.
- **Duplicate / overlapping entries behave differently per component.**
    - On the **AdministeredAgent**, re-adding an account reverts the whole deploy (`AccountAlreadyAdmin` / `AccountAlreadyActor` / `AccountAlreadyGrantor` / `AccountAlreadyRevoker`).
    - On **AccessControls / ALMProxy / RateLimits**, roles are granted through OpenZeppelin `grantRole`, which is **idempotent** — duplicate admins within a single component's `admins` are harmless no-ops, not guarded.

## Security & trust

- **Shared proxy — shared blast radius.** All Controllers share **one** `ALMProxy` and each is granted `CONTROLLER` on it. RateLimits are per-stack, but the proxy — and the funds it custodies — is **not** isolated between stacks: any Controller can drive the shared proxy within its own rate limits. Deploy together only stacks intended to share custody of the same proxy assets.
- **Trustless post-deploy.** The assembler renounces `DEFAULT_ADMIN_ROLE` on the proxy, every AccessControls, and every RateLimits, and removes itself as an admin on every deployed agent; it retains no control over any deployed contract.
- **One-shot and non-upgradeable.** Each call deploys a fresh, independent group of stacks.
- **Call-scoped ids.** `id` cross-referencing lives only in transient storage for the duration of the call and is cleared before return; it confers no lasting authority or addressing.
- **Deterministic surface.** Roles are wired only as described above; no rate limits, proxy balances, or role-admin overrides are configured beyond the supplied inputs. `ALLOCATOR_ROLE` remains administered by `DEFAULT_ADMIN_ROLE` on AccessControls (OpenZeppelin default).

## Event

```solidity
event Deployment(
    address                   indexed proxy,
    address[]                         controllers,
    address[]                         accessControls,
    address[]                         rateLimits,
    address[]                         allocatorAgents,
    ControllerConfig[]                controllerConfigs,
    RateLimitsConfig[]                rateLimitsConfigs,
    AccessControlsConfig[]            accessControlsConfigs,
    AdministeredAgentConfig[]         allocatorAgentConfigs,
    ALMProxyConfig                    almProxyConfig
);
```
