# CitizenSDK Flutter Apple adapter

当前五端统一 63 方法；open 唯一请求为 `[1, modules]`。六模块由同一 Rust 实现按需装配。
十个 QR 方法与其它平台使用同名、同 tuple 和同上限；图像识别/生成只连接 SDK 内 ZXing-C++ 3.1.1。
无会话 verifySignature 只接受 `[1, accountId, signature, payload]`，返回 `[1, bool]`，
错误 session/sequence 均为 null；不创建 facade/session、事件订阅、链数据库或金库。
钱包管理、签名与历史分别投影，签名只使用既有安全账户，不增设秘密输出。
第 2 步当前为源码与合同更新，尚未完成新的编译、平台运行或硬件验收；既有分步测试数字与结果仅是历史证据。

第 3 步的 `getGenesisHash` 与 `getAccountBalances` 保留会话外壳，只投影原生链查询；
余额元素继续复用现有 tuple，不去重、不排序，也不在 Swift 循环发起单账户查询。
`viewAccountPrivateKey` 紧接 `getWalletProfile`，只传公开账户，成功字段为空。
它复用 SDK 自有安全界面与取消注册；内部显示缓冲不进入此目标，完成必须等清屏和 Core 真实终态。
新的平台运行态和硬件安全验收仍未完成。

This target only projects the native `CitizenSdk` Swift facade through the same
fixed-position protocol-v1 tuples used by Android. It contains no Core, chain,
wallet, signer, state-store, or secret-vault implementation.

The method channel is `citizen/sdk/core/v1`; the event channel is
`citizen/sdk/events/v1`. Mnemonics, passwords, DEKs, native handles, result
handles and prepared-wallet identities have no tuple position. Create/import/
add-account operations launch the SDK-owned Apple wallet UI. A recovery phrase
may be held briefly only by that non-selectable UI until commit/cancel; it is
cleared on terminal paths and never crosses this Flutter target.

Registration publishes the plugin instance on both Apple platforms. Detach is
idempotent and always revokes the method handler, revokes the event handler,
permanently invalidates the current event epoch, clears the sink, cancels every
session's outstanding operations, and only then awaits session closure. One
failed close is transferred to the existing Core supervisor and cannot prevent
later sessions from closing. iOS receives Flutter's published-object
`detachFromEngine(for:)` callback; the current FlutterMacOS registrar exposes no
equivalent callback, so macOS uses the same explicit detach entry and keeps
`deinit` only as the final shutdown fallback.
