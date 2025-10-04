English | [简体中文](./architecture.zh.md)

# SAS Architecture Design

## 1. Design Goals

SAS provides a set of "verifiable claim" primitives on Sui that at the same time satisfy:

1. **Discoverable**: a global Registry can answer "does this attestation exist / has it been revoked?"
2. **Ownable**: the recipient truly owns the Attestation object (NFT-style ownership)
3. **Extensible**: Resolver plugs in custom issue/revoke rules
4. **Upgradeable**: Registry uses a Versioned object for version gating
5. **Private**: off-chain Walrus + Seal threshold decryption, with the access policy written on-chain

## 2. Layered Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    sas::sas (Facade)                    │
│  register_schema / attest / attest_off_chain / revoke   │
└────────────┬──────────────────────────────┬─────────────┘
             │                              │
             ▼                              ▼
┌────────────────────────┐       ┌────────────────────────┐
│     sas::schema        │       │   sas::attestation     │
│  Shared Schema object  │       │  Owned Attestation     │
│  Resolver + Request    │       │  on-chain / Walrus     │
└────────────┬───────────┘       └────────────┬───────────┘
             │                                │
             ▼                                ▼
┌────────────────────────┐       ┌────────────────────────┐
│  schema_registry       │       │ attestation_registry   │
│  Table<schema, creator>│       │ Table<att, Status>     │
│  Versioned inner       │       │ Versioned inner        │
└────────────────────────┘       └────────────────────────┘
             │
             ▼
┌────────────────────────┐       ┌────────────────────────┐
│     sas::admin         │       │   sas::seal_access     │
│  Admin { schema } cap  │       │  seal_approve entry    │
└────────────────────────┘       └────────────────────────┘
```

`sas.move` itself stores almost no state; it only validates parameters and dispatches work to the individual modules. This is a classic Facade.

## 3. Object Ownership Model

Sui's security boundary is ownership. SAS separates three kinds of objects:

```
Shared                          Owned
──────                          ─────
Schema                          Attestation  → recipient
SchemaRegistry                  Admin        → schema creator
AttestationRegistry             SchemaRegistryAdminCap
                                AttestationRegistryAdminCap
```

| Object | Abilities | Why it is designed this way |
|------|------|----------------|
| `Schema` | `key + store`, `share_object` | `new` shares it immediately; `new_with_resolver` returns it owned and the creator must call `share_schema` before others can attest |
| `Attestation` | `key` only, `transfer` to the recipient | Only the recipient can put it into a transaction (Seal, display, transfer) |
| `Admin` | `key + store` | Intended to be transferable; **currently forgeable via the public `admin::new`**, see [Security model](../security-model.md#1-sas-admin-is-an-unauthenticated-bearer-capability) |
| Registry | Shared + Versioned | Global index; upgrades change `allowed_versions` |

Note that `Attestation` **has no `store`**, so it cannot be placed inside other objects and can only circulate as a top-level owned object. This reduces the risk of "hiding a proof inside another structure to bypass ownership checks".

## 4. Core Data Structures

### 4.1 Schema

```move
public struct Schema has key, store {
    id: UID,
    name: String,
    description: String,
    url: Url,
    creator: address,
    created_at: u64,
    schema: vector<u8>,      // encoding template, not parsed by the contract
    revokable: bool,
    resolver: Option<Resolver>
}
```

The contract treats `schema: vector<u8>` as opaque bytes. Type validation happens in the SDK `Codec` layer. On-chain, only the governance fields matter: `revokable` and `resolver`.

### 4.2 Attestation

```move
public struct Attestation has key {
    id: UID,
    schema: address,
    ref_attestation: address,   // 0x0 means no reference
    time: u64,
    expiration_time: u64,       // 0 means never expires
    revokable: bool,            // copied from the Schema, immutable after issuance
    attestor: address,
    storage_type: u8,           // 0 on-chain / 1 off-chain
    data: vector<u8>,           // only populated for on-chain
    walrus_sui_object_id: address,
    walrus_blob_id: vector<u8>,
    data_hash: vector<u8>,      // Blake2b-256
    encrypted: bool,
    seal_nonce: Option<vector<u8>>,
    seal_policy_id: Option<address>,
    name: String,
    description: String,
    url: Url,
}
```

A single object holds both storage modes, distinguished by `storage_type`. In on-chain mode the off-chain fields are zero-filled so the BCS layout stays stable and indexer-friendly.

**Revocation does not write to this object.** The state lives in the Registry's `Status.is_revoked`. Reason: the Attestation belongs to the recipient, so the schema admin has no `&mut Attestation` and cannot modify the recipient's object. Only modeling revocation as "a mark on a globally shared ledger" is consistent with ownership.

### 4.3 Registry Inner

```move
public struct RegistryInner has store {
    allowed_versions: VecSet<u64>,
    attestations_status: Table<address, Status>,
}

public struct Status has copy, store {
    schema_address: address,
    is_revoked: bool,
    timestamp: u64,            // revocation time
}
```

`AttestationRegistry` / `SchemaRegistry` are wrapped in a layer of `sui::versioned::Versioned`. Every read and write does:

1. `load_value(_mut)`
2. `assert!(allowed_versions.contains(&constants::current_version()))`

`update_allowed_versions` uses the same loader, so it can only run while the **current** version is allowed. The new version must be pre-authorized before the upgrade: with v1 live, add `2` to both registries; then bump `CURRENT_VERSION` and publish. Doing it the other way round locks every registry call with `EVersionNotEnabled`.

## 5. Storage Architecture

```
                    ┌─ storage_type = 0 ─► data stored in the object
