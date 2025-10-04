English | [简体中文](./flows.zh.md)

# AAS Core Flows

## 0. Publishing and Initialization

```mermaid
sequenceDiagram
    participant Pub as Publisher
    participant PM as package_manager
    participant RS as resolver_storage

    Pub->>PM: publish aas (init_module)
    PM->>PM: create object + save ExtendRef
    Note over RS: the Dispatcher table is not created automatically
    Pub->>RS: initialize()  entry
    RS->>RS: move_to(package_signer, Dispatcher)
```

`resolver_storage::initialize` is a separate entry function and must be called once before using a Resolver. `is_initialized` prevents repeated calls.

The sample Resolver package `resolver_example` calls `register_dispatchable` in its own `init_module`.

## 1. Creating a Schema

```mermaid
sequenceDiagram
    participant C as Creator
    participant AAS as aas::aas
    participant Sch as aas::schema
    participant PM as package_manager

    C->>AAS: create_schema(schema_bytes, name, desc, url, revokable, resolver)
    AAS->>AAS: check string lengths
    AAS->>Sch: create_schema(creator_addr, ...)
    Sch->>Sch: seed = keccak256(bcs fields...)
    Sch->>PM: get_signer()
    Sch->>Sch: create_named_object(signer, seed)
    Sch->>Sch: move_to(object_signer, Schema)
    Sch->>Sch: emit SchemaCreated
    Sch-->>AAS: schema_address
```

`resolver = @0x0` means no custom validation. A non-zero resolver requires two deployment steps: `resolver_storage::initialize()` must have run (otherwise issuance aborts on the missing `Dispatcher`), and the resolver should have called `register_dispatchable` (otherwise it is treated as open and validation is skipped).

Address precomputation:

```move
schema::get_schema_address(name, description, url, revokable, resolver, schema_bytes)
```

Tests compare the result with `expected` right after creation, guaranteeing that the SDK and the on-chain formula agree.

## 2. On-Chain Issuance

```mermaid
sequenceDiagram
    participant A as Attestor
    participant AAS as aas::aas
    participant Disp as resolver_dispatcher
    participant Att as aas::attestation

    A->>AAS: create_attestation(recipient, schema, ref, exp, revokable, data)
    AAS->>AAS: assert !attestation_exists(ref)  ⚠️ see below
    AAS->>AAS: assert schema_exists
    alt schema.resolver != 0x0
        AAS->>Disp: on_attest(resolver, all arguments)
        Disp-->>AAS: bool
        AAS->>AAS: assert success else ERESOLVE_FAILED
    end
    AAS->>Att: create_attestation(...)
    Att->>Att: seed includes now and data
    Att->>Att: named object + emit AttestationCreated
    Att-->>AAS: attestation_address
```

Issuance flowchart:

```mermaid
flowchart TD
    S[create_attestation] --> E2{ref does not exist?}
    E2 -->|no| X2[EATTESTATIONS_NOT_EXIST...]
    E2 -->|yes| E1{schema exists?}
    E1 -->|no| X1[ESCHEMA_NOT_FOUND]
    E1 -->|yes| E3{resolver == 0x0?}
    E3 -->|yes| C[create named Attestation]
    E3 -->|no| D[on_attest]
    D --> E4{returns true?}
    E4 -->|no| X3[ERESOLVE_FAILED]
    E4 -->|yes| C
    C --> Ev[emit AttestationCreated]
```

⚠️ `assert!(!attestation_exists(ref))` makes a real ref unusable. To use attestation chains, this line must be changed first.

`attestor` comes from `signer::address_of`, synonymous with `ctx.sender()` in SAS.

## 3. Off-Chain Issuance (Shelby)

The contract likewise does not access Shelby. The SDK uploads first, then submits the pointer.

```mermaid
sequenceDiagram
    participant SDK
    participant Shelby
    participant AAS as aas::aas

    SDK->>SDK: data_hash = blake2b256(plaintext)
    SDK->>Shelby: upload blob, get account / name / merkle / tx
    SDK->>AAS: create_attestation_off_chain(...)
    Note over AAS: if a resolver exists, on_attest receives data_hash, not the plaintext
    AAS->>AAS: create a Named Object with storage_type=1
```

Object fields:

- `data` empty
- `data_hash` hash of the plaintext
- `shelby_account`, `shelby_blob_name` locate the blob
- `shelby_blob_merkle_root`, `shelby_register_tx_hash` are the evidence

Reading:

