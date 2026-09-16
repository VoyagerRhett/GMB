# Third-party notices

CitizenSDK 组合了不同许可证覆盖的源码。根 `LICENSE` 是组件许可证入口；任何分发都必须
保留本文件及对应许可证原文，不能只分发原生二进制。GitHub Release 审计包另外保留完整源码、
来源说明和锁文件；Hosted Package 只过滤开发输入，但继续携带本文件、根许可证入口、MIT、
GPL with Classpath Exception 原文，以及根许可证入口中完整重现的 Apache-2.0 原文。

## ZXing-C++ 与 libzint

第4步的五端 QR 图像层静态链接未修改的 ZXing-C++ 3.1.1 官方完整源码，
且为了 QR 生成启用其内置 libzint。ZXing-C++ 是 Apache-2.0，其官方顶层 `LICENSE`
摘要为 `c6596eb7be8581c18be736c846fb9173b69eccf6ef94c5135893ec56bd92ba08`；根 `LICENSE`
已保留 Apache-2.0 完整原文。libzint 的生产文件声明 BSD-3-Clause，完整分发条款也保留在根 `LICENSE`。

Copyright (C) 2008-2025 Robin Stuart <rstuart114@gmail.com>

SDK 源树只包含自有窄包装，不复制上游源码；官方归档、准确版本和 SHA256
由CitizenSDK依赖锁固定。发布候选必须保留本声明和许可证，不得将上游著作权写成CitizenSDK自有实现。

第 7.1 步新增的 `linux/` Host 与合同测试是 CitizenSDK 自有实现，适用根 MIT 许可证。该步只
提交源码，没有在仓库中携带 TPM2-TSS、SQLite、GTK 或 C++ runtime 的第三方源码/二进制副本，
也没有执行 Linux 编译或测试、没有生成 Linux `.so`。第 7.4 步把同版本安装投影与 Hosted
过滤纳入唯一候选合同，不新增或更改第三方组件版本。后续统一 GitHub CI/Release 必须根据
实际构建输入与最终静态/动态链接闭包重新核对每个组件的许可证、
copyright notice 与可重分发条件并写入正式候选；本段不能替代届时从实际二进制和锁定构建输入
得到的依赖清单，证据不齐不得生成可分发候选。Hosted 排除 Linux Host 私有构建源码，不等于
免除随同版 Core/Host 运行库分发所需的许可证、归属和来源材料；不得用未知版本占位。

## sr25519 signer

`native/signer` 的最初密码学语义来自 `shared/citizen-signer`，许可证为 MIT；原文保存于根
目录 `LICENSE-MIT`。第 4.1 步已把算法集中到 `src/sr25519.rs`，由 `src/lib.rs` 的 legacy FFI
与 `src/chain_signer.rs` 的类型化合同共同调用；当前文件布局不再宣称与 shared 的 `lib.rs`
逐字节一致。该 crate 使用 `schnorrkel`、`zeroize` 等官方生态依赖，解析闭包由根
`Cargo.lock` 固定。

## CitizenSDK Rust Core

`native/contracts`、`native/engine`、`native/ffi` 与 `native/smoldot/provider` 是 CitizenSDK
自有实现，继承根 `Cargo.toml` workspace 声明的 MIT 许可证；自有代码的许可证原文保存于
`LICENSE-MIT`。contracts 使用 `zeroize 1.9.0` 保护短生命周期秘密缓冲区，并使用
`futures-core 0.3.34` 表达不绑定具体 executor 的对象安全异步合同。它还直接使用：

- `bs58 0.5.1`（crate manifest：`MIT/Apache-2.0`）编码规范 SS58；
- `blake2 0.10.6`（crate manifest：`MIT OR Apache-2.0`）计算 `SS58PRE` checksum。

engine 精确依赖 crates.io 官方 `subxt-core 0.43.0`；该依赖声明为
`Apache-2.0 OR GPL-3.0`。CitizenSDK 只使用它解析 SCALE metadata、`System.Events`、构造并
编码已签名 extrinsic V4，以及计算 Substrate extrinsic 哈希，不把它当作网络客户端，也不
由此引入远程 RPC 或第二份轻节点实现。
准确依赖闭包和 registry checksum 由根 `Cargo.lock` 固定。Rust Core/产品 FFI 的来源闭集
独立受 Release 合同保护；`native/smoldot/SOURCE_SHA256.json` 只分类收编的 smoldot 来源、
必要适配和与其共同演进的 SDK-only Provider，不承担 Core 清单职责。
`subxt-core 0.43.0` 的解析闭包另包含 `base58 0.2.0`（crate manifest：MIT）。这些第三方项目
的许可证与 copyright notice 以各 crate 自身分发内容为准；根 `LICENSE-MIT` 只覆盖
VoyagerRhett/CitizenSDK 自有代码，不能冒充第三方许可证原文。

