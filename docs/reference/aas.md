English | [简体中文](./aas.zh.md)

# AAS Module and API Reference

Reference for the Aptos Attestation Service package in [`aas/`](../../aas). For design context see [AAS architecture](../aas/architecture.md); for end-to-end flows see [AAS flows](../aas/flows.md).

Source files: [`aas.move`](../../aas/sources/aas.move), [`schema.move`](../../aas/sources/schema.move), [`attestation.move`](../../aas/sources/attestation.move), [`package_manager.move`](../../aas/sources/package_manager.move), [`resolver_dispatcher.move`](../../aas/sources/resolver/resolver_dispatcher.move), [`resolver_storage.move`](../../aas/sources/resolver/resolver_storage.move).

## Module map

| Module | Public surface |
|--------|----------------|
| `aas::aas` | Entry points for schema and attestation lifecycle |
| `aas::schema` | Schema object, events, address and seed derivation |
| `aas::attestation` | Attestation object, events, storage and integrity views |
| `aas::package_manager` | Object signer used to derive all named objects |
| `aas::resolver_dispatcher` | Resolver registration and dispatch |
| `aas::resolver_storage` | Serialized request storage shared with resolvers |

## `aas::aas`

### Entry functions

```move
public entry fun create_schema(
    creator: &signer,
    schema: vector<u8>,
    name: String,
    description: String,
    url: String,
    revokable: bool,
    resolver: address,
)

public entry fun create_attestation(
    attestor: &signer,
    recipient: address,
    schema_addr: address,
    ref_attestation: address,
    expiration_time: u64,
    revokable: bool,
    data: vector<u8>,
)

public entry fun create_multi_attestations(
    attestor: &signer,
    recipients: vector<address>,
    schema_addr: address,
    ref_attestations: vector<address>,
    expiration_times: vector<u64>,
    revokable: bool,
    data: vector<vector<u8>>,
)

public entry fun create_attestation_off_chain(
    attestor: &signer,
    recipient: address,
    schema_addr: address,
    ref_attestation: address,
    expiration_time: u64,
    revokable: bool,
    data_hash: vector<u8>,
    shelby_account: address,
    shelby_blob_name: String,
    shelby_blob_merkle_root: vector<u8>,
    shelby_register_tx_hash: vector<u8>,
)

public entry fun revoke_attestation(
    admin: &signer,
    schema_addr: address,
    attestation: address,
)

public entry fun revoke_multi_attestations(
    admin: &signer,
    schema_addr: vector<address>,
    attestations: vector<address>,
)
```

String limits enforced by `create_schema`: `name < 128`, `description < 512`, `url < 512` bytes.

### Public helpers

The `*_and_get_address` variants return the derived address and are used by tests and other Move code:

- `create_schema_and_get_schema_address`
- `create_attestation_and_get_address`
- `create_attestation_off_chain_and_get_address`

### Errors

| Constant | Code | Condition |
|----------|------|-----------|
| `ESTRING_TOO_LONG` | 1 | Name/description/url exceeds its limit |
| `ENOT_SCHEMA_CREATOR` | 2 | Revoker is not the schema creator |
| `E_NOT_REVOKABLE` | 3 | Schema is not revokable |
| `EATTESTATION_NOT_FOUND` | 4 | Attestation object does not exist |
| `EATTESTATION_ALREADY_REVOKED` | 5 | Attestation already revoked |
| `EATTESTATIONS_NOT_EXIST_AT_ADDRESS` | 6 | `ref_attestation` currently must not exist (see note) |
| `ESCHEMA_NOT_FOUND` | 7 | Schema object does not exist |
| `ERESOLVE_FAILED` | 8 | Resolver returned a non-zero value or no value |
| `EINVALID_LENGTH` | 9 | Batch vectors have different lengths |

> **Reference note:** `create_attestation` and `create_attestation_off_chain` assert `!attestation::attestation_exists(ref_attestation)`. As implemented, only `@0x0` is safe. The check is expected to be revised; do not build production flows on references until then.

