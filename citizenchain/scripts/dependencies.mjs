#!/usr/bin/env node
// CitizenChain开发者和CI按产品声明直接取得工具；取得结果只进入调用方源码外缓存。
import { createHash } from 'node:crypto';
import {
  createWriteStream,
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
} from 'node:fs';
import { chmod, open } from 'node:fs/promises';
import { isAbsolute, join, resolve } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const scripts = fileURLToPath(new URL('.', import.meta.url));
const contract = JSON.parse(readFileSync(join(scripts, 'dependencies.json'), 'utf8'));
const expectedVersion = '35.0';
const expectedSource = 'https://github.com/protocolbuffers/protobuf/releases/tag/v35.0';
const archiveNames = Object.freeze({
  macos: 'protoc-35.0-osx-aarch_64.zip',
  'linux-arm': 'protoc-35.0-linux-aarch_64.zip',
  'linux-amd': 'protoc-35.0-linux-x86_64.zip',
  windows: 'protoc-35.0-win64.zip',
});
function fail(message) { throw new Error(message); }
function safeWork(value) {
  if (!isAbsolute(value)) fail('CitizenChain工具工作目录必须是绝对路径');
  const source = realpathSync(join(scripts, '..'));
  const target = resolve(value);
  if (target === source || target.startsWith(source + '/')) fail('CitizenChain工具不得写入源码目录');
  mkdirSync(target, { recursive: true, mode: 0o700 });
  const actual = realpathSync(target);
  if (actual !== target) fail('CitizenChain工具工作目录禁止符号链接');
  return actual;
}
async function download(url, output) {
  const parsed = new URL(url);
  if (parsed.protocol !== 'https:' || parsed.hostname !== 'github.com' || parsed.username || parsed.password) fail('CitizenChain工具来源无效');
  let last;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const partial = `${output}.partial-${process.pid}-${attempt}`;
    try {
      const response = await fetch(url, { redirect: 'follow', signal: AbortSignal.timeout(300_000) });
      const final = new URL(response.url);
      if (!response.ok || !response.body) fail(`CitizenChain工具下载失败：${response.status}`);
      if (final.protocol !== 'https:'
          || !['github.com', 'release-assets.githubusercontent.com'].includes(final.hostname)
          || final.username || final.password) fail('CitizenChain工具重定向来源无效');
      await pipeline(response.body, createWriteStream(partial, { flags: 'wx', mode: 0o600 }));
      renameSync(partial, output);
      return;
    } catch (error) {
      rmSync(partial, { force: true });
      last = error;
    }
  }
  throw last;
}
async function main() {
  const [command, toolName, platform, workValue] = process.argv.slice(2);
  if (command !== 'prepare' || toolName !== 'protoc' || !workValue || process.argv.length !== 6) fail('CitizenChain工具参数无效');
  const entry = contract.tools?.protoc?.archives?.[platform];
  const archiveName = archiveNames[platform];
  const expectedURL = archiveName
    ? `https://github.com/protocolbuffers/protobuf/releases/download/v${expectedVersion}/${archiveName}`
    : null;
  const expectedExecutable = platform === 'windows' ? 'bin/protoc.exe' : 'bin/protoc';
  if (contract.schema !== 1 || contract.tools?.protoc?.version !== expectedVersion
      || contract.tools?.protoc?.source !== expectedSource
      || Object.keys(contract.tools.protoc.archives).sort().join(',') !== Object.keys(archiveNames).sort().join(',')
      || !entry || entry.url !== expectedURL || entry.executable !== expectedExecutable
      || !/^[a-f0-9]{64}$/.test(entry.sha256)) fail('CitizenChain protoc声明无效');
  const work = safeWork(workValue);
  const archive = join(work, archiveName);
  const payload = join(work, 'payload');
  rmSync(payload, { recursive: true, force: true });
  if (existsSync(archive)
      && createHash('sha256').update(readFileSync(archive)).digest('hex') !== entry.sha256) {
    rmSync(archive, { force: true });
  }
  if (!existsSync(archive)) await download(entry.url, archive);
  if (createHash('sha256').update(readFileSync(archive)).digest('hex') !== entry.sha256) {
    rmSync(archive, { force: true });
    fail('CitizenChain protoc摘要不符');
  }
  mkdirSync(payload, { mode: 0o700 });
  const result = spawnSync('unzip', ['-q', archive, '-d', payload], { stdio: 'inherit' });
  if (result.error || result.status !== 0) { rmSync(payload, { recursive: true, force: true }); fail('CitizenChain protoc解包失败'); }
  const executable = join(payload, entry.executable);
  if (!existsSync(executable) || !lstatSync(executable).isFile()) fail('CitizenChain protoc可执行文件无效');
  const handle = await open(executable, 'r');
  await handle.close();
  await chmod(executable, 0o700);
  const version = spawnSync(executable, ['--version'], { encoding: 'utf8' });
  if (version.error || version.status !== 0 || version.stdout.trim() !== `libprotoc ${expectedVersion}`) {
    rmSync(payload, { recursive: true, force: true });
    fail('CitizenChain protoc版本验真失败');
  }
  process.stdout.write(executable);
}
main().catch(error => { process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`); process.exitCode = 1; });
