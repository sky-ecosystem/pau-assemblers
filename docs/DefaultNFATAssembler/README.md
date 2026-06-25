# Default NFAT Assembler

`DefaultNFATAssembler` deploys a full PAU stack via [`PAUAssembler`](../PAUAssembler/README.md) and then deploys an **NFAT facility** wired to the resulting shared `ALMProxy`, in a single transaction. It is a thin composition layer: all PAU role wiring and renunciation is delegated to `PAUAssembler`, and the NFAT facility's wards/cops are set directly by the NFAT factory. The assembler itself never holds a role on any deployed contract.

Implementation version: `1.0.0` (`VERSION`).

## Dependencies

| Constructor argument | Type             | Role                                                                  |
| -------------------- | ---------------- | -------------------------------------------------------------------- |
| `pauAssembler_`      | `IPAUAssembler`  | Deploys and wires the full PAU stack (shared proxy + stacks + agents). |
| `nfatFactory_`       | `INFATFactoryLike` | Deploys the NFAT facility.                                          |

Both must be non-zero (`ZeroPAUAssembler` / `ZeroNFATFactory`). For the PAU stack's own dependencies, configuration semantics, and permission layout, see the [`PAUAssembler` documentation](../PAUAssembler/README.md) — this assembler forwards its `PAUAssemblerInput` to `PAUAssembler.deploy` verbatim.

> **Auditor note — dependency status.** The assembler depends on `PAUAssembler` only through the `IPAUAssembler` interface and on the NFAT factory only through the inline `INFATFactoryLike` adapter; the production bytecode imports neither implementation. The NFAT factory is not deployed on mainnet, so the integration test runs the **real** `PAUAssembler` against the forked `PAUFactory` and exercises the NFAT leg through a recording mock factory.

## Entry point

```solidity
function deploy(
    PAUAssemblerInput memory pauAssemblerInput,
    NFATFactoryInput  memory nfatFactoryInput
)
    external
    returns (
        address          proxy,
        address          nfatFacility,
        address[] memory controllers,
        address[] memory accessControls,
        address[] memory rateLimits,
        address[] memory allocatorAgents
    );
```

## Deploy flow

1. **Deploy the PAU stack** — forward `pauAssemblerInput` to `PAUAssembler.deploy`, returning the shared `proxy`, `controllers`, `accessControls`, `rateLimits`, and `allocatorAgents`. All PAU role wiring and the assembler's renunciation happen inside this call.
2. **Deploy the NFAT facility** — call the NFAT factory wired to the shared proxy. The facility's **`recipient` and sole `bud` are both fixed to the deployed `ALMProxy`**; neither is caller-supplied. `wards` and `cops` are forwarded from `nfatFactoryInput`.

A `Deployment` event is emitted with every deployed address and the full configuration.

> **NFAT factory argument order.** The forwarded call is `deploy(name, symbol, baseURI, gem, recipient, identityNetwork, wards, buds, cops)` with `recipient = proxy` and `buds = [proxy]`. This matches the `NFATFacilityFactory` implementation overload (`gem` before `recipient`), which differs from its other overload — confirm the bound factory exposes this exact signature.

## Resulting layout

After a successful deploy:

- The PAU stack permission layout is exactly as produced by `PAUAssembler` — see its [Resulting permission layout](../PAUAssembler/README.md#resulting-permission-layout). Neither `PAUAssembler` nor `DefaultNFATAssembler` retains any role.
- The NFAT facility is deployed with `recipient = bud = proxy`, and `wards` / `cops` as supplied. Facility role semantics are owned by the NFAT factory / facility, not by this assembler.

Post-deploy invariants checked by `DefaultNFATAssembler.t.sol`:

- `nfatFacility` is the address returned by the NFAT factory.
- The PAU result arrays are returned intact (lengths match the inputs).
- Neither the inner `PAUAssembler` nor `DefaultNFATAssembler` holds `DEFAULT_ADMIN_ROLE` on the shared proxy.
- The NFAT factory was called with `recipient == bud == proxy`, and pass-through fields (`name`, `symbol`, `baseURI`, `gem`, `identityNetwork`, `wards`, `cops`) forwarded verbatim.

## Configuration reference

### `PAUAssemblerInput`

The full set of `PAUAssembler` configuration arrays, forwarded verbatim. See the [`PAUAssembler` configuration reference](../PAUAssembler/README.md#configuration-reference).

| Field                   | Forwarded to                              |
| ----------------------- | ----------------------------------------- |
| `controllerConfigs`     | `PAUAssembler.deploy` `controllerConfigs`     |
| `rateLimitConfigs`      | `PAUAssembler.deploy` `rateLimitConfigs`      |
| `accessControlConfigs`  | `PAUAssembler.deploy` `accessControlConfigs`  |
| `allocatorAgentConfigs` | `PAUAssembler.deploy` `allocatorAgentConfigs` |
| `almProxyConfig`        | `PAUAssembler.deploy` `almProxyConfig`        |

### `NFATFactoryInput`

Parameters forwarded to the NFAT factory. `recipient` and `buds` are **not** supplied here — both are fixed to the deployed proxy.

| Field             | Meaning                                  |
| ----------------- | ---------------------------------------- |
| `name`            | NFAT name.                               |
| `symbol`          | NFAT symbol.                             |
| `baseURI`         | NFAT base URI.                           |
| `gem`             | Gem token backing the facility.          |
| `identityNetwork` | Identity network used by the facility.   |
| `wards`           | Wards for the facility.                  |
| `cops`            | Cops for the facility.                   |

## Preconditions & behavior

- **PAU preconditions apply in full** — the forwarded `pauAssemblerInput` is subject to every `PAUAssembler` revert (`NoDefaultAdmins`, `ZeroDefaultAdmin`, `Duplicate…Id`, `Invalid…Id`, `NoAgentAdmins`, …). See the [`PAUAssembler` preconditions](../PAUAssembler/README.md#preconditions--behavior).
- **Facility wiring is fixed** — `recipient` and the sole `bud` are always the deployed proxy; callers cannot override them.
- **`wards` / `cops` validation** is owned by the NFAT factory, not this assembler.

## Security & trust

- **Trustless post-deploy.** This assembler grants and revokes nothing of its own: PAU roles are wired and renounced inside `PAUAssembler`, and the NFAT factory sets the facility's final `wards` / `cops` directly. The assembler retains no control over any deployed contract.
- **Shared proxy.** The NFAT facility is bound to the **same** shared `ALMProxy` as every PAU stack deployed in the call — the shared-custody trust model from `PAUAssembler` applies, now extended to the facility's recipient/bud. See [`PAUAssembler` security & trust](../PAUAssembler/README.md#security--trust).
- **One-shot and non-upgradeable.** Each call deploys a fresh stack and facility.

## Event

```solidity
event Deployment(
    address           indexed proxy,
    address           indexed nfatFacility,
    address[]                 controllers,
    address[]                 accessControls,
    address[]                 rateLimits,
    address[]                 allocatorAgents,
    PAUAssemblerInput         pauAssemblerInput,
    NFATFactoryInput          nfatFactoryInput
);
```
