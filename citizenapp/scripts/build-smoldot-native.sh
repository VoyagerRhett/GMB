#!/usr/bin/env bash
# 编译 smoldot native library 并放置到 Flutter 能自动打包的位置。
#
# 编译完成后 flutter build / flutter run 会自动将 .so / .dylib 打包进 App，
# 不需要额外操作。
#
# 前置条件：安装 Rust (rustup)
#   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
#
# 用法：
#   ./scripts/build-smoldot-native.sh           # 编译所有平台
#   ./scripts/build-smoldot-native.sh android    # 仅 Android
#   ./scripts/build-smoldot-native.sh ios        # 仅 iOS
#   ./scripts/build-smoldot-native.sh host       # 当前宿主（flutter test 用）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CITIZENAPP_DIR="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$CITIZENAPP_DIR/smoldot/ffi"
TARGET="${1:-all}"

if [[ "$TARGET" == ios || "$TARGET" == android ]]; then
  if [[ -n "${TATA_CONSOLE_BUILD_CACHE_DIR:-}" ]]; then
    export CARGO_TARGET_DIR="$TATA_CONSOLE_BUILD_CACHE_DIR/cargo-target"
  elif [[ -n "${TATA_CONSOLE_CACHE_DIR:-}" ]]; then
    export CARGO_TARGET_DIR="$TATA_CONSOLE_CACHE_DIR/native/cargo"
  elif [[ "${CI:-}" == true ]]; then
    export CARGO_TARGET_DIR="$RUST_DIR/target"
    export TATA_CONSOLE_NATIVE_ANDROID_DIR="$CITIZENAPP_DIR/android/app/src/main/jniLibs"
    export TATA_CONSOLE_NATIVE_IOS_DIR="$CITIZENAPP_DIR/ios/smoldot"
  else
    echo '本机原生库编译必须由TataConsole提供中央工作目录' >&2
    exit 1
  fi
fi

# 确保 Rust 交叉编译目标已安装
ensure_target() {
  local target="$1"
  if ! rustup target list --installed | grep -q "$target"; then
    echo "安装 Rust 目标: $target"
    rustup target add "$target"
  fi
}

build_android() {
  echo ""
  echo "=== 编译 Android (arm64-v8a) ==="
  ensure_target aarch64-linux-android

  # 自动检测 NDK
  local ndk_home="${ANDROID_NDK_HOME:-}"
  if [ -z "$ndk_home" ]; then
    # 从 Android SDK 中查找
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

  # CitizenApp Android 唯一支持 arm64-v8a；禁止重新生成任何 32 位或 x86 ABI。
  local arm64_dest="${TATA_CONSOLE_NATIVE_ANDROID_DIR:?缺少中央Android原生库目录}/arm64-v8a"
  mkdir -p "$arm64_dest"
  cp "$CARGO_TARGET_DIR/aarch64-linux-android/release/libsmoldot.so" "$arm64_dest/"
  echo "Android arm64-v8a: $arm64_dest/libsmoldot.so ($(wc -c < "$arm64_dest/libsmoldot.so" | tr -d ' ') bytes)"
  local account_crypto_count
  account_crypto_count="$("$toolchain/bin/llvm-nm" -D "$arm64_dest/libsmoldot.so" 2>/dev/null | grep -c 'account_crypto_' || true)"
  if [ "$account_crypto_count" != "4" ]; then
    echo "错误: Android libsmoldot.so 的 account_crypto_* 符号为 $account_crypto_count 个（应为 4）"
    return 1
  fi
}

