# Sky Factories

![Foundry CI](https://github.com/soterlabs/sky-factories/actions/workflows/test.yml/badge.svg)
[![Foundry][foundry-badge]][foundry]
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](./LICENSE)

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Overview

A collection of one-shot **factory contracts for the Sky ecosystem**. Each factory deploys and fully
wires a standardized on-chain system in a single transaction, hands all administrative rights to a
caller-supplied admin, and renounces every role it held during setup — so the factory is trustless
once the call returns.

The first factory builds on the [PAU](https://github.com/sky-ecosystem/diamond-pau) stack, giving a
reviewable, deterministic path to deploying Prime PAUs as more primes enter the ecosystem and
replacing ad-hoc manual deployments.

### Factories

| Contract                       | Description                                                                                              |
| ------------------------------ | -------------------------------------------------------------------------------------------------------- |
| `PAUAdministeredAgentFactory`  | Deploys a full PAU stack (AccessControls, ALMProxy, RateLimits, Controller) plus an `AdministeredAgent`. |

## Documentation

| Document                                                                | Description                                                              |
| ----------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| [PAU Administered Agent Factory](./docs/PAUAdministeredAgentFactory.md)  | Deploy flow, role/permission matrix, configuration, and security notes. |

## Design

Every factory in this repository follows the same model:

- **Atomic** — the full system is deployed and wired in a single call.
- **Hand-off** — administrative rights are transferred to a caller-supplied `admin` (and any extra
  admins) as part of that call.
- **Trustless after deploy** — the factory renounces every role it held during setup, retaining no
  control over the deployed contracts.
- **Deterministic surface** — only the roles and configuration described by the inputs are applied,
  keeping each deployment easy to review.

Per-factory mechanics — deploy flow, resulting role layout, and configuration — live under
[`docs/`](./docs). The first, `PAUAdministeredAgentFactory`, builds on the
[`diamond-pau`](https://github.com/sky-ecosystem/diamond-pau) PAU factory and the
[`pau-administered-agent`](https://github.com/sky-ecosystem/pau-administered-agent) agent factory; see
its [documentation](./docs/PAUAdministeredAgentFactory.md) for details.

> **Auditor note.** Factory `src/` has no compile-time dependency on those repositories — it talks to
> them only through inline `*Like` adapter interfaces, and the submodules are imported **only by the
> tests**. Both are pinned to in-PR / pre-release commits (not tagged releases) and sit in the same
> audit slot as this factory; we may need to re-pin or migrate once they ship. See the
> [dependency status note](./docs/PAUAdministeredAgentFactory.md#dependencies) for the exact refs.

## Quick Start

### Build

```bash
forge build
```

### Test

```bash
forge test
```

The suite covers the factory in isolation (against the real PAU components with a mocked Controller),
an integration pass against the canonical `PAUFactory`, and a full end-to-end test that routes a real
ERC-20 transfer through `AdministeredAgent -> Controller -> TransferAssetFacet -> ALMProxy`.

## Conventions

- Solidity `0.8.34`, `cancun` EVM.
- The external surface of each factory lives in `src/interfaces/I<Factory>.sol` (errors, structs,
  events, and address-returning functions). The `*Like` adapter interfaces for the underlying
  contracts are declared inline in the implementation file.
- Licensed under AGPL-3.0-or-later.