## `aas::schema`

### Structs

`Schema` (`key`):

| Field | Type | Notes |
|-------|------|-------|
| `name` | `String` | |
| `description` | `String` | |
| `url` | `String` | |
| `creator` | `address` | |
| `created_at` | `u64` | Seconds |
| `schema` | `vector<u8>` | Opaque schema payload |
| `revokable` | `bool` | |
| `resolver` | `address` | `@0x0` means no resolver |
| `tx_hash` | `vector<u8>` | Reserved; currently empty |

`SchemaData` mirrors the fields for the `schema_data` view.

### Event

`SchemaCreated`:

```text
schema_address, name, description, url, creator, created_at, revokable, resolver, schema
```

### Views

| Function | Returns |
|----------|---------|
| `schema_data(address)` | `SchemaData` |
| `schema_unpacked(address)` | `(String, String, String, address, u64, vector<u8>, bool, address)` |
| `schema_creator(address)` | `address` |
| `schema_revokable(address)` | `bool` |
| `schema_resolver(address)` | `address` |
| `schema_exists(address)` | `bool` |
| `get_schema_address(name, description, url, revokable, resolver, schema)` | `address` |
| `get_schema_seeds(name, description, url, revokable, resolver, schema)` | `vector<u8>` |

### Seed derivation

```text
seed = keccak256(
    bcs(name) ‖ bcs(description) ‖ bcs(url) ‖ bcs(revokable) ‖ bcs(resolver) ‖ schema
)
address = object::create_object_address(package_manager_signer, seed)
```

## `aas::attestation`

### Structs

`Attestation` (`key`):

| Field | Type | Notes |
|-------|------|-------|
| `schema` | `address` | Schema object address |
| `ref_attestation` | `address` | Reserved reference |
| `time` | `u64` | Seconds |
| `expiration_time` | `u64` | Seconds; `0` = never |
| `revocation_time` | `u64` | `0` until revoked |
| `revokable` | `bool` | Copied from the schema at issuance |
| `attestor` | `address` | |
| `recipient` | `address` | |
| `storage_type` | `u8` | `0` on-chain, `1` Shelby |
| `data` | `vector<u8>` | On-chain payload |
| `data_hash` | `vector<u8>` | Blake2b-256 for off-chain |
| `shelby_account` | `address` | Shelby account |
| `shelby_blob_name` | `String` | Shelby blob name |
| `shelby_blob_merkle_root` | `vector<u8>` | Shelby registration metadata |
| `shelby_register_tx_hash` | `vector<u8>` | Shelby registration transaction hash |

`AttestationData` mirrors all fields for the `attestation_data` view.

### Events

`AttestationCreated`:

```text
attestation_address, schema, ref_attestation, time, expiration_time, revokable,
attestor, recipient, storage_type, data, data_hash, shelby_account,
shelby_blob_name, shelby_blob_merkle_root, shelby_register_tx_hash
```

`AttestationRevoked`:

```text
attestation_address, revocation_time
```

### Views

| Function | Returns |
|----------|---------|
| `attestation_data(address)` | `AttestationData` |
| `attestation_unpacked(address)` | 15-tuple: `(schema, ref, time, expiration, revocation, revokable, attestor, recipient, storage_type, data, data_hash, shelby_account, shelby_blob_name, merkle_root, register_tx_hash)` |
| `attestation_exists(address)` | `bool` |
| `attestation_revoked(address)` | `bool` (`revocation_time != 0`) |
| `storage_type(address)` | `u8` |
| `data_hash(address)` | `vector<u8>` |
| `shelby_account(address)` | `address` |
| `shelby_blob_name(address)` | `String` |
| `verify_data_integrity(address, data)` | `bool`; false for on-chain attestations |
| `get_attestation_address(attestor, schema, recipient, ref_id, expiration_time, revokable, now, data)` | `address` |
| `get_attestation_address_off_chain(attestor, schema, recipient, ref_id, expiration_time, revokable, now, data_hash, shelby_account, shelby_blob_name)` | `address` |
| `get_attestation_seeds(...)` | `vector<u8>` |
| `get_attestation_seeds_off_chain(...)` | `vector<u8>` |

