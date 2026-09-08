#!/usr/bin/env bash
# 编译 CitizenWallet 冷钱包原生密码学库，放到 Flutter 能自动打包的位置。
#
# sr25519 与账户用途钥实现分别来自 citizenwallet/rust/src/sr25519.rs、citizenwallet/rust/src/account_crypto.rs，
# 均属于本产品；本库是冷端 FFI 外壳（冷钱包永久离线、不需要链）。
#
# 前置条件：安装 Rust (rustup)
#   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
#
# 用法：
#   ./scripts/build-signer-native.sh            # 编译所有平台
#   ./scripts/build-signer-native.sh android    # 仅 Android
#   ./scripts/build-signer-native.sh ios        # 仅 iOS
#   ./scripts/build-signer-native.sh macos      # 仅 macOS（flutter test 用）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WALLET_DIR="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$WALLET_DIR/rust"
LIB_NAME="libcitizenwallet_signer"
TARGET="${1:-all}"

# 所有本机编译（包括宿主测试）都必须使用中央产物目录。
if [[ "${CI:-}" == true ]]; then
  export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${RUNNER_TEMP:?缺少CI任务临时目录}/citizenwallet/cargo-target}"
fi
: "${CARGO_TARGET_DIR:?必须由塔塔控制台提供CARGO_TARGET_DIR，禁止写入源码rust/target}"
python3 - "$CARGO_TARGET_DIR" "$WALLET_DIR" <<'CHECK_TARGET'
from pathlib import Path
import sys
target, source = map(Path, sys.argv[1:])
if not target.is_absolute() or target.resolve().is_relative_to(source.resolve()):
    raise SystemExit('原生产物目录必须为钱包源码之外的绝对路径')
CHECK_TARGET

ensure_target() {
  local target="$1"
  if ! rustup target list --installed | grep -q "$target"; then
    echo "安装 Rust 目标: $target"
    rustup target add "$target"
  fi
}

# 两组 C 符号必须齐全，否则 Dart 侧 lookupFunction 会在运行时才失败。
# 注意平台差异：ELF 用 -D，Mach-O 用 -g，用错标志会误判为 0。
verify_symbols() {
  local lib="$1"
  local nm_flag="$2"
  local nm_bin
  nm_bin="$(command -v llvm-nm || true)"
  if [ -z "$nm_bin" ]; then
    local sdk_home="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
    nm_bin="$(ls "$sdk_home"/ndk/*/toolchains/llvm/prebuilt/*/bin/llvm-nm 2>/dev/null | tail -1 || true)"
  fi
  if [ -z "$nm_bin" ]; then
    echo "错误: 未找到 llvm-nm，不能验证原生库导出符号。"
    return 1
  fi
  local signer_count account_crypto_count
  signer_count="$("$nm_bin" "$nm_flag" "$lib" 2>/dev/null | grep -c 'citizen_sr25519' || true)"
  account_crypto_count="$("$nm_bin" "$nm_flag" "$lib" 2>/dev/null | grep -c 'account_crypto_' || true)"
  if [ "$signer_count" != "4" ] || [ "$account_crypto_count" != "4" ]; then
    echo "错误: $lib 符号不完整（citizen_sr25519_*=$signer_count/4, account_crypto_*=$account_crypto_count/4）"
    return 1
  fi
  echo "    符号检查通过：citizen_sr25519_*=4, account_crypto_*=4"
}

