# PAU Administered Agent Factory

`DefaultPAUFactory` deploys and fully wires a Prime PAU stack plus an `AdministeredAgent`
in a single transaction, transfers all administrative rights to a caller-supplied `admin`, and
renounces every role it held during setup. After the call returns the factory holds **no** privileged
role on any deployed contract.

## Dependencies

The factory is constructed with two underlying factories and calls into them at deploy time:

| Constructor argument        | Type                            | Role                                                                  |
| --------------------------- | ------------------------------- | --------------------------------------------------------------------- |
| `pauFactory_`               | `IPAUFactoryLike`               | Deploys AccessControls, ALMProxy(/Freezable), RateLimits, Controller. |
| `administeredAgentFactory_` | `IAdministeredAgentFactoryLike` | Deploys the `AdministeredAgent`.                                      |

Both must be non-zero (`ZeroPAUFactory` / `ZeroAdministeredAgentFactory`). The PAU factory points its
deployed Controllers at a shared **Beacon**; integrations must be registered on that Beacon _before_
they can be passed to `deploy` (see [Preconditions](#preconditions--behavior)).

> **Auditor note — dependency status.** The factory has **no compile-time dependency** on the underlying
> contracts: `src/` interacts with them solely through the inline `*Like` adapter interfaces, so the
> production bytecode imports neither repository. The submodules are pulled in **only by the test suite**
> (the mocks and integration tests, to exercise the factory against real bytecode).
>
> Both are currently pinned to **in-PR / pre-release commits, not tagged releases**, and are understood
> to be in the **same audit slot** as this factory:
>
> - [`diamond-pau`](https://github.com/sky-ecosystem/diamond-pau) @ `222798b` (`v1.12.0-4-g222798b`)
> - [`pau-administered-agent`](https://github.com/sky-ecosystem/pau-administered-agent) @ `f0c28ec` (branch `feat/initial-code`)
>
> We are aware these are not yet finalized and may need to re-pin or migrate once official releases land.
> The `*Like` interfaces mirror only the functions the factory calls, so any incompatible change to those
> upstream signatures would surface there (and in the integration tests).

## Entry points

```solidity
function deploy(
    address admin,
    bytes32[] integrationIds,
    AdminConfig adminConfig,
    AdministeredAgentConfig administeredAgentConfig,
    AccessControlRoleAdminConfig[] roleAdminConfig
) external returns (address accessControls, address controller, address proxy, address rateLimits, address agent);

function deployFreezable(
    address admin,
    address[] freezers,
    bytes32[] integrationIds,
    AdminConfig adminConfig,
    AdministeredAgentConfig administeredAgentConfig,
    AccessControlRoleAdminConfig[] roleAdminConfig
) external returns (address accessControls, address controller, address proxy, address rateLimits, address agent);
```

Both share an internal implementation. The only differences are the ALMProxy variant deployed and the
role the Controller is granted on it — see [Standard vs. freezable](#standard-vs-freezable-proxy).

## Deploy flow

1. **Deploy the stack** — AccessControls, ALMProxy (standard or freezable), RateLimits, Controller (all
   admined by the factory initially), and the AdministeredAgent.
2. **Configure the agent** — add `actors`, `grantors`, and `revokers`.
3. **Wire roles** — grant the Controller its proxy/rate-limit roles, grant freezers `FREEZER_ROLE`
   (freezable only), grant `admin` and the per-component extra admins `DEFAULT_ADMIN_ROLE`, add the
   agent admins, and grant the agent `ALLOCATOR_ROLE` on AccessControls.
4. **Register integrations** — `Controller.updateIntegrations(integrationIds)`, **skipped** when the
   list is empty.
5. **Apply role-admin reassignments** — `AccessControls.setRoleAdmin` for each `roleAdminConfig` entry,
   while the factory still holds `DEFAULT_ADMIN_ROLE`.
6. **Renounce** — the factory revokes its own `DEFAULT_ADMIN_ROLE` on AccessControls, ALMProxy, and
   RateLimits, and removes itself as an agent admin.

A `PAUAdministeredAgentFactoryDeploy` event is emitted with every deployed address and the full
configuration.

## Resulting permission layout

After a successful deploy:

| Contract               | Role                  | Holders                                                    |
| ---------------------- | --------------------- | ---------------------------------------------------------- |
| AccessControls         | `DEFAULT_ADMIN_ROLE`  | `admin` + `adminConfig.accessControlAdmins`                |
| AccessControls         | `ALLOCATOR_ROLE`      | the AdministeredAgent                                      |
| ALMProxy               | `DEFAULT_ADMIN_ROLE`  | `admin` + `adminConfig.proxyAdmins`                        |
| ALMProxy (standard)    | `CONTROLLER`          | the Controller                                             |
| ALMProxy (freezable)   | `ALLOCATOR_ROLE`      | the Controller                                             |
| ALMProxy (freezable)   | `FREEZER_ROLE`        | `freezers`                                                 |
| RateLimits             | `DEFAULT_ADMIN_ROLE`  | `admin` + `adminConfig.rateLimitsAdmins`                   |
| RateLimits             | `CONTROLLER`          | the Controller                                             |
| AdministeredAgent      | admin                 | `admin` + `adminConfig.administeredAgentAdmins`            |
| AdministeredAgent      | actor/grantor/revoker | `administeredAgentConfig.actors` / `grantors` / `revokers` |
| **the factory itself** | —                     | **nothing** (all bootstrap roles renounced)                |

> **Note.** The Controller has no roles of its own — admin actions on it are authorized against
> `DEFAULT_ADMIN_ROLE` on AccessControls. So the `accessControlAdmins` (which hold `DEFAULT_ADMIN_ROLE`
> on AccessControls) also effectively govern the Controller.

## Standard vs. freezable proxy

`deploy` wires a standard `ALMProxy`; `deployFreezable` wires an `ALMProxyFreezable`. They use different
authorization for the proxy's `doCall`:

- **Standard** `ALMProxy.doCall` is gated on `CONTROLLER`, so the Controller is granted `CONTROLLER`.
- **Freezable** `ALMProxyFreezable.doCall` is gated on `ALLOCATOR_ROLE` (it has no `CONTROLLER` role),
  so the Controller is granted `ALLOCATOR_ROLE`. `FREEZER_ROLE` holders can remove the allocator for an
  emergency freeze.

RateLimits always uses `CONTROLLER`, regardless of proxy variant.

The factory grants `FREEZER_ROLE` to the supplied `freezers` but does **not** assign a dedicated
role-admin for `FREEZER_ROLE`; manage freezers afterward via `admin` (who holds `DEFAULT_ADMIN_ROLE` on
the proxy), or pass a `roleAdminConfig` entry.

## Configuration reference

### `AdminConfig`

Additional admins granted **in addition to** the system-wide `admin`:

| Field                     | Granted on        |
| ------------------------- | ----------------- |
| `accessControlAdmins`     | AccessControls    |
| `proxyAdmins`             | ALMProxy          |
| `rateLimitsAdmins`        | RateLimits        |
| `administeredAgentAdmins` | AdministeredAgent |

> `admin` is the **system-wide admin** and is always granted admin rights on every component, so it
> must **not** be repeated in any `AdminConfig` array. Listing it in `administeredAgentAdmins` reverts
> (`AlreadyAdmin`); in the other arrays it is a redundant no-op.

### `AdministeredAgentConfig`

| Field      | Meaning                                                                  |
| ---------- | ------------------------------------------------------------------------ |
| `actors`   | Granted the actor role (may execute `call` / `batchCall` / `sendValue`). |
| `grantors` | May add actors on the agent.                                             |
| `revokers` | May remove actors on the agent.                                          |

### `AccessControlRoleAdminConfig[]`

Each entry is applied as `AccessControls.setRoleAdmin(role, adminRole)` (e.g. to put `ALLOCATOR_ROLE`
under a custom `ALLOCATOR_ADMIN_ROLE`).

## Preconditions & behavior

- **`admin` must be non-zero** (`ZeroAdmin`).
- **Integrations must be pre-registered on the Beacon.** `updateIntegrations` reads each id's config
  (facet + selector wiring) from the Beacon the underlying `PAUFactory` points at. Unknown ids revert.
- **Empty `integrationIds` is supported** — the `updateIntegrations` call is skipped (the Controller
  reverts on an empty array), so a stack can be deployed bare and configured later by an admin.
- **Duplicate / overlapping entries behave differently per component.**
    - On the **AdministeredAgent**, re-adding an account reverts the whole deploy — this acts as a
      built-in guard against duplicate or overlapping agent entries. Duplicate `actors`, `grantors`,
      `revokers`, or `administeredAgentAdmins` revert with `AlreadyActor` / `AlreadyGrantor` /
      `AlreadyRevoker` / `AlreadyAdmin` respectively, as does listing `admin` again inside
      `administeredAgentAdmins` (it is already the agent admin).
    - On **AccessControls / ALMProxy / RateLimits**, and for the `freezers`, roles are granted through
      OpenZeppelin `grantRole`, which is **idempotent**: re-granting an already-held role is a silent
      no-op. Duplicates and `admin`-overlaps in `accessControlAdmins` / `proxyAdmins` /
      `rateLimitsAdmins` / `freezers` are therefore harmless (no revert), not guarded.

## Security & trust

- **Trustless post-deploy.** The factory renounces `DEFAULT_ADMIN_ROLE` on AccessControls, ALMProxy,
  and RateLimits and removes itself as an agent admin; it retains no control over any deployed contract.
- **One-shot and non-upgradeable.** Each call deploys a fresh, independent stack.
- **`roleAdminConfig` guards `DEFAULT_ADMIN_ROLE`.** Role-admin reassignments are applied while the
  factory still holds `DEFAULT_ADMIN_ROLE` (step 5), immediately before renouncing it (step 6). A
  `roleAdminConfig` entry targeting `DEFAULT_ADMIN_ROLE` is rejected up front with
  `CannotReassignDefaultAdminRole`, since reassigning its admin would otherwise leave the factory unable
  to renounce its own admin and brick the deploy.
- **Deterministic surface.** Roles are wired only as described above; no rate limits, freezer admins, or
  integrations are configured beyond the supplied inputs.

## Event

```solidity
event PAUAdministeredAgentFactoryDeploy(
    address indexed admin,
    bool freezableProxy,
    address accessControls,
    address controller,
    address proxy,
    address rateLimits,
    address administeredAgent,
    address[] freezers,
    bytes32[] integrationIds,
    AdminConfig adminConfig,
    AdministeredAgentConfig administeredAgentConfig,
    AccessControlRoleAdminConfig[] roleAdminConfig
);
```
