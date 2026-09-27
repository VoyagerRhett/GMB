#!/usr/bin/env bash
# 在调用方指定的源码外工作根生成本机优化安装包；本脚本不启动、不安装产品。
#
# 用法：citizenwallet-run.sh <ios|android>
#
# 目标平台是必填参数，不做任何自动探测：探测总要在失败时选一个回落，
# 而回落的那一端会被当成用户想编的那一端。每个调用方必须明确传入目标平台。
#
# 调用方必须提供源码外 Flutter 工程根；其它工作目录未提供时使用系统临时目录。
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

CITIZENWALLET_WORK_DIR="${CITIZENWALLET_WORK_DIR:-${TMPDIR:-/tmp}/citizenwallet/$PLATFORM}"
# 源码根只读；两个端的Flutter、Pods和Gradle状态分别写入当前产品工作目录。
[[ "$CITIZENWALLET_DIR" == "$REPO_ROOT/citizenwallet" ]] || {
  echo "citizenwallet本机Build源码身份无效：$CITIZENWALLET_DIR" >&2
  exit 1
}
export CITIZENWALLET_PROJECT_ROOT="${CITIZENWALLET_PROJECT_ROOT:?必须提供源码外CitizenWallet Flutter工程根}"
[[ -d "$CITIZENWALLET_PROJECT_ROOT" && -f "$CITIZENWALLET_PROJECT_ROOT/pubspec.yaml" ]] \
  || { echo 'CitizenWallet Flutter 产品目录无效' >&2; exit 1; }
BUILD_WORK_DIR="${CITIZENWALLET_BUILD_WORK_DIR:-$CITIZENWALLET_WORK_DIR/work}"
DEPENDENCY_WORK_DIR="${CITIZENWALLET_DEPENDENCY_DIR:-$CITIZENWALLET_WORK_DIR/dependencies}"
BUILD_DIR="${CITIZENWALLET_BUILD_DIR:-$BUILD_WORK_DIR/flutter}"
ARTIFACT_ROOT="${CITIZENWALLET_ARTIFACT_DIR:-$CITIZENWALLET_WORK_DIR}"
# Pub始终向工程根写.dart_tool；build-dir不能改变这个位置。先解析真实路径，
# 拒绝工程根、.dart_tool及Kotlin持久目录链接把生成状态导回产品源码，再允许任何写入。
python3 - "$CITIZENWALLET_DIR" "$CITIZENWALLET_PROJECT_ROOT" "$CITIZENWALLET_PROJECT_ROOT/.dart_tool" "$CITIZENWALLET_WORK_DIR" "$BUILD_WORK_DIR" "$BUILD_WORK_DIR/kotlin-project" "$DEPENDENCY_WORK_DIR" "$BUILD_DIR" "$ARTIFACT_ROOT" <<'CHECK_OUTPUTS'
from pathlib import Path
import sys
source = Path(sys.argv[1]).resolve()
for value in sys.argv[2:]:
    raw = Path(value)
    target = raw.resolve()
    if not raw.is_absolute() or target == source or source in target.parents:
        raise SystemExit(f'CitizenWallet可写目录必须是源码外绝对路径：{value}')
CHECK_OUTPUTS
# CocoaPods 会改写工程锁文件；先确认工程与工作目录均在源码外，再把
# 指向源码的锁文件链接原子替换为工程普通文件，禁止本机 Build 回写源码。
if [[ "$PLATFORM" == ios ]]; then
  python3 - "$CITIZENWALLET_DIR/ios/Podfile.lock" "$CITIZENWALLET_PROJECT_ROOT/ios/Podfile.lock" <<'DETACH_IOS_LOCK'
from pathlib import Path
import os
import tempfile
import sys

source = Path(sys.argv[1]).resolve(strict=True)
project_lock = Path(sys.argv[2])
if project_lock.is_symlink():
    if project_lock.resolve(strict=True) != source:
        raise SystemExit('CitizenWallet iOS工程锁文件链接目标不是本产品源码')
    fd, temporary = tempfile.mkstemp(prefix='Podfile.lock.', dir=project_lock.parent)
    try:
        with os.fdopen(fd, 'wb') as output:
            output.write(source.read_bytes())
        os.replace(temporary, project_lock)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
