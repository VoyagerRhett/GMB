#!/usr/bin/env node
import { startWorkflow } from '../workflow.mjs';

// 本文件只保存一个准确CitizenApp Release Job身份及其平台步骤；执行器与版本验证均使用唯一实现。
export const jobIdentity = Object.freeze({"pipeline":"gmb.citizenapp.ios.release","job":"ios"});
export const workflowSteps = Object.freeze({
  "0": {
    "shell": "bash",
    "source": "set -euo pipefail\nsource=\"$GITHUB_WORKSPACE/.sdk/tatachatsdk\"\ndestination=\"${GITHUB_WORKSPACE%/*}/TATA/tatachatsdk\"\ntest -d \"$source\" && test ! -L \"$source\"\ntest ! -e \"$destination\" && test ! -L \"$destination\"\nmkdir -p \"${destination%/*}\"\nln -s \"$source\" \"$destination\"\n"
  },
  "1": {
    "shell": "bash",
    "source": "node $GITHUB_WORKSPACE/citizenapp/scripts/release/version.mjs verify-release-source --ci-run-id \"$GMB_CI_RUN_ID\" --version-tag \"$GMB_VERSION_TAG\" --source-sha \"$GMB_SOURCE_SHA\" --prefix citizenapp-ios-v --product-id citizenapp --target ios --workflow gmb.citizenapp.ios.ci"
  },
  "2": {
    "shell": "bash",
    "source": "test \"$(git rev-parse HEAD)\" = \"$GMB_SOURCE_SHA\"\npython3 - <<'PY'\nimport os, re\nfrom pathlib import Path\nversion, build = os.environ[\"GMB_SOFTWARE_VERSION\"], os.environ[\"GITHUB_RUN_NUMBER\"]\nif not re.fullmatch(r\"\\d+\\.\\d{1,2}\\.\\d{1,2}\", version) or not re.fullmatch(r\"[1-9]d*\", build):\n    raise SystemExit(\"CitizenApp 候选版本输入无效\")\npath = Path(\"citizenapp/pubspec.yaml\")\ntext, count = re.subn(r\"(?m)^version:\\s*\\d+\\.\\d+\\.\\d+\\+\\d+\\s*$\", f\"version: {version}+{build}\", path.read_text(), count=1)\nif count != 1: raise SystemExit(\"CitizenApp pubspec 版本真源无效\")\npath.write_text(text)\nPY\n"
  },
  "3": {
    "shell": "bash",
    "source": "# 版本只读受控工具登记，不读取产品依赖合同中的副本。\nprintf 'version=3.47.2\n' >> \"$GITHUB_OUTPUT\"\n"
  },
  "4": {
    "shell": "bash",
    "source": "# 安装后先验真，再统一准备目标平台缓存与受控修订。\nflutter --version --machine >/dev/null\nplatform=\"ios\"\nflutter --version >/dev/null\n"
  },
  "5": {
    "shell": "bash",
    "source": "set -euo pipefail\nnative_root=\"$RUNNER_TEMP/citizenapp-citizensdk-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT\"\nexport CITIZENSDK_WORK_DIR=\"$native_root/work\"\nexport CITIZENSDK_NATIVE_OUTPUT_DIR=\"$native_root/output\"\nbash \"$GITHUB_WORKSPACE/citizensdk/scripts/build-native.sh\" apple\nCITIZENAPP_FLUTTER_ROOT=\"$(\n  node \"$GITHUB_WORKSPACE/citizenapp/scripts/citizenapp-view.mjs\" create \\\n    --source-root \"$GITHUB_WORKSPACE/citizenapp\" \\\n    --work-root \"$native_root\"\n)\"\nnode \"$GITHUB_WORKSPACE/citizenapp/scripts/citizenapp-view.mjs\" project-framework \\\n  --source-root \"$GITHUB_WORKSPACE/citizenapp\" \\\n  --project-root \"$CITIZENAPP_FLUTTER_ROOT\" \\\n  --work-root \"$native_root\" \\\n  --package-root \"$GITHUB_WORKSPACE/citizensdk\" \\\n  --package-subpath darwin/CitizenSDK.xcframework \\\n  --framework \"$CITIZENSDK_NATIVE_OUTPUT_DIR/apple/CitizenSDK.xcframework\"\nmkdir -p \"$native_root/flutter-build\"\ntest ! -e \"$CITIZENAPP_FLUTTER_ROOT/build\" && test ! -L \"$CITIZENAPP_FLUTTER_ROOT/build\"\nln -s \"$native_root/flutter-build\" \"$CITIZENAPP_FLUTTER_ROOT/build\"\n{\n  printf 'CITIZENAPP_FLUTTER_ROOT=%s\\n' \"$CITIZENAPP_FLUTTER_ROOT\"\n  printf 'CITIZENAPP_RELEASE_ROOT=%s\\n' \"$native_root/release\"\n  printf 'CITIZENSDK_NATIVE_OUTPUT_DIR=%s\\n' \"$CITIZENSDK_NATIVE_OUTPUT_DIR\"\n} >> \"$GITHUB_ENV\"\n"
  },
  "6": {
    "shell": "bash",
    "source": "cd \"$CITIZENAPP_FLUTTER_ROOT\"\nflutter pub get --enforce-lockfile\n"
  },
  "7": {
    "shell": "bash",
    "source": "cd \"$CITIZENAPP_FLUTTER_ROOT\"\nflutter build ios --release --no-codesign\n"
  },
  "8": {
    "shell": "bash",
    "source": "set -euo pipefail\napp=\"$CITIZENAPP_FLUTTER_ROOT/build/ios/iphoneos/Runner.app\"\npackaged=\"$app/Frameworks/CitizenSDK.framework/CitizenSDK\"\nsource=\"$CITIZENSDK_NATIVE_OUTPUT_DIR/apple/CitizenSDK.xcframework/ios-arm64/CitizenSDK.framework/CitizenSDK\"\ntest -f \"$packaged\" && test -f \"$source\"\ncmp -s \"$packaged\" \"$source\"\ntest -z \"$(find \"$app\" -iname '*smoldot*' -print -quit)\"\n"
  },
  "9": {
    "shell": "bash",
    "source": "bash \"$GITHUB_WORKSPACE/citizenapp/scripts/citizenapp-run.sh\" verify-ios-localization \\\n  \"$CITIZENAPP_FLUTTER_ROOT/build/ios/iphoneos/Runner.app\"\n"
  },
  "10": {
    "shell": "bash",
    "source": "set -euo pipefail\numask 077\nwork=\"$RUNNER_TEMP/citizenapp-ios-signing\"\npublish=\"$CITIZENAPP_RELEASE_ROOT\"\nrm -rf \"$work\" \"$publish\"\nmkdir -p \"$work\" \"$publish\"\nkeychain=\"$work/release.keychain-db\"\nkeychain_password=\"$(openssl rand -hex 32)\"\ncleanup() {\n  security delete-keychain \"$keychain\" >/dev/null 2>&1 || true\n  rm -rf \"$work\"\n}\ntrap cleanup EXIT\npython3 - \"$work\" <<'PY'\nimport base64, os, pathlib, re, sys\nroot = pathlib.Path(sys.argv[1])\nfields = {}\nfor raw in os.environ.get(\"IOS_KEY\", \"\").splitlines():\n    line = raw.strip()\n    if not line or line.startswith(\"#\"):\n        continue\n    name, sep, value = line.partition(\"=\")\n    if not sep or name.strip() in fields or not value.strip():\n        raise SystemExit(\"IOS_KEY 行格式无效\")\n    fields[name.strip()] = value.strip()\nif set(fields) != {\"pkcs12\", \"password\", \"certificate_sha1\"}:\n    raise SystemExit(\"IOS_KEY 字段集合无效\")\nif not re.fullmatch(r\"[0-9A-F]{40}\", fields[\"certificate_sha1\"]):\n    raise SystemExit(\"Apple Distribution 证书摘要无效\")\ntry:\n    pkcs12 = base64.b64decode(fields[\"pkcs12\"], validate=True)\n    profile = base64.b64decode(os.environ.get(\"IOS_PROVISIONING_PROFILE\", \"\"), validate=True)\nexcept ValueError as exc:\n    raise SystemExit(\"Apple Distribution 或 provisioning profile Base64 无效\") from exc\nif not 1024 <= len(pkcs12) <= 32 * 1024 * 1024 or not 1024 <= len(profile) <= 1024 * 1024:\n    raise SystemExit(\"Apple Distribution 签名材料大小无效\")\n(root / \"distribution.p12\").write_bytes(pkcs12)\n(root / \"password\").write_text(fields[\"password\"])\n(root / \"certificate-sha1\").write_text(fields[\"certificate_sha1\"])\n(root / \"profile.mobileprovision\").write_bytes(profile)\nPY\nsecurity create-keychain -p \"$keychain_password\" \"$keychain\"\nsecurity set-keychain-settings -lut 21600 \"$keychain\"\nsecurity unlock-keychain -p \"$keychain_password\" \"$keychain\"\n# 中文注释：codesign 查找 identity 依赖用户钥匙串搜索列表；仅传 --keychain\n# 不能保证干净 runner 能从证书继续定位到同钥匙串中的私钥。\nsecurity list-keychains -d user -s \"$keychain\"\nsecurity import \"$work/distribution.p12\" -k \"$keychain\" -P \"$(cat \"$work/password\")\" -T /usr/bin/codesign\nsecurity set-key-partition-list -S apple-tool:,apple:,codesign: -s -k \"$keychain_password\" \"$keychain\" >/dev/null\ncertificate_sha1=\"$(cat \"$work/certificate-sha1\")\"\nsecurity find-certificate -a -Z \"$keychain\" | grep -F \"SHA-1 hash: $certificate_sha1\"\nsecurity find-identity -v -p codesigning \"$keychain\" | grep -Fq \"$certificate_sha1\"\n# 中文注释：干净 runner 的钥匙串不保证预装描述文件 CMS 签发链；LibreSSL\n# 直接验证 CMS 密码学签名并解出载荷，再用正式证书摘要锁定唯一配对。\n/usr/bin/openssl smime -verify -inform DER -in \"$work/profile.mobileprovision\" \\\n  -noverify -out \"$work/profile.plist\" >/dev/null\nprofile_certificate_sha1=\"$(\n  plutil -extract DeveloperCertificates.0 raw -o - \"$work/profile.plist\" \\\n    | base64 -D | shasum -a 1 | awk '{print toupper($1)}'\n)\"\ntest \"$profile_certificate_sha1\" = \"$certificate_sha1\"\ntest \"$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' \"$work/profile.plist\")\" = MHYMVRN6FC\ntest \"$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' \"$work/profile.plist\")\" = MHYMVRN6FC.ios.citizenapp\ntest \"$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' \"$work/profile.plist\")\" = false\nplutil -extract Entitlements xml1 -o \"$work/entitlements.plist\" \"$work/profile.plist\"\napp=\"$CITIZENAPP_FLUTTER_ROOT/build/ios/iphoneos/Runner.app\"\ntest \"$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \"$app/Info.plist\")\" = ios.citizenapp\ncp \"$work/profile.mobileprovision\" \"$app/embedded.mobileprovision\"\nfind \"$app\" -type f -name '*.dylib' -print0 | while IFS= read -r -d '' item; do\n  codesign --force --sign \"$certificate_sha1\" --keychain \"$keychain\" --timestamp=none \"$item\"\ndone\nfind \"$app\" -type d \\( -name '*.framework' -o -name '*.appex' \\) -print0 \\\n  | while IFS= read -r -d '' item; do\n      codesign --force --sign \"$certificate_sha1\" --keychain \"$keychain\" --timestamp=none \"$item\"\n    done\ncodesign --force --sign \"$certificate_sha1\" --keychain \"$keychain\" --timestamp=none \\\n  --generate-entitlement-der --entitlements \"$work/entitlements.plist\" \"$app\"\ncodesign --verify --deep --strict \"$app\"\ncodesign -dv --verbose=4 \"$app\" 2> \"$work/codesign.txt\"\ngrep -F 'TeamIdentifier=MHYMVRN6FC' \"$work/codesign.txt\"\nmkdir -p \"$work/package/Payload\"\ncp -R \"$app\" \"$work/package/Payload/Runner.app\"\n(cd \"$work/package\" && ditto -c -k --sequesterRsrc --keepParent Payload \"$publish/citizenapp.ipa\")\nunzip -Z1 \"$publish/citizenapp.ipa\" | grep -Fx 'Payload/Runner.app/Info.plist'\n"
  },
  "11": {
    "shell": "bash",
    "source": "set -euo pipefail\n# manifest 的 platform 是对外 Release 身份，必须使用标准 iOS；小写 ios\n# 只保留在 action target、Tag 与既有签名 wire 中，不能泄漏回正式制品。\nnode - <<'NODE'\nconst { createHash } = require('node:crypto');\nconst fs = require('node:fs');\nconst root = process.env.CITIZENAPP_RELEASE_ROOT;\nconst digest = createHash('sha256').update(fs.readFileSync(`${root}/citizenapp.ipa`)).digest('hex');\nfs.writeFileSync(`${root}/citizenapp-release-ios.json`, `${JSON.stringify({\n  product_id: 'citizenapp', version: process.env.GMB_SOFTWARE_VERSION,\n  github_run_number: Number(process.env.GITHUB_RUN_NUMBER), head_sha: process.env.GMB_SOURCE_SHA,\n  bundle_id: 'ios.citizenapp', package_name: 'com.crcfrcn.citizenapp',\n  assets: [{ platform: 'iOS', asset_name: 'citizenapp.ipa', asset_sha256: digest }],\n}, null, 2)}\n`);\nNODE\ntest \"$(find \"$CITIZENAPP_RELEASE_ROOT\" -type f | wc -l | tr -d ' ')\" = 2\n"
  }
});

startWorkflow(import.meta.url, jobIdentity, workflowSteps);

