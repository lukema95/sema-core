English | [简体中文](./sas.zh.md)

# SAS Module and API Reference

Reference for the Sui Attestation Service package in [`sas/`](../../sas). For design context see [SAS architecture](../sas/architecture.md); for end-to-end flows see [SAS flows](../sas/flows.md).

Source files: [`sas.move`](../../sas/sources/sas.move), [`schema.move`](../../sas/sources/schema.move), [`attestation.move`](../../sas/sources/attestation.move), [`schema_registy.move`](../../sas/sources/schema_registy.move) (module `sas::schema_registry`), [`attestation_registry.move`](../../sas/sources/attestation_registry.move), [`admin.move`](../../sas/sources/admin.move), [`constants.move`](../../sas/sources/constants.move), [`seal_access.move`](../../sas/sources/seal_access.move).

## Module map

| Module | Public surface |
|--------|----------------|
| `sas::sas` | Facade for schema registration, attestation, and revocation |
| `sas::schema` | `Schema`, resolver configuration, hot-potato `Request` |
| `sas::attestation` | `Attestation` object, storage modes, integrity check |
| `sas::schema_registry` | Shared schema index with version gating |
| `sas::attestation_registry` | Shared attestation status index with version gating |
| `sas::admin` | Schema-bound `Admin` capability |
| `sas::constants` | `CURRENT_VERSION` |
| `sas::seal_access` | Seal key-id computation and `seal_approve` |

## `sas::sas`

### Functions

```move
public fun register_schema(
    schema_registry: &mut SchemaRegistry, schema: vector<u8>, name: vector<u8>,
    description: vector<u8>, url: vector<u8>, revokable: bool, ctx: &mut TxContext,
): Admin

public fun register_schema_with_resolver(
    schema_registry: &mut SchemaRegistry, schema: vector<u8>, name: vector<u8>,
    description: vector<u8>, url: vector<u8>, revokable: bool, ctx: &mut TxContext,
): (ResolverBuilder, Admin, Schema)

public fun attest(
    schema_record: &mut Schema, attestation_registry: &mut AttestationRegistry,
    ref_attestation: address, recipient: address, expiration_time: u64,
    data: vector<u8>, name: vector<u8>, description: vector<u8>, url: vector<u8>,
    time: &Clock, ctx: &mut TxContext,
): address

public fun attest_multi(...)

public fun attest_off_chain(
    schema_record: &mut Schema, attestation_registry: &mut AttestationRegistry,
    ref_attestation: address, recipient: address, expiration_time: u64,
    walrus_sui_object_id: address, walrus_blob_id: vector<u8>, data_hash: vector<u8>,
    encrypted: bool, seal_nonce: Option<vector<u8>>, seal_policy_id: Option<address>,
    name: vector<u8>, description: vector<u8>, url: vector<u8>,
    time: &Clock, ctx: &mut TxContext,
): address

public fun attest_with_resolver(..., request: Request, ...): address
public fun revoke(admin: &Admin, attestation_registry: &mut AttestationRegistry,
                  schema_record: &Schema, attestation: address, ctx: &mut TxContext)
public fun revoke_multi(...)
public fun revoke_with_resolver(..., request: Request, ...)
```

Behavior details:

- `attest` rejects schemas that have a resolver (`EHasResolver`).
- A non-zero `ref_attestation` must exist in the attestation registry (`ERefIdNotFound`).
- A non-zero `expiration_time` must be greater than `clock.timestamp_ms()` (`EExpired`).
- Expiration values are milliseconds.
- `revokable` is copied from the schema, not chosen by the attestor.

### Errors

| Constant | Code | Condition |
|----------|------|-----------|
| `EExpired` | 0 | `expiration_time` is in the past |
| `ERefIdNotFound` | 1 | Referenced attestation is not registered |
| `EHasResolver` | 2 | Plain call used on a resolver schema (or the reverse) |
| `EInvalidLength` | 3 | Batch vectors have different lengths |

