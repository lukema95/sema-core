[English](./principles.md) | 简体中文

# AAS 原理

AAS 的核心不是「又一个 attestation 结构体」，而是三件事：确定性对象、包级 signer、以及在没有动态 dispatch 的语言里硬生生造出一个 Resolver。

## 1. Named Object：地址是哈希，不是 UID

Aptos Object 模型里，`create_named_object(signer, seed)` 的地址由 **创建者地址 + seed** 唯一确定。AAS 把整个业务主键编进 seed，再用 keccak256 压缩到 32 字节。

为什么要 hash 一次：原始 seed 可以任意长（链上模式还包含 payload），而 hash 让地址派生保持紧凑、定长，同时保住「相同参数 = 相同地址」。Aptos 对 named object 的 seed 没有长度限制；hash 是设计选择，不是协议要求。

性质：

- **防重复**：用相同参数再次创建会以 `EOBJECT_EXISTS` abort，而不是幂等的 no-op
- **可索引**：schema 地址可以由内容算出；attestation 地址需要执行时的 `now`，所以索引器从事件或 view 里读取
- **不含用户随机性**：不依赖用户账户下的 guid

代价：seed 少一个字段就会造成碰撞，或让记录无法区分。链上模式把整份 `data` 放进 seed，所以数据大时 seed 计算更重；链下模式改用 `data_hash`，这是正确的切分。

## 2. 对象不属于 Recipient

```move
move_to(object_signer, Attestation { recipient, ... });
```

`object_signer` 来自 named object；资源存在 **对象地址** 下，owner 在 object 体系里是包创建者一侧，而不是 recipient。

所以：

- recipient 不能「把 attestation 转给别人」，除非另加 transfer 逻辑（今天没有）
- 任何人只要知道地址就能用 `borrow_global` 读（view 函数）
- 模块可以用 `borrow_global_mut` 改 `revocation_time`

SAS 把 attestation 当 NFT；AAS 把 attestation 当 **可寻址的全局记录**。产品语义更接近 EAS（Ethereum Attestation Service），而不是 SBT/NFT。

一句话：`recipient` 是声明式对象，不是能力对象。

## 3. ExtendRef 为什么必须是 friend

`get_signer()` 能生成拥有创建权的 signer。如果它是 public，任何人都能以包的身份创建对象，且没有上限。所以：

```move
friend aas::aas;
friend aas::schema;
friend aas::attestation;
friend aas::resolver_storage;
friend aas::resolver_dispatcher;
```

这是 Move 的 **用模块可见性做能力控制**。Sui 用 Capability 对象表达同样的想法（Admin Cap、Registry AdminCap）；Aptos 这里用 friend + ExtendRef。两种能力系统：

| | Sui SAS | Aptos AAS |
|--|---------|-----------|
| 创建权 | 交易上下文 `object::new` | 包 ExtendRef signer |
| 撤销权 | 可转移的 Admin 对象 | 不可转移的 creator 地址 |
| 升级权 | Registry AdminCap | 包升级（框架级） |

## 4. Dispatchable FA：为什么用这么怪的机制

需求：Schema 只存一个 `address`，运行时调用该地址模块里的 `resolve`。

Move 做不到 `call(address, "resolve")`。Aptos 给 FA 留了一个官方后门：`register_derive_supply_dispatch_function`，之后 `derived_supply(metadata)` 会进入注册的函数。

AAS 把这个「算供应量」的钩子 **滥用成校验回调**：

- 返回值 `Option<u128>`：`some(0)` 算成功
- 期望的签名是 `fun resolve<T: key>(metadata: Object<T>): Option<u128>`，但注册并不校验这个签名；不匹配只会在 dispatch 时暴露
- 真正的参数没法通过 FA API 传，所以先 `insert` 到 `resolver_storage`，回调里再 `retrieve`

这引入两个本质问题：

1. **全局可变 scratchpad**：`Table<address, vector<u8>>` 按模块地址保存最近一次 packed data。并发方面：Aptos 在一笔交易内顺序执行，所以一般安全；但你不能在一次 dispatch 里用另一份 data 重入。
2. **未注册意味着放行，但未初始化意味着 abort**：`resolver_storage::initialize()` 跑过之后，地址没有注册 dispatcher 时 `on_attest` 返回 `true`。初始化之前，`dispatcher_is_exists` 会 borrow 一个不存在的 `Dispatcher`，交易 abort。初始化之后把 `Schema.resolver` 填成未注册地址 = 没有校验。

