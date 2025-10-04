[English](./sas.md) | 简体中文

# SAS 模块与 API 参考

本文是 [`sas/`](../../sas) 中 Sui Attestation Service 包的参考文档。设计背景参见 [SAS 架构](../sas/architecture.zh.md)；端到端流程参见 [SAS 流程](../sas/flows.zh.md)。

源文件：[`sas.move`](../../sas/sources/sas.move)、[`schema.move`](../../sas/sources/schema.move)、[`attestation.move`](../../sas/sources/attestation.move)、[`schema_registy.move`](../../sas/sources/schema_registy.move)（模块 `sas::schema_registry`）、[`attestation_registry.move`](../../sas/sources/attestation_registry.move)、[`admin.move`](../../sas/sources/admin.move)、[`constants.move`](../../sas/sources/constants.move)、[`seal_access.move`](../../sas/sources/seal_access.move)。

## 模块地图

| 模块 | 公开接口 |
|--------|----------------|
| `sas::sas` | schema 注册、attestation 与撤销的门面 |
| `sas::schema` | `Schema`、Resolver 配置、hot-potato `Request` |
| `sas::attestation` | `Attestation` 对象、存储模式、完整性校验 |
| `sas::schema_registry` | 带版本门控的共享 schema 索引 |
| `sas::attestation_registry` | 带版本门控的共享 attestation 状态索引 |
| `sas::admin` | 与 Schema 绑定的 `Admin` capability |
| `sas::constants` | `CURRENT_VERSION` |
| `sas::seal_access` | Seal key-id 计算与 `seal_approve` |

## `sas::sas`

### 函数

```move
public fun register_schema(
    schema_registry: &mut SchemaRegistry, schema: vector<u8>, name: vector<u8>,
    description: vector<u8>, url: vector<u8>, revokable: bool, ctx: &mut TxContext,
): Admin

public fun register_schema_with_resolver(
    schema_registry: &mut SchemaRegistry, schema: vector<u8>, name: vector<u8>,
    description: vector<u8>, url: vector<u8>, revokable: bool, ctx: &mut TxContext,
): (ResolverBuilder, Admin, Schema)

public fun attest(
    schema_record: &mut Schema, attestation_registry: &mut AttestationRegistry,
    ref_attestation: address, recipient: address, expiration_time: u64,
    data: vector<u8>, name: vector<u8>, description: vector<u8>, url: vector<u8>,
    time: &Clock, ctx: &mut TxContext,
): address

public fun attest_multi(...)

public fun attest_off_chain(
    schema_record: &mut Schema, attestation_registry: &mut AttestationRegistry,
    ref_attestation: address, recipient: address, expiration_time: u64,
    walrus_sui_object_id: address, walrus_blob_id: vector<u8>, data_hash: vector<u8>,
    encrypted: bool, seal_nonce: Option<vector<u8>>, seal_policy_id: Option<address>,
    name: vector<u8>, description: vector<u8>, url: vector<u8>,
    time: &Clock, ctx: &mut TxContext,
): address

public fun attest_with_resolver(..., request: Request, ...): address
public fun revoke(admin: &Admin, attestation_registry: &mut AttestationRegistry,
                  schema_record: &Schema, attestation: address, ctx: &mut TxContext)
public fun revoke_multi(...)
public fun revoke_with_resolver(..., request: Request, ...)
```

行为细节：

- `attest` 会拒绝带有 Resolver 的 schema（`EHasResolver`）。
- 非零的 `ref_attestation` 必须已存在于 attestation registry 中（`ERefIdNotFound`）。
- 非零的 `expiration_time` 必须大于 `clock.timestamp_ms()`（`EExpired`）。
- 过期时间的单位是毫秒。
- `revokable` 从 schema 复制而来，不由 attestor 选择。

### 错误

| 常量 | 错误码 | 触发条件 |
|----------|------|-----------|
| `EExpired` | 0 | `expiration_time` 已经过去 |
| `ERefIdNotFound` | 1 | 引用的 attestation 未注册 |
| `EHasResolver` | 2 | 在带 Resolver 的 schema 上使用了普通调用（或反之） |
| `EInvalidLength` | 3 | 批量向量长度不一致 |

## `sas::schema`

