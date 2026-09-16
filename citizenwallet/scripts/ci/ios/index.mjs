#!/usr/bin/env node
// CI_BUILD: incremental

// 本文件是 citizenwallet/ci-ios.yml 的完整动作入口。
// 所需实现内嵌于本文件，运行时不得导入其它产品或动作脚本。
import { mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const repositoryRoot = process.env.GITHUB_WORKSPACE || process.cwd();
const implementations = Object.freeze({});
const [command, ...argumentsList] = process.argv.slice(2);
if (!command || !Object.hasOwn(implementations, command)) {
  console.error(`未登记动作子命令：${command || '(empty)'}；允许值：${Object.keys(implementations).join(', ')}`);
  process.exit(2);
}
const temporaryDirectory = mkdtempSync(join(tmpdir(), 'gmb-action-'));
const shellCommand = command === 'linux-deps' || command === 'guardrails';
const implementationPath = join(temporaryDirectory, shellCommand ? 'implementation.sh' : 'implementation.mjs');
try {
  writeFileSync(implementationPath, implementations[command], { mode: 0o700 });
  const result = spawnSync(shellCommand ? '/bin/bash' : process.execPath, [realpathSync(implementationPath), ...argumentsList], {
    cwd: repositoryRoot,
    env: { ...process.env, GMB_REPOSITORY_ROOT: repositoryRoot },
    stdio: 'inherit',
  });
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
} finally {
  rmSync(temporaryDirectory, { recursive: true, force: true });
}
