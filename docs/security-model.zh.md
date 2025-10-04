[English](./security-model.md) | 简体中文

# 安全模型与已知限制

本页说明谁有权做什么、合约提供与不提供哪些保证，以及当前修订版中的已知缺口。在部署或集成之前，这是必读内容。

这些合约**未经审计**，运行在 testnet 上。报告方式见 [SECURITY.md](../SECURITY.zh.md)。

## 信任模型

### Sui（SAS）

| 操作 | 授权 |
|--------|---------------|
| 创建 schema | 任何人；调用方会收到一个 `Admin` capability |
| 共享 schema | schema 创建者（或创建它的模块）；`new_with_resolver` 返回一个拥有型 schema，必须显式共享 |
| Attest（无 resolver） | 任何账户；attestation 会被转移给接收方 |
| Attest（有 resolver） | 任何账户，只要从配置的 resolver 获得所需的批准 |
| 撤销 | 持有 `Admin` capability 且其 `schema` 字段与该 schema 匹配者，且该 schema 可撤销 |
| 配置 resolver | schema 创建者，通过 `register_schema_with_resolver` 返回的 `ResolverBuilder` |
| 更新注册表版本 | 持有发布时创建的 registry admin caps 者 |
| 升级包 | 持有包的 `UpgradeCap` 者 |
| 解密 Seal 数据 | attestation 对象的所有者（接收方） |

### Aptos（AAS）

| 操作 | 授权 |
|--------|---------------|
| 创建 schema | 任何人；调用方被记录为 `creator` |
| Attest | 任何账户；attestation 是由 package-manager 签名者控制的命名对象，`recipient` 记录为其中一个字段 |
| 撤销 | schema 的 `creator` 地址，且 schema 可撤销；配置了 resolver 时还需 resolver 批准 |
| 配置 resolver | schema 创建者（选择 resolver 地址），通过发布 resolver 模块 |
| 升级包 | 发布该包的账户，使用兼容的升级策略 |

## 已知限制

<a id="1-sas-admin-is-an-unauthenticated-bearer-capability"></a>

### 1. SAS 的 `Admin` 是未经认证的 bearer capability

`sas::admin::new(schema, ctx)` 是一个**公开**构造函数，它不检查调用方是否创建或拥有该 schema。调用方可以为任意 schema 地址铸造一个 `Admin`，然后调用 `sas::revoke`、resolver 的 `add_user`/`remove_user`，或 `schema::new_resolver_builder`。

影响：在 `revokable = true` 且没有 resolver 的 schema 上，任何账户都可以撤销任何 attestation。在配置了 resolver 的 schema 上，攻击者还可以改动 resolver 配置。

在构造函数受到限制之前的缓解措施：不要将撤销权限视为安全，监控注册表状态，并避免授予超出撤销范围的权限的 resolver 配置。修复需要将 `admin::new` 限制为包内（或限制到 schema 创建路径），这是一项会破坏升级兼容性的变更。

<a id="2-sas-upgrade-ordering-is-easy-to-get-wrong"></a>

### 2. SAS 升级顺序很容易弄错

`update_allowed_versions` 通过 `load_inner_mut` 加载注册表，而该方法断言 `constants::current_version()` 已经在 `allowed_versions` 中。如果你提升 `CURRENT_VERSION` 并在预先授权新版本之前发布，更新调用会以 `EVersionNotEnabled` abort，注册表在此后再次升级之前将不可用。

安全顺序：

1. 在**旧**包仍在线时，调用 `update_allowed_versions`，并包含你即将发布的版本。
2. 提升 `CURRENT_VERSION` 并发布升级。
3. 验证注册表读取正常；只有在这之后才退役旧 caps。

### 3. 链下数据哈希由调用方提供

签发时将 `data_hash` 作为参数接受，并且不会针对任何 blob 进行验证。`verify_data_integrity` 是一个可选的 view。索引器和客户端必须：

- 对他们下载的载荷重新计算哈希。
- 将其与链上的 `data_hash` 比较。
- 将链下网关（Walrus 或 Shelby）视为不受信任的传输通道。

在 Sui 上，对链上 attestation 调用 `verify_data_integrity` 会 abort；在 Aptos 上它返回 `false`。

### 4. SAS 链下签发无法使用 resolver

`attest_off_chain` 断言 schema 没有 resolver。`attest_multi` 或 `revoke_multi` 也没有 resolver 变体。因此链下 attestation 在签发时无法被白名单/黑名单门控。

### 5. AAS 的引用检查是反的

`create_attestation` 和 `create_attestation_off_chain` 断言 `ref_attestation` **不是**已存在的 attestation。按当前实现，只有 `@0x0` 是安全的；在此修订版中引用实际上不可用。

### 6. AAS 没有链上 schema 注册表

`SchemaRegistry` 结构体已定义，但从未初始化或写入。发现依赖 `SchemaCreated` 事件以及重新计算命名对象地址。索引器必须从事件回填。

### 7. Resolver 注册是可选的，且失效时默认放行

在 Aptos 上，如果某个 schema 设置了非零 resolver 地址，但没有为其注册任何 dispatcher，`resolver_dispatcher::on_attest` 会返回 `true`。在 Sui 上，resolver 必须构造 witness 来批准；配置错误的 resolver 可能按其自身代码阻止或允许签发。

Resolver 代码由 schema 创建者信任。在将其附加到 schema 之前请先审阅。

### 8. 可观测性缺口

- Sui 没有 `AttestationRevoked` 事件；撤销记录在 `AttestationRegistry` 中，其 `Status` 字段（`schema_address`、`is_revoked`、`timestamp`）除 `is_revoked` 外没有公开的 Move 访问器。
- 在 Sui 上，普通签发与链下签发时 `AttestationCreated.event_type` 都为 `0`；应使用 `storage_type` 加以区分。
- AAS 会发出 `AttestationRevoked` 并提供完整的 view，但 schema 发现仍依赖事件。

### 9. 错误码不是稳定的标识符

Revert 错误码是模块局部的常量，可能跨版本变化。不要在生产客户端中对数字错误码做 switch；应基于交易失败进行匹配，或防御性地解析错误。

## 运维指引

- 将 Sui 的 `UpgradeCap`、registry admin caps 和 Aptos 发布者密钥存放在相互独立、访问受控的保管环境中。
- 将部署者账户视为特权角色。
- 使用专用的 RPC 端点，并在转移资金或授予访问权限时独立验证响应。
- 在主网升级之前重新运行完整测试套件并做一次预发部署。
- 有修复版本可用时发布安全公告；参见 [SECURITY.md](../SECURITY.zh.md)。

## 报告

请通过 `lukema95@gmail.com` 私下报告安全问题。不要为漏洞开公开 issue。
