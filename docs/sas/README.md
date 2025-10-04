English | [简体中文](./README.zh.md)

# SAS Documentation

Sui Attestation Service — shared schemas, recipient-owned attestations, version-gated registries, Walrus storage, and Seal encryption.

- Package and build instructions: [sas/README.md](../../sas/README.md)
- Module and API reference: [reference/sas.md](../reference/sas.md)
- Deployment: [deployment.md](../deployment.md)

## Documents

| Page | Contents |
|------|----------|
| [architecture.md](./architecture.md) | Object model, registries, resolver hot potato, Seal, versioning |
| [flows.md](./flows.md) | Register, issue, off-chain, resolver, revoke sequences |
| [principles.md](./principles.md) | Design rationale and trade-offs |

## Module map

| Module | Responsibility |
|--------|----------------|
| `sas::sas` | Facade: register schema, attest, attest off-chain, resolver paths, revoke |
| `sas::schema` | `Schema`, `Resolver`, `ResolverBuilder`, `Request`, `SchemaCreated` |
| `sas::attestation` | `Attestation` object, storage modes, Seal fields, integrity check |
| `sas::schema_registry` | Shared schema index with version gating |
| `sas::attestation_registry` | Shared attestation status index with version gating |
| `sas::admin` | Schema-bound `Admin` capability |
| `sas::constants` | `CURRENT_VERSION` |
| `sas::seal_access` | Seal key-id derivation and recipient-only `seal_approve` |
| `resolvers` | Reference whitelist and blocklist resolvers |

## Key invariants

- `Schema` becomes shared on `new`, or after `new_with_resolver` + `share_schema`; `Attestation` is owned by the recipient; registries are shared system objects.
- Revocation requires the schema's `Admin` capability, a revokable schema, and an existing, not-yet-revoked attestation that belongs to the schema. `admin::new` is currently public and unguarded, so do not treat this as a security boundary.
- The registry version check runs on every load; pre-authorize the new `CURRENT_VERSION` with `update_allowed_versions` **before** upgrading.
- Expiration uses milliseconds; `0` means no expiration.
- Off-chain data stores a Walrus pointer plus a caller-supplied Blake2b-256 hash; clients must verify it (the contract only exposes an opt-in view).
- Resolver flows use a hot-potato `Request`; `finish_attest`/`finish_revoke` consume it after all configured rules approve.

## One-sentence summary

Sui's object model makes schemas shared, attestations recipient-owned, and registries the shared source of truth; resolvers are enforced with a hot-potato request and witnesses, and encrypted payloads are gated by Seal object ownership.
