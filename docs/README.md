# Documentation

Per-assembler mechanics — deploy flow, resulting role/permission layout, configuration reference, and security notes — plus a Sky Core reviewer checklist for validating deploy arguments before sign-off.

| Assembler              | What it deploys                                                                                  | Docs                                                  | Reviewer checklist                                              |
| ---------------------- | ----------------------------------------------------------------------------------------------- | ---------------------------------------------------- | -------------------------------------------------------------- |
| `DefaultPAUAssembler`  | One PAU stack (AccessControls, ALMProxy, RateLimits, Controller) + allocator `AdministeredAgent`s. | [README](./DefaultPAUAssembler/README.md)            | [CHECKLIST](./DefaultPAUAssembler/CHECKLIST.md)               |
| `PAUAssembler`         | A multi-controller / multi-rate-limit / multi-access-control stack **sharing a single `ALMProxy`**, cross-referenced by caller-supplied ids. | [README](./PAUAssembler/README.md)                   | [CHECKLIST](./PAUAssembler/CHECKLIST.md)                     |
| `DefaultNFATPAUAssembler` | A PAU stack via `PAUAssembler` + an NFAT facility wired to the resulting shared `ALMProxy`.       | [README](./DefaultNFATPAUAssembler/README.md)           | [CHECKLIST](./DefaultNFATPAUAssembler/CHECKLIST.md) _(draft)_   |

## Relationships

- **`PAUAssembler`** generalises **`DefaultPAUAssembler`** from one proxy / one controller to many stacks sharing one proxy. Its README documents the shared-custody trust model and the call-scoped `id` cross-referencing.
- **`DefaultNFATPAUAssembler`** composes **`PAUAssembler`**: it forwards the full PAU configuration, then binds an NFAT facility's `recipient` and sole `bud` to the shared proxy. The PAU half of its review is covered by the `PAUAssembler` checklist.

For the underlying components, see [`diamond-pau`](https://github.com/sky-ecosystem/diamond-pau) (PAU factory) and [`pau-administered-agent`](https://github.com/sky-ecosystem/pau-administered-agent) (agent factory).
