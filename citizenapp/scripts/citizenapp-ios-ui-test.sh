#!/usr/bin/env bash
# 对真机中已经安装的 CitizenApp Release 做长期黑盒 UI 验收。
#
# 安全边界：本脚本只构建和安装独立的 UITestHost/xctrunner，永远不构建、安装、卸载或
# 清空 `ios.citizenapp`。测试前后会核对正式 App 的版本、bundle 容器、数据容器和 Isar
# 数据库；任一项消失或变化都拒绝把测试判为成功。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEME="RunnerUITests"
TARGET_BUNDLE_ID="ios.citizenapp"
TEST_HOST_BUNDLE_ID="ios.citizenapp.UITestHost"
TEST_RUNNER_BUNDLE_ID="ios.citizenapp.UITests.xctrunner"
: "${TATA_CONSOLE_TARGET_ROOT:?UI检查必须由控制台提供中央产物根}"
: "${TATA_CONSOLE_CACHE_DIR:?UI检查必须由控制台提供当前iOS任务目录}"
: "${TATA_CONSOLE_FLUTTER_ROOT:?UI检查必须使用本端独立工程配置}"
BUILD_ROOT="$TATA_CONSOLE_CACHE_DIR"
PROJECT="$TATA_CONSOLE_FLUTTER_ROOT/ios/Runner.xcodeproj"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
RESULT_BUNDLE="$BUILD_ROOT/RunnerUITests.xcresult"

[[ "$BUILD_ROOT" == "${TATA_CONSOLE_TARGET_ROOT%/target}/cache/gmb/citizenapp/ios" \
  && "$TATA_CONSOLE_FLUTTER_ROOT" == "$BUILD_ROOT" \
  && -f "$PROJECT/project.pbxproj" && ! -L "$PROJECT/project.pbxproj" ]] || {
  echo "UI 测试缺少准确iOS任务配置：$BUILD_ROOT" >&2
  exit 1
}
# 不清空平台目录；只有当前控制台持有的 iOS 任务可以复用其配置执行检查。
python3 - "$BUILD_ROOT" <<'PY'
import json, os, pathlib, sys
root = pathlib.Path(sys.argv[1])
lock = root / '.owner'
if str(root.resolve()) != str(root) or lock.is_symlink() or not lock.is_file():
    raise SystemExit('CitizenApp UI检查缺少本端任务所有权')
owner = json.loads(lock.read_text())
if owner.get('canonicalId') != 'gmb.citizenapp.ios.build' or not owner.get('runId') or not isinstance(owner.get('pid'), int) or owner['pid'] <= 0:
    raise SystemExit('CitizenApp UI检查任务身份不匹配')
if os.environ.get('TATA_CONSOLE_RUN_ID') != owner['runId']:
    raise SystemExit('CitizenApp UI检查运行任务不匹配')
os.kill(owner['pid'], 0)
PY
export TMPDIR="$BUILD_ROOT/"

device_json="$(xcrun devicectl list devices --quiet --json-output -)"
device_fields="$(python3 -c '
import json, sys
devices = json.load(sys.stdin).get("result", {}).get("devices", [])
online = []
for item in devices:
    props = item.get("properties", {})
    if props.get("hardware", {}).get("platform") != "iOS":
        continue
    if props.get("connection", {}).get("state") != "connected":
        continue
    online.append(item)
if len(online) != 1:
    names = [item.get("properties", {}).get("state", {}).get("name", "未知 iPhone") for item in online]
    joined_names = ", ".join(names) or "无"
    raise SystemExit(f"必须且只能连接一台可用 iPhone，当前：{len(online)}（{joined_names}）")
item = online[0]
props = item["properties"]
print(item["identifier"])
print(props["hardware"]["udid"])
print(props.get("state", {}).get("name", "iPhone"))
' <<<"$device_json")"
CORE_DEVICE_ID="$(sed -n '1p' <<<"$device_fields")"
HARDWARE_UDID="$(sed -n '2p' <<<"$device_fields")"
DEVICE_NAME="$(sed -n '3p' <<<"$device_fields")"
[[ -n "$CORE_DEVICE_ID" && -n "$HARDWARE_UDID" ]] || {
  echo "无法解析 iPhone 标识，拒绝测试" >&2
  exit 1
}

