[English](./README.md) | 简体中文

# AAS — Aptos Attestation Service

AAS 在 Aptos 上实现 Attestation 协议。Schema 和 Attestation 均是由协议自有的对象签名者创建的**命名对象（named object）**，因此其地址是自身内容与创建参数的确定性函数。Attestation 存储在链上，或通过 [Shelby](https://shelby.xyz/) 在链下引用；可选的 Resolver 负责校验签发与撤销。

- 源码：[`sources/`](./sources)
- 测试：[`tests/`](./tests)
- 示例 Resolver：[`resolver_example/`](./resolver_example)
- 完整 API 参考：[docs/reference/aas.md](../docs/reference/aas.zh.md)

## 模块

| 模块 | 职责 |
|--------|----------------|
| `aas::aas` | 入口点：创建 Schema、签发/撤销 Attestation、批量操作 |
| `aas::schema` | `Schema` 对象、Schema 地址推导、Schema 视图与 `SchemaCreated` 事件 |
| `aas::attestation` | `Attestation` 对象、存储模式、完整性校验、地址推导、事件 |
| `aas::package_manager` | 协议对象签名者（`ExtendRef`），用于创建所有命名对象 |
| `aas::resolver_dispatcher` | 将 attest/revoke 校验分发到 Resolver 模块 |
| `aas::resolver_storage` | 在模块之间存储 Resolver 元数据和序列化的请求数据 |

## 对象模型

发布时，`package_manager::init_module` 创建一个由包账户拥有的对象，并将其 `ExtendRef` 存储到 `@aas` 处的 `PermissionConfig` 中。每个 Schema 和 Attestation 都是用该对象的签名者创建的命名对象：

```text
schema_seed      = keccak256(bcs(name) ‖ bcs(description) ‖ bcs(url) ‖ bcs(revokable) ‖ bcs(resolver) ‖ schema_bytes)
attestation_seed = keccak256(bcs(attestor) ‖ bcs(schema) ‖ bcs(recipient) ‖ bcs(ref_attestation)
                             ‖ bcs(expiration_time) ‖ bcs(revokable) ‖ bcs(now) ‖ data)
```

链下 Attestation 追加的是 `data_hash ‖ bcs(shelby_account) ‖ bcs(shelby_blob_name)`，而不是 `data`。最终地址为 `object::create_object_address(package_manager_signer, seed)`，由 `get_*_address` 视图暴露。

由于 `now` 是 seed 的一部分，相同参数在不同秒会产生不同地址，而在同一秒内则会冲突。

## 存储模式

| `storage_type` | 值 | 链上字段 | 链下字段 |
|----------------|-------|-----------------|------------------|
| 链上 | `0` | `data` 已填充，`data_hash` 为空 | Shelby 字段为空 / 零值 |
| Shelby | `1` | `data` 为空 | `data_hash`, `shelby_account`, `shelby_blob_name`, `shelby_blob_merkle_root`, `shelby_register_tx_hash` |

`attestation::verify_data_integrity(address, data)` 会重新计算 `blake2b_256(data)` 并与 `data_hash` 比较；对于链上 Attestation 返回 `false`。

## 入口函数

| 函数 | 用途 |
|----------|---------|
| `aas::create_schema(creator, schema, name, description, url, revokable, resolver)` | 创建一个 Schema 命名对象并发出 `SchemaCreated` 事件 |
| `aas::create_attestation(attestor, recipient, schema, ref_attestation, expiration_time, revokable, data)` | 签发一个链上 Attestation |
| `aas::create_multi_attestations(attestor, recipients, schema, ref_attestations, expiration_times, revokable, data)` | 在一笔交易中签发多个 Attestation |
| `aas::create_attestation_off_chain(attestor, recipient, schema, ref_attestation, expiration_time, revokable, data_hash, shelby_account, shelby_blob_name, shelby_blob_merkle_root, shelby_register_tx_hash)` | 签发一个引用 Shelby blob 的 Attestation |
| `aas::revoke_attestation(admin, schema, attestation)` | 撤销一个 Attestation（仅限 Schema 创建者） |
| `aas::revoke_multi_attestations(admin, schemas, attestations)` | 撤销多个 Attestation |

`*_and_get_address` 系列变体是 public（非 entry）函数，供其他 Move 代码和测试使用。

## 视图

Schema：`schema_data`, `schema_unpacked`, `schema_creator`, `schema_revokable`, `schema_resolver`, `schema_exists`, `get_schema_address`, `get_schema_seeds`。

Attestation：`attestation_data`, `attestation_unpacked`, `attestation_exists`, `attestation_revoked`, `storage_type`, `data_hash`, `shelby_account`, `shelby_blob_name`, `verify_data_integrity`, `get_attestation_address`, `get_attestation_address_off_chain`, `get_attestation_seeds`, `get_attestation_seeds_off_chain`。

Resolver 存储视图：`is_initialized`, `dispatcher_metadata`, `dispatcher_is_exists`, `pack_attest_data`, `pack_revoke_data`, `unpack_attest_data`, `unpack_revoke_data`。`retrieve` 是普通的 public 函数（没有 `#[view]`），可从 Resolver 模块调用。

## 事件

| 事件 | 字段 |
|-------|--------|
| `schema::SchemaCreated` | `schema_address, name, description, url, creator, created_at, revokable, resolver, schema` |
| `attestation::AttestationCreated` | `attestation_address, schema, ref_attestation, time, expiration_time, revokable, attestor, recipient, storage_type, data, data_hash, shelby_account, shelby_blob_name, shelby_blob_merkle_root, shelby_register_tx_hash` |
| `attestation::AttestationRevoked` | `attestation_address, revocation_time` |

## 错误

`aas::aas` 会在以下情况 abort：`ESTRING_TOO_LONG` (1), `ENOT_SCHEMA_CREATOR` (2), `E_NOT_REVOKABLE` (3), `EATTESTATION_NOT_FOUND` (4), `EATTESTATION_ALREADY_REVOKED` (5), `EATTESTATIONS_NOT_EXIST_AT_ADDRESS` (6), `ESCHEMA_NOT_FOUND` (7), `ERESOLVE_FAILED` (8), `EINVALID_LENGTH` (9)。

## Resolver 集成

当 Schema 的 `resolver` 地址非零时，`create_*` 和 `revoke_*` 会在写入状态之前调用 `resolver_dispatcher`：

1. 分发器将请求序列化后写入 `resolver_storage`，以 Resolver 模块地址为键。
2. 它通过可分发（dispatchable）的 fungible asset 调用 Resolver 的 `public fun resolve<T: key>(_metadata: Object<T>): Option<u128>`。
3. 仅当 Resolver 返回 `Some(0)`（`VERIFY_SUCCESS`）时请求才会成功。

Resolver 必须通过调用 `resolver_dispatcher::register_dispatchable(publisher)` 自行注册 —— 通常在其 `init_module` 中完成，如 [`resolver_example`](./resolver_example/sources/schema_resolver.move) 所做的那样。注册是一次性的，并以发布者的地址为键；回调名称硬编码为 `schema_resolver::resolve`。在首次分发之前，必须有人调用入口函数 `resolver_storage::initialize()`；该函数是幂等的。

如果 `resolver_storage` 已初始化但没有为配置的地址注册 dispatcher，则分发器将该请求视为已批准。如果从未调用 `initialize()`，签发和撤销会在尝试读取缺失的 `Dispatcher` 时 abort。

<a id="known-behavior"></a>

## 已知行为

`create_attestation*` 目前会断言 `ref_attestation` **不会**解析到一个已存在的 Attestation。实际上在当前版本只有传入 `@0x0` 才是安全的；在校验逻辑修改之前，应将引用视为保留。

## 构建与测试

```bash
cd aas
aptos move test
```

该包在 [`Move.toml`](./Move.toml) 中固定 Aptos framework 的版本；`Move.lock` 记录解析后的依赖图。

## 部署

```bash
cd aas
aptos move publish --named-addresses aas=<your_address>
```

发布之后，调用一次 `resolver_storage::initialize()`。若要使用 Resolver，先发布它并注册其可分发回调。完整流程见 [docs/deployment.md](../docs/deployment.zh.md)。

升级时需保持 public 函数签名和 struct 布局兼容；现有的命名对象地址依赖上述 seed 格式。

## 许可证

Business Source License 1.1 —— 见 [LICENSE](../LICENSE)。
