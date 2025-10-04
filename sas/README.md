English | [简体中文](./README.zh.md)

# SAS — Sui Attestation Service

SAS implements the attestation protocol on Sui. A `Schema` becomes a shared object when created with `new`, or after `new_with_resolver` + `share_schema`; each `Attestation` is an object owned by its recipient; two shared, version-gated registries index schemas and attestations. Data can live on-chain or in Walrus, optionally encrypted with Seal.

- Source: [`sources/`](./sources)
- Tests: [`tests/`](./tests)
- Reference resolvers: [`resolvers/`](./resolvers)
- Full API reference: [docs/reference/sas.md](../docs/reference/sas.md)

## Modules

| Module | Responsibility |
|--------|----------------|
| `sas::sas` | Facade: register schemas, attest, attest off-chain, attest/revoke through resolvers |
| `sas::schema` | `Schema`, `Resolver`, `ResolverBuilder`, `Request`, schema views, `SchemaCreated` event |
| `sas::attestation` | `Attestation` object, storage modes, Seal fields, integrity check, `AttestationCreated` event |
| `sas::schema_registry` | Shared registry of schemas with version gating |
| `sas::attestation_registry` | Shared registry of attestation status with version gating |
| `sas::admin` | `Admin` capability bound to a schema; required to revoke |
| `sas::constants` | `CURRENT_VERSION` used by both registries |
| `sas::seal_access` | Seal key-id derivation and recipient-only `seal_approve` |

## Object model

- `Schema` is created by `schema::new` (shared immediately) or `new_with_resolver` (returned to the caller, who must call `share_schema` after configuring the resolver).
- `Admin` is an owned capability created with the schema and transferred to the creator. Revocation requires it.
- `Attestation` is an owned object transferred to the recipient. The event carries the recipient; the struct itself does not.
- `SchemaRegistry` and `AttestationRegistry` are shared objects created by their module initializers when the package is published. Each keeps `allowed_versions` inside a `Versioned` container.

## Storage modes

| `storage_type` | Value | Fields |
|----------------|-------|--------|
| On-chain | `0` | `data`; Walrus/Seal fields empty |
| Walrus | `1` | `walrus_sui_object_id`, `walrus_blob_id`, `data_hash`, `encrypted`, `seal_nonce`, `seal_policy_id`; `data` empty |

`attestation::verify_data_integrity` computes `blake2b256(data)` and compares it with `data_hash`; it aborts for on-chain attestations.

Expiration times are Unix milliseconds (`Clock::timestamp_ms`); `0` means no expiration.

## Entry points

SAS exposes public (non-`entry`) functions that compose with other Move code; typical transactions call them directly.

| Function | Purpose |
|----------|---------|
| `sas::register_schema(registry, schema, name, description, url, revokable, ctx)` | Create and share a schema; returns `Admin` |
| `sas::register_schema_with_resolver(registry, schema, name, description, url, revokable, ctx)` | Create a schema plus `ResolverBuilder`; caller configures and shares it |
| `sas::attest(schema, registry, ref_attestation, recipient, expiration_time, data, name, description, url, clock, ctx)` | Issue an on-chain attestation |
| `sas::attest_multi(...)` | Issue a batch of on-chain attestations |
| `sas::attest_off_chain(schema, registry, ref_attestation, recipient, expiration_time, walrus_sui_object_id, walrus_blob_id, data_hash, encrypted, seal_nonce, seal_policy_id, name, description, url, clock, ctx)` | Issue a Walrus-backed attestation |
| `sas::attest_with_resolver(...)` | Finish a resolver request and issue an attestation |
| `sas::revoke(admin, registry, schema, attestation, ctx)` | Revoke an attestation (no resolver) |
| `sas::revoke_multi(...)` | Revoke a batch |
| `sas::revoke_with_resolver(..., request, ctx)` | Finish a resolver request and revoke |

A non-zero `ref_attestation` must already exist in the attestation registry.

## Resolver flow

Sui resolvers use a hot-potato `Request`. Setup and issuance happen in separate transactions:

