# GMB

GMB 是公民链、公民移动端、公民服务端、公民钱包、CitizenSDK 和官网的开源产品仓库。产品源码、
公开契约和测试源码由本仓库维护；各产品可独立完成开发、测试、依赖准备、构建和运行，源码目录不保存生成物。
GitHub CI/Release直接调用本仓产品流程；GMB不复制私人运维源码或第二套产品流水线。

快速入口：

- 白皮书唯一真源：[`citizenweb/src/whitepaper.md`](citizenweb/src/whitepaper.md)
- 公民宪法唯一真源：链上立法院模块 [`citizenchain/runtime/public/legislation-yuan/`](citizenchain/runtime/public/legislation-yuan/)（`law_id=0`、`tier=宪法`，创世注入 + 立法投票修订；展示端从链上结构化法律重建）
- 统一数据字典：TATA 私有仓库中的 [`dictionary/gmb`](https://github.com/VoyagerRhett/TATA/tree/main/dictionary/gmb)；
  GMB 门禁通过中央流程只读索引、共享分片和准确产品分片，本仓不保留副本。
- 统一二维码协议：[`citizenchain/crates/qr-protocol/`](citizenchain/crates/qr-protocol/)
- 公民链内部组件位于 `citizenchain/crates/`；静态资源统一位于 `citizenchain/node/resources/`，
  仅整合 Logo 母版、桌面图标和原有打包资源。
  Cargo 链接配置统一放在公民链脚本目录 `citizenchain/scripts/config.toml`，公民链构建入口显式加载该文件。
- 公民链构建、Logo 和账户派生工具位于 `citizenchain/scripts/`；公民治理机构数据生成器位于 `citizenapp/scripts/`。
- 各产品独立维护脚本只放在本产品根 `scripts/`，禁止根层执行脚本及内部第二个脚本目录。没有维护脚本的产品不创建空目录；构建配置、测试源码和工具固定入口按其原有职责放置。
- 产品与发布边界：[本文件“产品与发布边界”](#产品与发布边界)
- GitHub Actions：[`repository.yml`](.github/workflows/repository.yml)是唯一接受显式调度的入口，
  直接调用当前提交中的产品流程。GMB一级产品根目录
  不保存 GMB 产品级 Workflow 副本；内嵌上游依赖保留的来源仓库 `.github` 元数据不会成为本仓
  可执行 Workflow。统一仓库门禁继续检查文档、残留、安全边界和新增代码的中文注释。

## 产品与发布边界

产品目录：

- `citizenchain`：公民链 Node、Runtime 与 OnChina。
- `citizenapp`：公民 iOS、Android 移动端，不包含服务端实现。
- `citizenserve`：独立部署到 Cloudflare 的公民服务端。
- `citizenchatserver`：CitizenChatServer 的公民产品声明与 Cloudflare 资源配置，不复制通用聊天源码。
- `citizenwallet`：公民钱包 iOS、Android 离线冷钱包。
- `citizenweb`：公民网 Web 前端，不包含公民服务端。
- `citizensdk`：公民链跨平台 SDK 独立产品，不承载广场、聊天或其它应用业务。

产品与流程的 `platform` 只允许以下小写闭集：`ios`、`android`、`macos`、`windows`、
`linux-arm`、`linux-amd`、`sdk`、`cloudflare`、`wasm`、`web`。官方 ABI、target triple、
Apple 技术变体、交付渠道和供应商事实使用各自准确字段，不得拼接或重载平台值。

- CitizenApp 与 CitizenWallet 使用 `ios`、`android`。
- CitizenChain Node 使用 `linux-arm`、`linux-amd`、`macos`、`windows`；Runtime 使用 `wasm`。
- CitizenSDK 的产品流程身份使用 `sdk`，具体原生制品继续记录各自宿主平台与架构。
- CitizenWeb 使用 `web`；CitizenServe 的流程平台使用 `cloudflare`，正式 Release 字段服从其产品字典。
- CitizenChatServer 的产品声明、CI 候选、正式 Release 与发布授权全部且只能使用
  `platform: cloudflare`。

所有产品只保留当前字典规定的唯一最终字段和值，不保留别名、双写、转换或过渡路径。

每个产品、类型化交付目标和动作独立管理。CitizenServe 的 Cloudflare 部署目标分别使用独立的
CI、Release逻辑流水线、记录和产物，不与CitizenApp或CitizenWeb合并计算；生产Publish
只由本机产品发布器执行，不属于GitHub Workflow。

会员状态采用“手机即时确认 + 服务端唯一 finalized 投影”两条互补写入路径。CitizenApp 在
订阅、取消、换档或档位变更交易 finalized 后，只用链上 `tx_hash + block_hash` 立即确认；
禁止另造操作编号，HTTP 重试只复用同一交易，不得重新签名或重新发送链上交易。
CitizenServe 每五分钟通过既有 Cloudflare Access + Tunnel 连接国储会权威 RPC，以
System.Events 发现受影响关系，再从同一 finalized 区块批量读取订阅和创作者档位 storage。
平台会员、创作者订阅和创作者档位共用一个游标，整块处理成功后才推进；自动续费、自动
恢复、挂起、终止以及手机同步失败都由这一任务补齐，不增加节点回调、密钥、操作编号或
链时钟。广场发布与资料读取仍只读 CitizenServe D1，禁止在请求路径点查链或追赶投影。
D1 没有会员行就不向其他用户展示会员信息，不输出“未知”“尚未同步”等第三状态。

CitizenServe 的 Cloudflare 物理资源唯一命名为：Worker、主 D1、KV 与 Queue 均为
`citizenserve`，下载 D1 为 `citizenweb-download`，私有与公开媒体 R2 分别为
`citizenserve-private` 与 `citizenserve-media`。两个 R2 保持物理隔离，不迁移、不兼容旧名称。

真机聊天诊断统一使用客户端已有 `envelope_id` 串联本机入队、WSS 阶段、密文投递、接收和
落库，不新增操作编号。诊断只在 debug/profile 构建写入手机本地
`citizenapp_diag.log`，只允许稳定阶段码、投递状态、CID/设备路由标识和耗时；禁止记录消息
正文、媒体内容、钱包密钥、设备子钥、签名、会话令牌或完整服务端异常。Release 构建默认
保持零诊断日志；只有本机真机排障构建显式设置编译期
`CITIZENAPP_DIAGNOSTICS=true` 时才临时启用，不能运行时远程开启。复现完成后直接读取两台
手机的本地日志进行同一信封的数据流对账。WSS 握手诊断只在该模式下使用独立 nonce 对同
一路径执行一次无 Upgrade 的 HTTPS 预检，只记录 HTTP 状态和稳定错误码；不记录响应正文
或复用正式 WSS 签名。正常发布不携带该开关。

iOS必须由CitizenApp产品Release流程完成编译并安装到真机；安装完成后的真机测试、设备操作和日志
检查必须统一使用 Device Hub，禁止以截图驱动、拍照、模拟器或其他未登记测试工具替代。
真机记录继续遵守最小诊断边界，不得保存消息正文、附件内容、钱包密钥、设备子钥、会话令牌
或生物识别数据。

公民聊天唯一链路是 CitizenApp `lib/chat/` → TataChatSDK → CitizenChatServer。TataChatSDK
唯一实现聊天页面、OpenMLS、消息与附件存储、本机可靠队列、HTTPS/WSS、离线补拉、ACK 和重连；
CitizenChatServer 是唯一公民聊天服务端。CitizenApp 不复制聊天内核，CitizenServe 不保存或转发
聊天消息、附件、KeyPackage、邮箱、信令、ACK 或聊天推送端点。

CitizenServe 只在合法会话、当前 CID 绑定和有效会员状态成立时，通过
`POST /auth/chatserver/access` 签发短期授权。普通应用通知独立使用
`PUT /square/push-endpoint`，只服务广场公开提醒和会员存储清理预告；聊天唤醒及其端点完全属于
CitizenChatServer。旧 CitizenServe 聊天数据面没有兼容、迁移、别名、双轨或回退路径。

产品目录只保留代码实现、公开配置、测试、脚本与资源文件；私人运维源码、长期记忆、任务卡、
证书和机密不属于本仓库。

#### CitizenApp隔离测试快照真源规则（2026-08-28）

- CitizenApp本机测试只在产品源码外隔离快照运行；应用目录不得保存链端SCALE金标或CitizenServe推送实现的镜像副本。
- 官方测试入口必须把 `scale_codec_vectors.json`、`role_permission.json` 与
  `citizenserve/src/shared/push.ts` 从当前 GMB 仓库复制到一次性快照，并在任一真源缺失时立即失败。
- 跨产品契约测试始终读取本次仓库源码，禁止读取历史缓存、发布产物或另行维护的兼容副本。

### 设备子钥登记的前台验证规则

- CitizenApp 新设备或硬件子钥变化时，只允许在根导航器就绪后展示一次 Cloudflare Turnstile 设备绑定验证；冷启动不得提交空 token。
- Turnstile 未配置、界面未就绪、用户取消或 token 不合法都必须失败关闭，不得登记设备子钥，也不得循环重试。
- 已登记设备继续使用按 CID 隔离的 P-256 硬件子钥静默登录；该登录和日常请求不触发生物识别。
- iOS 真机交互回归统一使用 Device Hub/XCTest；禁止用桌面坐标点击冒充设备触控。

## 公民聊天服务边界

- CitizenApp 的现有 `lib/chat/` 只保留产品入口、TataChatSDK 适配、会员附件策略和推送桥。
- CID、当前账户、会员策略、用途钥、CitizenServe 会话和普通应用通知继续由各自业务模块拥有。
- TataChatSDK 是聊天客户端能力唯一所有者；TataChatServer 是通用聊天服务内核唯一所有者。
- CitizenChatServer 只保存公民实例配置、CI、Release 和宿主合同，不复制服务内核。
- CitizenServe 只签发 CitizenChatServer 短期授权；不存在第二套聊天客户端或聊天服务端。
