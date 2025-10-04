[English](./README.md) | 简体中文

# SAS — Sui Attestation Service

SAS 在 Sui 上实现 Attestation 协议。`Schema` 在以 `new` 创建时会成为共享对象，或在 `new_with_resolver` + `share_schema` 之后成为共享对象；每个 `Attestation` 都是由其 recipient 拥有的对象；两个受版本门控的共享 registry 分别索引 Schema 和 Attestation。数据可以存放在链上或 Walrus 中，并可选地使用 Seal 加密。

- 源码：[`sources/`](./sources)
- 测试：[`tests/`](./tests)
- 参考 Resolver：[`resolvers/`](./resolvers)
- 完整 API 参考：[docs/reference/sas.md](../docs/reference/sas.zh.md)

## 模块

| 模块 | 职责 |
|--------|----------------|
| `sas::sas` | 门面层：注册 Schema、attest、链下 attest、通过 Resolver 进行 attest/revoke |
| `sas::schema` | `Schema`、`Resolver`、`ResolverBuilder`、`Request`、Schema 视图、`SchemaCreated` 事件 |
| `sas::attestation` | `Attestation` 对象、存储模式、Seal 字段、完整性校验、`AttestationCreated` 事件 |
| `sas::schema_registry` | 带版本门控的 Schema 共享 registry |
| `sas::attestation_registry` | 带版本门控的 Attestation 状态共享 registry |
| `sas::admin` | 绑定到某个 Schema 的 `Admin` capability；撤销时需要 |
| `sas::constants` | 两个 registry 都使用的 `CURRENT_VERSION` |
| `sas::seal_access` | Seal key-id 推导与仅限 recipient 的 `seal_approve` |

## 对象模型

- `Schema` 由 `schema::new` 创建（立即共享），或由 `new_with_resolver` 创建（返回给调用方，调用方必须在配置好 Resolver 后调用 `share_schema`）。
- `Admin` 是随 Schema 一同创建的 owned capability，并被转移给创建者。撤销时需要它。
- `Attestation` 是转移给 recipient 的 owned 对象。事件中携带 recipient；struct 本身不携带。
- `SchemaRegistry` 和 `AttestationRegistry` 是包发布时由各自模块的初始化函数创建的共享对象。每个都在 `Versioned` 容器中保存 `allowed_versions`。

## 存储模式

| `storage_type` | 值 | 字段 |
|----------------|-------|--------|
| 链上 | `0` | `data`；Walrus/Seal 字段为空 |
| Walrus | `1` | `walrus_sui_object_id`, `walrus_blob_id`, `data_hash`, `encrypted`, `seal_nonce`, `seal_policy_id`；`data` 为空 |

`attestation::verify_data_integrity` 计算 `blake2b256(data)` 并与 `data_hash` 比较；对于链上 Attestation 会 abort。

过期时间为 Unix 毫秒（`Clock::timestamp_ms`）；`0` 表示永不过期。

## 入口点

SAS 暴露的是可与其他 Move 代码组合的 public（非 `entry`）函数；典型交易会直接调用它们。

| 函数 | 用途 |
|----------|---------|
| `sas::register_schema(registry, schema, name, description, url, revokable, ctx)` | 创建并共享一个 Schema；返回 `Admin` |
| `sas::register_schema_with_resolver(registry, schema, name, description, url, revokable, ctx)` | 创建一个 Schema 及 `ResolverBuilder`；由调用方配置并共享 |
| `sas::attest(schema, registry, ref_attestation, recipient, expiration_time, data, name, description, url, clock, ctx)` | 签发一个链上 Attestation |
| `sas::attest_multi(...)` | 批量签发链上 Attestation |
| `sas::attest_off_chain(schema, registry, ref_attestation, recipient, expiration_time, walrus_sui_object_id, walrus_blob_id, data_hash, encrypted, seal_nonce, seal_policy_id, name, description, url, clock, ctx)` | 签发一个由 Walrus 支撑的 Attestation |
| `sas::attest_with_resolver(...)` | 完成 Resolver 请求并签发 Attestation |
| `sas::revoke(admin, registry, schema, attestation, ctx)` | 撤销一个 Attestation（不使用 Resolver） |
| `sas::revoke_multi(...)` | 批量撤销 |
| `sas::revoke_with_resolver(..., request, ctx)` | 完成 Resolver 请求并撤销 |

非零的 `ref_attestation` 必须已存在于 Attestation registry 中。

## Resolver 流程

Sui 的 Resolver 使用 hot-potato `Request`。设置与签发发生在不同的交易中：