### 结构体

`Schema` (`key, store`): `id: UID`, `name: String`, `description: String`, `url: Url`, `creator: address`, `created_at: u64`, `schema: vector<u8>`, `revokable: bool`, `resolver: Option<Resolver>`.

`Resolver` (`store`): `rules: VecMap<String, VecSet<TypeName>>`, `config: Bag`, `resolver_address: address`, `resolver_module: vector<u8>`.

`ResolverBuilder` (`store`): `schema_address`, `resolver_address`, `resolver_module`, `rules`, `config: Bag`.

`Request`（hot potato，无 abilities）: `name: String`, `schema_address: address`, `approvals: VecSet<TypeName>`.

### 事件

`SchemaCreated`：

```text
event_type, schema_address, name, description, url, creator, created_at,
schema, revokable, admin_cap
```

`event_type` 在 `new` 中为 `0`，在 `new_with_resolver` 中为 `1`。走普通路径时 `admin_cap` 为 `@0x0`。

### 生命周期函数

| 函数 | 用途 |
|----------|---------|
| `new(registry, schema, name, description, url, revokable, ctx): Admin` | 创建并 share 一个 schema，返回 admin cap |
| `new_with_resolver(...): (ResolverBuilder, Admin, Schema)` | 创建 schema 但不 share；由调用方配置后再 share |
| `share_schema(schema)` | share 由 `new_with_resolver` 创建的 schema |
| `add_resolver(schema, builder)` | 将配置好的 Resolver 附加到 schema |
| `new_resolver_builder(admin, schema, ctx)` | 开始配置 Resolver |
| `add_resolver_address(builder, address)` / `add_resolver_module(builder, bytes)` | 设置 Resolver 目标 |
| `add_rule<Rule: drop>(builder, name, witness)` | 为某个请求类型要求 witness |
| `add_rule_config<Rule: drop, Config: store>(builder, witness, config)` | 附加带类型的配置 |
| `start_attest(schema): Request` / `start_revoke(schema): Request` | 发起 Resolver 请求 |
| `finish_attest(schema, request)` / `finish_revoke(schema, request)` | 检查所有规则均已批准并消耗该请求 |
| `approve<Rule: drop>(request, witness)` | 记录一次 Resolver 批准 |
| `config<Rule, Config>(schema): &Config` / `config_mut<Rule, Config>(schema): &mut Config` | 读写带类型的配置 |

### 视图函数

`schema`, `name`, `description`, `url`, `created_at`, `creator`, `revokable`, `addy`, `has_resolver`, `resolver_address`, `resolver_module`, `get_resolver_address`, `start_attest_name`, `start_revoke_name`, `schema_address_from_request`, `request_name`, `approvals`, `schema_address_from_builder`, `rules`, `config_from_builder`.

### 错误

| 常量 | 错误码 | 触发条件 |
|----------|------|-----------|
| `EWrongSchemaAddress` | 0 | Builder/Request 属于另一个 schema |
| `ENoResolver` | 1 | 在普通 schema 上使用了仅限 Resolver 的函数 |
| `EMustBeFinishRequest` | 2 | Request 类型与 finish 调用不匹配 |
| `ERuleNotApproved` | 3 | 某个必需规则未被批准 |

## `sas::attestation`

### 结构体

`Attestation` (`key`): `id: UID`, `schema`, `ref_attestation`, `time`, `expiration_time`, `revokable`, `attestor`, `storage_type`, `data`, `walrus_sui_object_id`, `walrus_blob_id`, `data_hash`, `encrypted`, `seal_nonce`, `seal_policy_id`, `name`, `description`, `url`.

没有 `recipient` 字段：所有权通过转移对象来表达。

### 事件

`AttestationCreated`：

```text
event_type, id, schema, ref_attestation, time, expiration_time, revokable,
attestor, recipient, storage_type, data, walrus_sui_object_id, walrus_blob_id,
data_hash, encrypted, seal_nonce, seal_policy_id, name, description, url
```

`event_type` 在 `attest` 中为 `0`，在 `attest_with_resolver` 中为 `1`。

### 视图函数

