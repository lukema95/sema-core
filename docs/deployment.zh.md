[English](./deployment.md) | 简体中文

# 部署与升级

本指南涵盖 Sema Core 合约的发布、初始化与升级。它假设你已在目标网络上拥有已注资的账户，并已阅读 [SECURITY.md](../SECURITY.zh.md)。这些合约未经审计；在没有独立审查的情况下不要部署到生产环境。

本地开发与测试参见[快速开始](../README.zh.md#quick-start)。

## Sui（SAS）

### 前置条件

- Sui CLI `1.61.x`
- 一个已注资的 Sui 账户，用于支付 gas 并持有升级能力
- Sui CLI 中的网络配置（`sui client active-env`）

### 发布

```bash
cd sas
sui move build
sui client publish --gas-budget 100000000
```

发布会自动完成三件事：

1. 创建并共享 `SchemaRegistry`。
2. 创建并共享 `AttestationRegistry`。
3. 将 `SchemaRegistryAdminCap` 和 `AttestationRegistryAdminCap` 以及包的 `UpgradeCap` 转移给发布者。

从发布输出中记录以下各项（在适用情况下也会存入 `Published.toml`）：

| 值 | 在哪里找到 | 使用者 |
|-------|------------------|---------|
| Package ID | `Published.toml` → `published-at`，或 `published` effects | 客户端、索引器、resolver |
| `SchemaRegistry` 对象 ID | 创建的共享对象 | 每一项 schema 操作 |
| `AttestationRegistry` 对象 ID | 创建的共享对象 | 每一项 attestation 操作 |
| `UpgradeCap` 对象 ID | 被转移的对象 | 未来的升级 |
| Registry admin caps | 被转移的对象 | `update_allowed_versions` |

### 验证

```bash
sui client object <schema_registry_id>
sui client object <attestation_registry_id>
sui client object <package_id>
```

两个注册表都应为共享对象并归系统所有；admin caps 应归发布者所有。

### 发布参考 resolver（可选）

resolver 包通过本地路径依赖 `sas`，并从 `sas/Published.toml` 解析已部署的地址：

```bash
cd sas/resolvers
sui move build
sui client publish --gas-budget 100000000
```

发布者将成为 resolver 包及其 `UpgradeCap` 的所有者。schema 创建者可以把该 resolver 地址/模块附加到 schema 上；builder 调用方式参见 `sas/resolvers/sources/whitelist.move`。

如果你部署到的环境在 `sas/Published.toml` 中没有匹配的 `[published.<env>]` 条目，请在发布前将 `sas/resolvers/Move.toml` 中的 `sas` 命名地址设为已部署的 package ID。

### 升级

`update_allowed_versions` 通过版本检查加载注册表，因此只有在**当前**版本被允许时才能工作。先授权下一个版本，再进行升级：

1. 在旧包仍在线时，调用 `schema_registry::update_allowed_versions` 和 `attestation_registry::update_allowed_versions`，传入包含当前版本和你即将发布的版本的集合。
2. 提升 `sas/sources/constants.move` 中的 `CURRENT_VERSION`。
3. 发布升级。

```bash
cd sas
sui client upgrade --upgrade-capability <upgrade_cap_id> --gas-budget 100000000
```

如果你在第 1 步之前就发布，更新调用本身会以 `EVersionNotEnabled` abort，并且所有注册表读写都会停止，直到再次升级。参见[安全模型 §2](./security-model.zh.md#2-sas-upgrade-ordering-is-easy-to-get-wrong)。

### 主网注意事项

`Move.lock` 记录了经过测试的 testnet 构建所使用的框架修订版。对于主网，请将 Sui CLI 环境切换到 mainnet，必要时更新依赖，重新运行完整测试套件，并从干净的代码树发布。不要在 `sas` 和 `sas/resolvers` 之间混用框架修订版。

## Aptos（AAS）

### 前置条件

- Aptos CLI `7.14.x`
- 一个已注资的 Aptos 账户
- 一个 CLI profile（`aptos init --profile sema --network testnet`）

### 发布

```bash
cd aas
aptos move publish --profile sema --named-addresses aas=<publisher_address>
```

`aas` 是 `aas/Move.toml` 中声明的命名地址；它必须与承载该包的地址一致（通常是发布者账户）。发布过程会运行 `package_manager::init_module`，它创建用于所有命名对象的协议对象签名者，并将 `PermissionConfig` 存储在 `@aas`。

### 初始化 resolver 存储

resolver dispatcher 将请求数据存储在一个必须创建一次的资源中：

```bash
aptos move run --profile sema \
  --function-id <aas_address>::resolver_storage::initialize
```

该入口是幂等的；如果资源已存在则提前返回。任何账户都可以调用它，因为它只在包地址处创建协议状态。

### 发布 resolver（可选）

```bash
cd aas/resolver_example
aptos move publish --profile sema \
  --named-addresses aas=<aas_address>,resolver_example=<resolver_address>
```

`resolver_example::schema_resolver::init_module` 注册一个可分发的回调。dispatcher 期望 resolver 模块暴露 `public fun resolve<T: key>(_metadata: Object<T>): Option<u128>`，并在批准时返回 `option::some(0)`。resolver 通过 `resolver_storage::retrieve(@<resolver_address>)` 读取请求。

### 升级

Aptos 包就地升级：

```bash
cd aas
aptos move publish --profile sema --named-addresses aas=<publisher_address>
```

发布者必须使用相同的地址和兼容的升级策略。只要 seed 派生方式和 `package_manager` 对象不变，已有的命名对象会保留其地址。保持公开签名和结构体布局稳定；参见 [CONTRIBUTING.md](../CONTRIBUTING.zh.md#compatibility-rules)。

### Movement

AAS 可以用 Movement CLI 从相同的源码部署到 Movement。请使用 Movement 的 profile 和网络；`aas/Move.toml` 中的 Aptos 框架修订版可能需要与 Movement 框架匹配。为每个网络记录单独的包地址——命名对象地址以包签名者为作用域，因此在不同部署之间会有所不同。

## 部署后检查清单

- [ ] Package ID 与注册表对象 ID 已记录到你的部署清单中。
- [ ] `UpgradeCap`（Sui）与 registry admin caps 已安全存储。
- [ ] `resolver_storage::initialize()` 已执行（Aptos）。
- [ ] 下游使用方已更新：SDK 地址常量、后端环境变量（`SUI_PACKAGE_ID`、`APTOS_PACKAGE_ADDRESS`、`MOVEMENT_ADDRESS`）、索引器。
- [ ] 事件订阅已验证（`SchemaCreated`、`AttestationCreated`、`AttestationRevoked`）。
- [ ] 已创建一个冒烟测试用的 schema 和 attestation 并读回验证。
- [ ] 如果你在 git 中跟踪部署，`Published.toml`（Sui）已提交。

## 故障排查

| 现象 | 可能原因 |
|---------|--------------|
| Sui 上出现 `EVersionNotEnabled` | `CURRENT_VERSION` 不在注册表的 `allowed_versions` 中。应在升级前预先授权新版本；如果已经升级且没有预授权，注册表会被锁住，需要一次恢复性升级。 |
| `ESchmaAlreadyExist` / 对象已存在 | 已创建过内容与参数完全相同的 schema；地址是确定性的 |
| Aptos resolver 从未被调用 | 未调用 `resolver_storage::initialize()`，或 resolver 未注册可分发的回调 |
| 创建 attestation 时以 `EATTESTATIONS_NOT_EXIST_AT_ADDRESS` abort | AAS 目前要求 `ref_attestation` 为 `@0x0`；参见 [aas/README.md](../aas/README.zh.md#known-behavior) |
| Sui 在 resolver 包上发布失败 | 无法解析 `sas`；显式设置 `sas` 地址，或从具有匹配 `Published.toml` 条目的环境发布 |
