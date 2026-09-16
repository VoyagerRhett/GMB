#!/usr/bin/env node
import { startWorkflow } from '../workflow.mjs';
import { cacheCommands } from './cache.mjs';

// 本文件只保存一个准确CitizenApp远端Job身份及其平台步骤；缓存与执行器均使用唯一公共实现。
export const jobIdentity = Object.freeze({"pipeline":"gmb.citizenapp.ios.ci","job":"ios"});
export const workflowSteps = Object.freeze({
  "0": {
    "shell": "bash",
    "source": "set -euo pipefail\nsource=\"$GITHUB_WORKSPACE/.sdk/tatachatsdk\"\ndestination=\"${GITHUB_WORKSPACE%/*}/TATA/tatachatsdk\"\ntest -d \"$source\" && test ! -L \"$source\"\ntest ! -e \"$destination\" && test ! -L \"$destination\"\nmkdir -p \"${destination%/*}\"\nln -s \"$source\" \"$destination\"\n"
  },
  "1": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios.mjs\" prepare"
  },
  "2": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios.mjs\" wire"
  },
  "3": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios.mjs\" sanitize"
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
    "source": "# 安装后先验真，再统一准备目标平台缓存与受控修订。\nflutter --version --machine >/dev/null\nplatform=\"ios\"\nflutter --version >/dev/null\n"
  },
  "7": {
    "shell": "bash",
    "source": "set -euo pipefail\nexport CITIZENSDK_WORK_DIR=\"$CI_INCREMENTAL_ROOT/citizensdk-work\"\nexport CITIZENSDK_NATIVE_OUTPUT_DIR=\"$CI_INCREMENTAL_ROOT/citizensdk-output\"\nbash \"$GITHUB_WORKSPACE/citizensdk/scripts/build-native.sh\" apple\nCITIZENAPP_FLUTTER_ROOT=\"$(\n  node \"$GITHUB_WORKSPACE/citizenapp/scripts/citizenapp-view.mjs\" create \\\n    --source-root \"$GITHUB_WORKSPACE/citizenapp\" \\\n    --work-root \"$CI_INCREMENTAL_ROOT\"\n)\"\nnode \"$GITHUB_WORKSPACE/citizenapp/scripts/citizenapp-view.mjs\" project-framework \\\n  --source-root \"$GITHUB_WORKSPACE/citizenapp\" \\\n  --project-root \"$CITIZENAPP_FLUTTER_ROOT\" \\\n  --work-root \"$CI_INCREMENTAL_ROOT\" \\\n  --package-root \"$GITHUB_WORKSPACE/citizensdk\" \\\n  --package-subpath darwin/CitizenSDK.xcframework \\\n  --framework \"$CITIZENSDK_NATIVE_OUTPUT_DIR/apple/CitizenSDK.xcframework\"\nmkdir -p \"$CI_INCREMENTAL_ROOT/flutter-build\"\ntest ! -e \"$CITIZENAPP_FLUTTER_ROOT/build\" && test ! -L \"$CITIZENAPP_FLUTTER_ROOT/build\"\nln -s \"$CI_INCREMENTAL_ROOT/flutter-build\" \"$CITIZENAPP_FLUTTER_ROOT/build\"\n{\n  printf 'CITIZENAPP_FLUTTER_ROOT=%s\\n' \"$CITIZENAPP_FLUTTER_ROOT\"\n  printf 'CITIZENSDK_NATIVE_OUTPUT_DIR=%s\\n' \"$CITIZENSDK_NATIVE_OUTPUT_DIR\"\n} >> \"$GITHUB_ENV\"\n"
  },
  "8": {
    "shell": "bash",
    "source": "cd \"$CITIZENAPP_FLUTTER_ROOT\"\nflutter pub get --enforce-lockfile\n"
  },
  "9": {
    "shell": "bash",
    "source": "cd \"$CITIZENAPP_FLUTTER_ROOT\"\nflutter build ios --release --no-codesign\n"
  },
  "10": {
    "shell": "bash",
    "source": "set -euo pipefail\napp=\"$CITIZENAPP_FLUTTER_ROOT/build/ios/iphoneos/Runner.app\"\npackaged=\"$app/Frameworks/CitizenSDK.framework/CitizenSDK\"\nsource=\"$CITIZENSDK_NATIVE_OUTPUT_DIR/apple/CitizenSDK.xcframework/ios-arm64/CitizenSDK.framework/CitizenSDK\"\ntest -f \"$packaged\" && test -f \"$source\"\ncmp -s \"$packaged\" \"$source\"\ntest -z \"$(find \"$app\" -iname '*smoldot*' -print -quit)\"\n"
  },
  "11": {
    "shell": "bash",
    "source": "codesign --force --deep --sign - \"$CITIZENAPP_FLUTTER_ROOT/build/ios/iphoneos/Runner.app\"\ncodesign --verify --deep --strict \"$CITIZENAPP_FLUTTER_ROOT/build/ios/iphoneos/Runner.app\"\n"
  },
  "12": {
    "shell": "bash",
    "source": "bash \"$GITHUB_WORKSPACE/citizenapp/scripts/citizenapp-run.sh\" verify-ios-localization \\\n  \"$CITIZENAPP_FLUTTER_ROOT/build/ios/iphoneos/Runner.app\"\n"
  },
  "13": {
    "shell": "bash",
    "source": "set -euo pipefail\ncandidate=\"$CITIZENAPP_FLUTTER_ROOT/build/release-candidate/ios\"\nmkdir -p \"$candidate\"\nasset='公民-iOS-CI.app.zip'\nditto -c -k --keepParent \"$CITIZENAPP_FLUTTER_ROOT/build/ios/iphoneos/Runner.app\" \\\n  \"$candidate/$asset\"\n"
  },
  "14": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios.mjs\" sanitize\nnode \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios.mjs\" record\n"
  },
  "15": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios.mjs\" prune"
  },
  "16": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios.mjs\" sanitize\nnode \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios.mjs\" record\n"
  },
  "17": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios.mjs\" prune"
  }
});

startWorkflow(import.meta.url, jobIdentity, workflowSteps, cacheCommands);

