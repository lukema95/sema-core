[English](./CHANGELOG.md) | 简体中文

# 更新日志

此处记录 Sema Core 的所有重要变更。格式遵循 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，并且本项目遵循[语义化版本](https://semver.org/spec/v2.0.0.html)。

合约包版本、部署版本与仓库标签彼此相关但并不相同：`sas::constants::CURRENT_VERSION` 是链上 Registry 版本，而发布标签用于标记源码树与文档的版本。

## [Unreleased]

## [1.0.0] - 2025-10-05

### 新增

- Sui Attestation Service（`sas`）：
  - 共享的、受版本门控的 `SchemaRegistry` 与 `AttestationRegistry`。
  - 支持可选 resolver 与 `Admin` 能力的 Schema 注册。
  - 链上 Attestation、Walrus 支撑的链下 Attestation、完整性哈希、过期与引用。
  - Resolver Hot Potato 流程（`Request`、规则、类型化配置），并附带白名单与黑名单引用 resolver。
  - 针对加密链下数据的 Seal 访问控制（`compute_key_id`、仅限接收方的 `seal_approve`）。
- Aptos Attestation Service（`aas`）：
  - 由 BCS 编码种子与 keccak256 派生出的 named object Schema 与 Attestation。
  - 链上与 Shelby 支撑的链下 Attestation，以及批量签发与撤销。
  - 支持 Dispatchable resolver，并提供引用 resolver 与 `resolver_storage` 请求传递。
  - 完整的 view 接口，覆盖 Schema、Attestation、种子与计算出的地址。
- 仓库与工具链：
  - 面向两套工具链的 `Makefile` 目标与 GitHub Actions CI。
  - 初始公开发布。
  - 英文与中文的架构、流程、原则、参考、部署与安全文档。
  - 双语文档约定：英文为默认，提供 `.zh.md` 译本。

### 安全

- 合约未经审计。披露政策与范围见 [SECURITY.zh.md](./SECURITY.zh.md)；已知限制（Sui `Admin` 构造函数、升级顺序、Aptos 引用检查）见 [docs/security-model.zh.md](./docs/security-model.zh.md)。

[Unreleased]: https://github.com/lukema95/sema-core/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/lukema95/sema-core/releases/tag/v1.0.0