verify_android_package() {
  local package="$1" expected="${TATA_CONSOLE_NATIVE_ANDROID_DIR:?缺少中央Android原生库目录}/arm64-v8a/$LIB_NAME.so" entry temporary packaged
  [[ -f "$package" ]] || { echo "错误: Android 包不存在：$package"; return 1; }
  [[ -f "$expected" ]] || { echo "错误: Android 原生库不存在：$expected"; return 1; }
  case "$package" in
    *.apk) entry="lib/arm64-v8a/$LIB_NAME.so" ;;
    *.aab) entry="base/lib/arm64-v8a/$LIB_NAME.so" ;;
    *) echo "错误: 只支持校验 APK/AAB：$package"; return 1 ;;
  esac
  # 中文注释：Android 打包会剥离调试段，不能按原文件字节比对；从最终包提取后验证
  # ELF 架构和真实导出符号，缺失、错 ABI 或错误库都会在上传前失败。
  temporary="$(mktemp -d)"
  packaged="$temporary/$LIB_NAME.so"
  unzip -p "$package" "$entry" > "$packaged" || { rm -rf "$temporary"; return 1; }
  [[ -s "$packaged" ]] || { rm -rf "$temporary"; echo "错误: Android 包内原生库为空：$entry"; return 1; }
  file "$packaged" | grep -Eq 'ARM aarch64|ARM64' || {
    rm -rf "$temporary"; echo "错误: Android 包内原生库不是 arm64：$entry"; return 1;
  }
  verify_symbols "$packaged" -D || { rm -rf "$temporary"; return 1; }
  rm -rf "$temporary"
  if unzip -Z1 "$package" | grep -E "(^|/)lib/(armeabi-v7a|x86|x86_64)/$LIB_NAME\\.so$"; then
    echo "错误: Android 包含未支持 ABI 的原生库。"; return 1
  fi
  echo "Android 包原生库门禁通过：$entry"
}

verify_ios_package() {
  local app_bundle="$1" executable nm_bin symbols
  executable="$app_bundle/Runner"
  [[ -f "$executable" ]] || { echo "错误: iOS Runner 不存在：$executable"; return 1; }
  [[ "$(lipo -archs "$executable")" = "arm64" ]] || {
    echo "错误: iOS 真机包必须且只能包含 arm64：$(lipo -archs "$executable")"; return 1;
  }
  nm_bin="$(xcrun --find llvm-nm)"
  symbols="$("$nm_bin" -gU "$executable" 2>/dev/null | awk '{print $NF}' | sed 's/^_//' || true)"
  [[ "$(printf '%s\n' "$symbols" | grep -c '^citizen_sr25519_' || true)" = "4" ]] || {
    echo "错误: iOS Runner 的 citizen_sr25519_* 符号不完整。"; return 1;
  }
  [[ "$(printf '%s\n' "$symbols" | grep -c '^account_crypto_' || true)" = "4" ]] || {
    echo "错误: iOS Runner 的 account_crypto_* 符号不完整。"; return 1;
  }
  echo "iOS 包原生库门禁通过：arm64 与两组 FFI 符号完整"
}

build_android() {
  echo ""
  echo "=== 编译 Android (arm64-v8a) ==="
  ensure_target aarch64-linux-android

  local ndk_home="${ANDROID_NDK_HOME:-}"
  if [ -z "$ndk_home" ]; then
    local sdk_home="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
    ndk_home="$(ls -d "$sdk_home/ndk/"* 2>/dev/null | sort -V | tail -1 || true)"
  fi
  if [ -z "$ndk_home" ] || [ ! -d "$ndk_home" ]; then
    echo "错误: 未找到 Android NDK。请设置 ANDROID_NDK_HOME 或通过 Android Studio 安装 NDK。"
    return 1
  fi
  echo "使用 NDK: $ndk_home"

  local toolchain=""
  case "$(uname -s)" in
    Darwin)
      toolchain="$ndk_home/toolchains/llvm/prebuilt/darwin-x86_64"
      if [ ! -d "$toolchain" ]; then
        toolchain="$ndk_home/toolchains/llvm/prebuilt/darwin-aarch64"
      fi
      ;;
    Linux)
      toolchain="$ndk_home/toolchains/llvm/prebuilt/linux-x86_64"
      ;;
    *)
      echo "错误: 当前系统不支持自动定位 Android NDK toolchain: $(uname -s)"
      return 1
      ;;
  esac
  if [ ! -d "$toolchain" ]; then
    echo "错误: 未找到 Android NDK toolchain: $toolchain"
    return 1
  fi

  export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$toolchain/bin/aarch64-linux-android24-clang"
  export CC_aarch64_linux_android="$toolchain/bin/aarch64-linux-android24-clang"
  export AR_aarch64_linux_android="$toolchain/bin/llvm-ar"

  cd "$RUST_DIR"
  cargo build --release --target aarch64-linux-android

  # CitizenWallet Android 唯一支持 arm64-v8a；禁止重新生成任何 32 位或 x86 ABI。
  local arm64_dest="${TATA_CONSOLE_NATIVE_ANDROID_DIR:?缺少中央Android原生库目录}/arm64-v8a"
  mkdir -p "$arm64_dest"
  cp "$CARGO_TARGET_DIR/aarch64-linux-android/release/$LIB_NAME.so" "$arm64_dest/"
  echo "Android arm64-v8a: $arm64_dest/$LIB_NAME.so ($(wc -c < "$arm64_dest/$LIB_NAME.so" | tr -d ' ') bytes)"
  verify_symbols "$arm64_dest/$LIB_NAME.so" -D
}

