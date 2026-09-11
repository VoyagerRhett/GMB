#!/usr/bin/env bash
# 在本端中央工作根生成本机优化安装包；本脚本不启动、不安装产品。
#
# 用法：citizenwallet-run.sh <ios|android>
#
# 目标平台是必填参数，不做任何自动探测：探测总要在失败时选一个回落，
# 而回落的那一端会被当成用户想编的那一端。塔塔控制台的「编译iOS端 / 编译Android端」
# 两个按钮各自传死这个参数。与 citizenapp-run.sh 同口径。
#
# 调用方可提供独立缓存目录；没有 TataConsole 时使用系统临时目录。
set -euo pipefail
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
  LINK_TARGET="$(readlink "$SCRIPT_PATH")"
  [[ "$LINK_TARGET" == /* ]] || LINK_TARGET="$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P)/$LINK_TARGET"
  SCRIPT_PATH="$LINK_TARGET"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P)"
CITIZENWALLET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLATFORM="${1:?缺少目标平台，用法：$0 <ios|android>}"
[[ "$PLATFORM" == ios || "$PLATFORM" == android ]] \
  || { echo "本机目标平台只接受 ios 或 android：$PLATFORM" >&2; exit 1; }

TATA_CONSOLE_CACHE_DIR="${TATA_CONSOLE_CACHE_DIR:-${TMPDIR:-/tmp}/citizenwallet-$PLATFORM}"
# 源码根只读；两个端的 Flutter、Pods 和 Gradle 状态分别由控制台生成。
[[ "$CITIZENWALLET_DIR" == "$REPO_ROOT/citizenwallet" ]] || {
  echo "citizenwallet本机Build源码身份无效：$CITIZENWALLET_DIR" >&2
  exit 1
}
TATA_CONSOLE_FLUTTER_ROOT="${TATA_CONSOLE_FLUTTER_ROOT:-$CITIZENWALLET_DIR}"
[[ -d "$TATA_CONSOLE_FLUTTER_ROOT" && -f "$TATA_CONSOLE_FLUTTER_ROOT/pubspec.yaml" ]] \
  || { echo 'CitizenWallet Flutter 产品目录无效' >&2; exit 1; }
cd "$TATA_CONSOLE_FLUTTER_ROOT"
BUILD_WORK_DIR="${TATA_CONSOLE_BUILD_CACHE_DIR:-$TATA_CONSOLE_CACHE_DIR/build}"
DEPENDENCY_WORK_DIR="${TATA_CONSOLE_DEPENDENCY_CACHE_DIR:-$TATA_CONSOLE_CACHE_DIR/dependencies}"
BUILD_DIR="${TATA_CONSOLE_BUILD_DIR:-$BUILD_WORK_DIR/flutter}"
ARTIFACT_ROOT="$TATA_CONSOLE_CACHE_DIR"
export TATA_CONSOLE_BUILD_DIR="$BUILD_DIR"
export TATA_CONSOLE_NATIVE_ANDROID_DIR="$BUILD_WORK_DIR/native/android"
export TATA_CONSOLE_NATIVE_IOS_DIR="$BUILD_WORK_DIR/native/ios"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$BUILD_WORK_DIR/cargo}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$DEPENDENCY_WORK_DIR/flutter-config}"
export PUB_CACHE="${PUB_CACHE:-$DEPENDENCY_WORK_DIR/pub}"
export GRADLE_USER_HOME="$DEPENDENCY_WORK_DIR/gradle"
export CP_HOME_DIR="$DEPENDENCY_WORK_DIR/cocoapods"
export TMPDIR="${TMPDIR:-$TATA_CONSOLE_CACHE_DIR/tmp/}"
export FLUTTER_SUPPRESS_ANALYTICS=true COCOAPODS_DISABLE_STATS=true
mkdir -p "$XDG_CONFIG_HOME" "$TMPDIR"
# Flutter只接受相对产品根的build-dir配置；把中央绝对目录换算为相对路径，
# 不能写死为产品源码下的cache/build，也不能在产品根生成build。
FLUTTER_BUILD_RELATIVE="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$BUILD_DIR" "$TATA_CONSOLE_FLUTTER_ROOT")"
flutter config --build-dir="$FLUTTER_BUILD_RELATIVE" >/dev/null

# Flutter 版本及依赖配置由产品工程自行决定。

# Flutter在缓存工程生成配置和插件清单；Gradle只从公民钱包真实android根启动，
# 项目缓存、依赖缓存、编译物和临时文件继续使用当前Android任务缓存。
build_android_release() {
  local properties flutter_command flutter_sdk android_sdk product_version version_name version_code
  local flutter_version dart_defines link_target java_home
  properties="$TATA_CONSOLE_FLUTTER_ROOT/android/local.properties"
  flutter_command="$(command -v flutter)"
  while [[ -L "$flutter_command" ]]; do
    link_target="$(readlink "$flutter_command")"
    [[ "$link_target" == /* ]] || link_target="$(cd "$(dirname "$flutter_command")" && pwd -P)/$link_target"
    flutter_command="$link_target"
  done
  flutter_sdk="$(cd "$(dirname "$flutter_command")/.." && pwd -P)"
  android_sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  # JDK选择属于CitizenWallet产品流程：保留调用方选择；本机未传入时使用
  # Android Studio随包JBR。Gradle自行报告工具错误，不增加控制台前置门禁。
  java_home="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
  product_version="$(sed -n 's/^version:[[:space:]]*//p' "$TATA_CONSOLE_FLUTTER_ROOT/pubspec.yaml" | head -n 1)"
  version_name="${product_version%%+*}"
  version_code="${product_version##*+}"
  printf 'sdk.dir=%s\nflutter.sdk=%s\nflutter.buildMode=release\nflutter.versionName=%s\nflutter.versionCode=%s\n' \
    "$android_sdk" "$flutter_sdk" "$version_name" "$version_code" >"$properties"
  flutter_version="$(flutter --version --machine)"
  dart_defines="$(printf '%s' "$flutter_version" | python3 -c '
import base64, json, sys
value = json.load(sys.stdin)
fields = (
    ("FLUTTER_VERSION", "frameworkVersion"),
    ("FLUTTER_CHANNEL", "channel"),
    ("FLUTTER_GIT_URL", "repositoryUrl"),
    ("FLUTTER_FRAMEWORK_REVISION", "frameworkRevision"),
    ("FLUTTER_ENGINE_REVISION", "engineRevision"),
    ("FLUTTER_DART_VERSION", "dartSdkVersion"),
)
print(",".join(base64.b64encode(f"{name}={value[key]}".encode()).decode() for name, key in fields))
')"
  (
    cd "$CITIZENWALLET_DIR/android"
    ANDROID_HOME="$android_sdk" ANDROID_SDK_ROOT="$android_sdk" JAVA_HOME="$java_home" PATH="$java_home/bin:$PATH" \
    TATA_CONSOLE_FLUTTER_GRADLE_ROOT="$flutter_sdk/packages/flutter_tools/gradle" \
    FLUTTER_ROOT="$flutter_sdk" "$CITIZENWALLET_DIR/android/gradlew" --no-daemon --stacktrace --no-problems-report \
      --init-script "${TATA_CONSOLE_GRADLE_INIT_SCRIPT:?CitizenWallet缺少Gradle缓存初始化脚本}" \
      --project-cache-dir "$BUILD_WORK_DIR/gradle-project" \
      -Ptarget-platform=android-arm64 \
      -Ptarget=lib/main.dart \
      -Pbase-application-name=android.app.Application \
      -Pdart-defines="$dart_defines" \
      -Pdart-obfuscation=false \
      -Ptrack-widget-creation=true \
      -Ptree-shake-icons=true \
      assembleRelease
  )
}

# 仅清理本任务候选包；退出清理由控制台核对任务身份后执行，不触碰源码或另一端。
clean_platform_build_outputs() {
  case "$PLATFORM" in
    ios) rm -rf "$BUILD_DIR/ios/iphoneos/Runner.app" ;;
    android) rm -f "$BUILD_DIR/app/outputs/flutter-apk/"*.apk ;;
  esac
  mkdir -p "$BUILD_DIR"
}

