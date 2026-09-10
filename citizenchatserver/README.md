# CitizenChatServer

Cloudflare 正式资源统一使用小写 `<product>-<resource>`：Worker 为
`citizenchatserver-workers`，D1 为 `citizenchatserver-d1`，R2 为
`citizenchatserver-r2`，正式域名为 `chat.crcfrcn.com`。

CI 只消费 TataChatServer 的正式 Cloudflare Release 并绑定当前 GMB `main` 的实例声明；
Release 只封装准确成功 CI 候选；发布只由 TataConsole 原生发布器消费正式 GMB Release。

CitizenChatServer 是公民产品使用的 TataChatServer Cloudflare 实例。该目录只保存宿主产品声明与资源配置，不复制通用聊天源码，也不保存编译产物、密钥或生产资源编号。

CitizenChatServer 是无宿主操作系统平台的云端服务；Cloudflare 是它的部署供应商，不是
iOS、Android、macOS、LinuxARM、LinuxAMD、Windows、WASM 或 SDK 这类发布平台。
因此 `scripts/product.json` 与正式 Release manifest 使用 `deployment_provider: cloudflare`，禁止再把
`cloudflare` 写入这两个合同的 `platform` 字段。

QR_V1 发布/恢复签名载荷与现有 action 边界中的 `platform=cloudflare` 属于尚未迁移的既有
签名协议字段。本次只纠正产品声明和 Release manifest，不能全局禁用该旧字段；其迁移必须
在所有签名、验签和恢复端就绪后另行原子实施。

- HTTPS：`https://chat.crcfrcn.com`
- WSS：`wss://chat.crcfrcn.com/realtime`
- 授权签发方：CitizenServe
- 授权受众：`citizenchatserver`
- 通用实现：TATA 仓库的 `tatachatserver`

本机候选由中央 `flows/gmb/citizenchatserver/cloudflare/build.sh` 调用同目录 `ci.mjs`，在
`TATA/tataconsole/cache/gmb/citizenchatserver/cloudflare/stage/candidate/` 中装配。
流程消费并校验 TataChatServer 的正式 Cloudflare Release，复制其中的 Worker 与唯一 D1
结构，再绑定当前 GMB `main` 的实例声明；不复制聊天源码或调用 `worker-build` 重新编译。
验真后的候选由本机入口归档到准确产物库目录。候选只保留：

- 官方 Worker 运行模块集：`worker/shim.mjs`、`index.js`、WebAssembly、必要 snippets 与 `package.json`。
- `scripts/wrangler.jsonc`：CitizenChatServer 独立资源、域名、应用标识和授权合同。
- `schema.sql`：TataChatServer 唯一 D1 最终结构。
- `scripts/product.json`、候选中的 `upstream-release.json` 与 `SHA256SUMS`：实例声明、上游正式来源及候选闭集验真。

装配必须复制 `worker-build` 的完整现代模块布局，禁止只保留 `worker/` 而遗漏 `shim.mjs`
引用的 `index.js`、WebAssembly 或 snippets；官方构建目录中的 `.gitignore` 不得进入候选。

Cloudflare WASM 构建单独关闭 Release strip，保留 `wasm-bindgen` 运行必需的 `externref` 表；
该设置不改变 LinuxARM 产物规则。

GMB 产品源码目录禁止生成 Worker、Rust `target` 或 `build`。D1 生产资源编号、授权公钥、
APNs 私钥和 FCM 服务账户只在发布事务中注入隔离候选，不写入本目录。当前步骤不部署，
也不切换 CitizenServe 聊天数据面。
