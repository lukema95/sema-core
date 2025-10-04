English | [简体中文](./principles.zh.md)

# AAS Principles

The core of AAS is not "yet another attestation struct" but three things: deterministic objects, a package-level signer, and forcing a Resolver into existence in a language that has no dynamic dispatch.

## 1. Named Object: the Address Is a Hash, Not a UID

In the Aptos Object model, the address of `create_named_object(signer, seed)` is uniquely determined by **creator address + seed**. AAS encodes the entire business key into the seed, then compresses it to 32 bytes with keccak256.

Why hash once: the raw seed can be arbitrarily long (on-chain mode includes the payload), and hashing keeps the address derivation compact and constant-size while preserving "same parameters = same address". Aptos does not impose a length constraint on named-object seeds; the hash is a design choice, not a protocol requirement.

Properties:

- **Duplicate prevention**: creating again with the same parameters aborts with `EOBJECT_EXISTS`, not an idempotent no-op
- **Indexable**: schema addresses can be computed from content; attestation addresses require the execution `now`, so indexers read them from events or views
- **No user randomness**: does not depend on a guid under the user's account

The cost: a missing field in the seed causes collisions or makes records indistinguishable. The on-chain mode puts the entire `data` into the seed, so large data makes seed computation heavier; the off-chain mode switches to `data_hash`, which is the correct split.

## 2. The Object Does Not Belong to the Recipient

```move
move_to(object_signer, Attestation { recipient, ... });
```

`object_signer` comes from the named object; the resource lives under the **object address**, and the owner is the package creator side within the object system, not the recipient.

Therefore:

- The recipient cannot "transfer the attestation to someone else" unless separate transfer logic is added (there is none today)
- Anyone who knows the address can read it with `borrow_global` (view functions)
- The module can change `revocation_time` with `borrow_global_mut`

SAS treats attestations as NFTs; AAS treats them as **addressable global records**. The product semantics are closer to EAS (Ethereum Attestation Service) than to SBTs/NFTs.

In one line: `recipient` is a declarative object, not a capability object.

## 3. Why ExtendRef Must Be friend

`get_signer()` can produce a signer with creation authority. If it were public, anyone could create objects as the package, without limit. Hence:

```move
friend aas::aas;
friend aas::schema;
friend aas::attestation;
friend aas::resolver_storage;
friend aas::resolver_dispatcher;
```

This is Move's **capability control through module visibility**. Sui expresses the same idea with Capability objects (Admin Cap, Registry AdminCap); Aptos uses friend + ExtendRef here. Two capability systems:

| | Sui SAS | Aptos AAS |
|--|---------|-----------|
| Creation authority | Transaction context `object::new` | Package ExtendRef signer |
| Revocation authority | Transferable Admin object | Non-transferable creator address |
| Upgrade authority | Registry AdminCap | Package upgrade (framework level) |

## 4. Dispatchable FA: Why Such a Strange Mechanism

Requirement: Schema stores only an `address` and at runtime calls `resolve` in the module at that address.

Move cannot do `call(address, "resolve")`. Aptos left an official backdoor for FA: `register_derive_supply_dispatch_function`, after which `derived_supply(metadata)` enters the registered function.

AAS **abuses this "compute the supply" hook as a validation callback**:

- Return value `Option<u128>`: `some(0)` counts as success
- The expected signature is `fun resolve<T: key>(metadata: Object<T>): Option<u128>`, but registration does not validate it; a mismatch only surfaces at dispatch time
- The real parameters cannot be passed through the FA API, so they are `insert`ed into `resolver_storage` first and `retrieve`d in the callback

This introduces two fundamental problems:

1. **A global mutable scratchpad**: `Table<address, vector<u8>>` stores the most recent packed data keyed by module address. On concurrency: Aptos executes sequentially within a transaction, so this is generally safe; but you cannot re-enter with a different piece of data within a single dispatch.
2. **Unregistered means pass, but uninitialized means abort**: after `resolver_storage::initialize()` has run, `on_attest` returns `true` when no dispatcher is registered for the address. Before initialization, `dispatcher_is_exists` borrows a missing `Dispatcher` and the transaction aborts. Filling `Schema.resolver` with an unregistered address after initialization = no validation.

