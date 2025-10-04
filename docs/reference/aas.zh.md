[English](./aas.md) | 简体中文

# AAS 模块与 API 参考

[`aas/`](../../aas) 中 Aptos Attestation Service 包的参考。设计背景见 [AAS architecture](../aas/architecture.zh.md)；端到端流程见 [AAS flows](../aas/flows.zh.md)。

源文件：[`aas.move`](../../aas/sources/aas.move)、[`schema.move`](../../aas/sources/schema.move)、[`attestation.move`](../../aas/sources/attestation.move)、[`package_manager.move`](../../aas/sources/package_manager.move)、[`resolver_dispatcher.move`](../../aas/sources/resolver/resolver_dispatcher.move)、[`resolver_storage.move`](../../aas/sources/resolver/resolver_storage.move)。

## 模块映射

| 模块 | 公开接口 |
|--------|----------------|
| `aas::aas` | Schema 与 Attestation 生命周期的入口函数 |
| `aas::schema` | Schema 对象、事件、地址与 seed 派生 |
| `aas::attestation` | Attestation 对象、事件、存储与完整性视图 |
| `aas::package_manager` | 用于派生所有 named object 的对象签名者 |
| `aas::resolver_dispatcher` | Resolver 注册与分发 |
| `aas::resolver_storage` | 与 Resolver 共享的序列化请求存储 |

## `aas::aas`

### 入口函数

```move
public entry fun create_schema(
    creator: &signer,
    schema: vector<u8>,
    name: String,
    description: String,
    url: String,
    revokable: bool,
    resolver: address,
)

public entry fun create_attestation(
    attestor: &signer,
    recipient: address,
    schema_addr: address,
    ref_attestation: address,
    expiration_time: u64,
    revokable: bool,
    data: vector<u8>,
)

public entry fun create_multi_attestations(
    attestor: &signer,
    recipients: vector<address>,
    schema_addr: address,
    ref_attestations: vector<address>,
    expiration_times: vector<u64>,
    revokable: bool,
    data: vector<vector<u8>>,
)

public entry fun create_attestation_off_chain(
    attestor: &signer,
    recipient: address,
    schema_addr: address,
    ref_attestation: address,
    expiration_time: u64,
    revokable: bool,
    data_hash: vector<u8>,
    shelby_account: address,
    shelby_blob_name: String,
    shelby_blob_merkle_root: vector<u8>,
    shelby_register_tx_hash: vector<u8>,
)

public entry fun revoke_attestation(
    admin: &signer,
    schema_addr: address,
    attestation: address,
)

public entry fun revoke_multi_attestations(
    admin: &signer,
    schema_addr: vector<address>,
    attestations: vector<address>,
)
```

`create_schema` 强制执行的字符串限制：`name < 128`、`description < 512`、`url < 512` 字节。

### 公共辅助函数

`*_and_get_address` 变体返回派生出的地址，供测试和其他 Move 代码使用：

- `create_schema_and_get_schema_address`
- `create_attestation_and_get_address`
- `create_attestation_off_chain_and_get_address`

### 错误

| 常量 | 代码 | 条件 |
|----------|------|-----------|
| `ESTRING_TOO_LONG` | 1 | 名称/描述/url 超出其限制 |
| `ENOT_SCHEMA_CREATOR` | 2 | 撤销者不是 Schema 创建者 |
| `E_NOT_REVOKABLE` | 3 | Schema 不可撤销 |
| `EATTESTATION_NOT_FOUND` | 4 | Attestation 对象不存在 |
| `EATTESTATION_ALREADY_REVOKED` | 5 | Attestation 已被撤销 |
| `EATTESTATIONS_NOT_EXIST_AT_ADDRESS` | 6 | `ref_attestation` 当前必须不存在（见注释） |
| `ESCHEMA_NOT_FOUND` | 7 | Schema 对象不存在 |
| `ERESOLVE_FAILED` | 8 | Resolver 返回非零值或未返回任何值 |
| `EINVALID_LENGTH` | 9 | 批量向量长度不一致 |

> **参考说明：** `create_attestation` 与 `create_attestation_off_chain` 会断言 `!attestation::attestation_exists(ref_attestation)`。按当前实现，只有 `@0x0` 是安全的。该检查预计会被修订；在此之前，不要基于引用构建生产流程。

