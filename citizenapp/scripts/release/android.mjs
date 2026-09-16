#!/usr/bin/env node
import { startWorkflow } from '../workflow.mjs';

// 本文件只保存一个准确CitizenApp Release Job身份及其平台步骤；执行器与版本验证均使用唯一实现。
export const jobIdentity = Object.freeze({"pipeline":"gmb.citizenapp.android.release","job":"android"});
export const workflowSteps = Object.freeze({
  "0": {
    "shell": "bash",
    "source": "set -euo pipefail\nsource=\"$GITHUB_WORKSPACE/.sdk/tatachatsdk\"\ndestination=\"${GITHUB_WORKSPACE%/*}/TATA/tatachatsdk\"\ntest -d \"$source\" && test ! -L \"$source\"\ntest ! -e \"$destination\" && test ! -L \"$destination\"\nmkdir -p \"${destination%/*}\"\nln -s \"$source\" \"$destination\"\n"
  },
  "1": {
    "shell": "bash",
    "source": "node $GITHUB_WORKSPACE/citizenapp/scripts/release/version.mjs verify-release-source --ci-run-id \"$GMB_CI_RUN_ID\" --version-tag \"$GMB_VERSION_TAG\" --source-sha \"$GMB_SOURCE_SHA\" --prefix citizenapp-android-v --product-id citizenapp --target android --workflow gmb.citizenapp.android.ci"
  },
  "2": {
    "shell": "bash",
    "source": "test \"$(git rev-parse HEAD)\" = \"$GMB_SOURCE_SHA\"\npython3 - <<'PY'\nimport os, re\nfrom pathlib import Path\nversion, build = os.environ[\"GMB_SOFTWARE_VERSION\"], os.environ[\"GITHUB_RUN_NUMBER\"]\nif not re.fullmatch(r\"d+.d{1,2}.d{1,2}\", version) or not re.fullmatch(r\"[1-9]d*\", build):\n    raise SystemExit(\"CitizenApp 候选版本输入无效\")\npath = Path(\"citizenapp/pubspec.yaml\")\ntext, count = re.subn(r\"(?m)^version:s*d+.d+.d++d+s*$\", f\"version: {version}+{build}\", path.read_text(), count=1)\nif count != 1: raise SystemExit(\"CitizenApp pubspec 版本真源无效\")\npath.write_text(text)\nPY\n"
  },
  "3": {
    "shell": "bash",
    "source": "# 版本只读受控工具登记，不读取产品依赖合同中的副本。\nprintf 'version=3.47.2\n' >> \"$GITHUB_OUTPUT\"\n"
  },
  "4": {
    "shell": "bash",
    "source": "# 安装后先验真，再统一准备目标平台缓存与受控修订。\nflutter --version --machine >/dev/null\nplatform=\"android\"\nflutter --version >/dev/null\n"
  },
  "5": {
    "shell": "bash",
    "source": "sdkmanager \"platforms;android-36\" \"build-tools;36.0.0\" \"platform-tools\" \"cmdline-tools;22.0\" \"ndk;28.2.13676358\" \"cmake;3.31.6\""
  },
  "6": {
    "shell": "bash",
    "source": "set -euo pipefail\nnative_root=\"$RUNNER_TEMP/citizenapp-citizensdk-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT\"\nexport CITIZENSDK_WORK_DIR=\"$native_root/work\"\nexport CITIZENSDK_NATIVE_OUTPUT_DIR=\"$native_root/output\"\nexport CITIZENSDK_GRADLE=\"$GITHUB_WORKSPACE/citizenapp/android/gradlew\"\nmkdir -p \"$native_root/flutter-build\"\ntest ! -e citizenapp/build && test ! -L citizenapp/build\nln -s \"$native_root/flutter-build\" citizenapp/build\nbash citizensdk/scripts/build-native.sh android\n{\n  printf 'CITIZENSDK_ANDROID_CORE_DIR=%s\n' \"$CITIZENSDK_NATIVE_OUTPUT_DIR/android/arm64-v8a\"\n  printf 'CITIZENSDK_ANDROID_BUILD_DIR=%s\n' \"$native_root/flutter-plugin\"\n  printf 'CITIZENSDK_NATIVE_OUTPUT_DIR=%s\n' \"$CITIZENSDK_NATIVE_OUTPUT_DIR\"\n} >> \"$GITHUB_ENV\"\n"
  },
  "7": {
    "shell": "bash",
    "source": "flutter pub get --enforce-lockfile\n"
  },
  "8": {
    "shell": "bash",
    "source": "flutter build apk --release --target-platform android-arm64\nflutter build appbundle --release --target-platform android-arm64\n"
  },
  "9": {
    "shell": "bash",
    "source": "set -euo pipefail\nverify_archive() {\n  local archive=\"$1\" prefix=\"$2\" entries library path\n  entries=\"$(unzip -Z1 \"$archive\")\"\n  for library in libcitizensdk.so libcitizensdk_jni.so; do\n    path=\"$prefix/arm64-v8a/$library\"\n    test \"$(printf '%s\\n' \"$entries\" | grep -Fxc \"$path\")\" = 1\n    cmp -s <(unzip -p \"$archive\" \"$path\") \\\n      \"$CITIZENSDK_NATIVE_OUTPUT_DIR/android/arm64-v8a/$library\"\n  done\n  ! printf '%s\\n' \"$entries\" | grep -Eq '(^|/)libsmoldot[.]so$'\n}\nverify_archive citizenapp/build/app/outputs/flutter-apk/app-release.apk lib\nverify_archive citizenapp/build/app/outputs/bundle/release/app-release.aab base/lib\n"
  },
  "10": {
    "shell": "bash",
    "source": "bash scripts/citizenapp-run.sh verify-android-localization build/app/outputs/flutter-apk/app-release.apk"
  },
  "11": {
    "shell": "bash",
    "source": "set -euo pipefail\numask 077\nwork=\"$RUNNER_TEMP/citizenapp-android-signing\"\npublish=\"citizenapp/build/release\"\nrm -rf \"$work\" \"$publish\"\nmkdir -p \"$work\" \"$publish\"\ntrap 'rm -rf \"$work\"' EXIT\npython3 - \"$work\" <<'PY'\nimport base64, os, pathlib, re, sys\nroot = pathlib.Path(sys.argv[1])\nfields = {}\nfor raw in os.environ.get(\"APP_KEY\", \"\").splitlines():\n    line = raw.strip()\n    if not line or line.startswith(\"#\"):\n        continue\n    name, sep, value = line.partition(\"=\")\n    if not sep or name.strip() in fields or not value.strip():\n        raise SystemExit(\"APP_KEY 行格式无效\")\n    fields[name.strip()] = value.strip()\nif set(fields) - {\"keystore\", \"password\", \"alias\", \"keyPassword\"}:\n    raise SystemExit(\"APP_KEY 包含未登记字段\")\nalias = fields.get(\"alias\", \"upload\")\nif not re.fullmatch(r\"[A-Za-z0-9._-]{1,128}\", alias):\n    raise SystemExit(\"APP_KEY alias 无效\")\ntry:\n    key = base64.b64decode(fields[\"keystore\"], validate=True)\n    password = fields[\"password\"]\nexcept (KeyError, ValueError) as exc:\n    raise SystemExit(\"APP_KEY 缺少有效签名材料\") from exc\nif not 1024 <= len(key) <= 32 * 1024 * 1024:\n    raise SystemExit(\"APP_KEY keystore 大小无效\")\n(root / \"release.keystore\").write_bytes(key)\n(root / \"password\").write_text(password)\n(root / \"key-password\").write_text(fields.get(\"keyPassword\", password))\n(root / \"alias\").write_text(alias)\nPY\nstore_password=\"$(cat \"$work/password\")\"\nkey_password=\"$(cat \"$work/key-password\")\"\nalias=\"$(cat \"$work/alias\")\"\nexport GMB_ANDROID_STORE_PASSWORD=\"$store_password\"\nexport GMB_ANDROID_KEY_PASSWORD=\"$key_password\"\napksigner=\"$ANDROID_HOME/build-tools/36.1.0/apksigner\"\ntest -x \"$apksigner\"\n\"$apksigner\" sign --ks \"$work/release.keystore\" \\n  --ks-pass env:GMB_ANDROID_STORE_PASSWORD --key-pass env:GMB_ANDROID_KEY_PASSWORD \\n  --v4-signing-enabled false \\n  --ks-key-alias \"$alias\" --out \"$publish/citizenapp.apk\" \\n  citizenapp/build/app/outputs/flutter-apk/app-release.apk\ncp citizenapp/build/app/outputs/bundle/release/app-release.aab \"$publish/citizenapp.aab\"\njarsigner -keystore \"$work/release.keystore\" \\n  -storepass:env GMB_ANDROID_STORE_PASSWORD -keypass:env GMB_ANDROID_KEY_PASSWORD \\n  \"$publish/citizenapp.aab\" \"$alias\"\n\"$apksigner\" verify --verbose --print-certs \"$publish/citizenapp.apk\" \\n  | tee \"$work/apk-verification.txt\"\ngrep -F 'Verified using v2 scheme (APK Signature Scheme v2): true' \"$work/apk-verification.txt\"\n# Android 上传证书按平台规范可以自签名；只验证包完整性，再从三处回读同一证书。\njarsigner -verify \"$publish/citizenapp.aab\"\napk_certificate_sha256=\"$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' \"$work/apk-verification.txt\")\"\nkey_certificate_sha256=\"$(keytool -exportcert -alias \"$alias\" \\n  -keystore \"$work/release.keystore\" -storepass:env GMB_ANDROID_STORE_PASSWORD -rfc \\n  | openssl x509 -outform DER | sha256sum | awk '{print $1}')\"\naab_certificate_sha256=\"$(keytool -printcert -jarfile \"$publish/citizenapp.aab\" -rfc \\n  | openssl x509 -outform DER | sha256sum | awk '{print $1}')\"\n[[ \"$apk_certificate_sha256\" =~ ^[0-9a-f]{64}$ ]]\ntest \"$apk_certificate_sha256\" = \"$key_certificate_sha256\"\ntest \"$apk_certificate_sha256\" = \"$aab_certificate_sha256\"\ntest \"$(apkanalyzer manifest application-id \"$publish/citizenapp.apk\")\" = com.crcfrcn.citizenapp\ntest \"$(apkanalyzer manifest version-code \"$publish/citizenapp.apk\")\" = \"$GITHUB_RUN_NUMBER\"\n"
  },
  "12": {
    "shell": "bash",
    "source": "set -euo pipefail\n# manifest 的 platform 是对外 Release 身份，必须使用标准 Android；小写 android\n# 只保留在 action target、Tag 与既有签名 wire 中，不能泄漏回正式制品。\nnode <<'NODE'\n  const { createHash } = require(\"node:crypto\");\n  const fs = require(\"node:fs\");\n  const root = \"citizenapp/build/release\";\n  const digest = (name) => createHash(\"sha256\").update(fs.readFileSync(`${root}/${name}`)).digest(\"hex\");\n  fs.writeFileSync(`${root}/citizenapp-release-android.json`, `${JSON.stringify({\n    product_id: \"citizenapp\", version: process.env.GMB_SOFTWARE_VERSION,\n    github_run_number: Number(process.env.GITHUB_RUN_NUMBER), head_sha: process.env.GMB_SOURCE_SHA,\n    bundle_id: \"ios.citizenapp\", package_name: \"com.crcfrcn.citizenapp\",\n    assets: [\n      { platform: \"Android\", asset_name: \"citizenapp.apk\", asset_sha256: digest(\"citizenapp.apk\") },\n      { platform: \"Android\", asset_name: \"citizenapp.aab\", asset_sha256: digest(\"citizenapp.aab\") },\n    ],\n  }, null, 2)}\n`);\nNODE\ntest \"$(find citizenapp/build/release -type f | wc -l | tr -d ' ')\" = 3\n"
  }
});

startWorkflow(import.meta.url, jobIdentity, workflowSteps);