```move
// Transaction 1 — create and configure the schema, then share it.
let (mut builder, _admin, mut schema) =
    sas::register_schema_with_resolver(registry, schema_bytes, name, description, url, true, ctx);
whitelist::add(&schema, &mut builder, ctx);   // rules, config, resolver address and module
schema::add_resolver(&mut schema, builder);
schema::share_schema(schema);

// Transaction 2 — obtain approvals, then issue through the resolver.
let mut request = schema::start_attest(&schema);
whitelist::approve(&schema, &mut request, ctx);          // request.approve(witness)
sas::attest_with_resolver(
    &mut schema, registry, ref_attestation, recipient, expiration_time,
    data, name, description, url, clock, request, ctx,
);                                                        // finish_attest runs inside
```

`schema::finish_attest` is also public, but it consumes the `Request`; `attest_with_resolver` already performs the rule check and is the intended entry point. Revocation follows the same pattern with `start_revoke` and `revoke_with_resolver`.

Each schema has an optional `Resolver` with `rules`, a typed `config: Bag`, `resolver_address`, and `resolver_module`. Reference implementations are [`whitelist`](./resolvers/sources/whitelist.move) and [`blocklist`](./resolvers/sources/blocklist.move).

## Events

| Event | Fields |
|-------|--------|
| `schema::SchemaCreated` | `event_type` (0 = plain, 1 = with resolver), `schema_address, name, description, url, creator, created_at, schema, revokable, admin_cap`. `admin_cap` is `@0x0` for type 0 and the Admin object address for type 1 |
| `attestation::AttestationCreated` | `event_type` (0 = attest, 1 = with resolver; off-chain issuance also uses 0), `id, schema, ref_attestation, time, expiration_time, revokable, attestor, recipient, storage_type, data, walrus_sui_object_id, walrus_blob_id, data_hash, encrypted, seal_nonce, seal_policy_id, name, description, url` |

## Seal access control

`seal_access::compute_key_id(attestor, nonce)` returns `bcs(attestor) ‖ nonce`; the full Seal identity is `[package id][attestor][nonce]`. `seal_approve(id, attestation)` is an entry function that succeeds only when the attestation is encrypted, its nonce matches, and the caller owns the attestation object — Sui's object ownership guarantees that only the recipient can present it to a key server.

## Versioning

Both registries store `allowed_versions` and check `constants::current_version()` on every load. `update_allowed_versions` itself performs that check, so the new version must be authorized **before** the upgrade:

1. With the old package live, call `schema_registry::update_allowed_versions` and `attestation_registry::update_allowed_versions` with the old and new versions (using the admin caps).
2. Bump `CURRENT_VERSION`.
3. Publish the upgrade.

Publishing before step 1 leaves every registry call aborting with `EVersionNotEnabled`, including the update itself.

## Errors

Selected codes: `schema` — `EWrongSchemaAddress` (0), `ENoResolver` (1), `EMustBeFinishRequest` (2), `ERuleNotApproved` (3); `attestation_registry` — `EAttestationNotFound` (0), `EVersionNotEnabled` (1), `EAttestationAlreadyRevoked` (2), `ENotBelongToSchema` (3), `ENotRevokable` (4); `schema_registry` — `EVersionNotEnabled` (0), `ESchmaAlreadyExist` (1); `seal_access` — `ENoAccess` (0).

## Known limitations

- `admin::new` is public and unguarded, so anyone can mint an `Admin` for an arbitrary schema. Revocation and resolver administration are **not** protected by the capability in this revision. See [Security model](../docs/security-model.md#1-sas-admin-is-an-unauthenticated-bearer-capability).
- Off-chain issuance cannot use a resolver (`attest_off_chain` rejects resolver schemas), and there are no resolver variants of the batch functions.
- The stored `data_hash` is supplied by the caller; only the opt-in `verify_data_integrity` view checks it.
- Revocation emits no event; only `AttestationRegistry::is_revoked` is readable from Move.

## Build and test

```bash
cd sas
sui move test
```

## Deploy

```bash
cd sas
sui client publish --gas-budget 100000000
```

Publishing runs both registry initializers and transfers the registry admin caps to the publisher. Record the package ID, `SchemaRegistry` ID, and `AttestationRegistry` ID; `Published.toml` keeps the package metadata. See [docs/deployment.md](../docs/deployment.md).

Keep public function signatures and struct layouts upgrade-compatible.

## License

Business Source License 1.1 — see [LICENSE](../LICENSE).
