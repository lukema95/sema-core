English | [简体中文](./security-model.zh.md)

# Security Model and Known Limitations

This page describes who is authorized to do what, which guarantees the contracts do and do not provide, and the known gaps in the current revision. It is required reading before deploying or integrating.

The contracts are **unaudited** and run on testnet. See [SECURITY.md](../SECURITY.md) for reporting.

## Trust model

### Sui (SAS)

| Action | Authorization |
|--------|---------------|
| Create a schema | Anyone; the caller receives an `Admin` capability |
| Share a schema | The schema creator (or the module that created it); `new_with_resolver` returns an owned schema that must be shared explicitly |
| Attest (no resolver) | Any account; the attestation is transferred to the recipient |
| Attest (resolver) | Any account that obtains the required approvals from the configured resolver |
| Revoke | Holder of an `Admin` capability whose `schema` field matches the schema, for a revokable schema |
| Configure a resolver | The schema creator, via the `ResolverBuilder` returned by `register_schema_with_resolver` |
| Update registry versions | Holder of the registry admin caps created at publish time |
| Upgrade the package | Holder of the package `UpgradeCap` |
| Decrypt Seal data | Owner of the attestation object (the recipient) |

### Aptos (AAS)

| Action | Authorization |
|--------|---------------|
| Create a schema | Anyone; the caller is recorded as `creator` |
| Attest | Any account; the attestation is a named object controlled by the package-manager signer, with `recipient` recorded as a field |
| Revoke | The schema `creator` address, for a revokable schema, with resolver approval when configured |
| Configure a resolver | The schema creator (chooses the resolver address), by publishing a resolver module |
| Upgrade the package | The account that published the package, using a compatible upgrade policy |

## Known limitations

<a id="1-sas-admin-is-an-unauthenticated-bearer-capability"></a>

### 1. SAS `Admin` is an unauthenticated bearer capability

`sas::admin::new(schema, ctx)` is a **public** constructor with no check that the caller created or owns the schema. A caller can mint an `Admin` for any schema address and then call `sas::revoke`, resolver `add_user`/`remove_user`, or `schema::new_resolver_builder`.

Impact: on a resolver-less schema with `revokable = true`, any account can revoke any attestation. On a schema with a resolver, the attacker can also mutate resolver configuration.

Mitigation until the constructor is restricted: do not treat revocation authority as secure, monitor registry state, and avoid resolver configurations that grant privileges beyond revocation. A fix requires restricting `admin::new` to the package (or to the schema creation path) and is an upgrade-breaking change.

<a id="2-sas-upgrade-ordering-is-easy-to-get-wrong"></a>

### 2. SAS upgrade ordering is easy to get wrong

`update_allowed_versions` loads the registry through `load_inner_mut`, which asserts that `constants::current_version()` is already in `allowed_versions`. If you bump `CURRENT_VERSION` and publish before pre-authorizing the new version, the update call aborts with `EVersionNotEnabled` and the registries become unusable until a further upgrade.

Safe sequence:

1. With the **old** package live, call `update_allowed_versions` and include the version you are about to publish.
2. Bump `CURRENT_VERSION` and publish the upgrade.
3. Verify registry reads work; only then retire the old caps.

### 3. Off-chain data hashes are caller-supplied

Issuance accepts `data_hash` as an argument and does not validate it against any blob. `verify_data_integrity` is an opt-in view. Indexers and clients must:

- Recompute the hash over the payload they downloaded.
- Compare it with the on-chain `data_hash`.
- Treat the off-chain gateway (Walrus or Shelby) as untrusted transport.

On Sui, `verify_data_integrity` aborts when called on an on-chain attestation; on Aptos it returns `false`.

### 4. SAS off-chain issuance cannot use a resolver

`attest_off_chain` asserts that the schema has no resolver. There are also no resolver variants of `attest_multi` or `revoke_multi`. Off-chain attestations therefore cannot be gated by a whitelist/blocklist at issuance time.

### 5. AAS reference check is inverted

`create_attestation` and `create_attestation_off_chain` assert that `ref_attestation` is **not** an existing attestation. As implemented, only `@0x0` is safe; references are effectively unavailable in this revision.

### 6. AAS has no on-chain schema registry

The `SchemaRegistry` struct is defined but never initialized or written. Discovery relies on `SchemaCreated` events and on recomputing named-object addresses. Indexers must backfill from events.

### 7. Resolver registration is optional and fails open

On Aptos, if a schema sets a non-zero resolver address but no dispatcher has been registered for it, `resolver_dispatcher::on_attest` returns `true`. On Sui, a resolver must approve by constructing the witness; an incorrectly configured resolver can block or allow issuance according to its own code.

Resolver code is trusted by the schema creator. Review it before attaching it to a schema.

### 8. Observability gaps

- Sui has no `AttestationRevoked` event; revocation is recorded in `AttestationRegistry`, whose `Status` fields (`schema_address`, `is_revoked`, `timestamp`) have no public Move accessors besides `is_revoked`.
- `AttestationCreated.event_type` is `0` for both plain and off-chain issuance on Sui; use `storage_type` to distinguish them.
- AAS emits `AttestationRevoked` and exposes full views, but schema discovery still depends on events.

### 9. Error codes are not stable identifiers

Revert codes are module-local constants and can change across versions. Do not switch on numeric codes in production clients; match on transaction failure or parse errors defensively.

## Operational guidance

- Keep the Sui `UpgradeCap`, registry admin caps, and Aptos publisher keys in separate, access-controlled custody.
- Treat the deployer account as a privileged role.
- Use dedicated RPC endpoints and verify responses independently when moving funds or granting access.
- Re-run the full test suite and a staging deployment before mainnet upgrades.
- Publish an advisory when a fixed version is available; see [SECURITY.md](../SECURITY.md).

## Reporting

Report security issues privately to `lukema95@gmail.com`. Do not open a public issue for vulnerabilities.
