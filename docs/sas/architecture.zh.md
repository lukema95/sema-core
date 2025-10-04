[English](./architecture.md) | 简体中文

# SAS 架构设计

## 1. 设计目标

SAS 在 Sui 上提供一套「可验证声明」原语，同时满足：

1. **可发现**：全局 Registry 能回答「这个 attestation 是否存在 / 是否已被撤销？」
2. **可持有**：recipient 真正拥有 Attestation 对象（NFT 式所有权）
3. **可扩展**：Resolver 插入自定义的签发/撤销规则
4. **可升级**：Registry 使用 Versioned 对象做版本门控
5. **可隐私**：链下 Walrus + Seal 阈值解密，访问策略写在链上

## 2. 分层架构

```
┌─────────────────────────────────────────────────────────┐
│                    sas::sas (Facade)                    │
│  register_schema / attest / attest_off_chain / revoke   │
└────────────┬──────────────────────────────┬─────────────┘
             │                              │
             ▼                              ▼
┌────────────────────────┐       ┌────────────────────────┐
│     sas::schema        │       │   sas::attestation     │
│  Shared Schema object  │       │  Owned Attestation     │
│  Resolver + Request    │       │  on-chain / Walrus     │
└────────────┬───────────┘       └────────────┬───────────┘
             │                                │
             ▼                                ▼
┌────────────────────────┐       ┌────────────────────────┐
│  schema_registry       │       │ attestation_registry   │
│  Table<schema, creator>│       │ Table<att, Status>     │
│  Versioned inner       │       │ Versioned inner        │
└────────────────────────┘       └────────────────────────┘
             │
             ▼
┌────────────────────────┐       ┌────────────────────────┐
│     sas::admin         │       │   sas::seal_access     │
│  Admin { schema } cap  │       │  seal_approve entry    │
└────────────────────────┘       └────────────────────────┘
```

`sas.move` 本身几乎不存储状态；它只校验参数并把工作分发给各个模块。这是典型的 Facade。

## 3. 对象所有权模型

Sui 的安全边界就是所有权。SAS 把三类对象分开：

```
Shared                          Owned
──────                          ─────
Schema                          Attestation  → recipient
SchemaRegistry                  Admin        → schema creator
AttestationRegistry             SchemaRegistryAdminCap
                                AttestationRegistryAdminCap
```