build_ios() {
  echo ""
  echo "=== 编译 iOS (arm64, 静态库) ==="
  ensure_target aarch64-apple-ios
  # Rust/CC 原生对象与 Xcode Runner 使用同一个最低系统版本，禁止随本机 SDK 漂到 27.0。
  export IPHONEOS_DEPLOYMENT_TARGET=16.0

  cd "$RUST_DIR"
  cargo build --release --target aarch64-apple-ios

  # Smoldot 继续作为独立静态库进入 Runner；TataChatSDK 由自己的动态 XCFramework
  # 承载，禁止再把聊天 Rust crate 合并到本归档。
  local dest="${TATA_CONSOLE_NATIVE_IOS_DIR:?缺少中央iOS原生库目录}"
  mkdir -p "$dest"
  cp "$CARGO_TARGET_DIR/aarch64-apple-ios/release/libsmoldot.a" "$dest/"

  # 从 .a 实抽 FFI 导出符号清单,供 podspec 逐个生成 -Wl,-u,<符号>。
  # 手写清单必然漂移:漏一个符号 = Release 被 -dead_strip 静默剔除(Debug 正常、
  # Release 找不到符号),所以清单永远从产物现抽、绝不手维护。
  # Mach-O 符号带下划线前缀;llvm-nm 查 Mach-O 用 -g(-D 是 ELF 专用)。
  local nm
  nm="$(xcrun --find llvm-nm)"
  # llvm-nm 对 .a 里个别无符号表的对象会报警且以非零退出,但符号输出本身完整;
  # 在 pipefail 下必须吞掉它的退出码,真正的完整性由下方符号族计数门禁把关。
  # `-u` 只能保留公开 C FFI。若把 Rust 内部 T 符号也写入清单，Runner 会把
  # compiler_builtins 的 private external 主动变成外部必需符号并在最终链接失败。
  ("$nm" -g --defined-only "$dest/libsmoldot.a" 2>/dev/null || true) \
    | awk '$2 == "T" && $3 ~ /^_(smoldot_|citizen_sr25519_|account_crypto_)/ { print $3 }' \
    | sort -u > "$dest/exported_symbols.txt"

  local n_smoldot n_signer n_account_crypto n_tatachat_sdk
  n_smoldot=$(grep -c '^_smoldot_' "$dest/exported_symbols.txt" || true)
  n_signer=$(grep -c '^_citizen_sr25519_' "$dest/exported_symbols.txt" || true)
  n_account_crypto=$(grep -c '^_account_crypto_' "$dest/exported_symbols.txt" || true)
  n_tatachat_sdk=$(
    ("$nm" -g --defined-only "$dest/libsmoldot.a" 2>/dev/null || true) \
      | awk '$2 == "T" && $3 ~ /^_tatachat_sdk_/ { count += 1 } END { print count + 0 }'
  )
  local n_total
  n_total=$(wc -l < "$dest/exported_symbols.txt" | tr -d ' ')
  echo "iOS arm64: $dest/libsmoldot.a ($(wc -c < "$dest/libsmoldot.a" | tr -d ' ') bytes)"
  if [ "$n_smoldot" -eq 0 ] || [ "$n_signer" -eq 0 ] || [ "$n_account_crypto" -ne 4 ] \
    || [ "$n_tatachat_sdk" -ne 0 ] \
    || [ "$n_total" -ne "$((n_smoldot + n_signer + n_account_crypto))" ]; then
    echo "错误: iOS Smoldot 符号边界不完整或混入 TataChatSDK。"
    return 1
  fi
}

build_host() {
  echo ""
  echo "=== 编译宿主平台动态库（flutter test 用） ==="
  cd "$RUST_DIR"
  # macOS / Linux CI 宿主库要给 Dart FFI / flutter test 直接 dlopen。
  # Rust release profile 的 strip=true 会让本机 dyld 报 LINKEDIT 对齐错误，
  # 因此 host 调试库单独禁用 strip；Android/iOS 打包库仍沿用 release profile。
  CARGO_PROFILE_RELEASE_STRIP=false cargo build --release

  local host_extension
  case "$(uname -s)" in
    Darwin) host_extension=dylib ;;
    Linux) host_extension=so ;;
    *) echo "错误: 不支持的 flutter test 宿主平台：$(uname -s)"; return 1 ;;
  esac
  # Respect the caller-owned Cargo target directory so TataConsole can keep
  # every native build artifact inside its central work tree.
  local host_target_dir="${CARGO_TARGET_DIR:-$RUST_DIR/target}"
  local host_library="$host_target_dir/release/libsmoldot.$host_extension"
  echo "宿主库: $host_library ($(wc -c < "$host_library" | tr -d ' ') bytes)"

  # flutter_tester 不会链接 iOS 的 CocoaPods 静态库；宿主测试必须 dlopen 这份
  # dylib/so。构建成功不等于 FFI 完整，LTO 或导出配置漂移都可能只丢一部分符号，
  # 因此在启动任何 Dart 测试前从真实宿主产物逐族验收。
  local host_symbols
  case "$(uname -s)" in
    Darwin)
      local nm
      nm="$(xcrun --find llvm-nm)"
      host_symbols="$(
        (
          "$nm" -gU "$host_library" 2>/dev/null \
            | awk '{ print $NF }' \
            | sed 's/^_//' \
            | sort -u
        ) || true
      )"
      ;;
    Linux)
      host_symbols="$(
        (
          nm -D --defined-only "$host_library" 2>/dev/null \
            | awk '{ print $NF }' \
            | sort -u
        ) || true
      )"
      ;;
  esac

  local required_account_crypto_symbols=(
    account_crypto_derive_key
    account_crypto_x25519_public_key
    account_crypto_seal
    account_crypto_open
  )
  local symbol
  for symbol in "${required_account_crypto_symbols[@]}"; do
    if ! grep -qx "$symbol" <<<"$host_symbols"; then
      echo "错误: 宿主 libsmoldot 缺少 $symbol" >&2
      return 1
    fi
  done
  local n_smoldot n_signer n_account_crypto
  n_smoldot="$(grep -c '^smoldot_' <<<"$host_symbols" || true)"
  n_signer="$(grep -c '^citizen_sr25519_' <<<"$host_symbols" || true)"
  n_account_crypto="$(grep -c '^account_crypto_' <<<"$host_symbols" || true)"
  local n_tatachat_sdk
  n_tatachat_sdk="$(grep -c '^tatachat_sdk_' <<<"$host_symbols" || true)"
  if [ "$n_smoldot" -eq 0 ] || [ "$n_signer" -eq 0 ] || [ "$n_account_crypto" -ne 4 ] \
    || [ "$n_tatachat_sdk" -ne 0 ]; then
    echo "错误: 宿主符号清单不完整（account_crypto_* 必须精确，其余族必须非空）。" >&2
    return 1
  fi
}

