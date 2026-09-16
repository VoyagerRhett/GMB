import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

// 本模块锁定 CitizenApp 远端 Job 的仓库、流程、阶段和参数闭集，
// 并按产品声明逐项执行命令，不承载 TataConsole 仓库操作或产品选择逻辑。
function requireIdentity(identity, environment) {
  const fields = identity && typeof identity === 'object' ? Object.keys(identity).sort() : [];
  if (JSON.stringify(fields) !== JSON.stringify(['job', 'pipeline'])
    || !/^[a-z][a-z0-9.-]+$/u.test(identity.pipeline)
    || !/^[a-z][a-z0-9-]*$/u.test(identity.job)) {
    throw new Error('CitizenApp远程Job身份无效');
  }
  if (!/^gmb[.]citizenapp[.](?:ios|android)[.](?:ci|release)$/u.test(identity.pipeline)
    || environment.GITHUB_REPOSITORY !== 'VoyagerRhett/GMB') {
    throw new Error('CitizenApp远程Job仓库身份无效');
  }
}

function runStep(steps, index, environment, run) {
  if (!/^(?:0|[1-9][0-9]*)$/u.test(String(index ?? ''))
    || !Object.hasOwn(steps, String(index))) {
    throw new Error('CitizenApp远程Job阶段无效');
  }
  const step = steps[String(index)];
  if (!step || !['bash', 'pwsh'].includes(step.shell) || typeof step.source !== 'string'
    || step.source.length === 0) throw new Error('CitizenApp远程Job步骤无效');
  const command = step.shell === 'pwsh'
    ? 'pwsh'
    : (process.platform === 'win32' ? 'bash' : '/bin/bash');
  const argumentsList = step.shell === 'pwsh'
    ? ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', step.source]
    : ['--noprofile', '--norc', '-e', '-o', 'pipefail', '-c', step.source];
  const result = run(command, argumentsList, {
    cwd: process.cwd(), env: environment, stdio: 'inherit',
  });
  if (result.error) throw new Error('CitizenApp远程Job阶段无法启动');
  if (result.status !== 0) process.exitCode = Number.isInteger(result.status) ? result.status : 1;
}

export async function runWorkflow(identity, steps, commands = {}, {
  argumentsList = process.argv.slice(2), environment = process.env, run = spawnSync,
} = {}) {
  requireIdentity(identity, environment);
  const [command, argument, ...extra] = argumentsList;
  if (extra.length > 0) throw new Error('CitizenApp远程Job参数越界');
  if (command === 'workflow-step') return runStep(steps, argument, environment, run);
  if (argument !== undefined || !Object.hasOwn(commands, command ?? '')) {
    throw new Error('CitizenApp远程Job命令无效');
  }
  return commands[command](environment);
}

export function startWorkflow(metaUrl, identity, steps, commands = {}) {
  const invoked = process.argv[1] ? pathToFileURL(process.argv[1]).href : '';
  if (invoked !== metaUrl) return;
  runWorkflow(identity, steps, commands).catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