| 对象 | 能力 | 为什么这样设计 |
|------|------|----------------|
| `Schema` | `key + store`，`share_object` | `new` 会立即将其共享；`new_with_resolver` 返回 owned 的它，creator 必须先调用 `share_schema`，其他人才能签发 |
| `Attestation` | 仅 `key`，`transfer` 给 recipient | 只有 recipient 能把它放进交易（Seal、展示、转移） |
| `Admin` | `key + store` | 设计为可转移；**当前可通过公开的 `admin::new` 伪造**，见 [安全模型](../security-model.zh.md#1-sas-admin-is-an-unauthenticated-bearer-capability) |
| Registry | Shared + Versioned | 全局索引；升级会修改 `allowed_versions` |

注意 `Attestation` **没有 `store`**，因此不能放进其他对象，只能作为顶层 owned object 流转。这降低了「把证明藏进另一个结构里以绕过所有权检查」的风险。

## 4. 核心数据结构

### 4.1 Schema

```move
public struct Schema has key, store {
    id: UID,
    name: String,
    description: String,
    url: Url,
    creator: address,
    created_at: u64,
    schema: vector<u8>,      // encoding template, not parsed by the contract
    revokable: bool,
    resolver: Option<Resolver>
}
```

合约把 `schema: vector<u8>` 当作不透明字节。类型校验发生在 SDK 的 `Codec` 层。链上只有治理字段有意义：`revokable` 和 `resolver`。

### 4.2 Attestation

```move
public struct Attestation has key {
    id: UID,
    schema: address,
    ref_attestation: address,   // 0x0 means no reference
    time: u64,
    expiration_time: u64,       // 0 means never expires
    revokable: bool,            // copied from the Schema, immutable after issuance
    attestor: address,
    storage_type: u8,           // 0 on-chain / 1 off-chain
    data: vector<u8>,           // only populated for on-chain
    walrus_sui_object_id: address,
    walrus_blob_id: vector<u8>,
    data_hash: vector<u8>,      // Blake2b-256
    encrypted: bool,
    seal_nonce: Option<vector<u8>>,
    seal_policy_id: Option<address>,
    name: String,
    description: String,
    url: Url,
}
```

单个对象同时承载两种存储模式，用 `storage_type` 区分。在链上模式下，链下相关字段全部零填充，使 BCS 布局保持稳定、对 indexer 友好。

**撤销不会写入这个对象。** 状态存在 Registry 的 `Status.is_revoked` 中。原因：Attestation 属于 recipient，schema admin 拿不到 `&mut Attestation`，无法修改 recipient 的对象。只有把撤销建模为「全局共享账本上的一条标记」，才与所有权一致。

### 4.3 Registry Inner

```move
public struct RegistryInner has store {
    allowed_versions: VecSet<u64>,
    attestations_status: Table<address, Status>,
}

public struct Status has copy, store {
    schema_address: address,
    is_revoked: bool,
    timestamp: u64,            // revocation time
}
```

`AttestationRegistry` / `SchemaRegistry` 外面包了一层 `sui::versioned::Versioned`。每次读和写都执行：

1. `load_value(_mut)`
2. `assert!(allowed_versions.contains(&constants::current_version()))`

`update_allowed_versions` 使用同一个 loader，因此只有在**当前**版本被允许时才能运行。新版本必须在升级之前预先授权：在 v1 运行时，给两个 Registry 都加上 `2`；然后再提升 `CURRENT_VERSION` 并发布。反过来做会让所有 Registry 调用因 `EVersionNotEnabled` 而失败。

## 5. 存储架构

```
                    ┌─ storage_type = 0 ─► data stored in the object
Attestation object ─┤
                    └─ storage_type = 1 ─► data empty
                                           walrus_* + data_hash on-chain
                                           blob on Walrus
                                           optional Seal ciphertext
```

| | 链上 | 链下（Walrus） |
|--|----------|--------------------|
| 数据位置 | `Attestation.data` | Walrus blob |
| 链上锚点 | 数据本身 | 调用者提供的 `data_hash`（约定为明文的 blake2b256） |
| 事件 | `AttestationCreated.data` 携带明文 | 事件中 data 为空 |
| 适用场景 | 小数据、完全透明 | 大数据、隐私、节省 gas |
| 加密 | 不支持（`is_encrypted` 恒为 false） | Seal，nonce / policy 记录在对象上 |

完整性校验：

```move
public fun verify_data_integrity(self: &Attestation, data: vector<u8>): bool {
    assert!(self.storage_type == STORAGE_TYPE_OFF_CHAIN, 0);
    hash::blake2b256(&data) == *&self.data_hash
}
```

**按约定，哈希是在加密前对明文计算的。** 合约完全按签发时提供的样子存储该哈希，不会重新计算或校验。客户端必须自行验证下载到的载荷。没有这个约定，解密后就无法证明「这就是当初签发的那份数据」。

链下签发不能与 resolver 组合：`attest_off_chain` 断言 schema 没有 resolver，并且 `attest_multi` 或 `revoke_multi` 都没有链下变体。

## 6. Seal 访问控制

这里使用 Seal 的 **Private Data** 模式。

```
At encryption time: Key ID = [attestor_bytes || nonce]
Full Seal ID = [package_id || attestor || nonce]
```

用 nonce 而不是 attestation_id，才使**先加密、再上链**成为可能：签发交易尚未提交，对象 ID 仍是未知的。

`seal_approve` 是一个 `entry` 函数，由 Seal key server 通过 `dry_run_transaction_block` 调用：

```move
entry fun seal_approve(id: vector<u8>, attestation: &Attestation) {
    assert!(check_policy(id, attestation), ENoAccess);
}
```

权限叠加两层：

1. **Move VM 所有权**：传入的 `&Attestation` 必须是由交易签名者拥有的对象 → 只有 recipient
2. **策略匹配**：`id == compute_key_id(attestor, nonce)`，且该 attestation 必须已加密并带有 nonce

key server 不信任客户端；它只信任一次成功的 dry-run。

## 7. Resolver 架构

Resolver 不是「外部合约地址回调」（Sui 没有动态 dispatch），而是 **Hot Potato + Witness Rule**：

```
Schema.resolver: Option<Resolver>
  rules:  VecMap<String, VecSet<TypeName>>   // "START_ATTEST" / "START_REVOKE"
  config: Bag                                 // Rule type → config (whitelist tables, etc.)
  resolver_address / resolver_module          // metadata only, not called at runtime
```

签发必须走：

```
start_attest() → Request (no abilities)
    → resolver::approve(&mut Request, Witness)
    → attest_with_resolver(..., Request) internally finish_attest
        → confirm: every rule TypeName must appear in Request.approvals
```

`Request` 没有 `copy / drop / store / key`，因此必须在交易结束前被 `finish_*` 消费，否则编译/执行会失败。这保证了「一旦开始，就必须带着 approvals 结束」。

普通的 `attest()` 会执行 `assert!(!schema.has_resolver())`，防止绕过 Resolver。

示例实现位于 `sas/resolvers/`：

- `whitelist`：sender 必须在表中
- `blocklist`：sender 不能在表中

两者都把名单存在 Schema 的 `Bag` 里，并用 Admin Cap 管理。

## 8. 事件

Indexer 依赖两类事件：

| 事件 | 何时 | 关键字段 |
|------|------|----------|
| `SchemaCreated` | 注册 Schema 时 | `event_type` 0=普通 / 1=带 Resolver，`schema_address`，`admin_cap`（类型 0 为 `@0x0`，类型 1 为 Admin 对象地址） |
| `AttestationCreated` | 签发时 | `event_type` 0=attest / 1=with_resolver（链下签发同样使用 0），完整元数据 + 存储字段 |

**没有 `AttestationRevoked` 事件。** 撤销只修改 Registry 的表。后端必须扫描 Registry 或自行监听调用；这是与 AAS 的一个差异。Registry 的 `Status` 字段是私有的，仅以标量视图暴露 `is_revoked`。

## 9. 权限矩阵

| 操作 | 谁 | 检查 |
|------|----|------|
| 注册 Schema | 任意地址 | 无 |
| 签发（无 Resolver） | 任意地址 | Schema 无 resolver；过期时间 > now；ref 若非 0x0 则必须已登记 |
| 签发（带 Resolver） | 通过全部 Rule 的人 | `finish_attest` 校验 approvals |
| 撤销 | 持有对应 `Admin` 的人（设计意图如此；当前可被伪造） | Admin.schema == Schema；schema.revokable；attestation 存在、属于该 schema，且尚未被撤销 |
| Seal 解密授权 | Attestation 对象的拥有者（recipient） | `seal_approve` dry-run |
| 修改 Registry 允许的版本 | Registry AdminCap | 由发布者持有；在升级前调用 |

## 10. 与 AAS 的架构差异

1. SAS 用**对象所有权**表达「谁持有证明」；AAS 用 Named Object，recipient 只是一个字段。
2. SAS 在**共享 Registry** 上撤销；AAS 直接修改 Attestation 资源（因为对象不归 recipient）。
3. SAS Resolver 是**类型系统强制的多步 PTB**；AAS 是**运行时动态回调**。
4. SAS 有 Seal；AAS 没有链上加密策略。
5. SAS 地址不可预测；AAS 地址可以链下预计算。
