[English](./principles.md) | 简体中文

# SAS 原则

彻底读懂 SAS，归根结底是四个层层叠加的 Sui/Move 惯用法。

## 1. Capability：Admin 是一枚 bearer 标签（以及一个已知缺口）

```move
public struct Admin has key, store {
    id: UID,
    schema: address,
}
```

当 Schema 被注册时，`admin::new(schema_addr)` 会把它返回给调用者。撤销时：

```move
admin.assert_schema(schema_record.addy());
```

**它不比较 `tx.sender() == schema.creator`。** 拥有这枚 Cap 就是权限所在。设计意图是：

- 多签 / 钱包托管：把 Cap 转移给 DAO 或多签
- 权限可转移：当项目更换运营地址时，只需转移一个对象
- 最小权限：一枚 Cap 只绑定单个 schema，因此你不能用 A 的密钥去撤销 B

与 AAS 对比：AAS 的撤销检查 `signer == schema.creator`，所以权限永久绑定在创建地址上。

> **已知局限：** `admin::new` 是公开且无防护的构造函数。任何账户都可以为任意 schema 地址铸造一个 `Admin` 并通过 `assert_schema`。因此，在当前修订版中，该 capability 并不是安全边界。参见 [Security model §1](../security-model.zh.md#1-sas-admin-is-an-unauthenticated-bearer-capability)。在 `admin::new` 被限制为包内可见之前，不要依赖撤销或 resolver 管理来提供保护。

`Admin` 也会被传入 `new_resolver_builder` 以及 resolver 的 `add_user`/`remove_user`，同样带有上述限制。

## 2. Shared 与 Owned：谁能把对象放进交易

在 Sui 中，“能不能调用”首先取决于当前交易能否引用该对象。

| 需求 | 选择 | 结果 |
|------|------|------|
| 世界上任何人都可以针对某个 Schema 签发 | Schema → Shared | 任何交易都能取得 `&mut Schema` |
| Attestation 只属于被证明方 | Attestation → 由接收方 Owned | 其他人无法把该对象作为参数传入 |
| 全局可查询的撤销状态 | Registry → Shared | 任何人都能读取 `is_revoked` |

这直接决定了**为什么撤销不能修改 Attestation 对象**：admin 不是 owner，拿不到 `&mut Attestation`。Registry 是一份共享账本，所以 admin 修改的是账本，而不是别人的 NFT。

Seal 也遵循同样的模型：`seal_approve(id, &Attestation)` 要求调用者是 owner。如果在 Key server 的 dry-run 期间签名者不是 owner，交易会直接失败，因此无需在合约里写 `assert!(sender == recipient)`。

## 3. Hot Potato：为什么 Request 完全没有 ability

```move
public struct Request {
    name: String,                 // "START_ATTEST" / "START_REVOKE"
    schema_address: address,
    approvals: VecSet<TypeName>
}
```

没有 `copy`、没有 `drop`、没有 `store`、没有 `key`。这种结构称为 **Hot Potato**：

- 它不能被存入对象，也不能被丢弃
- 它必须在本 Programmable Transaction Block 内被某个函数“吃掉”
- 吃掉它的函数是 `finish_attest` / `finish_revoke`，它们在内部调用 `confirm` 来检查 approvals

如果攻击者调用 `start_attest` 之后跳过 resolver，这个未使用的 `Request` 会让交易无法提交。`schema::new_request` 是 public 的，因此 `Request` 可以被伪造，但它仍然需要 `confirm` 中收集的 witness approvals；当 resolver 设有规则时，空 request 会失败。

这比“一个 bool approved 字段”更强：`approved` 标志可以先被置为 true 再被改掉，而 Hot Potato 把“未完成的工作”变成了类型系统错误。

## 4. Witness 模式：规则是类型，不是字符串

```move
public fun approve<Rule: drop>(request: &mut Request, _: Rule) {
    request.approvals.insert(type_name::with_defining_ids<Rule>());
}
```

Whitelist 模块定义了：

```move
public struct WhitelistResolver has drop {}
```

只有能够构造 `WhitelistResolver {}` 的模块才能调用 `approve<WhitelistResolver>`。外部模块无法凭空塞入一个同名规则，因为 `TypeName` 携带了定义它的模块。

配置存放在 Schema 的 `Bag` 中，键同样是 Rule 的 TypeName：

```
rules["START_ATTEST"] = { TypeName(WhitelistResolver) }
config[TypeName(WhitelistResolver)] = Whitelist { Table<address, bool> }
```

`confirm` 遍历规则并要求 `approvals` 是超集。规则可以叠加（白名单 + 时间窗口）；`approvals` 是 `VecSet`，因此 `approve` 调用的顺序无关紧要。

`resolver_address` / `resolver_module` **不参与执行**；它们只是给人看的元数据。真正的执行点是 TypeName。这与 AAS 完全相反：AAS 必须在运行时跳转到另一个模块。

## 5. Facade 入口点的互斥

```move
public fun attest(...) {
    assert!(!schema_record.has_resolver(), EHasResolver);
    // ...
}

public fun attest_with_resolver(..., request: Request) {
    schema::finish_attest(schema_record, request);
    // ...
}
```

对配置了 Resolver 的 Schema 调用 `attest()` 会直接 abort。这是有意为之：否则攻击者就能跳过 `start_attest` + `approve`。

`revoke` / `revoke_with_resolver` 以同样的方式互斥。

## 6. 引用证明 ref_attestation

如果签发时 `ref_attestation != @0x0`，则要求 `attestation_registry.is_exist(ref)`。

目的：把证明串成链，例如用“KYC 证明”作为“信用证明”的前置条件。合约只检查**存在性**；它不检查被引用的证明是否未撤销、未过期，或属于同一个 schema。上层应用必须自行结合 `is_revoked` + `expiration_time` 判断。

## 7. 过期语义

```move
if (expiration_time != 0) {
    assert!(time.timestamp_ms() < expiration_time, EExpired);
}
```

- `0` = 永不过期
- 非零值必须**严格大于**当前 Clock
- 检查**只在签发时**发生。过期对象不会自动消失，合约也不会标记它。应用层读取 `expiration_time` 并自行判断是否过期。

时间来自 `&Clock`，单位是毫秒。测试使用 `clock::create_for_testing`。

## 8. 批量操作

`attest_multi` / `revoke_multi` 是循环调用单条版本的循环。`attest_multi` 检查所有六个向量长度相等（`EInvalidLength`）；`revoke_multi` 接收单个向量，没有长度检查。

除了原子性之外没有额外语义：失败的 PTB 会整体回滚，因此一批操作要么全部成功，要么全部失败。

## 9. 数据完整性 vs 机密性

| 目标 | 机制 | 防止 |
|------|------|------|
| 完整性 | 链上存储 Blake2b-256 哈希，由 opt-in 的 `verify_data_integrity` 视图检查 | Walrus 篡改、下载到错误的 blob —— 前提是客户端确实执行校验 |
| 机密性 | Seal 加密 + `seal_approve` | 拿到密文的非接收方无法从 key server 请求密钥 |
| 真实性 | attestor = `ctx.sender()` | 冒充他人的签发（除非对方把签名权委托给你） |
| 撤销真实性 | `Admin` capability —— **当前可伪造**，见 §1 | 在预期模型中防住路人；本修订版并未强制 |

常见误解：把密文哈希放到链上。SAS 明确哈希的是**明文**，因此解密后仍然匹配。

## 10. 版本门控如何工作

```move
public(package) fun load_inner_mut(self: &mut AttestationRegistry): &mut RegistryInner {
    let inner = versioned::load_value_mut(&mut self.inner);
    assert!(inner.allowed_versions.contains(&constants::current_version()), EVersionNotEnabled);
    inner
}
```

`constants::current_version()` 被编译进当前包。升级后这个数字会变化；如果 Registry 的 `allowed_versions` 尚未包含新版本，所有读写都会 abort。由于 `update_allowed_versions` 自身也调用 `load_inner_mut`，它同样会断言**当前正在运行**的版本被允许。因此新版本必须**在升级之前**获得授权：

1. 在 v1 仍在线时，用 registry admin caps 对两个 registry 调用 `update_allowed_versions`，传入 `{1, 2}`。该调用运行 v1 代码，因为 `1` 被允许而通过。
2. 把 `CURRENT_VERSION` 提升到 `2` 并发布升级。
3. v2 代码现在可以通过版本检查；只有需要回滚窗口时才保留 `1`。

如果先执行第 2 步再执行第 1 步，registry 会被 `EVersionNotEnabled` 锁死，admin 调用本身也无法再成功。

这避免了“一升级旧对象布局就对不上”和“未授权的新代码读写旧 registry”。
