[English](./CONTRIBUTING.md) | 简体中文

# 为 Sema Core 贡献

感谢你有兴趣改进 Sema Core。本仓库包含面向 Sui 与 Aptos 的 Move 包、它们的测试，以及协议文档。

参与本项目即表示你同意遵守[行为准则](./CODE_OF_CONDUCT.zh.md)。对于安全问题，请**不要**开启公开 issue — 请遵循 [SECURITY.md](./SECURITY.zh.md)。

## 仓库结构

| 路径 | 内容 |
|------|----------|
| `aas/` | Aptos 包（`aas::*` 模块）、测试、`resolver_example` |
| `sas/` | Sui 包（`sas::*` 模块）、测试、`resolvers` |
| `docs/` | 架构、流程、原则、参考、部署与安全指南 |
| `.github/workflows/` | 两套工具链的 CI |

## 前置要求

- [Aptos CLI](https://aptos.dev/tools/aptos-cli/) `7.14.x` — 用于 `aas/` 和 `aas/resolver_example/`
- [Sui CLI](https://docs.sui.io/guides/developer/getting-started/sui-install) `1.61.x` — 用于 `sas/` 和 `sas/resolvers/`
- GNU Make（可选；`Makefile` 仅封装了 CLI 命令）

Aptos 框架版本固定在 `aas/Move.toml` 中；Sui 框架版本记录在 `sas/Move.lock` 与 `sas/resolvers/Move.lock` 中。首次构建会将框架下载到 `~/.move`。

## 构建与测试

```bash
make test                    # all four packages
make test-aas                # aas
make test-sas                # sas
make test-resolvers          # sas/resolvers
make test-resolver-example   # aas/resolver_example
```

需要额外参数时，可直接运行单个包：

```bash
cd sas && sui move test
cd aas && aptos move test
```

CI 在每次 push 和 pull request 时运行相同命令。只有当四个测试套件全部通过，改动才可合并。

## 提交改动

1. Fork 本仓库，并从 `main` 创建分支（例如 `fix/sas-resolver-check`）。
2. 保持改动聚焦；避免将重构与行为变更混在一起。
3. 为每一处行为变更新增或更新测试。
4. 更新受影响的文档（见下文）。
5. 提交 pull request，说明动机、行为变更以及你运行的测试。

<a id="compatibility-rules"></a>

### 兼容性规则

已发布的包是可升级的。为使升级保持有效：

- 不要重命名或删除公共函数参数、结构体或结构体字段。
- 不要改变结构体字段的顺序或类型。
- 保持事件字段名与顺序稳定；索引器依赖它们。
- 新增字段和函数必须是追加式的，且不得破坏现有调用方。
- 地址派生种子属于公共接口的一部分。修改它们会使现有对象失效。

如果某项改动是有意破坏兼容性的，请在 pull request 和 `CHANGELOG.md` 中说明；这需要新的包版本和迁移方案。

### 提交信息

使用简短的命令式标题，可选择性添加作用域：

```text
sas: reject zero-length schema names
aas: add off-chain attestation tests
docs: document registry version gating
```

### 代码风格

- 遵循周边模块的格式风格。
- 在可用时为 Sui 包运行 `sui move fmt`；不要重新格式化无关代码。
- 优先使用显式错误常量而非魔法数字。
- 保持模块级文档注释最新。

<a id="documentation"></a>

## 文档

每个 Markdown 文件默认使用英文；简体中文翻译使用 `.zh.md` 后缀，且必须保持同步。当你修改文档时：

1. 更新英文文件。
2. 更新对应的 `.zh.md` 文件（若无法完成，请另开 issue 跟进）。
3. 保持语言切换器位于第一行。
4. 验证相对链接可以正确解析。

文档类型：

- `README.md` — 项目概览与快速开始。
- `docs/*/architecture.md` — 设计与不变量。
- `docs/*/flows.md` — 端到端交易流程。
- `docs/*/principles.md` — 设计动机与权衡。
- `docs/reference/*.md` — 模块、函数、事件与错误参考。
- `docs/deployment.md` — 发布与升级流程。

## Pull request 检查清单

- [ ] 已新增或更新测试，且所有测试套件在本地通过。
- [ ] 公共接口与存储布局保持升级兼容。
- [ ] 已更新英文文档。
- [ ] 已更新中文 `.zh.md` 文档。
- [ ] 已为用户可见的变更添加 `CHANGELOG.md` 条目。
- [ ] 未提交密钥、私钥或生成的构建产物。

## 发布流程

维护者：

1. 更新 `CHANGELOG.md`，并在适用处提升版本号。
2. 为仓库打 tag（`vX.Y.Z`）。
3. 按照 [docs/deployment.md](./docs/deployment.zh.md) 发布或升级包。
4. 为下游消费者记录新的包 ID 与 registry 对象 ID。
5. 发布说明，描述合约变更与迁移步骤。

## 许可证

贡献按本仓库的 [Business Source License 1.1](./LICENSE) 授权。