```mermaid
flowchart TD
    A[view attestation_data] --> B{storage_type}
    B -->|0| C[use the data field]
    B -->|1| D[fetch from Shelby by account+name]
    D --> E[blake2b256 == data_hash]
    E -->|yes| F[Codec.decode]
    E -->|no| G[reject]
```

There is no Seal step. Privacy can only be provided by encrypting in the application layer; the contract does not know the nonce and cannot do an on-chain approve.

## 4. Resolver Callback Details

```mermaid
sequenceDiagram
    participant AAS
    participant Store as resolver_storage
    participant Disp as resolver_dispatcher
    participant FA as dispatchable_fa
    participant R as schema_resolver

    AAS->>Disp: on_attest(module, args...)
    Disp->>Store: dispatcher_is_exists?
    alt not registered
        Disp-->>AAS: true
    else registered
        Disp->>Store: pack_attest_data + insert
        Disp->>FA: derived_supply(metadata)
        FA->>R: resolve(metadata)
        R->>Store: retrieve(@resolver_example)
        R->>R: unpack + business asserts
        R-->>FA: option::some(0)
        FA-->>Disp: some(0)
        Disp-->>AAS: true
    end
```

Sample `resolve_attest`:

```move
assert!(revokable, EINVALID_ARGUMENT);
option::some(0)
```

Failures use `assert!` to abort the whole transaction, or return a non-zero value / none. The Dispatcher treats anything other than `some(0)` as failure.

At registration the function names are hard-coded as `"schema_resolver"` / `"resolve"`:

```move
function_info::new_function_info(signer, b"schema_resolver", b"resolve")
```

A custom resolver package must use these two names, or the dispatcher must be changed to support configuration. Registration is keyed to the publisher's address (the FA named object uses `bcs(signer_address)` as its seed) and is single-shot: registering the same publisher twice aborts because the named object already exists.

## 5. Revocation

```mermaid
sequenceDiagram
    participant Admin as Schema creator
    participant AAS as aas::aas
    participant Disp as resolver_dispatcher
    participant Att as aas::attestation

    Admin->>AAS: revoke_attestation(schema, attestation)
    AAS->>AAS: schema_exists / attestation_exists
    AAS->>AAS: signer == schema.creator
    AAS->>AAS: schema.revokable
    AAS->>AAS: !attestation_revoked
    alt resolver != 0x0
        AAS->>Disp: on_revoke(resolver, admin, schema, att)
        AAS->>AAS: assert success
    end
    AAS->>Att: revoke_attestation
    Att->>Att: revocation_time = now_seconds
    Att->>Att: emit AttestationRevoked
```

The order of checks matters: authorize before dispatching, so that unauthenticated callers cannot trigger someone else's resolver logic (even though `on_revoke` itself only returns a bool).

After revocation the object still `exists`, and views can still read the historical data. Business logic should rely on `revocation_time != 0`.

Batch: `revoke_multi_attestations` requires `schema_addr` and `attestations` to have the same length and loops over them one at a time. A single failure rolls back the whole transaction.

## 6. End-to-End States

```mermaid
stateDiagram-v2
    [*] --> SchemaAlive: create_schema
    SchemaAlive --> AttestationAlive: create_attestation*
    AttestationAlive --> Revoked: revoke_attestation
    AttestationAlive --> Stale: marked expired by the application layer
    Revoked --> [*]
```

There is no Expired state on-chain, and no entry function for deleting an object.

## 7. Comparison with SAS Flows

| Step | SAS | AAS |
|------|-----|-----|
| Initialization | two Shared Registry | ExtendRef + optional Dispatcher init |
| Create Schema | returns Admin Cap, shares Schema | returns / precomputable address, no Cap |
| Issuance | transfer to recipient | named object stays at the object address |
| Custom validation | three-step Hot Potato in the same PTB | one synchronous dispatch |
| Off-chain | Walrus + optional Seal | Shelby, no Seal |
| Revocation | modifies Registry, no event | modifies object field, emits event |

## 8. SDK / Backend Integration Notes

1. After creation, use the `schema_data` / `attestation_data` views, or compute the named address yourself.
2. An indexer subscribing to `SchemaCreated`, `AttestationCreated`, and `AttestationRevoked` covers the whole lifecycle.
3. Off-chain verification must run `verify_data_integrity` again; do not trust the Shelby gateway alone.
4. Display timestamps in seconds; do not compare them directly with SAS's ms values.
5. Until `ref_attestation` is fixed, the SDK should only pass `@0x0`.
