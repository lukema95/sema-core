[English](./README.md) | 简体中文

# SAS 文档

Sui Attestation Service —— 共享 schema、归接收方所有的 attestation、带版本门控的 registry、Walrus 存储，以及 Seal 加密。

- 包与构建说明：[sas/README.md](../../sas/README.zh.md)
- 模块与 API 参考：[reference/sas.md](../reference/sas.zh.md)
- 部署：[deployment.md](../deployment.zh.md)

## 文档

| 页面 | 内容 |
|------|----------|
| [architecture.md](./architecture.zh.md) | 对象模型、registry、resolver hot potato、Seal、版本管理 |
| [flows.md](./flows.zh.md) | 注册、签发、链下、resolver、撤销流程 |
| [principles.md](./principles.zh.md) | 设计理由与权衡取舍 |

## 模块地图

| 模块 | 职责 |
|--------|----------------|
| `sas::sas` | 门面：注册 schema、签发 attestation、链下签发 attestation、resolver 路径、撤销 |
| `sas::schema` | `Schema`、`Resolver`、`ResolverBuilder`、`Request`、`SchemaCreated` |
| `sas::attestation` | `Attestation` 对象、存储模式、Seal 字段、完整性检查 |
| `sas::schema_registry` | 带版本门控的共享 schema 索引 |
| `sas::attestation_registry` | 带版本门控的共享 attestation 状态索引 |
| `sas::admin` | 绑定 schema 的 `Admin` capability |
| `sas::constants` | `CURRENT_VERSION` |
| `sas::seal_access` | Seal key-id 派生与仅限接收方的 `seal_approve` |
| `resolvers` | 参考用白名单与黑名单 resolver |

## 关键不变量

- `Schema` 在 `new` 时共享，或在 `new_with_resolver` 之后调用 `share_schema` 共享；`Attestation` 由接收方 owned；registry 是 shared 系统对象。
- 撤销需要 schema 的 `Admin` capability、一个可撤销的 schema，以及一个属于该 schema 的、已存在且尚未撤销的 attestation。`admin::new` 目前是 public 且无校验，因此不能把它当作安全边界。
- registry 版本检查在每次加载时执行；升级**前**必须先用 `update_allowed_versions` 预先授权新的 `CURRENT_VERSION`。
- 过期时间以毫秒计；`0` 表示永不过期。
- 链下数据保存 Walrus 指针与调用方提供的 Blake2b-256 哈希；客户端必须自行校验（合约只提供可选的 view）。
- resolver 流程使用 hot-potato `Request`；在所有已配置规则批准后，`finish_attest`/`finish_revoke` 将其消费掉。

## 一句话总结

Sui 的对象模型让 schema 成为 shared、attestation 归接收方 owned，并让 registry 成为 shared 的事实来源；resolver 通过 hot-potato request 与 witness 强制执行，加密载荷则由 Seal 对象所有权把关。
