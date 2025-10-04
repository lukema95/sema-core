English | [简体中文](./SECURITY.zh.md)

# Security Policy

## Supported versions

| Version | Supported | Notes |
|---------|-----------|-------|
| `main` | ✅ | Active development |
| Latest tagged release | ✅ | Security fixes are applied here first |
| Older tags / deployments | ❌ | Upgrade to the latest release |

The contracts are deployed on testnet and are **unaudited**. Treat them as experimental and obtain an independent review before any production deployment.

## Reporting a vulnerability

Please report suspected vulnerabilities **privately** to `lukema95@gmail.com`. Do not open a public issue, pull request, or discussion for a security report.

Include as much detail as possible:

- Affected package, module, and function (or object/registry).
- Network and deployed package address, if applicable.
- Reproduction steps or a proof-of-concept transaction.
- Expected vs. actual behavior and potential impact.
- Whether the issue is already public.

If you prefer encrypted communication, request a PGP key in your first email.

### Response targets

| Stage | Target |
|-------|--------|
| Acknowledgement | 3 business days |
| Initial triage and severity | 10 business days |
| Fix or mitigation plan | Communicated with triage |
| Public advisory | After a fix is released and users have an upgrade window |

These are best-effort targets for a small maintainer team, not contractual SLAs.

## Scope

**In scope**

- Move contracts in `aas/` and `sas/`, including the reference resolvers.
- Access control and capability checks (schema creator, `Admin`, registry admin caps).
- Address/seed derivation and named-object creation.
- Off-chain integrity checks, Seal access control, resolver dispatch.
- Upgrade and version-gating logic.

**Out of scope**

- SDKs, indexers, and frontends built by integrators.
- Walrus, Shelby, Seal key servers, and the Aptos/Sui frameworks.
- Issues requiring compromised keys, a malicious validator set, or a compromised RPC.
- Gas optimization or non-security best-practice reports.
- Test-only code and example resolvers deployed without modification (report the pattern instead).

## Disclosure process

1. We acknowledge the report and confirm scope and severity.
2. We coordinate privately on a fix and may request additional information.
3. A patch is prepared, tested, and released; affected deployments are notified when possible.
4. We publish an advisory describing impact, fixes, and credit once users have had a reasonable upgrade window.

Please do not disclose the issue publicly until a fix is released or a coordinated disclosure date is agreed.

## Safe harbor

We will not pursue legal action against researchers who:

- Make a good-faith effort to avoid privacy violations, data destruction, and service disruption.
- Report findings privately and give us a reasonable window to respond.
- Do not exploit the issue beyond what is necessary to demonstrate it.

## Third-party infrastructure

The protocol depends on Aptos and Sui networks and on external storage and encryption providers (Walrus, Shelby, Seal). Report issues in those systems to their respective maintainers. If a vulnerability involves contract code in this repository, notify us as described above.

## Known limitations

This revision has documented gaps that affect the security model:

- The Sui `Admin` capability can be minted by anyone through the public `admin::new`; revocation authority is not protected.
- Sui registry versions must be pre-authorized before an upgrade; the reverse order locks registry calls.
- Off-chain data hashes are caller-supplied; clients must verify payloads themselves.
- Aptos reference checks are inverted, so only `@0x0` is usable.
- Aptos resolvers require `resolver_storage::initialize()`; after initialization, an unregistered resolver fails open.

See [docs/security-model.md](./docs/security-model.md) for details, impact, and mitigations.

## Audits

No third-party audit has been completed. Audit reports, when available, will be linked from the repository README and release notes.
