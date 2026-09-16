#!/usr/bin/env bash
# 在调用方指定的源码外工作根生成本机优化安装包；本脚本不启动、不安装产品。
#
# 用法：citizenapp-run.sh <ios|android>
# 只读包检查：citizenapp-run.sh <verify-ios-localization|verify-android-localization> <产物路径>
#
# 目标平台是必填参数，不做任何自动探测：探测总要在失败时选一个回落，
# 而回落的那一端会被当成用户想编的那一端——「以为编了 iOS、实际编的 Android」
# 就是这么来的。任意调用方都必须显式传入且只能构建这一端。
#
# 调用方可提供独立缓存目录；未提供时使用系统临时目录。
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
CITIZENSDK_ROOT="$REPO_ROOT/citizensdk"
TATACHATSDK_ROOT="$(cd "$REPO_ROOT/../TATA/tatachatsdk" && pwd)"
VIEW_SCRIPT="$SCRIPT_DIR/citizenapp-view.mjs"
PLATFORM="${1:?缺少目标平台，用法：$0 <ios|android>}"
[[ "$PLATFORM" == ios || "$PLATFORM" == android \
  || "$PLATFORM" == verify-ios-localization || "$PLATFORM" == verify-android-localization ]] \
  || { echo "目标平台或检查模式不合法：$PLATFORM" >&2; exit 1; }
if [[ "$PLATFORM" == ios || "$PLATFORM" == android ]]; then
  CITIZENAPP_WORK_DIR="${CITIZENAPP_WORK_DIR:-${TMPDIR:-/tmp}/citizenapp/$PLATFORM}"
  # macOS 的 /tmp、/var 可能是系统链接；先创建再读取物理路径，使默认直接开发路径
  # 与工程视图的“规范绝对路径、无链接祖先”安全合同一致。
  mkdir -p "$CITIZENAPP_WORK_DIR"
  CITIZENAPP_WORK_DIR="$(cd "$CITIZENAPP_WORK_DIR" && pwd -P)"
  # 源码根只用于读取输入和调用原生脚本；Flutter可写状态始终进入调用方工作目录。
  [[ "$APP_ROOT" == "$REPO_ROOT/citizenapp" ]] || {
    echo "citizenapp本机Build源码身份无效：$APP_ROOT" >&2
    exit 1
  }
  if [[ -z "${CITIZENAPP_PROJECT_ROOT:-}" ]]; then
    CITIZENAPP_PROJECT_ROOT="$(node "$VIEW_SCRIPT" create \
      --source-root "$APP_ROOT" --work-root "$CITIZENAPP_WORK_DIR")"
  fi
  [[ -d "$CITIZENAPP_PROJECT_ROOT" && -f "$CITIZENAPP_PROJECT_ROOT/pubspec.yaml" ]] \
    || { echo 'CitizenApp Flutter 产品目录无效' >&2; exit 1; }
  export CITIZENAPP_PROJECT_ROOT
  cd "$CITIZENAPP_PROJECT_ROOT"
  BUILD_WORK_DIR="${CITIZENAPP_BUILD_WORK_DIR:-$CITIZENAPP_WORK_DIR/work}"
  DEPENDENCY_WORK_DIR="${CITIZENAPP_DEPENDENCY_DIR:-$CITIZENAPP_WORK_DIR/dependencies}"
  BUILD_DIR="${CITIZENAPP_BUILD_DIR:-$BUILD_WORK_DIR/flutter}"
  ARTIFACT_ROOT="${CITIZENAPP_ARTIFACT_DIR:-$CITIZENAPP_WORK_DIR}"
  python3 - "$APP_ROOT" "$CITIZENAPP_WORK_DIR" "$BUILD_WORK_DIR" "$DEPENDENCY_WORK_DIR" "$BUILD_DIR" "$ARTIFACT_ROOT" <<'CHECK_OUTPUTS'
from pathlib import Path
import sys
source = Path(sys.argv[1]).resolve()
for value in sys.argv[2:]:
    raw = Path(value)
    target = raw.resolve()
    if not raw.is_absolute() or target == source or source in target.parents:
        raise SystemExit(f'CitizenApp可写目录必须是源码外绝对路径：{value}')