```move
// Transaction 1 — create and configure the schema, then share it.
let (mut builder, _admin, mut schema) =
    sas::register_schema_with_resolver(registry, schema_bytes, name, description, url, true, ctx);
whitelist::add(&schema, &mut builder, ctx);   // rules, config, resolver address and module
schema::add_resolver(&mut schema, builder);
schema::share_schema(schema);

// Transaction 2 — obtain approvals, then issue through the resolver.
let mut request = schema::start_attest(&schema);
whitelist::approve(&schema, &mut request, ctx);          // request.approve(witness)
sas::attest_with_resolver(
    &mut schema, registry, ref_attestation, recipient, expiration_time,
    data, name, description, url, clock, request, ctx,
);                                                        // finish_attest runs inside
```

`schema::finish_attest` 也是 public 的，但它会消耗 `Request`；`attest_with_resolver` 已经执行了规则检查，是推荐的入口点。撤销遵循同样的模式，使用 `start_revoke` 和 `revoke_with_resolver`。

每个 Schema 都有一个可选的 `Resolver`，包含 `rules`、带类型的 `config: Bag`、`resolver_address` 以及 `resolver_module`。参考实现是 [`whitelist`](./resolvers/sources/whitelist.move) 和 [`blocklist`](./resolvers/sources/blocklist.move)。

## 事件

| 事件 | 字段 |
|-------|--------|
| `schema::SchemaCreated` | `event_type`（0 = 普通，1 = 带 Resolver）、`schema_address, name, description, url, creator, created_at, schema, revokable, admin_cap`。`admin_cap` 在 type 0 时为 `@0x0`，在 type 1 时为 Admin 对象地址 |
| `attestation::AttestationCreated` | `event_type`（0 = attest，1 = 带 Resolver；链下签发也使用 0）、`id, schema, ref_attestation, time, expiration_time, revokable, attestor, recipient, storage_type, data, walrus_sui_object_id, walrus_blob_id, data_hash, encrypted, seal_nonce, seal_policy_id, name, description, url` |

## Seal 访问控制

`seal_access::compute_key_id(attestor, nonce)` 返回 `bcs(attestor) ‖ nonce`；完整的 Seal 身份是 `[package id][attestor][nonce]`。`seal_approve(id, attestation)` 是一个 entry 函数，仅当该 Attestation 已加密、其 nonce 匹配且调用方拥有该 Attestation 对象时才会成功 —— Sui 的对象所有权机制保证只有 recipient 能把它出示给 key server。

## 版本管理

两个 registry 都保存 `allowed_versions`，并在每次加载时检查 `constants::current_version()`。`update_allowed_versions` 自身也会执行该检查，因此新版本必须**在升级之前**获得授权：

1. 在旧包仍生效时，用旧版本和新版本调用 `schema_registry::update_allowed_versions` 和 `attestation_registry::update_allowed_versions`（使用 admin caps）。
2. 提升 `CURRENT_VERSION`。
3. 发布升级。

若在步骤 1 之前发布，所有 registry 调用都会以 `EVersionNotEnabled` abort，包括该更新本身。

## 错误

部分错误码：`schema` —— `EWrongSchemaAddress` (0)、`ENoResolver` (1)、`EMustBeFinishRequest` (2)、`ERuleNotApproved` (3)；`attestation_registry` —— `EAttestationNotFound` (0)、`EVersionNotEnabled` (1)、`EAttestationAlreadyRevoked` (2)、`ENotBelongToSchema` (3)、`ENotRevokable` (4)；`schema_registry` —— `EVersionNotEnabled` (0)、`ESchmaAlreadyExist` (1)；`seal_access` —— `ENoAccess` (0)。

## 已知限制

- `admin::new` 是 public 且无保护的，因此任何人都可以为任意 schema 铸造 `Admin`。在本修订版本中，撤销和 Resolver 管理**不受**该 capability 保护。参见 [Security model](../docs/security-model.zh.md#1-sas-admin-is-an-unauthenticated-bearer-capability)。
- 链下签发无法使用 Resolver（`attest_off_chain` 会拒绝带 Resolver 的 Schema），并且批量函数没有对应的 Resolver 变体。
- 存储的 `data_hash` 由调用方提供；只有可选的 `verify_data_integrity` 视图会校验它。
- 撤销不会发出事件；从 Move 中只能读取 `AttestationRegistry::is_revoked`。

## 构建与测试

```bash
cd sas
sui move test
```

## 部署

```bash
cd sas
sui client publish --gas-budget 100000000
```

发布过程会运行两个 registry 的初始化函数，并将 registry admin caps 转移给发布者。记录 package ID、`SchemaRegistry` ID 和 `AttestationRegistry` ID；`Published.toml` 保存包元数据。参见 [docs/deployment.md](../docs/deployment.zh.md)。

保持 public 函数签名和 struct 布局的升级兼容性。

## 许可证

Business Source License 1.1 —— 见 [LICENSE](../LICENSE)。
