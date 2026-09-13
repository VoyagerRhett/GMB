#!/usr/bin/env bash
# 在本端中央工作根生成本机优化安装包；本脚本不启动、不安装产品。
#
# 用法：citizenapp-run.sh <ios|android>
# 只读包检查：citizenapp-run.sh <verify-ios-localization|verify-android-localization> <产物路径>
#
# 目标平台是必填参数，不做任何自动探测：探测总要在失败时选一个回落，
# 而回落的那一端会被当成用户想编的那一端——「以为编了 iOS、实际编的 Android」
# 就是这么来的。塔塔控制台的「编译iOS端 / 编译Android端」两个按钮各自传死这个参数。
#
# 调用方可提供独立缓存目录；没有 TataConsole 时使用系统临时目录。
# 公民链轻节点、交易和链存储全部由 CitizenSDK Flutter plugin 提供。
set -euo pipefail
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
  LINK_TARGET="$(readlink "$SCRIPT_PATH")"
  [[ "$LINK_TARGET" == /* ]] || LINK_TARGET="$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P)/$LINK_TARGET"
  SCRIPT_PATH="$LINK_TARGET"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P)"
# 消解 scripts/..，确保直接产品源码身份使用唯一真实路径。
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TATACHATSDK_ROOT="$(cd "$REPO_ROOT/../TATA/tatachatsdk" && pwd)"
PLATFORM="${1:?缺少目标平台，用法：$0 <ios|android>}"
[[ "$PLATFORM" == ios || "$PLATFORM" == android \
  || "$PLATFORM" == verify-ios-localization || "$PLATFORM" == verify-android-localization ]] \
  || { echo "目标平台或检查模式不合法：$PLATFORM" >&2; exit 1; }
if [[ "$PLATFORM" == ios || "$PLATFORM" == android ]]; then
  TATA_CONSOLE_CACHE_DIR="${TATA_CONSOLE_CACHE_DIR:-${TMPDIR:-/tmp}/citizenapp-$PLATFORM}"
  # 源码根只用于读取输入和调用原生脚本；Flutter 的所有可写配置由控制台在本端生成。
  [[ "$APP_ROOT" == "$REPO_ROOT/citizenapp" ]] || {
    echo "citizenapp本机Build源码身份无效：$APP_ROOT" >&2
    exit 1
  }
  TATA_CONSOLE_FLUTTER_ROOT="${TATA_CONSOLE_FLUTTER_ROOT:-$APP_ROOT}"
  [[ -d "$TATA_CONSOLE_FLUTTER_ROOT" && -f "$TATA_CONSOLE_FLUTTER_ROOT/pubspec.yaml" ]] \
    || { echo 'CitizenApp Flutter 产品目录无效' >&2; exit 1; }
  cd "$TATA_CONSOLE_FLUTTER_ROOT"
  BUILD_WORK_DIR="${TATA_CONSOLE_BUILD_CACHE_DIR:-$TATA_CONSOLE_CACHE_DIR/work}"
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
fi

# 仅清理本任务的候选包；退出清理由控制台核对任务身份后执行，不触碰源码或另一端。
clean_platform_build_outputs() {
  case "$PLATFORM" in
    ios) rm -rf "$BUILD_DIR/ios/iphoneos/Runner.app" ;;
    android) rm -f "$BUILD_DIR/app/outputs/flutter-apk/"*.apk ;;
  esac
  mkdir -p "$BUILD_DIR"
}

# iOS Runner.app完成签名后只覆盖固定 `ios.app.zip`。
retain_ios_local_artifact() {
  local app_bundle="$1" staging="$TATA_CONSOLE_CACHE_DIR/ios.app.zip" destination="$ARTIFACT_ROOT/ios.app.zip"
  rm -f "$staging"
  ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$staging"
  mkdir -p "$ARTIFACT_ROOT"
  # 同卷固定名称覆盖保证失败时不先删除上一次成功产物。
  mv -f "$staging" "$destination"
}

# 系统权限弹窗由操作系统渲染；App 唯一能提供的是最终包内的受支持语言和本地化产品名。
# 只检查源码会漏掉 Xcode variant group 未入 Resources 等问题，Build必须回读最终包。
verify_ios_release_localization() {
  local app_bundle="$1" info="$1/Info.plist"
  local zh_strings="$1/zh-Hans.lproj/InfoPlist.strings"
  local en_strings="$1/en.lproj/InfoPlist.strings"
  [[ -f "$info" && -f "$zh_strings" && -f "$en_strings" ]] || {
    echo "iOS Release 缺少 Info.plist 或中英文本地化资源：$app_bundle" >&2
    return 1
  }
  [[ "$(plutil -extract CFBundleDevelopmentRegion raw -o - "$info")" == zh-Hans ]] || {
    echo 'iOS Release 默认回落语言必须是 zh-Hans' >&2
    return 1
  }
  plutil -extract CFBundleLocalizations json -o - "$info" | python3 -c '
import json, sys
if json.load(sys.stdin) != ["zh-Hans", "en"]:
    raise SystemExit("iOS Release 支持语言必须严格为 zh-Hans、en")
'
  [[ "$(plutil -extract CFBundleDisplayName raw -o - "$zh_strings")" == 公民 \
    && "$(plutil -extract CFBundleName raw -o - "$zh_strings")" == 公民 ]] || {
    echo 'iOS Release 中文产品名必须是“公民”' >&2
    return 1
  }
  [[ "$(plutil -extract CFBundleDisplayName raw -o - "$en_strings")" == CitizenApp \
    && "$(plutil -extract CFBundleName raw -o - "$en_strings")" == CitizenApp ]] || {
    echo 'iOS Release 英文产品名必须是 CitizenApp' >&2
    return 1
  }
  echo '    iOS Release 本地化通过：中文=公民，英文=CitizenApp，默认回落=zh-Hans'
}

# Android 权限正文由系统按手机语言渲染；这里锁定最终 APK 的默认中文和英文限定应用名。
verify_android_release_localization() {
  local apk="$1" aapt_bin sdk_home
  [[ -f "$apk" ]] || { echo "Android Release APK 不存在：$apk" >&2; return 1; }
  aapt_bin="$(command -v aapt2 || true)"
  if [[ -z "$aapt_bin" ]]; then
    # TataConsole 只向子进程传公开工具链环境，不依赖启动它的桌面进程恰好继承
    # ANDROID_HOME。与原生库构建保持同一确定性规则：显式 SDK 优先，macOS 默认
    # SDK 目录兜底，再从已安装 build-tools 中选择最高版本，禁止硬编码具体版本。
    sdk_home="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
    aapt_bin="$(find "$sdk_home/build-tools" -type f -name aapt2 -print 2>/dev/null | sort -V | tail -n 1)"
  fi
  [[ -x "$aapt_bin" ]] || { echo '找不到 Android SDK aapt2，无法核验 APK 本地化' >&2; return 1; }
  "$aapt_bin" dump resources "$apk" | python3 -c '
import re, sys
text = sys.stdin.read()
match = re.search(r"resource 0x[0-9a-f]+ string/app_name\n(?P<body>(?:      .*\n)+?)    resource ", text)
if match is None:
    raise SystemExit("Android Release APK 缺少 string/app_name")
body = match.group("body")
if "() \"公民\"" not in body or "(en) \"CitizenApp\"" not in body:
    raise SystemExit("Android Release APK 的默认中文或英文应用名不正确")
'
  echo '    Android Release 本地化通过：默认=公民，英文=CitizenApp'
}

if [[ "$PLATFORM" == verify-ios-localization ]]; then
  verify_ios_release_localization "${2:?缺少 Runner.app 路径}"
  exit 0
fi
if [[ "$PLATFORM" == verify-android-localization ]]; then
  verify_android_release_localization "${2:?缺少 APK 路径}"
  exit 0
fi


# 构造 dart-define 参数
DART_DEFINES=()
echo "[Build模式] CitizenSDK · 目标平台 $PLATFORM"

# Flutter只负责在当前缓存根生成产品自己的Android配置和插件清单；真正的Gradle
# 从产品真实android目录启动，所有可写状态仍由既有环境变量指向本任务缓存。
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
  # JDK与Android SDK由CitizenApp产品入口传给同一次Gradle调用；不在Worker增加前置检查。
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
    cd "$APP_ROOT/android"
    ANDROID_HOME="$android_sdk" ANDROID_SDK_ROOT="$android_sdk" JAVA_HOME="$java_home" PATH="$java_home/bin:$PATH" \
    TATA_CONSOLE_FLUTTER_GRADLE_ROOT="$flutter_sdk/packages/flutter_tools/gradle" \
    FLUTTER_ROOT="$flutter_sdk" "$APP_ROOT/android/gradlew" --offline --no-daemon --stacktrace --no-problems-report \
      --init-script "${TATA_CONSOLE_GRADLE_INIT_SCRIPT:?CitizenApp缺少Gradle缓存初始化脚本}" \
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

# 这里曾有一句 `pkill -9 -f flutter_tools.snapshot`，用途是清掉上一轮残留的 flutter。
# 已删除：`-f` 匹配全命令行，而 `flutter_tools.snapshot` 是每一个 flutter 命令的实际执行体，
# 那一枪不区分产品、不区分平台、也不区分是不是本次运行的——公民钱包正在跑的编译、
# 乃至你自己在终端里手敲的 flutter，都会一起被 SIGKILL（现象是 `Killed: 9`）。
# 它要解决的残留问题已经由塔塔控制台承接：所有动作子进程都在独立进程组里启动，
# 「停止」与塔塔控制台退出都按进程组终止整棵进程树，不会再留下脱缰的 flutter。

# CitizenSDK 原生产物只由其 Flutter plugin/产品流程管理；CitizenApp 不编译、
# 复制或验收第二份链库。TataChatSDK 仍按聊天产品自有流程构建。
if [[ "$PLATFORM" == ios ]]; then
  # CocoaPods 插件根也属于本任务，不再把原生产物链接写进共享 SDK 源码。
  TATACHATSDK_PACKAGE_IOS_DIR="$TATA_CONSOLE_FLUTTER_ROOT/../../TATA/tatachatsdk/ios"
  [[ -f "$TATACHATSDK_PACKAGE_IOS_DIR/tatachat_sdk.podspec" ]] || {
    echo 'CitizenApp 本端 TataChatSDK iOS 插件配置缺失' >&2
    exit 1
  }
  TATACHATSDK_PACKAGE_IOS_DIR="$TATACHATSDK_PACKAGE_IOS_DIR" \
    "$TATACHATSDK_ROOT/scripts/build-native.sh" "$PLATFORM"
else
  "$TATACHATSDK_ROOT/scripts/build-native.sh" "$PLATFORM"
fi

echo "==> 清理 ${PLATFORM} 平台构建产物..."
clean_platform_build_outputs
echo "==> 使用塔塔依赖库已物化的离线依赖..."
flutter pub get --offline --enforce-lockfile

# Build不选择、不安装、不启动设备，只读取当前产品源码并生成中央产物。
# `--release`只是本机优化配置，不表示或触发正式Release流程。
echo "==> 编译本机优化安装包..."
if [[ "$PLATFORM" == ios ]]; then
  flutter build ios --no-pub --release ${DART_DEFINES[@]+"${DART_DEFINES[@]}"}
  IOS_APP="$BUILD_DIR/ios/iphoneos/Runner.app"
  "$TATACHATSDK_ROOT/scripts/build-native.sh" verify-ios-package "$IOS_APP"
  verify_ios_release_localization "$IOS_APP"
  retain_ios_local_artifact "$IOS_APP"
  echo ""
  echo "==> Build完成：iOS产物已写入TataConsole中央目录。"
elif [[ "$PLATFORM" == android ]]; then
  ANDROID_APK="$BUILD_DIR/app/outputs/flutter-apk/app-release.apk"
  build_android_release
  [[ -f "$ANDROID_APK" ]] || {
    echo "Android 本机无私钥 APK 不存在" >&2
    exit 1
  }
  "$TATACHATSDK_ROOT/scripts/build-native.sh" verify-android-package "$ANDROID_APK"
  verify_android_release_localization "$ANDROID_APK"
  echo "==> Android无私钥候选完成，正在交给原生安全进程完成Build签名。"
fi
