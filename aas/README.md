English | [简体中文](./README.zh.md)

# AAS — Aptos Attestation Service

AAS implements the attestation protocol on Aptos. Schemas and attestations are **named objects** created by a protocol-owned object signer, so their addresses are deterministic functions of their contents and creation parameters. Attestations are stored on-chain or referenced off-chain through [Shelby](https://shelby.xyz/), and optional resolvers validate issuance and revocation.

- Source: [`sources/`](./sources)
- Tests: [`tests/`](./tests)
- Example resolver: [`resolver_example/`](./resolver_example)
- Full API reference: [docs/reference/aas.md](../docs/reference/aas.md)

## Modules

| Module | Responsibility |
|--------|----------------|
| `aas::aas` | Entry points: create schemas, issue/revoke attestations, batch operations |
| `aas::schema` | `Schema` object, schema address derivation, schema views and `SchemaCreated` event |
| `aas::attestation` | `Attestation` object, storage modes, integrity checks, address derivation, events |
| `aas::package_manager` | Protocol object signer (`ExtendRef`) used to create all named objects |
| `aas::resolver_dispatcher` | Dispatches attest/revoke validation to a resolver module |
| `aas::resolver_storage` | Stores resolver metadata and serialized request data between modules |

## Object model

At publish time `package_manager::init_module` creates an object owned by the package account and stores its `ExtendRef` in `PermissionConfig` at `@aas`. Every schema and attestation is a named object created with that object's signer:

```text
schema_seed      = keccak256(bcs(name) ‖ bcs(description) ‖ bcs(url) ‖ bcs(revokable) ‖ bcs(resolver) ‖ schema_bytes)
attestation_seed = keccak256(bcs(attestor) ‖ bcs(schema) ‖ bcs(recipient) ‖ bcs(ref_attestation)
                             ‖ bcs(expiration_time) ‖ bcs(revokable) ‖ bcs(now) ‖ data)
```

Off-chain attestations append `data_hash ‖ bcs(shelby_account) ‖ bcs(shelby_blob_name)` instead of `data`. The final address is `object::create_object_address(package_manager_signer, seed)`, exposed by the `get_*_address` views.

Because `now` is part of the seed, the same parameters produce different addresses in different seconds and collide within the same second.

## Storage modes

| `storage_type` | Value | On-chain fields | Off-chain fields |
|----------------|-------|-----------------|------------------|
| On-chain | `0` | `data` populated, `data_hash` empty | Shelby fields empty / zero |
| Shelby | `1` | `data` empty | `data_hash`, `shelby_account`, `shelby_blob_name`, `shelby_blob_merkle_root`, `shelby_register_tx_hash` |

`attestation::verify_data_integrity(address, data)` recomputes `blake2b_256(data)` and compares it with `data_hash`; it returns `false` for on-chain attestations.

## Entry functions

| Function | Purpose |
|----------|---------|
| `aas::create_schema(creator, schema, name, description, url, revokable, resolver)` | Create a schema named object and emit `SchemaCreated` |
| `aas::create_attestation(attestor, recipient, schema, ref_attestation, expiration_time, revokable, data)` | Issue an on-chain attestation |
| `aas::create_multi_attestations(attestor, recipients, schema, ref_attestations, expiration_times, revokable, data)` | Issue several attestations in one transaction |
| `aas::create_attestation_off_chain(attestor, recipient, schema, ref_attestation, expiration_time, revokable, data_hash, shelby_account, shelby_blob_name, shelby_blob_merkle_root, shelby_register_tx_hash)` | Issue an attestation referencing a Shelby blob |
| `aas::revoke_attestation(admin, schema, attestation)` | Revoke one attestation (schema creator only) |
| `aas::revoke_multi_attestations(admin, schemas, attestations)` | Revoke several attestations |

The `*_and_get_address` variants are public (non-entry) functions used by other Move code and tests.

## Views

Schemas: `schema_data`, `schema_unpacked`, `schema_creator`, `schema_revokable`, `schema_resolver`, `schema_exists`, `get_schema_address`, `get_schema_seeds`.

Attestations: `attestation_data`, `attestation_unpacked`, `attestation_exists`, `attestation_revoked`, `storage_type`, `data_hash`, `shelby_account`, `shelby_blob_name`, `verify_data_integrity`, `get_attestation_address`, `get_attestation_address_off_chain`, `get_attestation_seeds`, `get_attestation_seeds_off_chain`.

Resolver storage views: `is_initialized`, `dispatcher_metadata`, `dispatcher_is_exists`, `pack_attest_data`, `pack_revoke_data`, `unpack_attest_data`, `unpack_revoke_data`. `retrieve` is a plain public function (no `#[view]`), callable from resolver modules.

## Events

| Event | Fields |
|-------|--------|
| `schema::SchemaCreated` | `schema_address, name, description, url, creator, created_at, revokable, resolver, schema` |
| `attestation::AttestationCreated` | `attestation_address, schema, ref_attestation, time, expiration_time, revokable, attestor, recipient, storage_type, data, data_hash, shelby_account, shelby_blob_name, shelby_blob_merkle_root, shelby_register_tx_hash` |
| `attestation::AttestationRevoked` | `attestation_address, revocation_time` |

## Errors

`aas::aas` aborts with: `ESTRING_TOO_LONG` (1), `ENOT_SCHEMA_CREATOR` (2), `E_NOT_REVOKABLE` (3), `EATTESTATION_NOT_FOUND` (4), `EATTESTATION_ALREADY_REVOKED` (5), `EATTESTATIONS_NOT_EXIST_AT_ADDRESS` (6), `ESCHEMA_NOT_FOUND` (7), `ERESOLVE_FAILED` (8), `EINVALID_LENGTH` (9).

## Resolver integration

When a schema has a non-zero `resolver` address, `create_*` and `revoke_*` call `resolver_dispatcher` before writing state:

1. The dispatcher serializes the request into `resolver_storage` under the resolver module address.
2. It invokes the resolver's `public fun resolve<T: key>(_metadata: Object<T>): Option<u128>` through a dispatchable fungible asset.
3. The request succeeds only when the resolver returns `Some(0)` (`VERIFY_SUCCESS`).

The resolver must register itself by calling `resolver_dispatcher::register_dispatchable(publisher)` — typically from its `init_module`, as [`resolver_example`](./resolver_example/sources/schema_resolver.move) does. Registration is single-shot and keyed to the publisher's address; the callback names are hard-coded as `schema_resolver::resolve`. Before the first dispatch, someone must call the entry `resolver_storage::initialize()`; it is idempotent.

If `resolver_storage` is initialized but no dispatcher is registered for the configured address, the dispatcher treats the request as approved. If `initialize()` was never called, issuance and revocation abort while trying to read the missing `Dispatcher`.

<a id="known-behavior"></a>

## Known behavior

`create_attestation*` currently asserts that `ref_attestation` does **not** resolve to an existing attestation. In practice only `@0x0` is safe to pass at this version; treat references as reserved until the check is revised.

## Build and test

```bash
cd aas
aptos move test
```

The package pins the Aptos framework revision in [`Move.toml`](./Move.toml); `Move.lock` records the resolved graph.

## Deploy

```bash
cd aas
aptos move publish --named-addresses aas=<your_address>
```

After publishing, call `resolver_storage::initialize()` once. To use a resolver, publish it and register its dispatchable callback. See [docs/deployment.md](../docs/deployment.md) for the full procedure.

Keep public function signatures and struct layouts compatible when upgrading; existing named-object addresses depend on the seed format above.

## License

Business Source License 1.1 — see [LICENSE](../LICENSE).