Attestation object ─┤
                    └─ storage_type = 1 ─► data empty
                                           walrus_* + data_hash on-chain
                                           blob on Walrus
                                           optional Seal ciphertext
```

| | On-chain | Off-chain (Walrus) |
|--|----------|--------------------|
| Data location | `Attestation.data` | Walrus blob |
| On-chain anchor | the data itself | caller-supplied `data_hash` (conventionally blake2b256 of the plaintext) |
| Event | `AttestationCreated.data` carries the plaintext | data is empty in the event |
| Fit | small data, full transparency | large data, privacy, gas savings |
| Encryption | unsupported (`is_encrypted` always false) | Seal, nonce / policy recorded on the object |

Integrity verification:

```move
public fun verify_data_integrity(self: &Attestation, data: vector<u8>): bool {
    assert!(self.storage_type == STORAGE_TYPE_OFF_CHAIN, 0);
    hash::blake2b256(&data) == *&self.data_hash
}
```

**By convention the hash is taken over the plaintext before encryption.** The contract stores the hash exactly as supplied at issuance; it does not recompute or validate it. Clients must verify the downloaded payload themselves. Without this convention, there is no way to prove after decryption that "this is the same data that was issued".

Off-chain issuance cannot be combined with a resolver: `attest_off_chain` asserts that the schema has no resolver, and there are no off-chain variants of `attest_multi` or `revoke_multi`.

## 6. Seal Access Control

This uses Seal's **Private Data** mode.

```
At encryption time: Key ID = [attestor_bytes || nonce]
Full Seal ID = [package_id || attestor || nonce]
```

Using a nonce instead of the attestation_id is what makes **encrypt first, then go on-chain** possible: the issuance transaction has not been submitted yet, so the object ID is unknown.

`seal_approve` is an `entry` function, invoked by the Seal key server via `dry_run_transaction_block`:

```move
entry fun seal_approve(id: vector<u8>, attestation: &Attestation) {
    assert!(check_policy(id, attestation), ENoAccess);
}
```

Permissions are layered twice:

1. **Move VM ownership**: the `&Attestation` passed in must be an object owned by the transaction signer → only the recipient
2. **Policy match**: `id == compute_key_id(attestor, nonce)`, and the attestation must be encrypted and carry a nonce

The key server does not trust the client; it only trusts a successful dry-run.

## 7. Resolver Architecture

Resolver is not an "external contract address callback" (Sui has no dynamic dispatch); it is **Hot Potato + Witness Rule**:

```
Schema.resolver: Option<Resolver>
  rules:  VecMap<String, VecSet<TypeName>>   // "START_ATTEST" / "START_REVOKE"
  config: Bag                                 // Rule type → config (whitelist tables, etc.)
  resolver_address / resolver_module          // metadata only, not called at runtime
```

Issuance must go through:

```
start_attest() → Request (no abilities)
    → resolver::approve(&mut Request, Witness)
    → attest_with_resolver(..., Request) internally finish_attest
        → confirm: every rule TypeName must appear in Request.approvals
```

`Request` has no `copy / drop / store / key`, so it must be consumed by `finish_*` before the transaction ends, otherwise compilation/execution fails. This guarantees that "once started, it must end with approvals".

Plain `attest()` does `assert!(!schema.has_resolver())` to prevent bypassing the Resolver.

Example implementations are in `sas/resolvers/`:

- `whitelist`: the sender must be in the table
- `blocklist`: the sender must not be in the table

Both store their lists in the Schema's `Bag` and mutate them through an `Admin` capability (currently forgeable, see the security model).

## 8. Events

The indexer relies on two kinds of events:

| Event | When | Key fields |
|------|------|----------|
| `SchemaCreated` | registering a Schema | `event_type` 0=plain / 1=with Resolver, `schema_address`, `admin_cap` (`@0x0` for type 0, the Admin object address for type 1) |
| `AttestationCreated` | issuance | `event_type` 0=attest / 1=with_resolver (off-chain issuance also uses 0), full metadata + storage fields |

**There is no `AttestationRevoked` event.** Revocation only mutates the Registry table. The backend has to scan the Registry or listen to calls itself; this is one difference from AAS. The registry `Status` fields are private and expose only `is_revoked` as a scalar view.

## 9. Permission Matrix

| Operation | Who | Checks |
|------|----|------|
| Register Schema | any address | none |
| Issue (no Resolver) | any address | Schema has no resolver; expiration time > now; if ref is not 0x0 it must already be registered |
| Issue (with Resolver) | whoever passes all Rules | `finish_attest` verifies approvals |
| Revoke | holder of the corresponding `Admin` (intended; currently forgeable) | Admin.schema == Schema; schema.revokable; attestation exists, belongs to the schema, and is not already revoked |
| Seal decryption authorization | owner of the Attestation object (recipient) | `seal_approve` dry-run |
| Change Registry allowed versions | Registry AdminCap | held by the publisher; call before upgrading |

## 10. Architectural Differences from AAS

1. SAS uses **object ownership** to express "who holds the proof"; AAS uses Named Object, where the recipient is merely a field.
2. SAS revokes on a **shared Registry**; AAS mutates the Attestation resource directly (because the object does not belong to the recipient).
3. SAS Resolver is **type-system-enforced multi-step PTB**; AAS is a **runtime dynamic callback**.
4. SAS has Seal; AAS has no on-chain encryption policy.
5. SAS addresses are unpredictable; AAS addresses can be precomputed off-chain.
