English | [简体中文](./CONTRIBUTING.zh.md)

# Contributing to Sema Core

Thanks for your interest in improving Sema Core. This repository contains Move packages for Sui and Aptos, their tests, and protocol documentation.

By participating you agree to follow the [Code of Conduct](./CODE_OF_CONDUCT.md). For security issues, do **not** open a public issue — follow [SECURITY.md](./SECURITY.md).

## Repository layout

| Path | Contents |
|------|----------|
| `aas/` | Aptos package (`aas::*` modules), tests, `resolver_example` |
| `sas/` | Sui package (`sas::*` modules), tests, `resolvers` |
| `docs/` | Architecture, flows, principles, reference, deployment, and security guides |
| `.github/workflows/` | CI for both toolchains |

## Prerequisites

- [Aptos CLI](https://aptos.dev/tools/aptos-cli/) `7.14.x` — for `aas/` and `aas/resolver_example/`
- [Sui CLI](https://docs.sui.io/guides/developer/getting-started/sui-install) `1.61.x` — for `sas/` and `sas/resolvers/`
- GNU Make (optional; the `Makefile` only wraps the CLI commands)

The Aptos framework revision is pinned in `aas/Move.toml`; Sui framework versions are recorded in `sas/Move.lock` and `sas/resolvers/Move.lock`. The first build downloads the frameworks into `~/.move`.

## Build and test

```bash
make test                    # all four packages
make test-aas                # aas
make test-sas                # sas
make test-resolvers          # sas/resolvers
make test-resolver-example   # aas/resolver_example
```

Run a single package directly when you need extra flags:

```bash
cd sas && sui move test
cd aas && aptos move test
```

CI runs the same commands on every push and pull request. A change is not ready to merge until all four suites pass.

## Making changes

1. Fork the repository and branch from `main` (for example `fix/sas-resolver-check`).
2. Keep changes focused; avoid mixing refactors with behavior changes.
3. Add or update tests for every behavior change.
4. Update affected documentation (see below).
5. Open a pull request describing the motivation, the behavior change, and the tests you ran.

<a id="compatibility-rules"></a>

### Compatibility rules

Published packages are upgradeable. To keep upgrades valid:

- Do not rename or remove public function parameters, structs, or struct fields.
- Do not change the order or types of struct fields.
- Keep event field names and order stable; indexers depend on them.
- New fields and functions must be additive and must not break existing callers.
- Address derivation seeds are part of the public interface. Changing them strands existing objects.

If a change is intentionally breaking, say so in the pull request and in `CHANGELOG.md`; it requires a new package version and a migration plan.

### Commit messages

Use short imperative subjects, optionally with a scope:

```text
sas: reject zero-length schema names
aas: add off-chain attestation tests
docs: document registry version gating
```

### Code style

- Follow the formatting of the surrounding module.
- Run `sui move fmt` for Sui packages when available; do not reformat unrelated code.
- Prefer explicit error constants over magic numbers.
- Keep module-level documentation comments current.

<a id="documentation"></a>

## Documentation

English is the default for every Markdown file; Simplified Chinese translations use the `.zh.md` suffix and must stay in sync. When you change a document:

1. Update the English file.
2. Update the corresponding `.zh.md` file (or open a follow-up issue if you cannot).
3. Keep the language switcher as the first line.
4. Verify relative links resolve.

Documentation types:

- `README.md` — project overview and quick start.
- `docs/*/architecture.md` — design and invariants.
- `docs/*/flows.md` — end-to-end transaction flows.
- `docs/*/principles.md` — design rationale and trade-offs.
- `docs/reference/*.md` — module, function, event, and error reference.
- `docs/deployment.md` — publishing and upgrade procedures.

## Pull request checklist

- [ ] Tests added or updated, and all suites pass locally.
- [ ] Public interfaces and storage layouts remain upgrade-compatible.
- [ ] English documentation updated.
- [ ] Chinese `.zh.md` documentation updated.
- [ ] `CHANGELOG.md` entry added for user-visible changes.
- [ ] No secrets, private keys, or generated build output committed.

## Release process

Maintainers:

1. Update `CHANGELOG.md` and bump versions where applicable.
2. Tag the repository (`vX.Y.Z`).
3. Publish or upgrade packages following [docs/deployment.md](./docs/deployment.md).
4. Record new package IDs and registry object IDs for downstream consumers.
5. Publish release notes describing contract changes and migration steps.

## License

Contributions are licensed under the repository's [Business Source License 1.1](./LICENSE).