verify_android_package() {
  local package="$1" expected="${TATA_CONSOLE_NATIVE_ANDROID_DIR:-$CITIZENAPP_DIR/android/app/src/main/jniLibs}/arm64-v8a/libsmoldot.so" entry temporary packaged nm_bin symbols
  [[ -f "$package" ]] || { echo "错误: Android 包不存在：$package"; return 1; }
  [[ -f "$expected" ]] || { echo "错误: Android 原生库不存在：$expected"; return 1; }
  case "$package" in
    *.apk) entry="lib/arm64-v8a/libsmoldot.so" ;;
    *.aab) entry="base/lib/arm64-v8a/libsmoldot.so" ;;
    *) echo "错误: 只支持校验 APK/AAB：$package"; return 1 ;;
  esac
  # 中文注释：Android 打包会剥离调试段；从最终包提取后验证 ELF 架构和全部 FFI
  # 符号族，避免源码库存在但 APK/AAB 漏包或装入错误 ABI。
  temporary="$(mktemp -d)"
  packaged="$temporary/libsmoldot.so"
  unzip -p "$package" "$entry" > "$packaged" || { rm -rf "$temporary"; return 1; }
  [[ -s "$packaged" ]] || { rm -rf "$temporary"; echo "错误: Android 包内 libsmoldot 为空。"; return 1; }
  file "$packaged" | grep -Eq 'ARM aarch64|ARM64' || {
    rm -rf "$temporary"; echo "错误: Android 包内 libsmoldot 不是 arm64。"; return 1;
  }
  nm_bin="$(command -v llvm-nm || true)"
  if [[ -z "$nm_bin" ]]; then
    local sdk_home="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
    nm_bin="$(ls "$sdk_home"/ndk/*/toolchains/llvm/prebuilt/*/bin/llvm-nm 2>/dev/null | tail -1 || true)"
  fi
  [[ -n "$nm_bin" ]] || { rm -rf "$temporary"; echo "错误: 未找到 llvm-nm。"; return 1; }
  symbols="$("$nm_bin" -D --defined-only "$packaged" 2>/dev/null | awk '{print $NF}' || true)"
  local family
  for family in smoldot_ citizen_sr25519_; do
    [[ "$(printf '%s\n' "$symbols" | grep -c "^$family" || true)" -gt 0 ]] || {
      rm -rf "$temporary"; echo "错误: Android 包内 libsmoldot 缺少 $family 符号。"; return 1;
    }
  done
  [[ "$(printf '%s\n' "$symbols" | grep -c '^account_crypto_' || true)" = "4" ]] || {
    rm -rf "$temporary"; echo "错误: Android 包内 account_crypto_* 符号必须正好 4 个。"; return 1;
  }
  rm -rf "$temporary"
  if unzip -Z1 "$package" | grep -E '(^|/)lib/(armeabi-v7a|x86|x86_64)/libsmoldot\.so$'; then
    echo "错误: Android 包含未支持 ABI 的 libsmoldot。"; return 1
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
  local family
  for family in smoldot_ citizen_sr25519_; do
    [[ "$(printf '%s\n' "$symbols" | grep -c "^$family" || true)" -gt 0 ]] || {
      echo "错误: iOS Runner 缺少 $family 导出符号。"; return 1;
    }
  done
  [[ "$(printf '%s\n' "$symbols" | grep -c '^account_crypto_' || true)" = "4" ]] || {
    echo "错误: iOS Runner 的 account_crypto_* 符号必须正好 4 个。"; return 1;
  }
  [[ "$(printf '%s\n' "$symbols" | grep -c '^tatachat_sdk_' || true)" = "0" ]] || {
    echo "错误: iOS Runner 静态符号中混入 TataChatSDK。"; return 1;
  }
  echo "iOS Smoldot 包门禁通过：arm64 与独立 FFI 符号边界完整"
}

case "$TARGET" in
  android)
    build_android
    ;;
  ios)
    build_ios
    ;;
  host|macos|linux)
    build_host
    ;;
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
    echo "用法: $0 [android|ios|host|all|verify-android-package|verify-ios-package]"
    exit 1
    ;;
esac

echo ""
echo "=== 编译完成 ==="
echo "flutter build / flutter run 会自动将 native library 打包进 App。"
