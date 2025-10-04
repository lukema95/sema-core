English | [简体中文](./CHANGELOG.zh.md)

# Changelog

All notable changes to Sema Core are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Contract package versions, deployment versions, and repository tags are related but not identical: `sas::constants::CURRENT_VERSION` is the on-chain registry version, while release tags version the source tree and documentation.

## [Unreleased]

## [1.0.0] - 2025-10-05

### Added

- Sui Attestation Service (`sas`):
  - Shared, version-gated `SchemaRegistry` and `AttestationRegistry`.
  - Schema registration with optional resolver and `Admin` capability.
  - On-chain attestations, Walrus-backed off-chain attestations, integrity hashes, expiration, and references.
  - Resolver hot-potato flow (`Request`, rules, typed config) with whitelist and blocklist reference resolvers.
  - Seal access control (`compute_key_id`, recipient-only `seal_approve`) for encrypted off-chain data.
- Aptos Attestation Service (`aas`):
  - Named-object schemas and attestations derived from BCS-encoded seeds and keccak256.
  - On-chain and Shelby-backed off-chain attestations, batch issuance and revocation.
  - Dispatchable resolver support with a reference resolver and `resolver_storage` request passing.
  - Full view surface for schemas, attestations, seeds, and computed addresses.
- Repository and tooling:
  - Initial public release.
  - `Makefile` targets and GitHub Actions CI for both toolchains.
  - Architecture, flow, principles, reference, deployment, and security documentation in English and Chinese.
  - Bilingual documentation convention: English default, `.zh.md` translations.

### Security

- Contracts are unaudited. See [SECURITY.md](./SECURITY.md) for the disclosure policy and scope, and [docs/security-model.md](./docs/security-model.md) for known limitations (Sui `Admin` constructor, upgrade ordering, Aptos reference checks).

[Unreleased]: https://github.com/lukema95/sema-core/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/lukema95/sema-core/releases/tag/v1.0.0
