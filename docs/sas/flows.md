English | [简体中文](./flows.zh.md)

# SAS Core Flows

## 0. Initialization

When the package is published, the `init` of both Registries runs automatically:

1. Create the `SchemaRegistry` / `AttestationRegistry` Shared Objects
2. `allowed_versions` of the Inner = `{ current_version }`
3. The corresponding `*AdminCap` is transferred to the publisher

After that, schema registration carries `SchemaRegistry`; issuance and revocation carry `AttestationRegistry` plus the shared `Schema`.

```mermaid
sequenceDiagram
    participant Pub as Publisher
    participant Chain as Sui
    Pub->>Chain: publish sas package
    Chain->>Chain: init SchemaRegistry (shared)
    Chain->>Chain: init AttestationRegistry (shared)
    Chain->>Pub: SchemaRegistryAdminCap
    Chain->>Pub: AttestationRegistryAdminCap
```

## 1. Registering a Schema (no Resolver)

```mermaid
sequenceDiagram
    participant C as Creator
    participant SAS as sas::sas
    participant Sch as sas::schema
    participant Reg as SchemaRegistry

    C->>SAS: register_schema(registry, schema_bytes, name, desc, url, revokable)
    SAS->>Sch: new(...)
    Sch->>Reg: registry(schema_addr, sender)
    Sch->>Sch: emit SchemaCreated (event_type=0)
    Sch->>C: Admin cap
    Sch->>Sch: share_object(Schema)
```

Key code path:

```move
public fun new(...): Admin {
    let schema_record = Schema { resolver: option::none(), ... };
    schema_registry.registry(schema_record.addy(), ctx);
    emit(SchemaCreated { event_type: 0, admin_cap: @0x0, ... });
    let admin_cap = admin::new(schema_record.addy(), ctx);
    transfer::share_object(schema_record);
    admin_cap
}
```

After receiving the `Admin`, the caller `transfer`s it to their own wallet. The Schema becomes a shared object, so any later issuance can reference it.

## 2. Registering a Schema (with Resolver)

With a Resolver, the Schema is **not shared yet**: the call returns `(ResolverBuilder, Admin, Schema)`, letting the caller configure rules in the same PTB and then `share_schema`.

```mermaid
flowchart TD
    A[register_schema_with_resolver] --> B[create Schema, resolver=None]
    B --> C[register in SchemaRegistry]
    C --> D[new Admin]
    D --> E[new ResolverBuilder<br/>pre-populated with empty START_ATTEST / START_REVOKE rule sets]
    E --> F[return Builder + Admin + Schema ownership]
    F --> G[caller: add_rule / add_rule_config<br/>whitelist::add etc.]
    G --> H[schema.add_resolver(builder)]
    H --> I[schema.share_schema]
```

Whitelist configuration example:

```move
// One transaction: configure, seed the list, then share.
let (mut builder, admin, mut schema) = sas::register_schema_with_resolver(...);
whitelist::add(&schema, &mut builder, ctx);
schema::add_resolver(&mut schema, builder);
whitelist::add_user(&admin, &mut schema, attestor_addr);
schema::share_schema(schema);

// Later transactions can mutate the shared schema through &mut Schema.
```

`share_schema` consumes the owned `Schema`; call `add_user` before sharing (as above) or in a separate transaction that takes the shared object by reference. `add_resolver` uses `option::fill`, so a Schema can only be given a Resolver once.

## 3. On-chain Issuance

```mermaid
sequenceDiagram
    participant A as Attestor
    participant SAS as sas::sas
    participant Att as sas::attestation
    participant Reg as AttestationRegistry
    participant R as Recipient

    A->>SAS: attest(schema, registry, ref, recipient, exp, data, meta, clock)
    SAS->>SAS: assert !has_resolver
    SAS->>SAS: if ref != 0x0: registry.is_exist(ref)
    SAS->>SAS: if exp != 0: now < exp
    SAS->>Att: create_attestation_on_chain(...)
    Att->>Att: emit AttestationCreated (storage_type=0, data=plaintext)
    Att->>R: transfer(Attestation)
    SAS->>Reg: registry(attestation_addr, schema_addr)
    SAS-->>A: attestation address
```

Validation checklist:

| Check | Error code |
|------|--------|
| Schema has no Resolver | `EHasResolver` |
| ref exists (when not 0x0) | `ERefIdNotFound` |
| not expired | `EExpired` |
| all vectors have equal length (multi only) | `EInvalidLength` |

`attestor` is taken from `ctx.sender()` and cannot be forged.

**The object is transferred to the recipient immediately after creation.** The attestor no longer holds it afterwards, unless recipient == attestor.

## 4. Off-chain Issuance (Walrus ± Seal)

The off-chain path **does not upload to Walrus and does not encrypt inside the contract**. The SDK performs all the I/O first, then puts the pointers and hash on-chain.

```mermaid
sequenceDiagram
    participant SDK
    participant Seal as Seal SDK
    participant Walrus
    participant SAS as sas::sas
    participant R as Recipient

    alt encryption required
        SDK->>SDK: nonce = random(16~32B)
        SDK->>SDK: keyId = attestor || nonce
        SDK->>Seal: encrypt(plaintext, keyId)
        SDK->>SDK: hash = blake2b256(plaintext)
        SDK->>Walrus: upload(ciphertext)
    else plaintext off-chain
        SDK->>SDK: hash = blake2b256(data)
        SDK->>Walrus: upload(data)
    end

    SDK->>SAS: attest_off_chain(walrus ids, hash, encrypted, nonce, policy)
    SAS->>SAS: same schema/ref/exp checks as on-chain issuance
    SAS->>R: transfer Attestation (storage_type=1, data empty)
```

