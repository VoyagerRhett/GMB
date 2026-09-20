# CitizenSDK smoldot PoW 上游记录

## 固定基线

- 上游仓库：`https://github.com/smol-dot/smoldot`
- 收编基线提交：`f471baac1f0fa821569c42ebb14c4f8533ba77ad`
- CitizenSDK 产品快照：`native/smoldot/pow/lib` 与 `native/smoldot/pow/light-base`

`native/smoldot/provider` 是 CitizenSDK 自有适配层，不属于上游 smoldot 快照。它只能依赖
上述收编源码并实现 `VerifiedChainClient`，不能把上游 JSON-RPC 任意透传成产品公共 API。

本目录不保存 `.git`、构建产物或临时 patch，CI/Release 也不联网拉取上游源码。GMB
`citizensdk` 是发布时的唯一源码输入。

## 基线已有的 PoW + GRANDPA 改动

收编前相对上游基线已有本地改动：

```text
lib/src/chain/blocks_tree.rs
lib/src/chain/blocks_tree/finality.rs
lib/src/chain/blocks_tree/verify.rs
lib/src/chain/chain_information.rs
lib/src/chain/chain_information/build.rs
lib/src/header.rs
lib/src/sync/warp_sync.rs
lib/src/verify.rs
lib/src/verify/header_only.rs
lib/src/verify/pow.rs
light-base/src/sync_service/standalone.rs
```

这些文件共同构成当前 PoW + GRANDPA 轻节点基线，不应在同步官方 smoldot 时丢失。

## 同步规则

1. 在临时目录检出上游目标提交，不在 CitizenSDK 内嵌套 `.git`。
2. 仅比较和更新 `lib`、`light-base`；CitizenSDK 不收编 `full-node` 或 `wasm-node`。
3. 先生成上游差异与文件闭集，确认上述 PoW 改动、轻客户端排除项和许可证。
4. 在独立 fork/分支上 rebase PoW 补丁并完成冲突审查，再逐字节回灌临时候选。
5. 同步测试夹具、内联测试、Cargo manifests、`Cargo.lock`、来源 manifest 和本文件。
6. 在源码树外完成三个 Rust workspace、Dart/Flutter、移动原生构建与候选验证后才接受更新。

同步上游后还必须执行 provider 的 exact-block、finalized、runtime context、提交/观察和
state import/export 合同测试，并证明 legacy `libsmoldot` 的库名、回调及全部既有导出未变。

临时 patch、上游 checkout 和构建目录使用后全部删除，不得进入 Release。完整产品来源分类
见塔塔文档库中的 CitizenSDK 来源记录。