## `sas::schema`

### Structs

`Schema` (`key, store`): `id: UID`, `name: String`, `description: String`, `url: Url`, `creator: address`, `created_at: u64`, `schema: vector<u8>`, `revokable: bool`, `resolver: Option<Resolver>`.

`Resolver` (`store`): `rules: VecMap<String, VecSet<TypeName>>`, `config: Bag`, `resolver_address: address`, `resolver_module: vector<u8>`.

`ResolverBuilder` (`store`): `schema_address`, `resolver_address`, `resolver_module`, `rules`, `config: Bag`.

`Request` (hot potato, no abilities): `name: String`, `schema_address: address`, `approvals: VecSet<TypeName>`.

### Event

`SchemaCreated`:

```text
event_type, schema_address, name, description, url, creator, created_at,
schema, revokable, admin_cap
```

`event_type` is `0` for `new` and `1` for `new_with_resolver`. `admin_cap` is `@0x0` for the plain path.

### Lifecycle functions

| Function | Purpose |
|----------|---------|
| `new(registry, schema, name, description, url, revokable, ctx): Admin` | Create and share a schema, return the admin cap |
| `new_with_resolver(...): (ResolverBuilder, Admin, Schema)` | Create a schema without sharing; caller configures and shares |
| `share_schema(schema)` | Share a schema created by `new_with_resolver` |
| `add_resolver(schema, builder)` | Attach the configured resolver to the schema |
| `new_resolver_builder(admin, schema, ctx)` | Start a resolver configuration |
| `add_resolver_address(builder, address)` / `add_resolver_module(builder, bytes)` | Set the resolver target |
| `add_rule<Rule: drop>(builder, name, witness)` | Require a witness for a request type |
| `add_rule_config<Rule: drop, Config: store>(builder, witness, config)` | Attach typed configuration |
| `start_attest(schema): Request` / `start_revoke(schema): Request` | Begin a resolver request |
| `finish_attest(schema, request)` / `finish_revoke(schema, request)` | Check all rules approved and consume the request |
| `approve<Rule: drop>(request, witness)` | Record a resolver approval |
| `config<Rule, Config>(schema): &Config` / `config_mut<Rule, Config>(schema): &mut Config` | Read/write typed config |

### Views

`schema`, `name`, `description`, `url`, `created_at`, `creator`, `revokable`, `addy`, `has_resolver`, `resolver_address`, `resolver_module`, `get_resolver_address`, `start_attest_name`, `start_revoke_name`, `schema_address_from_request`, `request_name`, `approvals`, `schema_address_from_builder`, `rules`, `config_from_builder`.

### Errors

| Constant | Code | Condition |
|----------|------|-----------|
| `EWrongSchemaAddress` | 0 | Builder/request belongs to another schema |
| `ENoResolver` | 1 | Resolver-only function used on a plain schema |
| `EMustBeFinishRequest` | 2 | Request type does not match the finish call |
| `ERuleNotApproved` | 3 | A required rule was not approved |

## `sas::attestation`

### Struct

`Attestation` (`key`): `id: UID`, `schema`, `ref_attestation`, `time`, `expiration_time`, `revokable`, `attestor`, `storage_type`, `data`, `walrus_sui_object_id`, `walrus_blob_id`, `data_hash`, `encrypted`, `seal_nonce`, `seal_policy_id`, `name`, `description`, `url`.

There is no `recipient` field: ownership is expressed by transferring the object.

### Events

`AttestationCreated`:

```text
event_type, id, schema, ref_attestation, time, expiration_time, revokable,
attestor, recipient, storage_type, data, walrus_sui_object_id, walrus_blob_id,
data_hash, encrypted, seal_nonce, seal_policy_id, name, description, url
```

`event_type` is `0` for `attest` and `1` for `attest_with_resolver`.

### Views