installed_app_snapshot() {
  xcrun devicectl device info apps --quiet \
    --device "$CORE_DEVICE_ID" \
    --bundle-id "$TARGET_BUNDLE_ID" \
    --include-container-paths \
    --json-output - |
    python3 -c '
import json, sys
bundle_id = sys.argv[1]
apps = json.load(sys.stdin).get("result", {}).get("apps", [])
if len(apps) != 1:
    raise SystemExit(f"设备中必须且只能有一个 {bundle_id}，当前：{len(apps)}")
app = apps[0]
if app.get("bundleIdentifier") != bundle_id:
    raise SystemExit("设备返回的 CitizenApp Bundle ID 不一致")
fields = {
    "bundleIdentifier": app.get("bundleIdentifier"),
    "version": app.get("version"),
    "shortVersion": app.get("shortVersion"),
    "bundleContainerPath": app.get("bundleContainerPath"),
    "dataContainerPath": app.get("dataContainerPath"),
}
if not fields["bundleContainerPath"] or not fields["dataContainerPath"]:
    raise SystemExit("无法读取 CitizenApp 的 bundle/data 容器，拒绝测试")
print(json.dumps(fields, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
' "$TARGET_BUNDLE_ID"
}

database_size() {
  xcrun devicectl device info files --quiet \
    --device "$CORE_DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$TARGET_BUNDLE_ID" \
    --subdirectory 'Library/Application Support' \
    --recurse \
    --json-output - |
    python3 -c '
import json, sys
files = json.load(sys.stdin).get("result", {}).get("files", [])
matches = [item for item in files if item.get("name") == "citizenapp.isar"]
if len(matches) != 1:
    raise SystemExit(f"CitizenApp Isar 数据库必须且只能有一个，当前：{len(matches)}")
size = matches[0].get("metadata", {}).get("size", 0)
if not isinstance(size, int) or size <= 0:
    raise SystemExit("CitizenApp Isar 数据库大小无效")
print(size)
'
}

is_installed() {
  xcrun devicectl device info apps --quiet \
    --device "$CORE_DEVICE_ID" --bundle-id "$1" --json-output - 2>/dev/null |
    python3 -c 'import json, sys; print("yes" if json.load(sys.stdin).get("result", {}).get("apps", []) else "no")' \
    2>/dev/null
}

cleanup_test_apps() {
  local bundle_id
  for bundle_id in "$TEST_RUNNER_BUNDLE_ID" "$TEST_HOST_BUNDLE_ID"; do
    if [[ "$(is_installed "$bundle_id" || true)" == yes ]]; then
      echo "[清理] 仅删除隔离测试组件：$bundle_id"
      xcrun devicectl device uninstall app --quiet --device "$CORE_DEVICE_ID" "$bundle_id" || true
    fi
  done
  # 仅卸载本脚本的设备测试组件；中央内容由控制台确认任务结束后统一清理。
}
trap cleanup_test_apps EXIT

echo "[设备] $DEVICE_NAME · $HARDWARE_UDID"
before_snapshot="$(installed_app_snapshot)"
before_database_size="$(database_size)"
echo "[保护] 已确认现有 ${TARGET_BUNDLE_ID}，Isar=${before_database_size} 字节"

# iPhone 镜像与 XCTest 都要独占设备图形会话；自动测试期间只关闭镜像窗口，不改变配对。
osascript -e 'tell application "iPhone Mirroring" to quit' >/dev/null 2>&1 || true

destination="platform=iOS,id=$HARDWARE_UDID"
echo "[构建] Release 隔离 UI Test Host（不含 CitizenApp target）"
xcodebuild build-for-testing \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "$destination" \
  -derivedDataPath "$DERIVED_DATA"

# 构建后、执行前审计所有 App 产物。只要混入正式 Bundle ID，就在任何安装发生前停止。
while IFS= read -r plist; do
  product_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
  [[ "$product_bundle_id" != "$TARGET_BUNDLE_ID" ]] || {
    echo "UI 测试产物错误包含正式 CitizenApp，已在安装前停止：$plist" >&2
    exit 1
  }
done < <(find "$DERIVED_DATA/Build/Products" -path '*.app/Info.plist' -type f -print)

echo "[测试] 启动设备中现有 CitizenApp Release"
set +e
xcodebuild test-without-building \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "$destination" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE"
test_status=$?
set -e

after_snapshot="$(installed_app_snapshot)"
after_database_size="$(database_size)"
[[ "$after_snapshot" == "$before_snapshot" ]] || {
  echo "CitizenApp 安装信息或数据容器在 UI 测试后发生变化，拒绝通过" >&2
  exit 1
}
echo "[保护] CitizenApp 容器未变化，Isar 仍存在：${before_database_size} → ${after_database_size} 字节"

if [[ "$test_status" -ne 0 ]]; then
  echo "UI 测试失败；结果保存在：$RESULT_BUNDLE" >&2
  exit "$test_status"
fi
echo "[完成] CitizenApp iOS Release 真机 UI 测试通过"
