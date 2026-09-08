# Linux public headers

当前根 Core 为 89 个函数，薄 Host 为 17 个函数；安装的 `citizensdk_qr_image.h` 另声明 3 个 ZXing-C++ 图像函数。新增 `citizensdk_host_create_with_modules`
与原入口进入同一私有装配，既有 Host ABI v1 enable_wallet 布局和布尔含义不变。
C++ Config 仅以 modules 选择功能；wallet 与 signing 独立，未选 wallet 不开放钱包 UI。
`citizensdk_host_view_account_private_key` 和 C++ `view_account_private_key` 只提供原生安全查看控制，
复用既有 WalletFlow handle/cancel/无秘密 result；不改变原有 wallet kind 或请求结构。
构建期生成的 `citizensdk_internal.h` 不安装，也不是消费者接口。
第 2 步当前为源码与合同更新，尚未完成新的编译、平台运行或硬件验收；既有分步测试数字与结果仅是历史证据。

`citizensdk_host.h` is the Linux Host C ABI. The remaining headers form a
header-only C++17 convenience layer over that ABI and the canonical root
`citizensdk.h`. No C++ symbol is part of CitizenSDK's compatibility promise.

`citizen_sdk_plugin.h` is the one Flutter generated-registrant declaration for
the Linux adapter registered as `CitizenSdkPlugin`. Native C/C++ installation excludes this header;
it adds no product ABI, Core symbol, wallet API or secret-bearing type.

第 7.4 步候选将根 `citizensdk.h`、`citizensdk_types.h` 原字节投影到本目录，并合并两种平台
共用的 7 个原生 Host/C++ 头；任何重叠文件必须字节一致。Hosted 另保留上述 Flutter 注册头，
合计 10 个头，不携带 Host 私有头。源码目录不保存生成的根头副本或运行库；实际 Linux
平台验证仍由后续统一 GitHub CI/Release 执行。

Every pointer returned by CitizenSDK remains governed by its declaring C ABI.
Raw C observers must release each Rust result exactly once. The official C++
`EventObserver` instead borrows the result only during the callback: it may
inspect or copy synchronously, but the C++ trampoline performs the one release
on every return path, so the observer must neither retain nor release it.