示例 resolver 只检查 `revokable == true` 就返回成功，这说明框架端到端是通的，但业务规则必须自己写严。

## 5. Packed data 的手工 BCS 切片

```move
let attestor = from_bcs::to_address(vector::slice(&data, 1, 33));
```

这依赖 BCS 的定长：`address` 是 32，`u64` 是 8，`bool` 是 1。`vector<u8> data` 放在最后，这样「剩余全部」就能当 payload。

这很脆：在中间插入字段会让所有 resolver 错位。演进时应该对 packed layout 做版本化（第一个 byte 已经是 type，可以再加一个 version）。

SAS 完全绕开了这个问题：它的参数是真正的 Move 值，通过函数签名传递。

## 6. 撤销权限：地址相等 vs Capability

```move
assert!(admin_addr == schema::schema_creator(schema_addr), ENOT_SCHEMA_CREATOR);
```

简单、好懂、难移交。账户被盗 = 撤销权被盗；换钱包 = 你再也撤不了旧 schema 下的 attestation。

SAS 的 Admin Cap 可以放进 multisig object。AAS 若要补上这个缺口，常见设计是在 creator 账户下另做一个 `Admin` 资源，或把 Object 的 `TransferRef` 交给治理合约。两者当前都没有。

## 7. ref_attestation 的实际行为

```move
assert!(!attestation::attestation_exists(ref_attestation), EATTESTATIONS_NOT_EXIST_AT_ADDRESS);
```

字面意思：**被引用的地址必须不存在**。再配合默认的 `ref = @0x0`（0x0 上没有 Attestation），不带引用的签发就能通过。一旦传入真实的 attestation 地址，`exists == true`，断言失败。

这与 SAS 的「非零则必须存在」相反，也和错误码自己的名字「NOT_EXIST」矛盾。更合理的代码是：

```move
if (ref_attestation != @0x0) {
    assert!(attestation::attestation_exists(ref_attestation), ...);
};
```

当前 AAS **实际上并不支持 attestation 链**。这是当前实现的真实缺口。

## 8. 时间与过期

AAS 签发时 **不检查** `expiration_time > now`。`0` 或过去的时间都会被接受。过期完全是应用层语义。

时间单位是 **秒**（`timestamp::now_seconds`）；SAS 用的是 **毫秒**。跨链展示时间戳时不要混用。

撤销会把 `revocation_time` 写成当前秒。`attestation_revoked` ⇔ `revocation_time != 0`。不可逆。

## 9. 字符串限制

```move
assert!(string::length(&name) < 128, ...);
assert!(string::length(&description) < 512, ...);
assert!(string::length(&url) < 512, ...);
```

只在创建 Schema 时检查。Attestation 没有 name/description/url 元数据字段（SAS 有）。AAS 更精简；展示信息交给 Schema 或链下数据。

## 10. friend 边界与攻击面

外部调用者不能调用 `attestation::create_attestation`；必须走 `aas::create_attestation*`，所以 resolver 检查无法被跳过。

在外部，`resolver_dispatcher::on_attest` **可以** 被调用（它是 public）。它只返回一个 bool，不创建对象，但会写 storage scratchpad 并调用 resolver。交易顺序执行，且 dispatcher 在 dispatch 之前立刻 insert，所以一笔交易无法破坏另一笔正在进行中的请求；剩下的风险是任何人都能在带外演练一个 resolver。把 `on_attest`/`on_revoke` 改成 `public(friend)` 可以缩小攻击面。

## 11. 完整性模型

```
信任链：
  attestor 签名交易
    → 合约写下 data 或 data_hash
      → 读者读取对象
        → 若走链下：从 Shelby 取回，blake2b256 == data_hash
          → 可选地验证 merkle_root（链下，合约不强制）
```

合约不验证 Shelby merkle proof。`shelby_blob_merkle_root` / `shelby_register_tx_hash` 是给索引器和争议解决用的证据锚点。