The example resolver returns success after checking only `revokable == true`, which shows the framework works end to end, but business rules must be written strictly yourself.

## 5. Manual BCS Slicing of Packed Data

```move
let attestor = from_bcs::to_address(vector::slice(&data, 1, 33));
```

This relies on BCS's fixed widths: `address` is 32, `u64` is 8, `bool` is 1. `vector<u8> data` goes last so that "everything remaining" can serve as the payload.

This is brittle: inserting a field in the middle shifts every resolver. Evolution should version the packed layout (the first byte is already the type, so a version can be added).

SAS sidesteps this problem entirely: its parameters are real Move values passed through the function signature.

## 6. Revocation Authority: Address Equality vs Capability

```move
assert!(admin_addr == schema::schema_creator(schema_addr), ENOT_SCHEMA_CREATOR);
```

Simple, easy to understand, hard to hand over. A compromised account = compromised revocation authority; changing wallets = you can no longer revoke attestations under the old schema.

SAS's Admin Cap can be placed in a multisig object. If AAS were to close the gap, the common design is a separate `Admin` resource under the creator's account, or the Object's `TransferRef` handed to a governance contract. Neither exists today.

## 7. Actual Behavior of ref_attestation

```move
assert!(!attestation::attestation_exists(ref_attestation), EATTESTATIONS_NOT_EXIST_AT_ADDRESS);
```

Literal meaning: **the referenced address must not exist**. Combined with the default `ref = @0x0` (there is no Attestation at 0x0), issuance without a reference passes. As soon as a real attestation address is passed in, `exists == true` and the assertion fails.

This is the opposite of SAS's "if non-zero, it must exist", and it also contradicts the error code's own name, "NOT_EXIST". More reasonable code would be:

```move
if (ref_attestation != @0x0) {
    assert!(attestation::attestation_exists(ref_attestation), ...);
};
```

AAS currently **does not actually support attestation chains**. This is a genuine implementation gap.

## 8. Time and Expiry

AAS **does not check** `expiration_time > now` on issuance. `0` or a time in the past is accepted. Expiry is purely application-layer semantics.

The time unit is **seconds** (`timestamp::now_seconds`); SAS uses **milliseconds**. Do not mix them when displaying timestamps across chains.

Revocation writes `revocation_time` as the current second. `attestation_revoked` ⇔ `revocation_time != 0`. It is irreversible.

## 9. String Limits

```move
assert!(string::length(&name) < 128, ...);
assert!(string::length(&description) < 512, ...);
assert!(string::length(&url) < 512, ...);
```

Checked only when creating a Schema. Attestation has no name/description/url metadata fields (SAS does). AAS is leaner; display information is left to the Schema or to off-chain data.

## 10. friend Boundary and Attack Surface

External callers cannot call `attestation::create_attestation`; they must go through `aas::create_attestation*`, so the resolver check cannot be skipped.

Externally, `resolver_dispatcher::on_attest` **can** be called (it is public). It only returns a bool and creates no objects, but it writes the storage scratchpad and invokes the resolver. Transactions execute sequentially and the dispatcher inserts immediately before dispatch, so one transaction cannot corrupt another's in-flight request; the residual risk is that anyone can exercise a resolver out of band. Making `on_attest`/`on_revoke` `public(friend)` would reduce the surface.

## 11. Integrity Model

```
Trust chain:
  attestor signs the transaction
    → the contract writes data or data_hash
      → the reader reads the object
        → if off-chain: fetch from Shelby, blake2b256 == data_hash
          → optionally verify merkle_root (off-chain, not enforced by the contract)
```

The contract does not verify the Shelby merkle proof. `shelby_blob_merkle_root` / `shelby_register_tx_hash` are evidence anchors for indexers and dispute resolution.