| Function | Returns |
|----------|---------|
| `schema`, `ref_attestation`, `attestor`, `time`, `revokable`, `expiration_time` | Scalar field accessors |
| `storage_type` | `u8` |
| `is_on_chain_storage`, `is_off_chain_storage` | `bool` |
| `data` | On-chain payload; empty for off-chain |
| `data_hash` | `Option<vector<u8>>` for off-chain |
| `walrus_sui_object_id`, `walrus_blob_id` | `Option<...>` for off-chain |
| `seal_nonce`, `seal_policy_id` | `Option<...>` for encrypted off-chain |
| `is_encrypted` | `bool` |
| `verify_data_integrity(attestation, data)` | `bool`; asserts off-chain storage |
| `name`, `description`, `url` | Metadata |

`verify_data_integrity` compares `hash::blake2b256(data)` with `data_hash`.

## `sas::schema_registry`

`SchemaRegistry` (`key, store`) wraps a `Versioned` containing `allowed_versions: VecSet<u64>` and `schema_records: Table<address, address>`.

| Function | Purpose |
|----------|---------|
| `update_allowed_versions(admin_cap, registry, versions)` | Replace the allowed version set |
| `is_exist(registry, schema): bool` | Whether a schema is registered |
| `schemas(registry): &Table<address, address>` | Schema → creator |
| `creator(registry, schema): &address` | Creator lookup |
| `size(registry): u64` | Number of schemas |

Errors: `EVersionNotEnabled` (0), `ESchmaAlreadyExist` (1).

## `sas::attestation_registry`

`AttestationRegistry` (`key, store`) wraps `Versioned` containing `allowed_versions` and `attestations_status: Table<address, Status>`.

`Status` (`copy, store`): `schema_address: address`, `is_revoked: bool`, `timestamp: u64`.

| Function | Purpose |
|----------|---------|
| `update_allowed_versions(admin_cap, registry, versions)` | Replace the allowed version set |
| `is_exist(registry, attestation): bool` | Whether the attestation is indexed |
| `is_revoked(registry, attestation): bool` | Revocation status |
| `status(registry, attestation): &Status` | Full status |
| `attestations(registry): &Table<address, Status>` | Full index |

Errors: `EAttestationNotFound` (0), `EVersionNotEnabled` (1), `EAttestationAlreadyRevoked` (2), `ENotBelongToSchema` (3), `ENotRevokable` (4).

## `sas::admin`

`Admin` (`key, store`): `id: UID`, `schema: address`.

Functions: `addy`, `schema`, `assert_schema(admin, schema)`, `destroy(admin)`, `new(schema, ctx)` (package-only use).

## `sas::constants`

`CURRENT_VERSION: u64 = 1`; `current_version(): u64`.

## `sas::seal_access`

| Function | Purpose |
|----------|---------|
| `compute_key_id(attestor, nonce): vector<u8>` | `bcs(attestor) ‖ nonce` |
| `seal_approve(id, attestation)` (entry) | Verify the key id and encryption metadata; abort with `ENoAccess` (0) otherwise |

The full Seal identity is `[package id][attestor][nonce]`. Only the owner of the attestation object can pass `&Attestation` to `seal_approve`, which binds decryption rights to the recipient.

## Reference resolvers (`sas/resolvers`)

`resolvers::whitelist` and `resolvers::blocklist` implement the resolver pattern:

- `add(schema, builder, ctx)` registers the resolver address/module, requires the `START_ATTEST`/`START_REVOKE` rules, and stores a `Table<address, bool>` config.
- `approve(schema, request, ctx)` checks the caller against the list and approves the rule.
- `add_user` / `remove_user` mutate the config (admin only).
- Views: `is_whitelisted`, `is_blocklisted`.

## Compatibility notes

- `schema_registy.move` is the file that defines `sas::schema_registry`; the filename is a historical typo and does not affect the ABI.
- Registry version gating requires pre-authorizing the next version before every package upgrade; `update_allowed_versions` itself runs through the same check.
- Struct field order and public signatures are part of the upgrade compatibility check.
