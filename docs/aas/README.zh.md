[English](./README.md) | 简体中文

# AAS 文档

Aptos Attestation Service —— 以 named object 表示 Schema 与 Attestation，支持可选的 Shelby 链下存储与 dispatchable resolver。

- 包与构建说明：[aas/README.zh.md](../../aas/README.zh.md)
- 模块与 API 参考：[reference/aas.zh.md](../reference/aas.zh.md)
- 部署：[deployment.zh.md](../deployment.zh.md)

## 文档

| 页面 | 内容 |
|------|------|
| [architecture.zh.md](./architecture.zh.md) | 对象模型、模块划分、package-manager signer、Shelby 存储 |
| [flows.zh.md](./flows.zh.md) | 注册、签发、链下、Resolver、撤销的完整流程 |
| [principles.zh.md](./principles.zh.md) | 确定性地址、`ExtendRef`、dispatchable resolver |

## 模块一览

| 模块 | 职责 |
|------|------|
| `aas::aas` | 入口：创建 Schema、签发、链下签发、批量、撤销 |
| `aas::schema` | `Schema` named object、seed/地址推导、视图、`SchemaCreated` |
| `aas::attestation` | `Attestation` named object、存储模式、完整性校验、事件 |
| `aas::package_manager` | 协议级 object signer（`ExtendRef`），创建所有 named object |
| `aas::resolver_dispatcher` | 注册并调用 resolver 回调 |
| `aas::resolver_storage` | 在 dispatcher 与 resolver 之间序列化请求数据 |
| `resolver_example` | 参考实现 `schema_resolver::resolve` |

## 关键不变量

- Schema 与 Attestation 的地址由 `keccak256(bcs(...))` seed 与 package-manager signer 通过 `object::create_object_address` 推导。
- Schema 地址可由内容计算；Attestation 地址还依赖执行时的 `now`，因此应从事件或视图中读取，而不是在签名前预测。
- 签发 seed 包含 `now`（秒）；相同参数在不同秒会得到不同地址。
- 只有 Schema 创建者可以撤销，且要求 Schema 可撤销、Resolver（如有）批准。
- 链下 Attestation 只保存 Blake2b-256 哈希与 Shelby 元数据，数据本体永不上链。
- Resolver 仅在返回 `Some(0)` 时视为通过；已初始化但未注册的 resolver 视为放行。

## 一句话总结

Schema 与 Attestation 都是由 package signer 创建的 named object；Schema 地址可以提前计算，Attestation 地址在执行时间确定后可知。撤销受 Schema 创建者与策略约束；链下数据通过 Blake2b-256 哈希锚定到 Shelby；Resolver 通过 dispatchable fungible asset 回调执行。
