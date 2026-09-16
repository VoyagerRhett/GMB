#!/usr/bin/env node
import { startWorkflow } from '../workflow.mjs';
import { cacheCommands } from './cache.mjs';

// 本文件只保存一个准确CitizenApp远端Job身份及其平台步骤；缓存与执行器均使用唯一公共实现。
export const jobIdentity = Object.freeze({"pipeline":"gmb.citizenapp.android.ci","job":"android"});
export const workflowSteps = Object.freeze({
  "0": {
    "shell": "bash",
    "source": "set -euo pipefail\nsource=\"$GITHUB_WORKSPACE/.sdk/tatachatsdk\"\ndestination=\"${GITHUB_WORKSPACE%/*}/TATA/tatachatsdk\"\ntest -d \"$source\" && test ! -L \"$source\"\ntest ! -e \"$destination\" && test ! -L \"$destination\"\nmkdir -p \"${destination%/*}\"\nln -s \"$source\" \"$destination\"\n"
  },
  "1": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/android.mjs\" prepare"
  },
  "2": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/android.mjs\" wire"
  },
  "3": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/android.mjs\" sanitize"
  },
  "4": {
    "shell": "bash",
    "source": "test \"$(git rev-parse HEAD)\" = \"$GMB_SOURCE_SHA\"\n"
  },
  "5": {
    "shell": "bash",
    "source": "# 版本只读受控工具登记，不读取产品依赖合同中的副本。\nprintf 'version=3.47.2\n' >> \"$GITHUB_OUTPUT\"\n"
  },
  "6": {
    "shell": "bash",
    "source": "# 安装后先验真，再统一准备目标平台缓存与受控修订。\nflutter --version --machine >/dev/null\nplatform=\"android\"\nflutter --version >/dev/null\n"
  },
  "7": {
    "shell": "bash",
    "source": "sdkmanager \"platforms;android-36\" \"build-tools;36.0.0\" \"platform-tools\" \"ndk;28.2.13676358\" \"cmake;3.31.6\""
  },
  "8": {
    "shell": "bash",
    "source": "set -euo pipefail\nexport CITIZENSDK_WORK_DIR=\"$CI_INCREMENTAL_ROOT/citizensdk-work\"\nexport CITIZENSDK_NATIVE_OUTPUT_DIR=\"$CI_INCREMENTAL_ROOT/citizensdk-output\"\nexport CITIZENSDK_GRADLE=\"$GITHUB_WORKSPACE/citizenapp/android/gradlew\"\nbash citizensdk/scripts/build-native.sh android\n{\n  printf 'CITIZENSDK_ANDROID_CORE_DIR=%s\n' \"$CITIZENSDK_NATIVE_OUTPUT_DIR/android/arm64-v8a\"\n  printf 'CITIZENSDK_ANDROID_BUILD_DIR=%s\n' \"$CI_INCREMENTAL_ROOT/flutter-build/citizensdk-android\"\n  printf 'CITIZENSDK_NATIVE_OUTPUT_DIR=%s\n' \"$CITIZENSDK_NATIVE_OUTPUT_DIR\"\n} >> \"$GITHUB_ENV\"\n"
  },
  "9": {
    "shell": "bash",
    "source": "flutter pub get --enforce-lockfile\n"
  },
  "10": {
    "shell": "bash",
    "source": "flutter build apk --release --target-platform android-arm64"
  },
  "11": {
    "shell": "bash",
    "source": "set -euo pipefail\narchive=\"citizenapp/build/app/outputs/flutter-apk/app-release.apk\"\nentries=\"$(unzip -Z1 \"$archive\")\"\nfor library in libcitizensdk.so libcitizensdk_jni.so; do\n  path=\"lib/arm64-v8a/$library\"\n  test \"$(printf '%s\\n' \"$entries\" | grep -Fxc \"$path\")\" = 1\n  cmp -s <(unzip -p \"$archive\" \"$path\") \\\n    \"$CITIZENSDK_NATIVE_OUTPUT_DIR/android/arm64-v8a/$library\"\ndone\n! printf '%s\\n' \"$entries\" | grep -Eq '(^|/)libsmoldot[.]so$'\n"
  },
  "12": {
    "shell": "bash",
    "source": "bash scripts/citizenapp-run.sh verify-android-localization build/app/outputs/flutter-apk/app-release.apk"
  },
  "13": {
    "shell": "bash",
    "source": "set -euo pipefail\nGMB_CI_STORE_PASSWORD=\"$(openssl rand -hex 32)\"\nGMB_CI_KEY_PASSWORD=\"$GMB_CI_STORE_PASSWORD\"\nGMB_CI_APKSIGNER=\"$ANDROID_HOME/build-tools/36.0.0/apksigner\"\nexport GMB_CI_STORE_PASSWORD GMB_CI_KEY_PASSWORD\ntest -x \"$GMB_CI_APKSIGNER\"\ntrap 'rm -f \"$RUNNER_TEMP/citizenapp-ci.p12\"' EXIT\nkeytool -genkeypair -storetype PKCS12 \n  -keystore \"$RUNNER_TEMP/citizenapp-ci.p12\" \n  -storepass:env GMB_CI_STORE_PASSWORD -keypass:env GMB_CI_KEY_PASSWORD -alias ci \n  -keyalg RSA -keysize 4096 -validity 2 \n  -dname 'CN=CitizenApp CI,O=GMB,C=US'\n\"$GMB_CI_APKSIGNER\" sign --ks \"$RUNNER_TEMP/citizenapp-ci.p12\" \n  --ks-type PKCS12 --ks-key-alias ci \n  --ks-pass env:GMB_CI_STORE_PASSWORD --key-pass env:GMB_CI_KEY_PASSWORD \n  --out citizenapp/build/app/outputs/flutter-apk/公民-CI.apk \n  citizenapp/build/app/outputs/flutter-apk/app-release.apk\n\"$GMB_CI_APKSIGNER\" verify --verbose --print-certs citizenapp/build/app/outputs/flutter-apk/公民-CI.apk\nunset GMB_CI_STORE_PASSWORD GMB_CI_KEY_PASSWORD\n"
  },
  "14": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/android.mjs\" sanitize\nnode \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/android.mjs\" record\n"
  },
  "15": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/android.mjs\" prune"
  },
  "16": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/android.mjs\" sanitize\nnode \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/android.mjs\" record\n"
  },
  "17": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/android.mjs\" prune"
  }
});

startWorkflow(import.meta.url, jobIdentity, workflowSteps, cacheCommands);
