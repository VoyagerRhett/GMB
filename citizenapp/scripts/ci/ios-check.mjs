#!/usr/bin/env node
import { startWorkflow } from '../workflow.mjs';
import { cacheCommands } from './cache.mjs';

// 本文件只保存一个准确CitizenApp远端Job身份及其平台步骤；缓存与执行器均使用唯一公共实现。
export const jobIdentity = Object.freeze({"pipeline":"gmb.citizenapp.ios.ci","job":"check"});
export const workflowSteps = Object.freeze({
  "0": {
    "shell": "bash",
    "source": "set -euo pipefail\nsource=\"$GITHUB_WORKSPACE/.sdk/tatachatsdk\"\ndestination=\"${GITHUB_WORKSPACE%/*}/TATA/tatachatsdk\"\ntest -d \"$source\" && test ! -L \"$source\"\ntest ! -e \"$destination\" && test ! -L \"$destination\"\nmkdir -p \"${destination%/*}\"\nln -s \"$source\" \"$destination\"\n"
  },
  "1": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios-check.mjs\" prepare"
  },
  "2": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios-check.mjs\" wire"
  },
  "3": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios-check.mjs\" sanitize"
  },
  "4": {
    "shell": "bash",
    "source": "node citizenchain/scripts/generate-logo-assets.mjs --check"
  },
  "5": {
    "shell": "bash",
    "source": "test \"$(git rev-parse HEAD)\" = \"$GMB_SOURCE_SHA\"\n"
  },
  "6": {
    "shell": "bash",
    "source": "# 版本只读受控工具登记，不读取产品依赖合同中的副本。\nprintf 'version=3.47.2\n' >> \"$GITHUB_OUTPUT\"\n"
  },
  "7": {
    "shell": "bash",
    "source": "# 安装后先验真，再统一准备目标平台缓存与受控修订。\nflutter --version --machine >/dev/null\nplatform=\"ios\"\nflutter --version >/dev/null\n"
  },
  "8": {
    "shell": "bash",
    "source": "flutter pub get --enforce-lockfile\n"
  },
  "9": {
    "shell": "bash",
    "source": "./scripts/citizenapp-test.sh"
  },
  "10": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios-check.mjs\" sanitize\nnode \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios-check.mjs\" record\n"
  },
  "11": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios-check.mjs\" prune"
  },
  "12": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios-check.mjs\" sanitize\nnode \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios-check.mjs\" record\n"
  },
  "13": {
    "shell": "bash",
    "source": "node \"$GITHUB_WORKSPACE/citizenapp/scripts/ci/ios-check.mjs\" prune"
  }
});

startWorkflow(import.meta.url, jobIdentity, workflowSteps, cacheCommands);