Rust 钱包派生与短生命周期秘密处理还直接使用 `bip39 2.2.2`、`getrandom 0.2.17`、
`hmac 0.12.1`、`pbkdf2 0.12.2`、`sha2 0.10.9`、`unicode-normalization 0.1.25`、
`unicode-segmentation 1.13.3` 与 `zeroize 1.9.0`；准确许可证声明、copyright notice、
registry checksum 和传递闭包以各 crate 分发内容及根 `Cargo.lock` 为准。`bip39` 的
`zeroize` feature 是本产品处理 mnemonic 的必选依赖语义，不是可省略的构建优化。

产品 FFI 使用 `sha2 0.10.9` 与 `blake2 0.10.6` 复核随包资产；平台金库适配另外使用
RustCrypto 官方 `aes-gcm 0.10.3`、`aes 0.8.4` 与 `ghash 0.5.1` 在 Rust 受控缓冲区内
认证加密账户 child mini-secret；三个 crate 均启用其可用的 `zeroize` feature，以清理
AES key schedule 和认证构造期间的临时 key material，
使用 `getrandom 0.2.17` 生成每份密文独立的 256 位 DEK 与 nonce，并以 `zeroize 1.9.0`
清理 DEK、助记词和其它短生命周期秘密。系统金库只封装随机 DEK，不直接接收
child mini-secret 或 sr25519 私钥。准确许可证声明、copyright notice、registry checksum
与传递闭包以各 crate 分发内容及根 `Cargo.lock` 为准。

smoldot provider 使用 `tokio 1.53.1` 驱动轻节点异步工作，并用 `blake2-rfc 0.2.18` 独立核对完整 extrinsic hash。
Provider 对 `smoldot-light` 的路径依赖继续受下述 smoldot PoW 许可证边界覆盖。根
`Cargo.lock` 固定这些准确版本与 registry checksum，且 Release 另外要求 Provider 的递归
smoldot registry 闭包与已验证 PoW 锁逐项一致。

## smoldot Dart 与 FFI

CitizenApp 已验证的 Dart smoldot 包已作为 CitizenSDK 内部实现并入 `lib/src/smoldot`，原六个
测试和两个公开链夹具并入 `test/smoldot`。历史包清单、锁文件、许可证、说明和示例保存于
`docs/smoldot-dart` 供审计；它们不再构成第二个 Dart 包或 `path` 依赖。迁移闭集继续由发布
合同逐文件校验。

`native/smoldot/ffi` 继承 CitizenApp 的 Apache-2.0 legacy FFI 边界，保留当前 Dart 所需的
轻节点和 signer C ABI，
排除只供聊天使用的 OpenMLS/聊天信封与账户数据加密代码。Apache 2.0 许可证原文保存于
`native/smoldot/LICENSE-APACHE-2.0`；Hosted 包排除 `native` 源码目录，但在根 `LICENSE`
逐字重现同一原文。FFI `Cargo.lock` 从 CitizenApp 已验证锁机械裁掉已排除产品闭包，并保持
全部保留 registry 包的 name/version/checksum。

新的产品级公共头文件只位于根 `include`，只声明 `citizensdk_*`，不把 legacy
`smoldot_*`、`citizen_sr25519_*` 或底层依赖接口提升为第三方产品 ABI。

## smoldot PoW 轻节点

`native/smoldot/pow/lib` 与 `native/smoldot/pow/light-base` 来源于 CitizenApp 当前使用的
smoldot PoW + GRANDPA 快照。该范围保留上游声明的
`GPL-3.0-or-later WITH Classpath-exception-2.0`；许可证原文保存于根目录
`LICENSE-GPL-3.0` 与 `native/smoldot/LICENSE`，上游提交和本地 PoW 改动记录保存于
`native/smoldot/UPSTREAM.md`。

轻客户端产品明确不包含全节点 `author` 出块模块，也不包含全节点 identity keystore 与
seed phrase 私钥入口。其余共享生产源码、夹具和上游内联测试按来源复制；仅 workspace、
crate 入口和 identity 模块做最小产品边界适配。PoW 依赖闭包由与 CitizenApp 稳定来源
中保留 registry 包 name/version/checksum 一致、但已机械裁掉全节点/WASM 不可达闭包的
`native/smoldot/pow/Cargo.lock` 固定。

完整来源分类、排除项和同步策略见 `docs/SOURCE_PROVENANCE.md`。锁文件是依赖输入，不是
构建产物；实际许可证义务仍以每个依赖包自身许可证为准。

## Windows 系统适配来源（第 8.1 步）

