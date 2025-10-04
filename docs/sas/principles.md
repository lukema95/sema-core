English | [简体中文](./principles.zh.md)

# SAS Principles

Reading SAS thoroughly comes down to four Sui/Move idioms stacked on top of each other.

## 1. Capability: Admin is a bearer tag (with a known gap)

```move
public struct Admin has key, store {
    id: UID,
    schema: address,
}
```

When a Schema is registered, `admin::new(schema_addr)` returns this to the caller. On revocation:

```move
admin.assert_schema(schema_record.addy());
```

**It does not compare `tx.sender() == schema.creator`.** Possession of the Cap is the authority. The design intent is:

- Multisig / wallet custody: transfer the Cap to a DAO or multisig
- Transferable permissions: when a project changes its operations address, one object transfer is enough
- Least privilege: a Cap is bound to a single schema, so you cannot use A's key to revoke B

Contrast with AAS: revocation checks `signer == schema.creator`, so the permission is permanently bound to the creating address.

> **Known limitation:** `admin::new` is a public, unguarded constructor. Any account can mint an `Admin` for an arbitrary schema address and pass `assert_schema`. The capability is therefore not a security boundary in the current revision. See [Security model §1](../security-model.md#1-sas-admin-is-an-unauthenticated-bearer-capability). Until `admin::new` is restricted to the package, do not rely on revocation or resolver administration for protection.

`Admin` is also passed to `new_resolver_builder` and resolver `add_user`/`remove_user`, with the same caveat.

## 2. Shared vs Owned: who can put an object into a transaction

In Sui, "can this be called" depends first on whether the current transaction can reference the object.

| Requirement | Choice | Result |
|------|------|------|
| Anyone in the world can issue against a Schema | Schema → Shared | Any transaction can take `&mut Schema` |
| The attestation belongs only to the attested party | Attestation → Owned by recipient | Others cannot pass the object as an argument |
| Globally queryable revocation | Registry → Shared | Anyone can read `is_revoked` |

This directly determines **why revocation cannot modify the Attestation object**: the admin is not the owner and cannot obtain `&mut Attestation`. The Registry is a shared ledger, so the admin modifies the ledger rather than someone else's NFT.

Seal consumes the same model: `seal_approve(id, &Attestation)` requires the caller to be the owner. If the signer is not the owner during the Key server's dry-run, the transaction fails outright, so there is no need to write `assert!(sender == recipient)` in the contract.

## 3. Hot Potato: why Request has no ability at all

```move
public struct Request {
    name: String,                 // "START_ATTEST" / "START_REVOKE"
    schema_address: address,
    approvals: VecSet<TypeName>
}
```

No `copy`, no `drop`, no `store`, no `key`. This structure is called a **Hot Potato**:

- It cannot be stored in an object and cannot be discarded
- It must be "eaten" by some function within this Programmable Transaction Block
- The functions that eat it are `finish_attest` / `finish_revoke`, which call `confirm` internally to check approvals

If an attacker calls `start_attest` and then skips the resolver, the unused `Request` prevents the transaction from being committed. `schema::new_request` is public, so a `Request` can be forged, but it still needs the witness approvals collected in `confirm`; an empty request fails when the resolver has rules.

This is stronger than a "bool approved field": an `approved` flag can be set to true and then changed, whereas a Hot Potato turns "unfinished work" into a type-system error.

## 4. Witness Pattern: rules are types, not strings

```move
public fun approve<Rule: drop>(request: &mut Request, _: Rule) {
    request.approvals.insert(type_name::with_defining_ids<Rule>());
}
```

The Whitelist module defines:

```move
public struct WhitelistResolver has drop {}
```

Only a module that can construct `WhitelistResolver {}` can call `approve<WhitelistResolver>`. An external module cannot slip in a rule with the same name out of thin air, because the `TypeName` carries the defining module.

Configuration lives in the Schema's `Bag`, and the keys are also the Rule's TypeName:

```
rules["START_ATTEST"] = { TypeName(WhitelistResolver) }
config[TypeName(WhitelistResolver)] = Whitelist { Table<address, bool> }
```

`confirm` iterates over rules and requires `approvals` to be a superset. Rules can be stacked (both a whitelist and a time window); `approvals` is a `VecSet`, so the order of `approve` calls does not matter.

`resolver_address` / `resolver_module` **do not participate in execution**; they are only metadata for humans. The real enforcement point is the TypeName. This is the exact opposite of AAS: AAS must jump to another module at runtime.

## 5. Mutual exclusion of Facade entry points

```move
public fun attest(...) {
    assert!(!schema_record.has_resolver(), EHasResolver);
    // ...
}

public fun attest_with_resolver(..., request: Request) {
    schema::finish_attest(schema_record, request);
    // ...
}
```

Calling `attest()` on a Schema that has a Resolver aborts outright. This is deliberate: otherwise an attacker would skip `start_attest` + `approve`.

`revoke` / `revoke_with_resolver` are mutually exclusive in the same way.

## 6. Reference attestation ref_attestation

If `ref_attestation != @0x0` at issuance time, `attestation_registry.is_exist(ref)` is required.

Purpose: chain attestations together, for example using a "KYC attestation" as the prerequisite for a "credit attestation". The contract only checks **existence**; it does not check that the reference is unrevoked, unexpired, or of the same schema. Upper-layer applications must combine `is_revoked` + `expiration_time` themselves.

## 7. Expiration semantics

```move
if (expiration_time != 0) {
    assert!(time.timestamp_ms() < expiration_time, EExpired);
}
```

- `0` = never expires
- A non-zero value must be **strictly greater** than the current Clock
- The check happens **only at issuance time**. An expired object does not disappear automatically, nor does the contract mark it. The application layer reads `expiration_time` and decides staleness itself.

Time comes from `&Clock`, in milliseconds. Tests use `clock::create_for_testing`.

## 8. Batch operations

`attest_multi` / `revoke_multi` are loops that call the single-item versions. `attest_multi` checks that all six vectors have equal length (`EInvalidLength`); `revoke_multi` takes a single vector and has no length check.

There is no extra semantics beyond atomicity: a failing PTB rolls back entirely, so a batch either fully succeeds or fully fails.

## 9. Data integrity vs confidentiality

| Goal | Mechanism | Prevents |
|------|------|--------|
| Integrity | Blake2b-256 hash stored on-chain, checked by the opt-in `verify_data_integrity` view | Walrus tampering, downloading the wrong blob — provided clients actually verify |
| Confidentiality | Seal encryption + `seal_approve` | A non-recipient who obtains the ciphertext cannot request the key from the key server |
| Authenticity | attestor = `ctx.sender()` | Impersonating someone else's issuance (unless they delegated signing rights to you) |
| Revocation authenticity | `Admin` capability — **currently forgeable**, see §1 | In the intended model, passers-by; not enforced in this revision |

Common misconception: putting the ciphertext hash on-chain. SAS explicitly hashes the **plaintext**, so it still matches after decryption.

## 10. How version gating works

```move
public(package) fun load_inner_mut(self: &mut AttestationRegistry): &mut RegistryInner {
    let inner = versioned::load_value_mut(&mut self.inner);
    assert!(inner.allowed_versions.contains(&constants::current_version()), EVersionNotEnabled);
    inner
}
```

`constants::current_version()` is compiled into the current package. After an upgrade this number changes; if the Registry's `allowed_versions` does not yet include the new version, every write/read aborts. Because `update_allowed_versions` itself calls `load_inner_mut`, it also asserts that the **currently running** version is allowed. The new version must therefore be authorized **before** the upgrade:

1. With v1 still live, call `update_allowed_versions` on both registries with `{1, 2}` (using the registry admin caps). The call runs v1 code and passes because `1` is allowed.
2. Bump `CURRENT_VERSION` to `2` and publish the upgrade.
3. v2 code now passes the version check; keep `1` only if you need a rollback window.

Doing step 2 before step 1 locks the registries with `EVersionNotEnabled`, and the admin call itself can no longer succeed.

This avoids "old object layouts no longer line up the moment we upgrade" and "unauthorized new code reading and writing the old registry".
