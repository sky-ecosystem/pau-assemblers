# Sky Core Review Checklist — `PAUAssembler`

**Version:** 0.1.0 (draft) · **Last edited:** 2026-06-25

A reviewer checklist for validating a `PAUAssembler` deployment and the arguments passed to `deploy`, before signing off on a multi-stack Prime PAU deployment.

Modeled on the [Sky PE checklists](https://github.com/sky-ecosystem/pe-checklists) and the [`DefaultPAUAssembler` checklist](../DefaultPAUAssembler/CHECKLIST.md). See the [assembler documentation](./README.md) for the full deploy flow and resulting permission layout, and the [diamond-pau-deploy](https://github.com/sky-ecosystem/diamond-pau-deploy) repo for the underlying PAU stack deployment.

> **Status:** living document. Items marked **(TBD)** await a definition from Soter / Sky Core (e.g. multisig `m/n` schemes, the `configurator` admin policy). Resolve them before first use.

## Conventions

- `* [ ]` items must each be verified and checked off.
- All addresses must be in **checksummed** form and cross-checked against the **chainlog** (or the agreed source of truth for this deployment).
- Role identifiers are `keccak256` of the role name — e.g. `ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE")`, `DEFAULT_ADMIN_ROLE = 0x00`. `ALLOCATOR_ROLE` on AccessControls is administered by `DEFAULT_ADMIN_ROLE` (OpenZeppelin default); the assembler applies no custom role-admin overrides.
- `id` fields are **call-scoped labels** used only to cross-reference components within a single `deploy`. They are not stored on-chain and need not be globally unique — only unique within their own set (AccessControls ids vs. RateLimits ids) for this call.

## Allowed configuration

This table is the **source of truth for what may appear in each deploy argument** for current deployments. Edit it (and bump the revision) as policy evolves; the checklist below verifies a deployment against this table rather than restating the policy inline.

> **Revision:** 1 (aligned with `PAUAssembler` `1.0.0`). **(TBD)** rows are not yet defined.

| Argument                                  | Allowed value(s) for current deployments                                                       |
| ----------------------------------------- | --------------------------------------------------------------------------------------------- |
| `almProxyConfig.admins`                   | One or more valid addresses. **(TBD: which subproxies / multisigs)**                           |
| `accessControlsConfigs[i].id`              | Unique within the AccessControls set; consistent with the ids referenced by controllers/agents. |
| `accessControlsConfigs[i].admins`          | One or more valid addresses per AccessControls. **(TBD)**                                      |
| `rateLimitConfigs[i].id`                  | Unique within the RateLimits set; consistent with the ids referenced by controllers.          |
| `rateLimitConfigs[i].admins`              | One or more valid addresses per RateLimits. **(TBD: e.g. `configurator` only)**               |
| `controllerConfigs[i].accessControlsId`    | An `id` present in `accessControlsConfigs`.                                                     |
| `controllerConfigs[i].rateLimitId`        | An `id` present in `rateLimitConfigs`.                                                         |
| `controllerConfigs[i].integrationIds`     | Approved, Beacon-registered facets only; may be empty.                                         |
| `allocatorAgentConfigs[i].accessControlsId`| An `id` present in `accessControlsConfigs`.                                                     |
| `allocatorAgentConfigs[i].admins`         | One or more valid addresses per agent. **(TBD)**                                              |
| `allocatorAgentConfigs[i].actors`         | Pre-vetted multisigs (`m/n` **TBD** by Soter). May be empty.                                   |
| `allocatorAgentConfigs[i].grantors`       | None (empty), unless policy allows. **(TBD)**                                                 |
| `allocatorAgentConfigs[i].revokers`       | Pre-vetted multisigs (`m/n` **TBD** by Soter). May be empty. Agent-level revokers only.        |

Each `allocatorAgentConfigs` entry deploys one agent that receives `ALLOCATOR_ROLE` on its referenced AccessControls. Actor EOAs operate through that agent contract; they do not hold `ALLOCATOR_ROLE` directly.

## Checklist

### 1. Assembler & dependencies

- [ ] The `PAUAssembler` source matches the audited commit, and the deployed bytecode matches that source.
- [ ] `pauFactory_` is the canonical, audited `PAUFactory` for this deployment (chainlog), and its `beacon()` is the intended Beacon.
- [ ] `administeredAgentFactory_` is the canonical, audited `AdministeredAgentFactory` (chainlog).

### 2. Deploy arguments

- [ ] Every argument matches the **[Allowed configuration](#allowed-configuration)** table.
- [ ] Every address is **checksummed** and verified against **chainlog** (the policy table says _which_ address is allowed; this confirms the value is the _correct_ one).
- [ ] **Shared-proxy intent is confirmed.** All stacks in this call are intended to **share custody of a single ALMProxy**; any Controller deployed here can drive that proxy within its own rate limits. Stacks requiring fund isolation must be deployed in **separate** transactions / separate proxies.
- [ ] **Id wiring is correct.** Every `controllerConfigs[i].accessControlsId` / `rateLimitId` and every `allocatorAgentConfigs[i].accessControlsId` references an `id` actually present in the corresponding config array, and each controller/agent is bound to the **intended** AccessControls/RateLimits.
- [ ] `accessControlsConfigs` ids and `rateLimitConfigs` ids are each unique within their set.
- [ ] `integrationIds` are registered on the factory's Beacon **before** this deploy, and each maps to the intended, audited facet (facet address + selector wiring reviewed).
- [ ] `controllerConfigs.length`, `accessControlsConfigs.length`, `rateLimitConfigs.length`, and `allocatorAgentConfigs.length` match the intended topology for this deployment.
- [ ] For each `allocatorAgentConfigs[i]`, `admins`, `actors`, `grantors`, and `revokers` are reviewed against policy (including empty `grantors` / `revokers` / `actors` where permitted).

> **Enforced on-chain (informational — not review items).** The deploy reverts on these, so they cannot be true of a successful deployment: empty `admins` on the proxy / any AccessControls / any RateLimits / any agent (`NoDefaultAdmins` / `NoAgentAdmins`); zero admin on proxy / AccessControls / RateLimits (`ZeroDefaultAdmin`); duplicate `id` within the AccessControls or RateLimits set (`DuplicateAccessControlsId` / `DuplicateRateLimitsId`); a controller/agent referencing an unknown `id` (`InvalidAccessControlsId` / `InvalidRateLimitsId`); zero factory dependency (`ZeroPAUFactory` / `ZeroAdministeredAgentFactory`); duplicate agent entries within a single config (`AccountAlreadyAdmin` / `AccountAlreadyActor` / `AccountAlreadyGrantor` / `AccountAlreadyRevoker`). Duplicate entries in a component's `admins` array are idempotent no-ops, not guarded.

### 3. Post-deploy

The assembler wires every role and renounces its own deterministically — audited and covered by the test suite — so given a correct assembler (§1) and correct inputs (§2), the resulting permission layout follows by construction. Per-role re-verification is therefore **not** required; the remaining checks are about the deploy succeeding and its outputs being recorded correctly.

- [ ] The deploy transaction succeeded and emitted `Deployment` with the expected addresses and configuration.
- [ ] The returned `controllers` / `accessControls` / `rateLimits` / `allocatorAgents` arrays line up index-for-index with the submitted config arrays, and `proxy` is the intended shared proxy.
- [ ] The deployed addresses are recorded correctly in the deployment artifacts / chainlog.