What stays on the object:

- `walrus_sui_object_id` / `walrus_blob_id`: where to download from
- `data_hash`: how to verify after downloading
- `encrypted` + `seal_nonce`: whether to go through Seal
- `seal_policy_id`: reserved for other Seal modes; may be empty on the Private Data path

Read flow:

```mermaid
flowchart TD
    A[obtain the Attestation object] --> B{storage_type}
    B -->|0| C[read data directly]
    B -->|1| D[fetch data from Walrus using blob_id]
    D --> E{encrypted?}
    E -->|no| F[blake2b256 == data_hash]
    E -->|yes| G[build seal_approve dry-run]
    G --> H[Key servers return the key]
    H --> I[decrypt]
    I --> F
    F -->|pass| J[Codec.decode]
    F -->|fail| K[reject: data has been tampered with]
```

## 5. Seal Decryption Authorization

```mermaid
sequenceDiagram
    participant Rec as Recipient
    participant KS as Seal Key Server
    participant Chain as seal_access
    participant Att as Attestation object

    Rec->>KS: request decryption (with session key)
    KS->>Chain: dry_run seal_approve(id, &attestation)
    Chain->>Att: can only be passed in if owned by Rec
    Chain->>Chain: is_encrypted && nonce present
    Chain->>Chain: id == attestor_bytes || nonce
    alt policy passes
        Chain-->>KS: dry-run success
        KS-->>Rec: threshold key shares
        Rec->>Rec: decrypt + verify_data_integrity
    else failure
        Chain-->>KS: abort ENoAccess
        KS-->>Rec: reject
    end
```

These three points summarize the difference:

1. Encryption happens before issuance, so the key uses a nonce rather than the object id
2. Authorization emits no events and changes no state — pure `entry` + dry-run
3. Ownership is guaranteed by the VM; the contract only checks the Seal ID

## 6. Resolver Issuance

```mermaid
sequenceDiagram
    participant A as Attestor
    participant Sch as Schema
    participant Res as resolvers::whitelist
    participant SAS as sas::sas

    A->>Sch: start_attest() → Request { approvals: ∅ }
    A->>Res: approve(&schema, &mut request)
    Note over Res: sender ∈ whitelist<br/>request.approve(WhitelistResolver{})
    A->>SAS: attest_with_resolver(..., request)
    SAS->>Sch: finish_attest(request)
    Note over Sch: destructure Request<br/>every rule TypeName ∈ approvals
    SAS->>SAS: create_attestation + registry
```

Core of `finish_attest`:

```move
fun confirm(self: &Schema, request: Request) {
    let Request { name, schema_address, approvals } = request;
    assert!(object::id_address(self) == schema_address, EWrongSchemaAddress);
    let rules = (*resolver.rules.get(&name)).into_keys();
    let i = 0;
    while (rules.length() > i) {
        assert!(approvals.contains(&rules[i]), ERuleNotApproved);
        i = i + 1;
    }
}
```

The Request is destructured and destroyed here. If a single rule is not approved, the whole transaction aborts and the Attestation is never created.

The tests use a local `Witness` to simulate a resolver without depending on the `sas/resolvers` package, showing that the rule system is generic and whitelist is only one Rule implementation.

## 7. Revocation

```mermaid
sequenceDiagram
    participant Admin as Admin Cap holder
    participant SAS as sas::sas
    participant Reg as AttestationRegistry

    alt no Resolver
        Admin->>SAS: revoke(&admin, registry, schema, att_addr)
        SAS->>SAS: assert !has_resolver
    else with Resolver
        Admin->>SAS: start_revoke → resolver.approve → revoke_with_resolver
        SAS->>SAS: finish_revoke(request)
    end

    SAS->>Reg: revoke(...)
    Note over Reg: Admin matches schema<br/>attestation exists and belongs to that schema<br/>schema.revokable<br/>not yet revoked
    Reg->>Reg: status.is_revoked = true<br/>status.timestamp = now
```

After revocation:

- The Attestation **object is still in the recipient's hands**, with its fields unchanged
- `registry.is_revoked(addr) == true`
- irreversible, there is no un-revoke

The correct approach for a verifier: check both the object (schema / expiration / data) and the Registry (revoked). Looking only at the object will treat a revoked attestation as valid.

## 8. End-to-end State Machine

```mermaid
stateDiagram-v2
    [*] --> SchemaRegistered: register_schema
    SchemaRegistered --> Active: attest / attest_off_chain
    SchemaRegistered --> Active: attest_with_resolver
    Active --> Revoked: revoke (+ resolver)
    Active --> Expired: now >= expiration_time<br/>(application-layer semantics only)
    Revoked --> [*]
    Expired --> Revoked: can still be revoked
```

The contract does not write Expired as a state. `expiration_time` is just a field.

## 9. PTB Assembly Tips for Callers

For on-chain issuance without a Resolver, a transaction usually contains:

1. Inputs: `&mut Schema`, `&mut AttestationRegistry`, `&Clock`
2. Call `sas::attest`
3. The returned address can be ignored (the object has already been transferred to the recipient, and it is also in the event)

With a Resolver:

1. `start_attest`
2. One or more `resolver::approve`
3. `attest_with_resolver` (finishes internally)

All three steps must be in the **same PTB**, because a Request cannot be held across transactions.