retain_ios_local_artifact() {
  local app_bundle="$1" staging="$TATA_CONSOLE_CACHE_DIR/ios.app.zip" destination="$ARTIFACT_ROOT/ios.app.zip"
  rm -f "$staging"
  ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$staging"
  mkdir -p "$ARTIFACT_ROOT"
  # 同卷固定名称覆盖保证失败时不先删除上一次成功产物。
  mv -f "$staging" "$destination"
}


# 已跟踪的 pallet_registry.dart 是构建输入；本机编译不得回写共享源码索引。

echo "==> 清理 ${PLATFORM} 平台构建产物..."
clean_platform_build_outputs
echo "==> 获取依赖..."
flutter pub get
# Isar 与 QR 生成文件已经纳入仓库。本机四端编译只消费同一份源码，禁止两个平台在
# 构建过程中同时运行 build_runner 改写源文件。

# sr25519 原生签名库(schnorrkel)。签名、派生、验签全走它，缺库会在运行时才炸，
# 所以必须先于 flutter build 产出；实现来自 citizenwallet/rust/src/sr25519.rs，
# 由公民钱包独立维护。
echo "==> 编译原生签名库（${PLATFORM}）..."
# 必须用绝对路径 SCRIPT_DIR:上方已 cd 进本端中央工作根,而塔塔控制台以相对路径
# 调本脚本时 $0 是相对串,$(dirname "$0") 会拼在新 cwd 上多套一层目录。
"$SCRIPT_DIR/build-signer-native.sh" "$PLATFORM"

# Build不选择、不安装、不启动设备，只读取当前产品源码并生成中央产物。
# `--release`只是本机优化配置，不表示或触发正式Release流程。
echo "==> 编译本机优化安装包..."
if [[ "$PLATFORM" == ios ]]; then
  flutter build ios --release
  IOS_APP="$BUILD_DIR/ios/iphoneos/Runner.app"
  "$SCRIPT_DIR/build-signer-native.sh" verify-ios-package "$IOS_APP"
  retain_ios_local_artifact "$IOS_APP"
  echo ""
  echo "==> Build完成：iOS产物已写入TataConsole中央目录。"
elif [[ "$PLATFORM" == android ]]; then
  build_android_release
  ANDROID_APK="$BUILD_DIR/app/outputs/flutter-apk/app-release.apk"
  [[ -f "$ANDROID_APK" ]] || {
    echo "Android 本机无私钥 APK 不存在" >&2
    exit 1
  }
  "$SCRIPT_DIR/build-signer-native.sh" verify-android-package "$ANDROID_APK"
  # 原生安全进程只接收当前产品/平台缓存根的固定候选名；复制在产品流程
  # 完成后发生，子进程退出前写完，原生层随后再校验普通文件、包名和未签名状态。
  cp "$ANDROID_APK" "$TATA_CONSOLE_CACHE_DIR/android.apk"
  echo "==> Android无私钥候选完成，正在交给原生安全进程完成Build签名。"
fi
