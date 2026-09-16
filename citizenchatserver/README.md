# CitizenChatServer

Cloudflare 正式资源只使用产品名称：Worker、D1 与 R2 均为
`citizenchatserver`，正式域名为 `chat.crcfrcn.com`。Worker 内部资源句柄唯一为
`D1`、`R2`、`DO`，其中 `DO` 的 `O` 是大写字母；公开变量与 Secret 统一使用
`CHATSERVER_` 前缀。

CI只消费TataChatServer的正式Cloudflare Release并绑定当前GMB `main`的实例声明；
Release只封装准确成功CI候选；产品发布器消费正式GMB Release。

CitizenChatServer 是公民产品使用的 TataChatServer Cloudflare 实例。该目录只保存宿主产品声明与资源配置，不复制通用聊天源码，也不保存编译产物、密钥或生产资源编号。

Cloudflare 是全仓平台闭集中的正式值。`scripts/product.json`、CI 候选和 Release manifest
全部且只能使用 `platform: cloudflare`；禁止第二个供应商字段、双写或过渡转换。

- HTTPS：`https://chat.crcfrcn.com`
- WSS：`wss://chat.crcfrcn.com/realtime`
- 授权签发方：CitizenServe
- 授权受众：`citizenchatserver`
- 通用实现：TATA 仓库的 `tatachatserver`

本机候选由CitizenChatServer产品流程在调用方指定的源码外工作目录中装配。
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
APNs 私钥和 FCM 服务账户只在发布事务中注入隔离候选，不写入本目录。CitizenServe 只签发
短期访问授权；消息、附件、邮箱、KeyPackage、实时连接和聊天推送全部只进入 CitizenChatServer。
