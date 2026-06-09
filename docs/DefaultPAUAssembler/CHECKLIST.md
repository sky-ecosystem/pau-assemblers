# Sky Core Review Checklist — `DefaultPAUAssembler`

**Version:** 0.2.0 (draft) · **Last edited:** 2026-06-08

A reviewer checklist for validating a `DefaultPAUAssembler` deployment and the arguments passed to `deploy`, before signing off on a Prime PAU deployment.

Modeled on the [Sky PE checklists](https://github.com/sky-ecosystem/pe-checklists). See the [assembler documentation](./README.md) for the full deploy flow and resulting permission layout, and the [diamond-pau-deploy](https://github.com/sky-ecosystem/diamond-pau-deploy) repo for the underlying PAU stack deployment.

> **Status:** living document. Items marked **(TBD)** await a definition from Soter / Sky Core (e.g. multisig `m/n` schemes, the `configurator` admin policy). Resolve them before first use.

## Conventions

- `* [ ]` items must each be verified and checked off.
- All addresses must be in **checksummed** form and cross-checked against the **chainlog** (or the agreed source of truth for this deployment).
- Role identifiers are `keccak256` of the role name — e.g. `ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE")`, `DEFAULT_ADMIN_ROLE = 0x00`. `ALLOCATOR_ROLE` on AccessControls is administered by `DEFAULT_ADMIN_ROLE` (OpenZeppelin default); the assembler does not apply custom role-admin overrides.

## Allowed configuration

This table is the **source of truth for what may appear in each deploy argument** for current deployments. Edit it (and bump the revision) as policy evolves; the checklist below verifies a deployment against this table rather than restating the policy inline.

> **Revision:** 1 (aligned with `DefaultPAUAssembler` `1.0.0`). **(TBD)** rows are not yet defined.

| Argument                            | Allowed value(s) for current deployments                                                    |
| ----------------------------------- | ------------------------------------------------------------------------------------------- |
| `integrationIds`                    | Approved, Beacon-registered facets only; may be empty.                                      |
| `adminConfig.accessControlAdmins`   | One or more valid addresses. **(TBD: which subproxies / multisigs)**                        |
| `adminConfig.proxyAdmins`           | One or more valid addresses. **(TBD)**                                                      |
| `adminConfig.rateLimitsAdmins`      | One or more valid addresses. **(TBD: e.g. `configurator` only)**                            |
| `allocatorAgentConfigs`             | One or more agent configs; length determines how many `AdministeredAgent` contracts deploy. |
| `allocatorAgentConfigs[i].admins`   | One or more valid addresses per agent. **(TBD)**                                            |
| `allocatorAgentConfigs[i].actors`   | Pre-vetted multisigs (`m/n` **TBD** by Soter). May be empty.                                |
| `allocatorAgentConfigs[i].grantors` | None (empty), unless policy allows. **(TBD)**                                               |
| `allocatorAgentConfigs[i].revokers` | Pre-vetted multisigs (`m/n` **TBD** by Soter). May be empty. Agent-level revokers only.     |

Each `allocatorAgentConfigs` entry deploys one agent that receives `ALLOCATOR_ROLE` on AccessControls. Actor EOAs operate through that agent contract; they do not hold `ALLOCATOR_ROLE` directly.

## Checklist

### 1. Assembler & dependencies

- [ ] The `DefaultPAUAssembler` source matches the audited commit, and the deployed bytecode matches that source.
- [ ] `pauFactory_` is the canonical, audited `PAUFactory` for this deployment (chainlog), and its `beacon()` is the intended Beacon.
- [ ] `administeredAgentFactory_` is the canonical, audited `AdministeredAgentFactory` (chainlog).

### 2. Deploy arguments

- [ ] Every argument matches the **[Allowed configuration](#allowed-configuration)** table.
- [ ] Every address is **checksummed** and verified against **chainlog** (the policy table says _which_ address is allowed; this confirms the value is the _correct_ one).
- [ ] `integrationIds` are registered on the factory's Beacon **before** this deploy, and each maps to the intended, audited facet (facet address + selector wiring reviewed).
- [ ] `allocatorAgentConfigs.length` matches the intended number of allocator agents for this Prime.
- [ ] For each `allocatorAgentConfigs[i]`, `admins`, `actors`, `grantors`, and `revokers` are reviewed against policy (including empty `grantors` / `revokers` / `actors` where permitted).

> **Enforced on-chain (informational — not review items).** The deploy reverts on these, so they cannot be true of a successful deployment: empty `adminConfig` component arrays or empty per-agent `admins` (`NoAdmins`); zero admin in `adminConfig` (`ZeroAdmin`); zero factory dependency (`ZeroPAUFactory` / `ZeroAdministeredAgentFactory`); duplicate agent entries within a single config (`AccountAlreadyAdmin` / `AccountAlreadyActor` / `AccountAlreadyGrantor` / `AccountAlreadyRevoker`). Duplicate entries in `adminConfig` arrays are idempotent no-ops, not guarded.

### 3. Post-deploy

The assembler wires every role and renounces its own deterministically — audited and covered by the test suite — so given a correct assembler (§1) and correct inputs (§2), the resulting permission layout follows by construction. Per-role re-verification is therefore **not** required; the remaining checks are about the deploy succeeding and its outputs being recorded correctly.

- [ ] The deploy transaction succeeded and emitted `Deployment` with the expected addresses and configuration.
- [ ] The deployed addresses are recorded correctly in the deployment artifacts / chainlog.
- [ ] _(Optional, defense-in-depth)_ Spot-check that the assembler address holds no roles on the deployed contracts — redundant with §1 if the audited assembler was used.

### 4. Sign-off

- [ ] All addresses double-checked against chainlog (or agreed source of truth).
- [ ] All **(TBD)** rows in the Allowed configuration table are resolved for this deployment.
- [ ] Reviewer 1: **\*\*\*\***\_\_\_\_**\*\*\*\***
- [ ] Reviewer 2: **\*\*\*\***\_\_\_\_**\*\*\*\***