DETACH_IOS_LOCK
fi
cd "$CITIZENWALLET_PROJECT_ROOT"
export CITIZENWALLET_BUILD_DIR="$BUILD_DIR"
export CITIZENWALLET_NATIVE_ANDROID_DIR="${CITIZENWALLET_NATIVE_ANDROID_DIR:-$BUILD_WORK_DIR/native/android}"
export CITIZENWALLET_NATIVE_IOS_DIR="${CITIZENWALLET_NATIVE_IOS_DIR:-$BUILD_WORK_DIR/native/ios}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$BUILD_WORK_DIR/cargo}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$DEPENDENCY_WORK_DIR/flutter-config}"
export PUB_CACHE="${PUB_CACHE:-$DEPENDENCY_WORK_DIR/pub}"
export GRADLE_USER_HOME="$DEPENDENCY_WORK_DIR/gradle"
export CP_HOME_DIR="$DEPENDENCY_WORK_DIR/cocoapods"
export TMPDIR="$CITIZENWALLET_WORK_DIR/tmp/"
export FLUTTER_SUPPRESS_ANALYTICS=true COCOAPODS_DISABLE_STATS=true
export CITIZENWALLET_GRADLE_INIT_SCRIPT="${CITIZENWALLET_GRADLE_INIT_SCRIPT:-$CITIZENWALLET_WORK_DIR/gradle.init.gradle}"
export CITIZENWALLET_FLUTTER_GRADLE_BUILD_DIR="${CITIZENWALLET_FLUTTER_GRADLE_BUILD_DIR:-$BUILD_WORK_DIR/flutter-gradle-plugin}"
mkdir -p "$XDG_CONFIG_HOME" "$TMPDIR" "$CITIZENWALLET_FLUTTER_GRADLE_BUILD_DIR"
# Flutter Gradle 插件原件只读；其 Kotlin 会话与编译状态必须写入本轮工作目录。
printf '%s\n' \
  'gradle.beforeProject { project ->' \
  '    def source = System.getenv("CITIZENWALLET_FLUTTER_GRADLE_ROOT")' \
  '    def output = System.getenv("CITIZENWALLET_FLUTTER_GRADLE_BUILD_DIR")' \
  '    if (source && output && project.rootDir.canonicalPath == new File(source).canonicalPath) {' \
  '        def suffix = project.path == ":" ? "root" : project.path.substring(1).replace(":", "/")' \
  '        project.layout.buildDirectory.set(new File(output, suffix))' \
  '        project.extensions.extraProperties.set("kotlin.project.persistent.dir", new File(output, suffix + "/kotlin-project").path)' \
  '    }' \
  '}' >"$CITIZENWALLET_GRADLE_INIT_SCRIPT"
# Flutter只接受相对产品根的build-dir配置；把源码外绝对目录换算为相对路径，
# 不能写死为产品源码下的cache/build，也不能在产品根生成build。
FLUTTER_BUILD_RELATIVE="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$BUILD_DIR" "$CITIZENWALLET_PROJECT_ROOT")"
flutter config --build-dir="$FLUTTER_BUILD_RELATIVE" >/dev/null

PUB_GET_ARGS=(--enforce-lockfile)
GRADLE_ARGS=(--no-daemon)
case "${CITIZENWALLET_PUB_OFFLINE:-false}" in
  true|false) ;;
  *) echo 'CITIZENWALLET_PUB_OFFLINE只接受true或false' >&2; exit 1 ;;
esac
PUB_OFFLINE="${CITIZENWALLET_PUB_OFFLINE:-false}"
case "${CITIZENWALLET_OFFLINE:-false}" in
  true) PUB_OFFLINE=true; GRADLE_ARGS+=(--offline); export CARGO_NET_OFFLINE=true ;;
  false) ;;
  *) echo 'CITIZENWALLET_OFFLINE只接受true或false' >&2; exit 1 ;;
esac
# 任务级Pub预装只约束Pub；原整体离线开关仍同时约束Pub、Gradle和Cargo。
if [[ "$PUB_OFFLINE" == true ]]; then PUB_GET_ARGS+=(--offline); fi

# Flutter 版本及依赖配置由产品工程自行决定。