build_ios() {
  echo ""
  echo "=== 编译 iOS (arm64 真机) ==="
  ensure_target aarch64-apple-ios

  cd "$RUST_DIR"
  cargo build --release --target aarch64-apple-ios

  # iOS 用**静态库**而非 dylib：裸 .dylib 需嵌入 + 单独签名，且 App Store 要求
  # 动态库必须包在 .framework 里；静态库直接链进 App 二进制，无这些坑。
  # 符号经 podspec 的 -force_load 保留，Dart 侧用 DynamicLibrary.process() 取。
  local dest="${TATA_CONSOLE_NATIVE_IOS_DIR:?缺少中央iOS原生库目录}"
  mkdir -p "$dest"
  cp "$CARGO_TARGET_DIR/aarch64-apple-ios/release/$LIB_NAME.a" "$dest/"
  echo "iOS arm64: $dest/$LIB_NAME.a ($(wc -c < "$dest/$LIB_NAME.a" | tr -d ' ') bytes)"
  verify_symbols "$dest/$LIB_NAME.a" ""
}

build_host() {
  echo ""
  echo "=== 编译宿主平台动态库 (flutter test 用) ==="
  cd "$RUST_DIR"
  # host 调试库给 Dart FFI / flutter test 直接 dlopen；release profile 已设
  # strip=false，本机 dyld 不会报 LINKEDIT 对齐错误。
  cargo build --release

  # 宿主扩展名：macOS 产 .dylib，Linux 产 .so；Dart 侧 native_sr25519.dart 按同一规则取。
  local host_ext
  case "$(uname -s)" in
    Darwin) host_ext=dylib ;;
    *)      host_ext=so ;;
  esac
  local host_lib="$CARGO_TARGET_DIR/release/$LIB_NAME.$host_ext"
  echo "宿主库: $host_lib ($(wc -c < "$host_lib" | tr -d ' ') bytes)"
  verify_symbols "$host_lib" -g
}

case "$TARGET" in
  android) build_android ;;
  ios)     build_ios ;;
  host|macos|linux) build_host ;;
  verify-android-package)
    [[ "$#" -eq 2 ]] || { echo "用法: $0 verify-android-package <apk|aab>"; exit 1; }
    verify_android_package "$2"
    exit 0
    ;;
  verify-ios-package)
    [[ "$#" -eq 2 ]] || { echo "用法: $0 verify-ios-package <Runner.app>"; exit 1; }
    verify_ios_package "$2"
    exit 0
    ;;
  all)
    build_android
    build_ios
    build_host
    ;;
  *)
    echo "用法: $0 [android|ios|macos|all|verify-android-package|verify-ios-package]"
    exit 1
    ;;
esac

echo ""
echo "=== 编译完成 ==="
echo "flutter build / flutter run 会自动把 native library 打包进 App。"
