#!/usr/bin/env bash
# 对真机中已经安装的 CitizenApp Release 做长期黑盒 UI 验收。
#
# 安全边界：本脚本只构建和安装独立的 UITestHost/xctrunner，永远不构建、安装、卸载或
# 清空 `ios.citizenapp`。测试前后会核对正式 App 的版本、bundle 容器、数据容器和全部 Isar
# 数据库；既有数据库任一消失都拒绝把测试判为成功，正常运行新增数据库或扩大文件允许。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEME="RunnerUITests"
TARGET_BUNDLE_ID="ios.citizenapp"
TEST_HOST_BUNDLE_ID="ios.citizenapp.UITestHost"
TEST_RUNNER_BUNDLE_ID="ios.citizenapp.UITests.xctrunner"
BUILD_ROOT="${CITIZENAPP_UI_TEST_WORK_DIR:-${TMPDIR:-/tmp}/citizenapp/ios-ui-test}"
PROJECT="$APP_ROOT/ios/Runner.xcodeproj"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
RESULT_BUNDLE="$BUILD_ROOT/RunnerUITests.xcresult"

python3 - "$APP_ROOT" "$BUILD_ROOT" <<'CHECK_OUTPUTS'
from pathlib import Path
import sys
source, raw = map(Path, sys.argv[1:])
source, target = source.resolve(), raw.resolve()
if not raw.is_absolute() or target == source or source in target.parents:
    raise SystemExit('CITIZENAPP_UI_TEST_WORK_DIR必须是CitizenApp源码外绝对路径')
CHECK_OUTPUTS

[[ -f "$PROJECT/project.pbxproj" && ! -L "$PROJECT/project.pbxproj" ]] || {
  echo "CitizenApp iOS 工程不存在：$PROJECT" >&2; exit 1
}
mkdir -p "$BUILD_ROOT"
export TMPDIR="$BUILD_ROOT/"

device_fields="$(python3 - <<'SELECT_DEVICE'
import json
import subprocess
import time

DEVICECTL = ["/usr/bin/xcrun", "devicectl"]
ATTEMPTS = 8


def developer_mode_enabled(value):
    if value == "enabled":
        return True
    if not isinstance(value, dict):
        return False
    enabled = value.get("enabled")
    return isinstance(enabled, dict) and enabled.get("mode") == 1


def command_json(arguments, timeout):
    try:
        result = subprocess.run(
            DEVICECTL + arguments + ["--quiet", "--json-output", "-"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=timeout,
            check=False,
        )
        if result.returncode != 0:
            return None
        value = json.loads(result.stdout)
        if value.get("info", {}).get("outcome") != "success":
            return None
        return value
    except (json.JSONDecodeError, subprocess.TimeoutExpired):
        return None


for attempt in range(ATTEMPTS):
    listing = command_json(["list", "devices"], timeout=15)
    candidates = []
    if listing is not None:
        for item in listing.get("result", {}).get("devices", []):
            props = item.get("properties", {})
            hardware = props.get("hardware", {})
            connection = props.get("connection", {})
            state = props.get("state", {})
            identifier = item.get("identifier")
            udid = hardware.get("udid")
            if (
                identifier
                and udid
                and hardware.get("platform") == "iOS"
                and hardware.get("reality") == "physical"
                and connection.get("pairingState") == "paired"
                and developer_mode_enabled(state.get("developerModeStatus"))
            ):
                candidates.append((identifier, udid))

    reachable = []
    for identifier, udid in candidates:
        details = command_json(
            ["device", "info", "details", "--device", identifier],
            timeout=20,
        )
        if details is None:
            continue
        result = details.get("result", {})
        props = result.get("properties", {})
        hardware = props.get("hardware", {})
        connection = props.get("connection", {})
        state = props.get("state", {})
        if (
            result.get("identifier") == identifier
            and hardware.get("udid") == udid
            and hardware.get("platform") == "iOS"
            and hardware.get("reality") == "physical"
            and connection.get("pairingState") == "paired"
            and state.get("bootState") == "booted"
            and developer_mode_enabled(state.get("developerModeStatus"))
        ):
            reachable.append((identifier, udid))

    if len(reachable) > 1:
        raise SystemExit("必须且只能主动探测到一台可用物理 iPhone，当前多于一台")
    if len(reachable) == 1:
        print(reachable[0][0])
        print(reachable[0][1])
        break
    if attempt + 1 < ATTEMPTS:
        time.sleep(2)
else:
    raise SystemExit("主动探测未发现可用物理 iPhone（已配对、开发者模式开启且可读取设备详情）")
SELECT_DEVICE
)"
CORE_DEVICE_ID="$(sed -n '1p' <<<"$device_fields")"
HARDWARE_UDID="$(sed -n '2p' <<<"$device_fields")"
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

database_snapshot() {
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
snapshot = {}
for item in files:
    relative = item.get("relativePath")
    if not isinstance(relative, str) or not relative.endswith(".isar"):
        continue
    resources = item.get("resources", {})
    size = item.get("metadata", {}).get("size", 0)
    if (
        relative in snapshot
        or resources.get("isDirectory") is not False
        or resources.get("isSymbolicLink") is not False
        or resources.get("isReadable") is not True
        or not isinstance(size, int)
        or size <= 0
    ):
        raise SystemExit("CitizenApp Isar 数据库路径、类型或大小无效")
    snapshot[relative] = size
print(json.dumps(snapshot, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
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
  # 仅卸载本脚本创建的设备测试组件；不触碰正式CitizenApp与其它工作目录。
}
trap cleanup_test_apps EXIT

echo "[设备] 已主动探测唯一物理 iPhone"
before_snapshot="$(installed_app_snapshot)"
before_databases="$(database_snapshot)"
before_database_count="$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1])))' "$before_databases")"
echo "[保护] 已确认现有 ${TARGET_BUNDLE_ID}，Isar数据库=${before_database_count}个"

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
after_databases="$(database_snapshot)"
[[ "$after_snapshot" == "$before_snapshot" ]] || {
  echo "CitizenApp 安装信息或数据容器在 UI 测试后发生变化，拒绝通过" >&2
  exit 1
}
database_counts="$(python3 - "$before_databases" "$after_databases" <<'CHECK_DATABASES'
import json
import sys

before = json.loads(sys.argv[1])
after = json.loads(sys.argv[2])
missing = sorted(set(before) - set(after))
if missing:
    raise SystemExit(f"CitizenApp UI测试删除了既有Isar数据库，数量：{len(missing)}")
print(f"{len(before)} → {len(after)}")
CHECK_DATABASES
)"
echo "[保护] CitizenApp容器未变化，既有Isar数据库仍全部存在：${database_counts}个"

if [[ "$test_status" -ne 0 ]]; then
  echo "UI 测试失败；结果保存在：$RESULT_BUNDLE" >&2
  exit "$test_status"
fi
echo "[完成] CitizenApp iOS Release 真机 UI 测试通过"