## `aas::schema`

### 结构体

`Schema`（`key`）：

| 字段 | 类型 | 说明 |
|-------|------|-------|
| `name` | `String` | |
| `description` | `String` | |
| `url` | `String` | |
| `creator` | `address` | |
| `created_at` | `u64` | 秒 |
| `schema` | `vector<u8>` | 不透明的 Schema 载荷 |
| `revokable` | `bool` | |
| `resolver` | `address` | `@0x0` 表示无 Resolver |
| `tx_hash` | `vector<u8>` | 保留；当前为空 |

`SchemaData` 为 `schema_data` 视图镜像这些字段。

### 事件

`SchemaCreated`：

```text
schema_address, name, description, url, creator, created_at, revokable, resolver, schema
```

### 视图

| 函数 | 返回 |
|----------|---------|
| `schema_data(address)` | `SchemaData` |
| `schema_unpacked(address)` | `(String, String, String, address, u64, vector<u8>, bool, address)` |
| `schema_creator(address)` | `address` |
| `schema_revokable(address)` | `bool` |
| `schema_resolver(address)` | `address` |
| `schema_exists(address)` | `bool` |
| `get_schema_address(name, description, url, revokable, resolver, schema)` | `address` |
| `get_schema_seeds(name, description, url, revokable, resolver, schema)` | `vector<u8>` |

### Seed 派生

```text
seed = keccak256(
    bcs(name) ‖ bcs(description) ‖ bcs(url) ‖ bcs(revokable) ‖ bcs(resolver) ‖ schema
)
address = object::create_object_address(package_manager_signer, seed)
```

## `aas::attestation`

### 结构体

`Attestation`（`key`）：

| 字段 | 类型 | 说明 |
|-------|------|-------|
| `schema` | `address` | Schema 对象地址 |
| `ref_attestation` | `address` | 保留引用 |
| `time` | `u64` | 秒 |
| `expiration_time` | `u64` | 秒；`0` = 永不过期 |
| `revocation_time` | `u64` | 撤销前为 `0` |
| `revokable` | `bool` | 签发时从 Schema 复制 |
| `attestor` | `address` | |
| `recipient` | `address` | |
| `storage_type` | `u8` | `0` 表示链上，`1` 表示 Shelby |
| `data` | `vector<u8>` | 链上载荷 |
| `data_hash` | `vector<u8>` | 链下场景使用 Blake2b-256 |
| `shelby_account` | `address` | Shelby 账户 |
| `shelby_blob_name` | `String` | Shelby blob 名称 |
| `shelby_blob_merkle_root` | `vector<u8>` | Shelby 注册元数据 |
| `shelby_register_tx_hash` | `vector<u8>` | Shelby 注册交易哈希 |

`AttestationData` 为 `attestation_data` 视图镜像所有字段。

### 事件

`AttestationCreated`：

```text
attestation_address, schema, ref_attestation, time, expiration_time, revokable,
attestor, recipient, storage_type, data, data_hash, shelby_account,
shelby_blob_name, shelby_blob_merkle_root, shelby_register_tx_hash
```

`AttestationRevoked`：

```text
attestation_address, revocation_time
```

### 视图

| 函数 | 返回 |
|----------|---------|
| `attestation_data(address)` | `AttestationData` |
| `attestation_unpacked(address)` | 15 元组：`(schema, ref, time, expiration, revocation, revokable, attestor, recipient, storage_type, data, data_hash, shelby_account, shelby_blob_name, merkle_root, register_tx_hash)` |
| `attestation_exists(address)` | `bool` |
| `attestation_revoked(address)` | `bool`（`revocation_time != 0`） |
| `storage_type(address)` | `u8` |
| `data_hash(address)` | `vector<u8>` |
| `shelby_account(address)` | `address` |
| `shelby_blob_name(address)` | `String` |
| `verify_data_integrity(address, data)` | `bool`；对于链上 Attestation 为 false |
| `get_attestation_address(attestor, schema, recipient, ref_id, expiration_time, revokable, now, data)` | `address` |
| `get_attestation_address_off_chain(attestor, schema, recipient, ref_id, expiration_time, revokable, now, data_hash, shelby_account, shelby_blob_name)` | `address` |
| `get_attestation_seeds(...)` | `vector<u8>` |
| `get_attestation_seeds_off_chain(...)` | `vector<u8>` |

