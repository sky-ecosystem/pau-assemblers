# Sky Core Review Checklist — `DefaultNFATAssembler`

**Version:** 0.1.0 (stub) · **Last edited:** 2026-06-25

> **Status:** stub — to be fleshed out for the Spark review pass. The PAU portion of any `DefaultNFATAssembler` deploy is governed by the [`PAUAssembler` checklist](../PAUAssembler/CHECKLIST.md); this document only adds the NFAT-facility-specific items. See the [assembler documentation](./README.md) for the deploy flow.

A reviewer checklist for validating a `DefaultNFATAssembler` deployment and the arguments passed to `deploy`, before signing off.

## Conventions

- `* [ ]` items must each be verified and checked off.
- All addresses must be in **checksummed** form and cross-checked against the **chainlog** (or the agreed source of truth for this deployment).

## Checklist

### 1. Assembler & dependencies

- [ ] The `DefaultNFATAssembler` source matches the audited commit, and the deployed bytecode matches that source.
- [ ] `pauAssembler_` is the canonical, audited `PAUAssembler` for this deployment (chainlog).
- [ ] `nfatFactory_` is the canonical, audited NFAT facility factory (chainlog), and exposes the `deploy(name, symbol, baseURI, gem, recipient, identityNetwork, wards, buds, cops)` overload this assembler calls.

### 2. PAU arguments (`pauAssemblerInput`)

- [ ] **Complete the [`PAUAssembler` checklist](../PAUAssembler/CHECKLIST.md) §2** against `pauAssemblerInput` — id wiring, shared-proxy intent, integrations, admins, agents, etc. All of it applies verbatim.

### 3. NFAT arguments (`nfatFactoryInput`) — **(TBD)**

- [ ] `name` / `symbol` / `baseURI` match the intended facility metadata.
- [ ] `gem` is the intended, approved backing token (chainlog). It must be USDS or sUSDS.
- [ ] `identityNetwork` is the intended identity network (chainlog).
- [ ] `wards` are reviewed against policy. **(TBD: which subproxies / multisigs)**
- [ ] `cops` are reviewed against policy. **(TBD)**
- [ ] **Recipient / bud are fixed.** Confirmed understanding that the facility `recipient` and sole `bud` are forced to the deployed shared `ALMProxy` and cannot be set via `nfatFactoryInput`.

> **Enforced on-chain (informational — not review items).** Zero `pauAssembler_` / `nfatFactory_` reverts the constructor (`ZeroPAUAssembler` / `ZeroNFATFactory`); all `PAUAssembler` reverts apply to the forwarded `pauAssemblerInput`. NFAT-facility input validation (e.g. on `wards` / `cops` / `gem`) is owned by the NFAT factory.

### 4. Post-deploy

- [ ] The deploy transaction succeeded and emitted `Deployment` with the expected `proxy`, `nfatFacility`, PAU result arrays, and configuration.
- [ ] The deployed addresses are recorded correctly in the deployment artifacts / chainlog.
