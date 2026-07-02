# PAU Assemblers

![Foundry CI](https://github.com/sky-ecosystem/pau-assemblers/actions/workflows/test.yml/badge.svg)
[![Foundry][foundry-badge]][foundry]
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](./LICENSE)

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Overview

A collection of one-shot **assembler contracts for the Sky ecosystem**. Each assembler uses factories to deploy and fully wire a standardized on-chain systems in a single transaction, hands administrative rights to caller-supplied admins as defined by its configuration structs, and renounces every role it held during setup — so the assembler is trustless once the call returns.

The first assembler builds on the [PAU](https://github.com/sky-ecosystem/diamond-pau) stack, giving a reviewable, deterministic path to deploying Prime PAUs as more primes enter the ecosystem and replacing ad-hoc manual deployments.

### Factories

| Contract               | Description                                                                                                       |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `DefaultPAUAssembler`  | Deploys a full PAU stack (AccessControls, ALMProxy, RateLimits, Controller) and one or more `AdministeredAgent`s. |
| `PAUAssembler`         | Deploys one or more PAU stacks **sharing a single `ALMProxy`**, cross-referenced by caller-supplied ids, plus allocator `AdministeredAgent`s. |
| `DefaultNFATPAUAssembler` | Deploys a PAU stack via `PAUAssembler` and an NFAT facility wired to the resulting shared `ALMProxy`.             |

## Documentation

See the [`docs/` index](./docs/README.md) for the full map. Per assembler:

| Assembler              | Documentation                                                  | Reviewer checklist                                                |
| ---------------------- | -------------------------------------------------------------- | ---------------------------------------------------------------- |
| `DefaultPAUAssembler`  | [README](./docs/DefaultPAUAssembler/README.md)                 | [CHECKLIST](./docs/DefaultPAUAssembler/CHECKLIST.md)             |
| `PAUAssembler`         | [README](./docs/PAUAssembler/README.md)                        | [CHECKLIST](./docs/PAUAssembler/CHECKLIST.md)                    |
| `DefaultNFATPAUAssembler` | [README](./docs/DefaultNFATPAUAssembler/README.md)                | [CHECKLIST](./docs/DefaultNFATPAUAssembler/CHECKLIST.md) _(draft)_  |

Each README covers the deploy flow, role/permission matrix, configuration, and security notes; each checklist validates deploy arguments before sign-off.

## Design

Every assembler in this repository follows the same model:

- **Atomic** — the full system is deployed and wired in a single call.
- **Hand-off** — administrative rights are transferred to the addresses named in the deploy configuration (`AdminConfig` for the PAU stack, per-agent `admins` for each `AdministeredAgent`) as part of that call.
- **Trustless after deploy** — the assembler renounces every role it held during setup, retaining no control over the deployed contracts.
- **Deterministic surface** — only the roles and configuration described by the inputs are applied, keeping each deployment easy to review.

Per-assembler mechanics — deploy flow, resulting role layout, and configuration — live under [`docs/`](./docs). The first, `DefaultPAUAssembler`, builds on the [`diamond-pau`](https://github.com/sky-ecosystem/diamond-pau) PAU factory and the [`pau-administered-agent`](https://github.com/sky-ecosystem/pau-administered-agent) agent factory; see its [documentation](./docs/DefaultPAUAssembler/README.md) for details.

> **Auditor note.** Assembler `src/` has no compile-time dependency on those repositories — it interfaces with them only through inline `*Like` adapter interfaces. Integration tests fork the target chain and call canonical on-chain `PAUFactory` and `AdministeredAgentFactory` deployments, which avoids pulling those repositories in as submodules.

## Quick Start

### Build

```bash
forge build
```

### Test

Integration tests fork mainnet and require a valid RPC endpoint. Copy [`.env.example`](./.env.example) to `.env` and set `MAINNET_RPC_URL`, then:

```bash
forge test
```

## Conventions

- Solidity `0.8.34`, `cancun` EVM.
- The external surface of each factory lives in `src/interfaces/I<Factory>.sol` (errors, structs, events, and address-returning functions). The `*Like` adapter interfaces for the underlying contracts are declared inline in the implementation file.
- Licensed under AGPL-3.0-or-later.