### Seed 派生

链上：

```text
seed = keccak256(
    bcs(attestor) ‖ bcs(schema) ‖ bcs(recipient) ‖ bcs(ref_id) ‖ bcs(expiration_time)
    ‖ bcs(revokable) ‖ bcs(now) ‖ data
)
```

链下则把末尾的 `data` 替换为：

```text
data_hash ‖ bcs(shelby_account) ‖ bcs(shelby_blob_name)
```

`now` 是创建时的 `timestamp::now_seconds()`。视图辅助函数显式接收 `now`，以便调用方复现地址。

## `aas::package_manager`

在发布时创建协议对象签名者：

```move
fun init_module(signer: &signer) {
    let construct_ref = object::create_object(signer::address_of(signer));
    let extend_ref = object::generate_extend_ref(&construct_ref);
    move_to(signer, PermissionConfig { extend_ref, addressess: table::new() });
}
```

| 函数 | 可见性 | 用途 |
|----------|-----------|---------|
| `get_signer()` | `public(friend)` | 用于创建 named object 的对象签名者 |
| `get_signer_address()` | `public(friend)` | seed 派生中使用的签名者地址 |
| `add_address(name, object)` | `public(friend)` | 保留的记账表 |
| `address_exists(name)` | `public` | 保留的记账表 |
| `get_address(name)` | `public` | 保留的记账表 |

## `aas::resolver_dispatcher`

```move
public fun on_attest(module_address, attestor, recipient, schema_address,
                     ref_attestation, expiration_time, revokable, data): bool
public fun on_revoke(module_address, revoker, schema_address, attestation): bool
public fun register_dispatchable(signer: &signer)
```

行为：

- 如果 `resolver_storage::dispatcher_is_exists(module_address)` 为 false，则请求被视为已批准（`true`）。
- 否则，dispatcher 将请求打包进 `resolver_storage`，通过 dispatchable 同质化资产调用 Resolver 的 `resolve`，并且仅对 `option::some(VERIFY_SUCCESS)` 返回 `true`，其中 `VERIFY_SUCCESS = 0`。
- `register_dispatchable` 会创建一个名为 `resolver`/`dispatch` 的同质化元数据对象，其 derived-supply 分发函数为签名者地址上的 `schema_resolver::resolve`。

## `aas::resolver_storage`

`Dispatcher` 在 package manager 签名者地址上持有 `dispatcher: Table<address, Object<Metadata>>` 和 `data: Table<address, vector<u8>>`。

| 函数 | 可见性 | 用途 |
|----------|-----------|---------|
| `initialize()` | `entry` | 幂等地创建 `Dispatcher` |
| `is_initialized()` | `view` | `Dispatcher` 是否存在 |
| `retrieve(module_address)` | `public` | 读取序列化后的请求 |
| `dispatcher_metadata(signer_address)` | `view` | 某个 Resolver 的元数据对象 |
| `dispatcher_is_exists(signer_address)` | `view` | Resolver 是否已注册 |
| `pack_attest_data(...)` / `pack_revoke_data(...)` | `view` | 序列化请求 |
| `unpack_attest_data(data)` | `view` | 解码 attest 请求 |
| `unpack_revoke_data(data)` | `view` | 解码 revoke 请求 |

序列化布局——attest：`type(0) ‖ attestor(32) ‖ recipient(32) ‖ schema(32) ‖ ref(32) ‖ expiration(8) ‖ revokable(1) ‖ data`；revoke：`type(1) ‖ revoker(32) ‖ schema(32) ‖ attestation(32)`。

`E_DISPATCHER_NOT_FOUND = 1` 在缺少 Resolver 或请求条目时抛出。

## 兼容性说明

- seed 输入与顺序对共识至关重要：改动它们会改变每个 Schema 和 Attestation 地址。
- 结构体字段顺序与类型是升级兼容性检查的一部分。
- 事件字段名与顺序会被索引器使用。
- `package_manager` 对象签名者必须在升级之间保持稳定。
