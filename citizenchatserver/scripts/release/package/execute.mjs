#!/usr/bin/env node
import { spawnSync as runExactProcess } from 'node:child_process';

function validateCandidate() {
  const value=process.env;
if(!/^[0-9a-f]{40}$/.test(value.SOURCE_SHA||'')||!/^[1-9][0-9]*$/.test(value.CI_RUN_ID||'')||!/^\d+\.\d{1,2}\.\d{1,2}$/.test(value.SOFTWARE_VERSION||'')||value.VERSION_TAG!=='citizenchatserver-cloudflare-v'+value.SOFTWARE_VERSION)throw Error('准确Release候选无效');
}

// 本文件只执行 gmb.citizenchatserver.cloudflare.release 的 package Job；阶段编号由本仓唯一 Workflow 固定，禁止接收其它身份。
export const EXACT_REMOTE_JOB_IDENTITY = Object.freeze({"pipeline":"gmb.citizenchatserver.cloudflare.release","job":"package"});

function requireExactRemoteJobEnvironment() {
  const owner = EXACT_REMOTE_JOB_IDENTITY.pipeline.split('.')[0];
  const expected = { gmb: 'VoyagerRhett/GMB', tuyu: 'VoyagerRhett/TUYU', tata: 'VoyagerRhett/TATA' }[owner];
  if (!expected || process.env.GITHUB_REPOSITORY !== expected) {
    throw new Error('准确远端Job仓库身份无效');
  }
}
const workflowSteps = Object.freeze({"0":{"shell":"bash","source":"node \"$GITHUB_WORKSPACE/citizenchatserver/scripts/release/index.mjs\" verify-release-source --ci-run-id \"$GMB_CI_RUN_ID\" --version-tag \"$GMB_VERSION_TAG\" --software-version \"$GMB_SOFTWARE_VERSION\" --source-sha \"$GMB_SOURCE_SHA\""},"1":{"shell":"bash","source":"mkdir -p \"$RUNNER_TEMP/citizenchatserver-ci\"\ngh run download \"$GMB_CI_RUN_ID\" --repo VoyagerRhett/GMB \\\n  --name CitizenChatServer-Cloudflare-CI \\\n  --dir \"$RUNNER_TEMP/citizenchatserver-ci\"\n"},"2":{"shell":"bash","source":"node \"$GITHUB_WORKSPACE/citizenchatserver/scripts/release/index.mjs\" action --candidate \"$RUNNER_TEMP/citizenchatserver-ci\" --output \"$RUNNER_TEMP/citizenchatserver-release\" --version-tag \"$GMB_VERSION_TAG\" --software-version \"$GMB_SOFTWARE_VERSION\" --source-sha \"$GMB_SOURCE_SHA\""}});

function runExactWorkflowStep(index) {
  requireExactRemoteJobEnvironment();
  if (!/^(?:0|[1-9][0-9]*)$/.test(String(index || '')) || !Object.hasOwn(workflowSteps, String(index))) {
    throw new Error('准确远端Job阶段无效');
  }
  const step = workflowSteps[String(index)];
  const command = step.shell === 'pwsh' ? 'pwsh' : (process.platform === 'win32' ? 'bash' : '/bin/bash');
  const args = step.shell === 'pwsh'
    ? ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', step.source]
    : ['--noprofile', '--norc', '-e', '-o', 'pipefail', '-c', step.source];
  const result = runExactProcess(command, args, { cwd: process.cwd(), env: process.env, stdio: 'inherit' });
  if (result.error) throw new Error('准确远端Job阶段无法启动');
  if (result.status !== 0) process.exitCode = Number.isInteger(result.status) ? result.status : 1;
}

requireExactRemoteJobEnvironment();
validateCandidate();
if (process.argv[2] !== 'workflow-step') throw new Error('准确Release Job只接受workflow-step');
runExactWorkflowStep(process.argv[3]);
