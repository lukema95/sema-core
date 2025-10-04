English | [简体中文](./README.zh.md)

# AAS Documentation

Aptos Attestation Service — schemas and attestations as named objects, with optional Shelby off-chain storage and dispatchable resolvers.

- Package and build instructions: [aas/README.md](../../aas/README.md)
- Module and API reference: [reference/aas.md](../reference/aas.md)
- Deployment: [deployment.md](../deployment.md)

## Documents

| Page | Contents |
|------|----------|
| [architecture.md](./architecture.md) | Object model, module breakdown, package-manager signer, Shelby storage |
| [flows.md](./flows.md) | Register, issue, off-chain, resolver, revoke sequences |
| [principles.md](./principles.md) | Deterministic addresses, `ExtendRef`, dispatchable resolvers |

## Module map

| Module | Responsibility |
|--------|----------------|
| `aas::aas` | Entry points: create schema, attest, attest off-chain, batch, revoke |
| `aas::schema` | `Schema` named object, seed/address derivation, views, `SchemaCreated` |
| `aas::attestation` | `Attestation` named object, storage modes, integrity checks, events |
| `aas::package_manager` | Protocol object signer (`ExtendRef`) used to create every named object |
| `aas::resolver_dispatcher` | Registers and calls resolver callbacks |
| `aas::resolver_storage` | Serializes request data between the dispatcher and resolvers |
| `resolver_example` | Reference `schema_resolver::resolve` implementation |

## Key invariants

- Schema and attestation addresses are derived from `keccak256(bcs(...))` seeds passed to `object::create_object_address` with the package-manager signer.
- Schema addresses are computable from content; attestation addresses also depend on the execution-time `now`, so they are read from events/views rather than predicted before signing.
- `now` (seconds) is part of the attestation seed; the same parameters produce different addresses across seconds.
- The schema creator is the only account that can revoke, and only when the schema is revokable and the resolver (if any) approves.
- Off-chain attestations store a Blake2b-256 hash and Shelby metadata; the payload is never written on-chain.
- Resolver requests are approved only when the resolver returns `Some(0)`; an unregistered resolver is treated as open.

## One-sentence summary

Both schemas and attestations are named objects created by the package signer; schema addresses are computable in advance, attestation addresses become known once execution time is fixed. Revocation is gated by schema creator and policy, off-chain data is anchored to Shelby by a Blake2b-256 hash, and resolvers are invoked through a dispatchable fungible asset callback.