| 函数 | 返回 |
|----------|---------|
| `schema`, `ref_attestation`, `attestor`, `time`, `revokable`, `expiration_time` | 标量字段访问器 |
| `storage_type` | `u8` |
| `is_on_chain_storage`, `is_off_chain_storage` | `bool` |
| `data` | 链上载荷；链下为空 |
| `data_hash` | 链下时为 `Option<vector<u8>>` |
| `walrus_sui_object_id`, `walrus_blob_id` | 链下时为 `Option<...>` |
| `seal_nonce`, `seal_policy_id` | 加密的链下场景为 `Option<...>` |
| `is_encrypted` | `bool` |
| `verify_data_integrity(attestation, data)` | `bool`；断言为链下存储 |
| `name`, `description`, `url` | 元数据 |

`verify_data_integrity` 将 `hash::blake2b256(data)` 与 `data_hash` 进行比较。

## `sas::schema_registry`

`SchemaRegistry` (`key, store`) 包装一个 `Versioned`，其中包含 `allowed_versions: VecSet<u64>` 与 `schema_records: Table<address, address>`。

| 函数 | 用途 |
|----------|---------|
| `update_allowed_versions(admin_cap, registry, versions)` | 替换允许的版本集合 |
| `is_exist(registry, schema): bool` | 某个 schema 是否已注册 |
| `schemas(registry): &Table<address, address>` | Schema → 创建者 |
| `creator(registry, schema): &address` | 查询创建者 |
| `size(registry): u64` | schema 数量 |

错误：`EVersionNotEnabled` (0)、`ESchmaAlreadyExist` (1)。

## `sas::attestation_registry`

`AttestationRegistry` (`key, store`) 包装 `Versioned`，其中包含 `allowed_versions` 与 `attestations_status: Table<address, Status>`。

`Status` (`copy, store`): `schema_address: address`, `is_revoked: bool`, `timestamp: u64`.

| 函数 | 用途 |
|----------|---------|
| `update_allowed_versions(admin_cap, registry, versions)` | 替换允许的版本集合 |
| `is_exist(registry, attestation): bool` | 该 attestation 是否已被索引 |
| `is_revoked(registry, attestation): bool` | 撤销状态 |
| `status(registry, attestation): &Status` | 完整状态 |
| `attestations(registry): &Table<address, Status>` | 完整索引 |

错误：`EAttestationNotFound` (0)、`EVersionNotEnabled` (1)、`EAttestationAlreadyRevoked` (2)、`ENotBelongToSchema` (3)、`ENotRevokable` (4)。

## `sas::admin`

`Admin` (`key, store`): `id: UID`, `schema: address`.

函数：`addy`、`schema`、`assert_schema(admin, schema)`、`destroy(admin)`、`new(schema, ctx)`（仅包内使用）。

## `sas::constants`

`CURRENT_VERSION: u64 = 1`；`current_version(): u64`。

## `sas::seal_access`

| 函数 | 用途 |
|----------|---------|
| `compute_key_id(attestor, nonce): vector<u8>` | `bcs(attestor) ‖ nonce` |
| `seal_approve(id, attestation)` (entry) | 校验 key id 与加密元数据；否则以 `ENoAccess` (0) 中止 |

完整的 Seal identity 是 `[package id][attestor][nonce]`。只有 attestation 对象的所有者才能把 `&Attestation` 传给 `seal_approve`，从而把解密权限绑定到 recipient。

## 参考 Resolver（`sas/resolvers`）

`resolvers::whitelist` 与 `resolvers::blocklist` 实现了 Resolver 模式：

- `add(schema, builder, ctx)` 注册 Resolver 的地址/模块，要求 `START_ATTEST`/`START_REVOKE` 规则，并存储一份 `Table<address, bool>` 配置。
- `approve(schema, request, ctx)` 将调用方与名单比对并批准该规则。
- `add_user` / `remove_user` 修改配置（仅 Admin）。
- 视图函数：`is_whitelisted`、`is_blocklisted`。

## 兼容性说明

- `schema_registy.move` 是定义 `sas::schema_registry` 的文件；该文件名是历史遗留的拼写错误，不影响 ABI。
- Registry 的版本门控要求每次包升级**前**预先授权新版本；`update_allowed_versions` 本身也要通过同一检查。
- 结构体字段顺序与公开签名是升级兼容性检查的一部分。