### Seed derivation

On-chain:

```text
seed = keccak256(
    bcs(attestor) ‖ bcs(schema) ‖ bcs(recipient) ‖ bcs(ref_id) ‖ bcs(expiration_time)
    ‖ bcs(revokable) ‖ bcs(now) ‖ data
)
```

Off-chain replaces the trailing `data` with:

```text
data_hash ‖ bcs(shelby_account) ‖ bcs(shelby_blob_name)
```

`now` is `timestamp::now_seconds()` at creation. The view helpers take `now` explicitly so callers can reproduce the address.

## `aas::package_manager`

Creates the protocol object signer at publish time:

```move
fun init_module(signer: &signer) {
    let construct_ref = object::create_object(signer::address_of(signer));
    let extend_ref = object::generate_extend_ref(&construct_ref);
    move_to(signer, PermissionConfig { extend_ref, addressess: table::new() });
}
```

| Function | Visibility | Purpose |
|----------|-----------|---------|
| `get_signer()` | `public(friend)` | Object signer for named-object creation |
| `get_signer_address()` | `public(friend)` | Signer address used in seed derivation |
| `add_address(name, object)` | `public(friend)` | Reserved bookkeeping table |
| `address_exists(name)` | `public` | Reserved bookkeeping table |
| `get_address(name)` | `public` | Reserved bookkeeping table |

## `aas::resolver_dispatcher`

```move
public fun on_attest(module_address, attestor, recipient, schema_address,
                     ref_attestation, expiration_time, revokable, data): bool
public fun on_revoke(module_address, revoker, schema_address, attestation): bool
public fun register_dispatchable(signer: &signer)
```

Behavior:

- If `resolver_storage::dispatcher_is_exists(module_address)` is false, the request is treated as approved (`true`).
- Otherwise the dispatcher packs the request into `resolver_storage`, invokes the resolver's `resolve` through a dispatchable fungible asset, and returns `true` only for `option::some(VERIFY_SUCCESS)`, where `VERIFY_SUCCESS = 0`.
- `register_dispatchable` creates a fungible metadata object named `resolver`/`dispatch` whose derived-supply dispatch function is `schema_resolver::resolve` at the signer's address.

## `aas::resolver_storage`

`Dispatcher` holds `dispatcher: Table<address, Object<Metadata>>` and `data: Table<address, vector<u8>>` at the package-manager signer address.

| Function | Visibility | Purpose |
|----------|-----------|---------|
| `initialize()` | `entry` | Idempotently create `Dispatcher` |
| `is_initialized()` | `view` | Whether `Dispatcher` exists |
| `retrieve(module_address)` | `public` | Read the serialized request |
| `dispatcher_metadata(signer_address)` | `view` | Metadata object for a resolver |
| `dispatcher_is_exists(signer_address)` | `view` | Whether a resolver is registered |
| `pack_attest_data(...)` / `pack_revoke_data(...)` | `view` | Serialize a request |
| `unpack_attest_data(data)` | `view` | Decode an attest request |
| `unpack_revoke_data(data)` | `view` | Decode a revoke request |

Serialized layout — attest: `type(0) ‖ attestor(32) ‖ recipient(32) ‖ schema(32) ‖ ref(32) ‖ expiration(8) ‖ revokable(1) ‖ data`; revoke: `type(1) ‖ revoker(32) ‖ schema(32) ‖ attestation(32)`.

`E_DISPATCHER_NOT_FOUND = 1` is raised when a resolver or request entry is missing.

## Compatibility notes

- Seed inputs and ordering are consensus-critical: changing them changes every schema and attestation address.
- Struct field order and types are part of the upgrade compatibility check.
- Event field names and order are consumed by indexers.
- `package_manager` object signer must remain stable across upgrades.