CHECK_OUTPUTS
  export CITIZENAPP_BUILD_DIR="$BUILD_DIR"
  export CITIZENAPP_NATIVE_ANDROID_DIR="${CITIZENAPP_NATIVE_ANDROID_DIR:-$BUILD_WORK_DIR/native/android}"
  export CITIZENAPP_NATIVE_IOS_DIR="${CITIZENAPP_NATIVE_IOS_DIR:-$BUILD_WORK_DIR/native/ios}"
  export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$BUILD_WORK_DIR/cargo}"
  export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$DEPENDENCY_WORK_DIR/flutter-config}"
  export PUB_CACHE="${PUB_CACHE:-$DEPENDENCY_WORK_DIR/pub}"
  export GRADLE_USER_HOME="$DEPENDENCY_WORK_DIR/gradle"
  export CP_HOME_DIR="$DEPENDENCY_WORK_DIR/cocoapods"
  export TMPDIR="$CITIZENAPP_WORK_DIR/tmp/"
  export FLUTTER_SUPPRESS_ANALYTICS=true COCOAPODS_DISABLE_STATS=true
  CITIZENAPP_GRADLE_INIT_SCRIPT="${CITIZENAPP_GRADLE_INIT_SCRIPT:-$CITIZENAPP_WORK_DIR/gradle.init.gradle}"
  CITIZENAPP_FLUTTER_GRADLE_BUILD_DIR="${CITIZENAPP_FLUTTER_GRADLE_BUILD_DIR:-$BUILD_WORK_DIR/flutter-gradle-plugin}"
  export CITIZENAPP_GRADLE_INIT_SCRIPT CITIZENAPP_FLUTTER_GRADLE_BUILD_DIR
  mkdir -p "$XDG_CONFIG_HOME" "$TMPDIR" "$CITIZENAPP_FLUTTER_GRADLE_BUILD_DIR"
  printf '%s\n' \
    'gradle.beforeSettings { settings ->' \
    '    def source = System.getenv("CITIZENAPP_FLUTTER_GRADLE_ROOT")' \
    '    if (source && settings.settingsDir.canonicalPath == new File(source).canonicalPath) {' \
    '        settings.pluginManagement.repositories {' \
    '            clear()' \
    '            mavenCentral()' \
    '            google()' \
    '            gradlePluginPortal()' \
    '        }' \
    '    }' \
    '}' \
    'gradle.beforeProject { project ->' \
    '    def source = System.getenv("CITIZENAPP_FLUTTER_GRADLE_ROOT")' \
    '    def output = System.getenv("CITIZENAPP_FLUTTER_GRADLE_BUILD_DIR")' \
    '    if (source && output && project.rootDir.canonicalPath == new File(source).canonicalPath) {' \
    '        def suffix = project.path == ":" ? "root" : project.path.substring(1).replace(":", "/")' \
    '        project.layout.buildDirectory.set(new File(output, suffix))' \
    '    }' \
    '}' >"$CITIZENAPP_GRADLE_INIT_SCRIPT"
  # Flutter只接受相对产品根的build-dir配置；把源码外绝对目录换算为相对路径，
  # 不能写死为产品源码下的cache/build，也不能在产品根生成build。
  FLUTTER_BUILD_RELATIVE="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$BUILD_DIR" "$CITIZENAPP_PROJECT_ROOT")"
  flutter config --build-dir="$FLUTTER_BUILD_RELATIVE" >/dev/null
fi