Windows 平台无关 Host、typed records、生命周期及钱包流程来自本 SDK 现有 Linux 实现；
必要 Windows 差异单独列入来源文档，不能声称这些适配与 CitizenApp 逐字节相同。
Microsoft Windows SDK 的 Win32、NCrypt、BCrypt、TBS 和 NT 文件 API 是目标系统接口；
本仓库没有复制 Microsoft SDK 或 PCPTool 源码，官方样例只用于接口参考。
Host 消费显式预置的 SQLite MSVC 静态归档。第 10.5 步已固定下述准确版本、构建选项
和许可证来源；真实原生构建仍待统一矩阵验收。Windows 不增加 OpenSSL、TPM2-TSS 或软件金库。

## 固定静态依赖（第 10.5 步）

本 SDK 的 LinuxARM/LinuxAMD Host 固定 SQLite 3.53.4、OpenSSL libcrypto 3.5.8、
TPM2-TSS 4.2.0（ESYS/SYS/MU/RC/device）；Windows Host 只固定 SQLite 3.53.4。
它们是待矩阵实编验证的准确输入，不能据本节宣称 Linux/Windows 已编译或运行通过。

SQLite 属于 Public Domain。OpenSSL 是 Apache-2.0；TPM2-TSS 所选闭集是 BSD-2-Clause。
三项法律原文均已加入根 LICENSE，Hosted 和审计包必须保留，不能由 SDK 的 MIT 替代。
官方来源、归档摘要、固定构建选项以中央 dependencies.json 的 native_dependencies 子合同
为唯一准备依据；SDK 发布器只固定该合同摘要，不在发布时联网选择依赖版本。

OpenSSL 官方 README.md 的原文归属：
Copyright (c) 1998-2026 The OpenSSL Project Authors
Copyright (c) 1995-1998 Eric A. Young, Tim J. Hudson
All rights reserved.

TPM2-TSS 所选生产实现与八个公共头的原文归属（重复行合并，未修饰上游拼写）：

Copyright (c) 2015-2018, Intel Corporation
Copyright (c) 2015 - 2018, Intel Corporation
Copyright 2015, Andreas Fuchs @ Fraunhofer SIT
Copyright (c) 2015 - 2017, Intel Corporation
Copyright (c) 2020, Intel Corporation
Copyright (c) 2025 - 2025, Huawei Technologies Co., Ltd.
Copyright (c) 2018, Intel Corporation
Copyright (c) 2017, Intel Corporation
Copyright (c) 2015 - 2020, Intel Corporation
Copyright (c) 2025, Juergen Repp
Copyright (c) 2015 - 2018 Intel Corporation
Copyright 2017-2018, Fraunhofer SIT sponsored by Infineon Technologies AG
SPDX-FileCopyrightText: 2018, David J. Maria @ fb.com
SPDX-FileCopyrightText: 2018, Intel
SPDX-FileCopyrightText: 2019, Infineon Technologies AG
SPDX-FileCopyrightText: 2019, Alon Bar-Lev
SPDX-FileCopyrightText: 2019, Fraunhofer SIT sponsored by Infineon
Copyright 2017, Fraunhofer SIT sponsored by Infineon Technologies AG
Copyright 2025, Juergen Repp
Copyright (c) 2022, Intel Corporation
Copyright 2020, Fraunhofer SIT sponsored by Infineon Technologies AG
SPDX-FileCopyrightText: 2018 - 2022, Intel
SPDX-FileCopyrightText: 2018 - 2020, Fraunhofer SIT sponsored by Infineon
SPDX-FileCopyrightText: 2019, Fabrice Funtaine
SPDX-FileCopyrightText: 2019 - 2022, Infineon Technologies AG
SPDX-FileCopyrightText: 2022, Juergen Repp
SPDX-FileCopyrightText: 2018, Fraunhofer SIT sponsored by Infineon
SPDX-FileCopyrightText: 2019 - 2023, Intel
SPDX-FileCopyrightText: 2022, Erik Larsson
SPDX-FileCopyrightText: 2023 - 2024, Infineon Technologies AG
SPDX-FileCopyrightText: 2023, Juergen Repp
Copyright 2019, Intel Corporation
Copyright (c) 2019, Wind River Systems.
Copyright (c) 2018 Intel Corporation
SPDX-FileCopyrightText: 2019 Intel Corporation
All rights reserved.

以上对应 tpm2-tss-4.2.0 的 src/tss2-esys、src/tss2-sys、src/tss2-mu、
src/tss2-rc、src/util、src/tss2-tcti 的 device/nodl 公共部分，以及所交付八个头。
不交付 SPI/I2C/FAPI/Policy 后端及其头。编译时使用未经修改的官方完整源码副本；
构建源码仅是中央工作状态，不能假称 SDK 源码树已经收编这些上游源码。

最终运行库继续经过既有 ELF/PE、导出与动态依赖门禁。新证据绑定静态输入和最终
Core/Host 字节；这不是独立签名证明，不替代同源 CI/Release 与平台运行测试。
GTK/系统库以及 Cargo 解析闭包的其余许可义务仍须随完整发布验收核对，本步骤只闭合
上述三项新固定静态输入，不把它们冒充整个 SDK 的完整 SBOM。
