English | [简体中文](./deployment.zh.md)

# Deployment and Upgrades

This guide covers publishing, initializing, and upgrading the Sema Core contracts. It assumes you have funded accounts on the target networks and have read [SECURITY.md](../SECURITY.md). The contracts are unaudited; do not deploy to production without an independent review.

For local development and tests, see the [quick start](../README.md#quick-start).

## Sui (SAS)

### Prerequisites

- Sui CLI `1.61.x`
- A funded Sui account for gas and the upgrade capability
- Network configuration in the Sui CLI (`sui client active-env`)

### Publish

```bash
cd sas
sui move build
sui client publish --gas-budget 100000000
```

Publishing performs three things automatically:

1. Creates and shares `SchemaRegistry`.
2. Creates and shares `AttestationRegistry`.
3. Transfers `SchemaRegistryAdminCap` and `AttestationRegistryAdminCap` to the publisher, plus the package `UpgradeCap`.

Record the following from the publish output (also stored in `Published.toml` where applicable):

| Value | Where to find it | Used by |
|-------|------------------|---------|
| Package ID | `Published.toml` → `published-at`, or the `published` effects | Clients, indexers, resolvers |
| `SchemaRegistry` object ID | Created shared object | Every schema operation |
| `AttestationRegistry` object ID | Created shared object | Every attestation operation |
| `UpgradeCap` object ID | Transferred object | Future upgrades |
| Registry admin caps | Transferred objects | `update_allowed_versions` |

### Verify

```bash
sui client object <schema_registry_id>
sui client object <attestation_registry_id>
sui client object <package_id>
```

Both registries should be shared and owned by the system; admin caps should be owned by the publisher.

### Publish reference resolvers (optional)

The resolver package depends on `sas` through a local path and resolves the deployed address from `sas/Published.toml`:

```bash
cd sas/resolvers
sui move build
sui client publish --gas-budget 100000000
```

The publisher becomes the owner of the resolver package and its `UpgradeCap`. A schema creator can attach the resolver address/module to a schema; see `sas/resolvers/sources/whitelist.move` for the builder calls.

If you deploy to an environment without a matching `[published.<env>]` entry in `sas/Published.toml`, set the `sas` named address in `sas/resolvers/Move.toml` to the deployed package ID before publishing.

### Upgrade

`update_allowed_versions` loads the registry through the version check, so it only works while the **current** version is allowed. Authorize the next version first, then upgrade:

1. With the old package live, call `schema_registry::update_allowed_versions` and `attestation_registry::update_allowed_versions` with a set containing the current version and the version you are about to publish.
2. Bump `CURRENT_VERSION` in `sas/sources/constants.move`.
3. Publish the upgrade.

```bash
cd sas
sui client upgrade --upgrade-capability <upgrade_cap_id> --gas-budget 100000000
```

If you publish before step 1, the update call itself aborts with `EVersionNotEnabled` and every registry read/write stops until a further upgrade. See [Security model §2](./security-model.md#2-sas-upgrade-ordering-is-easy-to-get-wrong).

### Mainnet notes

`Move.lock` records the framework revision used for the tested testnet build. For mainnet, switch the Sui CLI environment to mainnet, update dependencies if required, re-run the full test suite, and publish from a clean tree. Do not mix framework revisions between `sas` and `sas/resolvers`.

## Aptos (AAS)

### Prerequisites

- Aptos CLI `7.14.x`
- A funded Aptos account
- A CLI profile (`aptos init --profile sema --network testnet`)

### Publish

```bash
cd aas
aptos move publish --profile sema --named-addresses aas=<publisher_address>
```

`aas` is the named address declared in `aas/Move.toml`; it must match the address that hosts the package (normally the publisher account). Publishing runs `package_manager::init_module`, which creates the protocol object signer used for all named objects and stores `PermissionConfig` at `@aas`.

### Initialize resolver storage

The resolver dispatcher stores request data in a resource that must be created once:

```bash
aptos move run --profile sema \
  --function-id <aas_address>::resolver_storage::initialize
```

The entry is idempotent; it returns early if the resource already exists. It can be called by any account because it only creates protocol state at the package address.

### Publish a resolver (optional)

```bash
cd aas/resolver_example
aptos move publish --profile sema \
  --named-addresses aas=<aas_address>,resolver_example=<resolver_address>
```

`resolver_example::schema_resolver::init_module` registers a dispatchable callback. The dispatcher expects the resolver module to expose `public fun resolve<T: key>(_metadata: Object<T>): Option<u128>` and to return `option::some(0)` for approval. A resolver reads the request through `resolver_storage::retrieve(@<resolver_address>)`.

### Upgrade

Aptos packages upgrade in place:

```bash
cd aas
aptos move publish --profile sema --named-addresses aas=<publisher_address>
```

The publisher must use the same address and a compatible upgrade policy. Existing named objects keep their addresses as long as the seed derivation and `package_manager` object are unchanged. Keep public signatures and struct layouts stable; see [CONTRIBUTING.md](../CONTRIBUTING.md#compatibility-rules).

### Movement

AAS can be deployed to Movement with the Movement CLI from the same sources. Use a Movement profile and network; the Aptos framework revision in `aas/Move.toml` may need to match the Movement framework. Record a separate package address per network — named-object addresses are scoped to the package signer, so they differ across deployments.

## Post-deployment checklist

- [ ] Package ID and registry object IDs recorded in your deployment inventory.
- [ ] `UpgradeCap` (Sui) and registry admin caps stored securely.
- [ ] `resolver_storage::initialize()` executed (Aptos).
- [ ] Downstream consumers updated: SDK address constants, backend environment (`SUI_PACKAGE_ID`, `APTOS_PACKAGE_ADDRESS`, `MOVEMENT_ADDRESS`), indexers.
- [ ] Event subscription verified (`SchemaCreated`, `AttestationCreated`, `AttestationRevoked`).
- [ ] A smoke-test schema and attestation created and read back.
- [ ] `Published.toml` (Sui) committed if you track deployments in git.

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| `EVersionNotEnabled` on Sui | `CURRENT_VERSION` is not in the registry's `allowed_versions`. Pre-authorize the next version before upgrading; if you already upgraded without doing so, the registry is locked and needs a recovery upgrade. |
| `ESchmaAlreadyExist` / object already exists | A schema with identical content and parameters was already created; addresses are deterministic |
| Aptos resolver never invoked | `resolver_storage::initialize()` was not called, or the resolver did not register a dispatchable callback |
| Attestation creation aborts with `EATTESTATIONS_NOT_EXIST_AT_ADDRESS` | AAS currently requires `ref_attestation` to be `@0x0`; see [aas/README.md](../aas/README.md#known-behavior) |
| Sui publish fails on the resolver package | `sas` cannot be resolved; set the `sas` address explicitly or publish from an environment with a matching `Published.toml` entry |