# Android的SDK原生Gradle与最终App Gradle必须使用同一个产品JDK。
# 直接开发可显式传JAVA_HOME；macOS本机默认使用Android Studio自带JBR。
ANDROID_JAVA_HOME=''
ANDROID_SDK_HOME=''
if [[ "$PLATFORM" == android ]]; then
  if [[ -n "${ANDROID_HOME:-}" && -n "${ANDROID_SDK_ROOT:-}" \
    && "$ANDROID_HOME" != "$ANDROID_SDK_ROOT" ]]; then
    echo 'CitizenApp Android的ANDROID_HOME与ANDROID_SDK_ROOT必须一致' >&2
    exit 1
  fi
  ANDROID_SDK_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  ANDROID_JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
  [[ "$ANDROID_SDK_HOME" == /* && -d "$ANDROID_SDK_HOME" \
    && -d "$ANDROID_SDK_HOME/ndk/28.2.13676358" ]] \
    || { echo 'CitizenApp Android缺少带固定NDK的产品SDK目录' >&2; exit 1; }
  [[ "$ANDROID_JAVA_HOME" == /* && -x "$ANDROID_JAVA_HOME/bin/java" ]] \
    || { echo 'CitizenApp Android缺少可执行产品JDK' >&2; exit 1; }
fi

PUB_GET_ARGS=(--enforce-lockfile)
case "${CITIZENAPP_OFFLINE:-false}" in
  true) PUB_GET_ARGS+=(--offline); export CARGO_NET_OFFLINE=true ;;
  false) ;;
  *) echo 'CITIZENAPP_OFFLINE只接受true或false' >&2; exit 1 ;;
esac
gradle_network_arg=''
CITIZENAPP_GRADLE_OFFLINE="${CITIZENAPP_GRADLE_OFFLINE:-${CITIZENAPP_OFFLINE:-false}}"
case "$CITIZENAPP_GRADLE_OFFLINE" in
  true) gradle_network_arg='--offline' ;;
  false) ;;
  *) echo 'CITIZENAPP_GRADLE_OFFLINE只接受true或false' >&2; exit 1 ;;
esac

# 离线调用方必须分别提供SDK与聊天SDK的Cargo闭包；产品Build按实际所有者切换，
# 禁止把两套Cargo Home混用。普通开发者在线Build继续使用自己的标准Cargo环境。
if [[ "${CITIZENAPP_OFFLINE:-false}" == true ]]; then
  for value in "${CITIZENAPP_SDK_CARGO_HOME:-}" "${CITIZENAPP_CHAT_CARGO_HOME:-}"; do
    [[ "$value" == "$DEPENDENCY_WORK_DIR"/* && -d "$value" && ! -L "$value" \
      && -f "$value/config.toml" ]] \
      || { echo 'CitizenApp离线Build缺少独立Cargo依赖闭包' >&2; exit 1; }
  done
fi

# 仅清理本任务的候选包；不触碰源码、其它工作目录或另一端。
clean_platform_build_outputs() {
  case "$PLATFORM" in
    ios) rm -rf "$BUILD_DIR/ios/iphoneos/Runner.app" ;;
    android) rm -f "$BUILD_DIR/app/outputs/flutter-apk/"*.apk ;;
  esac
  mkdir -p "$BUILD_DIR"
}

# iOS Runner.app完成签名后只覆盖固定 `ios.app.zip`。
retain_ios_local_artifact() {
  local app_bundle="$1" staging="$CITIZENAPP_WORK_DIR/ios.app.zip" destination="$ARTIFACT_ROOT/ios.app.zip"
  rm -f "$staging"
  ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$staging"
  mkdir -p "$ARTIFACT_ROOT"
  # 同卷固定名称覆盖保证失败时不先删除上一次成功产物。
  mv -f "$staging" "$destination"
}

# Android产品Build只提交已验真的无私钥候选；签名、安装和安装后回读
# 继续由塔塔控制台原生安全进程唯一负责。
retain_android_local_artifact() {
  local apk="$1" staging="$CITIZENAPP_WORK_DIR/android.apk.pending" destination="$ARTIFACT_ROOT/android.apk"
  rm -f "$staging"
  cp "$apk" "$staging"
  chmod 600 "$staging"
  mkdir -p "$ARTIFACT_ROOT"
  # 同卷固定名称覆盖，安全进程只会看到完整普通文件。
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
    # 产品只读取公开工具链环境，不依赖启动它的桌面进程恰好继承ANDROID_HOME。
    # 与原生库构建保持同一确定性规则：显式 SDK 优先，macOS 默认
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
  properties="$CITIZENAPP_PROJECT_ROOT/android/local.properties"
  flutter_command="$(command -v flutter)"
  while [[ -L "$flutter_command" ]]; do
    link_target="$(readlink "$flutter_command")"
    [[ "$link_target" == /* ]] || link_target="$(cd "$(dirname "$flutter_command")" && pwd -P)/$link_target"
    flutter_command="$link_target"
  done
  flutter_sdk="$(cd "$(dirname "$flutter_command")/.." && pwd -P)"
  android_sdk="$ANDROID_SDK_HOME"
  # JDK与Android SDK由CitizenApp产品入口传给同一次Gradle调用；不在Worker增加前置检查。
  java_home="$ANDROID_JAVA_HOME"
  product_version="$(sed -n 's/^version:[[:space:]]*//p' "$CITIZENAPP_PROJECT_ROOT/pubspec.yaml" | head -n 1)"
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
    CITIZENAPP_FLUTTER_GRADLE_ROOT="$flutter_sdk/packages/flutter_tools/gradle" \
    FLUTTER_ROOT="$flutter_sdk" "$APP_ROOT/android/gradlew" ${gradle_network_arg:+"$gradle_network_arg"} --no-daemon --stacktrace --no-problems-report \
      --init-script "$CITIZENAPP_GRADLE_INIT_SCRIPT" \
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
# 产品脚本不终止任何既有Flutter进程；进程生命周期由当前调用方管理。

# 本机开发场景直接调用CitizenSDK唯一产品入口生成原生产物；CitizenApp只把SDK产物
# 目录交给Flutter插件，不复制、不修改也不实现第二份链库。
CITIZENSDK_DEPENDENCY_WORK_DIR="${CITIZENAPP_SDK_DEPENDENCY_WORK_DIR:-$DEPENDENCY_WORK_DIR/citizensdk-native}"
[[ "$CITIZENSDK_DEPENDENCY_WORK_DIR" == "$DEPENDENCY_WORK_DIR"/* ]] \
  || { echo 'CitizenSDK依赖目录必须属于CitizenApp依赖工作目录' >&2; exit 1; }
CITIZENSDK_PRODUCT_WORK_DIR="$BUILD_WORK_DIR/citizensdk-work"
CITIZENSDK_PRODUCT_OUTPUT_DIR="$BUILD_WORK_DIR/citizensdk-output"
rm -rf "$CITIZENSDK_PRODUCT_WORK_DIR" "$CITIZENSDK_PRODUCT_OUTPUT_DIR"
node "$CITIZENSDK_ROOT/scripts/dependencies.mjs" prepare-environment \
  --scope citizensdk --platform "$([[ "$PLATFORM" == ios ]] && printf macOS || printf Android)" \
  --work "$CITIZENSDK_DEPENDENCY_WORK_DIR"
export CITIZENSDK_ZXING_SOURCE_DIR="$CITIZENSDK_DEPENDENCY_WORK_DIR/zxing-cpp-3.1.1"
if [[ "${CITIZENAPP_OFFLINE:-false}" == true ]]; then
  export CARGO_HOME="$CITIZENAPP_SDK_CARGO_HOME"
fi
if [[ "$PLATFORM" == ios ]]; then
  CITIZENSDK_WORK_DIR="$CITIZENSDK_PRODUCT_WORK_DIR" \
    CITIZENSDK_NATIVE_OUTPUT_DIR="$CITIZENSDK_PRODUCT_OUTPUT_DIR" \
    "$CITIZENSDK_ROOT/scripts/build-native.sh" apple
  node "$VIEW_SCRIPT" project-framework \
    --source-root "$APP_ROOT" --project-root "$CITIZENAPP_PROJECT_ROOT" \
    --work-root "$CITIZENAPP_WORK_DIR" --package-root "$CITIZENSDK_ROOT" \
    --package-subpath darwin/CitizenSDK.xcframework \
    --framework "$CITIZENSDK_PRODUCT_OUTPUT_DIR/apple/CitizenSDK.xcframework" >/dev/null
else
  CITIZENSDK_WORK_DIR="$CITIZENSDK_PRODUCT_WORK_DIR" \
    CITIZENSDK_NATIVE_OUTPUT_DIR="$CITIZENSDK_PRODUCT_OUTPUT_DIR" \
    CITIZENSDK_GRADLE="$APP_ROOT/android/gradlew" \
    CITIZENSDK_OFFLINE="$CITIZENAPP_GRADLE_OFFLINE" \
    JAVA_HOME="$ANDROID_JAVA_HOME" PATH="$ANDROID_JAVA_HOME/bin:$PATH" \
    ANDROID_HOME="$ANDROID_SDK_HOME" ANDROID_SDK_ROOT="$ANDROID_SDK_HOME" \
    "$CITIZENSDK_ROOT/scripts/build-native.sh" android
  export CITIZENSDK_ANDROID_CORE_DIR="$CITIZENSDK_PRODUCT_OUTPUT_DIR/android/arm64-v8a"
fi

# TataChatSDK仍按聊天产品自有流程构建。
if [[ "${CITIZENAPP_OFFLINE:-false}" == true ]]; then
  export CARGO_HOME="$CITIZENAPP_CHAT_CARGO_HOME"
fi
if [[ "$PLATFORM" == ios ]]; then
  [[ -f "$TATACHATSDK_ROOT/ios/tatachat_sdk.podspec" ]] || {
    echo 'CitizenApp 本端 TataChatSDK iOS 插件配置缺失' >&2
    exit 1
  }
  TATACHATSDK_NATIVE_IOS_DIR="$CITIZENAPP_NATIVE_IOS_DIR" \
    TATACHATSDK_WORK_DIR="$BUILD_WORK_DIR/tatachatsdk-work" \
    "$TATACHATSDK_ROOT/scripts/build-native.sh" "$PLATFORM"
  node "$VIEW_SCRIPT" project-framework \
    --source-root "$APP_ROOT" --project-root "$CITIZENAPP_PROJECT_ROOT" \
    --work-root "$CITIZENAPP_WORK_DIR" --package-root "$TATACHATSDK_ROOT" \
    --package-subpath ios/TataChatSDK.xcframework \
    --framework "$CITIZENAPP_NATIVE_IOS_DIR/TataChatSDK.xcframework" >/dev/null
else
  TATACHATSDK_NATIVE_ANDROID_DIR="$CITIZENAPP_NATIVE_ANDROID_DIR" \
    TATACHATSDK_WORK_DIR="$BUILD_WORK_DIR/tatachatsdk-work" \
    "$TATACHATSDK_ROOT/scripts/build-native.sh" "$PLATFORM"
fi

echo "==> 清理 ${PLATFORM} 平台构建产物..."
clean_platform_build_outputs
echo "==> 按CitizenApp锁文件准备依赖..."
flutter pub get "${PUB_GET_ARGS[@]}"

# Build不选择、不安装、不启动设备，只读取当前产品源码并生成产品产物。
# `--release`只是本机优化配置，不表示或触发正式Release流程。
echo "==> 编译本机优化安装包..."
if [[ "$PLATFORM" == ios ]]; then
  flutter build ios --no-pub --release ${DART_DEFINES[@]+"${DART_DEFINES[@]}"}
  IOS_APP="$BUILD_DIR/ios/iphoneos/Runner.app"
  "$TATACHATSDK_ROOT/scripts/build-native.sh" verify-ios-package "$IOS_APP"
  verify_ios_release_localization "$IOS_APP"
  retain_ios_local_artifact "$IOS_APP"
  echo ""
  echo "==> Build完成：iOS产物已写入CitizenApp产物目录。"
elif [[ "$PLATFORM" == android ]]; then
  ANDROID_APK="$BUILD_DIR/app/outputs/flutter-apk/app-release.apk"
  build_android_release
  [[ -f "$ANDROID_APK" ]] || {
    echo "Android 本机无私钥 APK 不存在" >&2
    exit 1
  }
  "$TATACHATSDK_ROOT/scripts/build-native.sh" verify-android-package "$ANDROID_APK"
  verify_android_release_localization "$ANDROID_APK"
  retain_android_local_artifact "$ANDROID_APK"
  echo "==> Android无私钥候选完成，正在交给原生安全进程完成Build签名。"
fi