# Flutter在缓存工程生成配置和插件清单；Gradle只从公民钱包真实android根启动，
# 项目缓存、依赖缓存、编译物和临时文件继续使用当前Android任务缓存。
# Kotlin持久状态不受--project-cache-dir控制，必须另传官方工程属性避免源码生成.kotlin。
build_android_release() {
  local properties flutter_command flutter_sdk android_sdk product_version version_name version_code gradle_bin
  local flutter_version dart_defines link_target java_home expected_gradle_version actual_gradle_version
  gradle_bin="${CITIZENWALLET_GRADLE_BIN:?Android Build必须提供绝对Gradle工具路径}"
  [[ "$gradle_bin" == /* && -f "$gradle_bin" && -x "$gradle_bin" ]] \
    || { echo "Android Gradle工具无效：$gradle_bin" >&2; return 1; }
  properties="$CITIZENWALLET_PROJECT_ROOT/android/local.properties"
  flutter_command="$(command -v flutter)"
  while [[ -L "$flutter_command" ]]; do
    link_target="$(readlink "$flutter_command")"
    [[ "$link_target" == /* ]] || link_target="$(cd "$(dirname "$flutter_command")" && pwd -P)/$link_target"
    flutter_command="$link_target"
  done
  flutter_sdk="$(cd "$(dirname "$flutter_command")/.." && pwd -P)"
  android_sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  # JDK选择属于CitizenWallet产品流程：保留调用方选择；本机未传入时使用
  # Android Studio随包JBR。Gradle自行报告工具错误，不增加外部前置门禁。
  java_home="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
  # Wrapper属性仍是产品的Gradle版本真源；调用方给出的工具必须与它完全一致。
  expected_gradle_version="$(sed -nE 's@^distributionUrl=.*gradle-([0-9][0-9.]*)-bin\.zip$@\1@p' \
    "$CITIZENWALLET_DIR/android/gradle/wrapper/gradle-wrapper.properties")"
  [[ -n "$expected_gradle_version" ]] || { echo 'Android Gradle版本声明无效' >&2; return 1; }
  actual_gradle_version="$(JAVA_HOME="$java_home" "$gradle_bin" --version | sed -n 's/^Gradle //p' | head -n 1)"
  [[ "$actual_gradle_version" == "$expected_gradle_version" ]] \
    || { echo 'Android Gradle工具版本与钱包锁定版本不一致' >&2; return 1; }
  product_version="$(sed -n 's/^version:[[:space:]]*//p' "$CITIZENWALLET_PROJECT_ROOT/pubspec.yaml" | head -n 1)"
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
    # 调用方提供同一已验真 Gradle 工具，任务目录只承载依赖和编译状态，不再下载工具分发包。
    ANDROID_HOME="$android_sdk" ANDROID_SDK_ROOT="$android_sdk" JAVA_HOME="$java_home" PATH="$java_home/bin:$PATH" \
    CITIZENWALLET_FLUTTER_GRADLE_ROOT="$flutter_sdk/packages/flutter_tools/gradle" \
    FLUTTER_ROOT="$flutter_sdk" "$gradle_bin" "${GRADLE_ARGS[@]}" --stacktrace --no-problems-report \
      --init-script "$CITIZENWALLET_GRADLE_INIT_SCRIPT" \
      --project-cache-dir "$BUILD_WORK_DIR/gradle-project" \
      -Pkotlin.project.persistent.dir="$BUILD_WORK_DIR/kotlin-project" \
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

# 仅清理当前工作目录中的候选包，不触碰源码或另一端。
clean_platform_build_outputs() {
  case "$PLATFORM" in
    ios) rm -rf "$BUILD_DIR/ios/iphoneos/Runner.app" ;;
    android) rm -f "$BUILD_DIR/app/outputs/flutter-apk/"*.apk ;;
  esac
  mkdir -p "$BUILD_DIR"
}

retain_ios_local_artifact() {
  local app_bundle="$1" staging="$CITIZENWALLET_WORK_DIR/ios.app.zip" destination="$ARTIFACT_ROOT/ios.app.zip"
  rm -f "$staging"
  ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$staging"
  mkdir -p "$ARTIFACT_ROOT"
  # 同卷固定名称覆盖保证失败时不先删除上一次成功产物。
  mv -f "$staging" "$destination"
}

# 仅选择 Xcode 报告的一台可用 iOS 真机；不在无设备或多设备时回落模拟器。
run_ios_ui_tests() {
  local xcodebuild_bin destinations device_id
  xcodebuild_bin="${CITIZENWALLET_XCODEBUILD_BIN:?iOS Build必须提供绝对Xcode工具路径}"
  [[ "$xcodebuild_bin" == /* && -f "$xcodebuild_bin" && -x "$xcodebuild_bin" ]] \
    || { echo 'iOS Xcode工具无效' >&2; return 1; }
  destinations="$("$xcodebuild_bin" -workspace "$CITIZENWALLET_PROJECT_ROOT/ios/Runner.xcworkspace" \
    -scheme Runner -configuration Release -showdestinations)"
  device_id="$(printf '%s\n' "$destinations" | python3 -c '
import re, sys
available = sys.stdin.read().split("Ineligible destinations", 1)[0]
ids = re.findall(r"\{\s*platform:iOS,\s*arch:arm64,\s*id:([0-9A-Fa-f-]+),", available)
if len(ids) != 1 or not re.fullmatch(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f-]{16,}", ids[0]):
    raise SystemExit("iOS UI测试需要唯一可用真机")
print(ids[0])
')"
  # 测试计划关闭自动屏幕采集，避免触发钱包既有录屏保护；Release 测试应用与编译物均留在调用方工作根。
  "$xcodebuild_bin" test \
    -workspace "$CITIZENWALLET_PROJECT_ROOT/ios/Runner.xcworkspace" \
    -scheme Runner -configuration Release \
    -destination "platform=iOS,id=$device_id" \
    -only-testing:RunnerUITests -parallel-testing-enabled NO \
    -collect-test-diagnostics never \
    -derivedDataPath "$BUILD_WORK_DIR/xcode-ui" \
    -resultBundlePath "$BUILD_WORK_DIR/ios-ui-tests.xcresult"
}


# 已跟踪的 pallet_registry.dart 是构建输入；本机编译不得回写共享源码索引。

echo "==> 清理 ${PLATFORM} 平台构建产物..."
clean_platform_build_outputs
echo "==> 获取依赖..."
flutter pub get "${PUB_GET_ARGS[@]}"
# 已登记 Node 在当前任务目录运行钱包自身的构建合同测试；失败同样阻止平台编译。
node_bin="${CITIZENWALLET_NODE_BIN:?本机Build必须提供绝对Node工具路径}"
[[ "$node_bin" == /* && -f "$node_bin" && -x "$node_bin" ]] \
  || { echo '本机Build的Node工具无效' >&2; exit 1; }
"$node_bin" --test "$CITIZENWALLET_DIR/test/release_manifest.test.mjs"
# 本机钱包 Build 与 CI 使用同一套单元和组件测试。先在本轮源码外 Cargo 目录
# 编译宿主 FFI 动态库，再运行 Flutter 测试；测试失败立即阻止后续平台编译与安装。
echo "==> 编译宿主签名库并运行钱包测试..."
"$SCRIPT_DIR/build-signer-native.sh" host
flutter test --no-pub
# Isar 与 QR 生成文件已经纳入仓库。本机四端编译只消费同一份源码，禁止两个平台在
# 构建过程中同时运行 build_runner 改写源文件。

# sr25519 原生签名库(schnorrkel)。签名、派生、验签全走它，缺库会在运行时才炸，
# 所以必须先于 flutter build 产出；实现来自 citizenwallet/rust/src/sr25519.rs，
# 由公民钱包独立维护。
echo "==> 编译原生签名库（${PLATFORM}）..."
# 必须用绝对路径SCRIPT_DIR：上方已经切换工作目录，相对$0不能稳定定位脚本。
"$SCRIPT_DIR/build-signer-native.sh" "$PLATFORM"

# Build不选择、不安装、不启动设备，只读取当前产品源码并生成产品产物。
# `--release`只是本机优化配置，不表示或触发正式Release流程。
echo "==> 编译本机优化安装包..."
if [[ "$PLATFORM" == ios ]]; then
  flutter build ios --release
  echo "==> 在唯一真机运行 Release UI 测试..."
  run_ios_ui_tests
  IOS_APP="$BUILD_DIR/ios/iphoneos/Runner.app"
  "$SCRIPT_DIR/build-signer-native.sh" verify-ios-package "$IOS_APP"
  retain_ios_local_artifact "$IOS_APP"
  echo ""
  echo "==> Build完成：iOS产物已写入CitizenWallet产物目录。"
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
  mkdir -p "$ARTIFACT_ROOT"
  cp "$ANDROID_APK" "$ARTIFACT_ROOT/android.apk"
  echo "==> Android无私钥候选完成，正在交给原生安全进程完成Build签名。"
fi
