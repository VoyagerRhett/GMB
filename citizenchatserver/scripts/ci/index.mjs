#!/usr/bin/env node

// CI_BUILD: immutable-upstream
// 中文注释：本单平台实例只消费并复核 TataChatServer 正式 Release，不缓存、不重编译上游源码。
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import {
  cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync,
  readdirSync, rmSync, writeFileSync,
} from 'node:fs';
import { basename, join, relative, resolve, sep } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const upstreamRepository = 'VoyagerRhett/TATA';
const upstreamPrefix = 'tatachatserver-cloudflare-v';
const upstreamAssets = [
  'tatachatserver-cloudflare.tar.gz',
  'tatachatserver-cloudflare-release.json',
  'SHA256SUMS',
];

function fail(message) { throw new Error(message); }
function sha256(path) { return createHash('sha256').update(readFileSync(path)).digest('hex'); }
function run(command, args, options = {}) {
  return execFileSync(command, args, {
    encoding: options.encoding ?? 'utf8', maxBuffer: 256 * 1024 * 1024,
    stdio: options.stdio ?? ['ignore', 'pipe', 'pipe'],
  });
}
function parseArguments(argv) {
  const command = argv.shift();
  const values = {};
  while (argv.length) {
    const key = argv.shift();
    if (!key?.startsWith('--') || !argv.length) fail('CitizenChatServer CI 参数无效');
    values[key.slice(2)] = argv.shift();
  }
  return { command, values };
}
function regularFiles(root) {
  const output = [];
  const walk = (directory) => {
    for (const name of readdirSync(directory).sort()) {
      const path = join(directory, name);
      const stat = lstatSync(path);
      if (stat.isSymbolicLink()) fail('候选禁止符号链接');
      if (stat.isDirectory()) walk(path);
      else if (stat.isFile()) output.push(relative(root, path).split(sep).join('/'));
      else fail('候选包含非常规文件');
    }
  };
  walk(root);
  return output;
}
function writeChecksums(root) {
  const files = regularFiles(root).filter((path) => path !== 'SHA256SUMS');
  writeFileSync(join(root, 'SHA256SUMS'), `${files.map((path) => `${sha256(join(root, path))}  ${path}`).join('\n')}\n`);
}
function verifyChecksums(root) {
  const expected = [];
  for (const line of readFileSync(join(root, 'SHA256SUMS'), 'utf8').trim().split('\n')) {
    const match = /^([0-9a-f]{64})  ([^\r\n]+)$/.exec(line);
    if (!match || match[2] === 'SHA256SUMS' || match[2].startsWith('/')
        || match[2].split('/').includes('..')) fail('SHA256SUMS 格式无效');
    if (sha256(join(root, match[2])) !== match[1]) fail(`候选哈希不一致：${match[2]}`);
    expected.push(match[2]);
  }
  const actual = regularFiles(root).filter((path) => path !== 'SHA256SUMS');
  if (JSON.stringify(actual) !== JSON.stringify([...expected].sort())) fail('候选文件闭集与 SHA256SUMS 不一致');
}
function safeExtract(archive, output) {
  const rows = run('tar', ['-tzf', archive]).trim().split('\n').filter(Boolean);
  if (!rows.length || rows.some((path) => path.startsWith('/') || path.split('/').includes('..'))) fail('上游归档路径无效');
  if (run('tar', ['-tvzf', archive]).trim().split('\n').some((line) => /^[lh]/.test(line))) fail('上游归档禁止链接');
  mkdirSync(output, { recursive: true, mode: 0o700 });
  run('tar', ['-xzf', archive, '-C', output]);
}
function findUnique(root, name, directory = false) {
  const matches = [];
  const walk = (path) => {
    for (const entry of readdirSync(path)) {
      const child = join(path, entry);
      const stat = lstatSync(child);
      if (stat.isSymbolicLink()) fail('上游归档禁止符号链接');
      if ((directory ? stat.isDirectory() : stat.isFile()) && entry === name) matches.push(child);
      if (stat.isDirectory()) walk(child);
    }
  };
  walk(root);
  if (matches.length !== 1) fail(`上游归档缺少唯一 ${name}`);
  return matches[0];
}
function latestFormalRelease() {
  const releases = JSON.parse(run('gh', ['api', `repos/${upstreamRepository}/releases?per_page=100`]));
  const candidates = releases.filter((release) => !release.draft && !release.prerelease
    && String(release.tag_name ?? '').startsWith(upstreamPrefix));
  if (!candidates.length) fail('TataChatServer 没有正式 Cloudflare Release');
  candidates.sort((left, right) => String(right.published_at).localeCompare(String(left.published_at)));
  const release = candidates[0];
  const assets = new Map((release.assets ?? []).map((asset) => [asset.name, asset]));
  if (assets.size !== upstreamAssets.length || upstreamAssets.some((name) => !assets.has(name))) {
    fail('TataChatServer 正式 Release 资产闭集无效');
  }
  return { release, assets };
}
function downloadAsset(asset, output) {
  const data = run('gh', [
    'api', '-H', 'Accept: application/octet-stream',
    `repos/${upstreamRepository}/releases/assets/${asset.id}`,
  ], { encoding: 'buffer' });
  if (!Buffer.isBuffer(data) || data.length !== asset.size) fail(`上游资产下载长度无效：${asset.name}`);
  writeFileSync(output, data, { mode: 0o600 });
}
export function verifyUpstream(download, release) {
  const sumsSource = readFileSync(join(download, 'SHA256SUMS'), 'utf8');
  if (!sumsSource.endsWith('\n') || sumsSource.includes('\r')) fail('上游 SHA256SUMS 编码无效');
  const indexed = new Map();
  for (const line of sumsSource.slice(0, -1).split('\n')) {
    const match = /^([0-9a-f]{64})  ([A-Za-z0-9._-]+)$/.exec(line);
    if (!match || indexed.has(match[2])) fail('上游 SHA256SUMS 格式无效');
    indexed.set(match[2], match[1]);
  }
  const expectedAssets = upstreamAssets.filter((item) => item !== 'SHA256SUMS');
  if (indexed.size !== expectedAssets.length
      || expectedAssets.some((name) => indexed.get(name) !== sha256(join(download, name)))) {
    fail('上游资产哈希闭集无效');
  }
  const metadata = JSON.parse(readFileSync(join(download, 'tatachatserver-cloudflare-release.json'), 'utf8'));
  const metadataKeys = [
    'artifact', 'ci_artifact', 'files', 'git_commit_sha', 'platform', 'product_id',
    'schema', 'software_version',
  ];
  if (JSON.stringify(Object.keys(metadata).sort()) !== JSON.stringify(metadataKeys)
      || metadata.schema !== 1 || metadata.product_id !== 'tatachatserver'
      || metadata.platform !== 'cloudflare'
      || metadata.artifact !== 'tatachatserver-cloudflare.tar.gz'
      || metadata.ci_artifact !== 'TataChatServer-Cloudflare-CI'
      || !Array.isArray(metadata.files)
      || !metadata.files.includes('build/worker/shim.mjs')
      || !metadata.files.includes('schema.sql')
      || !metadata.files.includes('wrangler.jsonc')
      || !/^[0-9a-f]{40}$/.test(metadata.git_commit_sha)
      || !/^\d+\.\d{1,2}\.\d{1,2}$/.test(metadata.software_version)
      || release.tag_name !== `${upstreamPrefix}${metadata.software_version}`
      || release.target_commitish !== metadata.git_commit_sha
      || release.name !== '塔塔聊天服务 · Release · Cloudflare') {
    fail('上游 Release 产品、源码或版本身份无效');
  }
  return metadata.git_commit_sha;
}
function verifyCandidate(root, sourceSHA) {
  verifyChecksums(root);
  const product = JSON.parse(readFileSync(join(root, 'product.json'), 'utf8'));
  const wrangler = JSON.parse(readFileSync(join(root, 'wrangler.jsonc'), 'utf8'));
  // 中文注释：Cloudflare 是平台闭集中的正式值；产品声明只接受最终七字段合同。
  const productKeys = [
    'platform', 'product_id', 'public_url', 'realtime_url',
    'source_product_id', 'source_repository', 'version',
  ];
  if (JSON.stringify(Object.keys(product).sort()) !== JSON.stringify(productKeys)
      || product.product_id !== 'citizenchatserver' || product.source_product_id !== 'tatachatserver'
      || product.source_repository !== upstreamRepository
      || product.platform !== 'cloudflare'
      || !/^\d+\.\d+\.\d+$/.test(product.version)
      || product.public_url !== 'https://chat.crcfrcn.com'
      || product.realtime_url !== 'wss://chat.crcfrcn.com/realtime') fail('CitizenChatServer 产品声明无效');
  const wranglerKeys = [
    'compatibility_date', 'd1_databases', 'durable_objects', 'exports', 'main', 'name',
    'preview_urls', 'r2_buckets', 'routes', 'triggers', 'vars', 'workers_dev',
  ];
  const variableKeys = [
    'CHATSERVER_ANDROID_APP_ID', 'CHATSERVER_APNS_ALLOWED_TOPICS',
    'CHATSERVER_APNS_SANDBOX', 'CHATSERVER_AUTH_AUDIENCE',
    'CHATSERVER_AUTH_ISSUER', 'CHATSERVER_IOS_APP_ID',
    'CHATSERVER_MAX_ATTACHMENT_BYTES',
  ];
  if (JSON.stringify(Object.keys(wrangler).sort()) !== JSON.stringify(wranglerKeys)
      || JSON.stringify(Object.keys(wrangler.vars ?? {}).sort()) !== JSON.stringify(variableKeys)) {
    fail('CitizenChatServer Wrangler 字段闭集无效');
  }
  if (wrangler.name !== 'citizenchatserver' || wrangler.main !== 'worker/shim.mjs') fail('CitizenChatServer Worker 身份无效');
  if (wrangler.d1_databases?.length !== 1 || wrangler.d1_databases[0].binding !== 'D1'
      || wrangler.d1_databases[0].database_name !== 'citizenchatserver') fail('CitizenChatServer D1 名称无效');
  if (wrangler.r2_buckets?.length !== 1 || wrangler.r2_buckets[0].binding !== 'R2'
      || wrangler.r2_buckets[0].bucket_name !== 'citizenchatserver') fail('CitizenChatServer R2 名称无效');
  if (wrangler.durable_objects?.bindings?.length !== 1
      || wrangler.durable_objects.bindings[0].name !== 'DO'
      || wrangler.durable_objects.bindings[0].class_name !== 'DO'
      || wrangler.exports?.DO?.type !== 'durable-object'
      || wrangler.exports.DO.storage !== 'sqlite') fail('CitizenChatServer Durable Object exports 无效');
  if (wrangler.compatibility_date !== '2026-08-30'
      || wrangler.workers_dev !== false || wrangler.preview_urls !== false
      || JSON.stringify(wrangler.routes) !== JSON.stringify([
        { pattern: 'chat.crcfrcn.com', custom_domain: true },
      ])
      || JSON.stringify(wrangler.triggers) !== JSON.stringify({ crons: ['* * * * *'] })
      || wrangler.vars.CHATSERVER_ANDROID_APP_ID !== 'com.crcfrcn.citizenapp'
      || wrangler.vars.CHATSERVER_APNS_ALLOWED_TOPICS !== 'ios.citizenapp'
      || wrangler.vars.CHATSERVER_APNS_SANDBOX !== 'false'
      || wrangler.vars.CHATSERVER_AUTH_AUDIENCE !== 'citizenchatserver'
      || wrangler.vars.CHATSERVER_AUTH_ISSUER !== 'https://www.crcfrcn.com'
      || wrangler.vars.CHATSERVER_IOS_APP_ID !== 'ios.citizenapp'
      || wrangler.vars.CHATSERVER_MAX_ATTACHMENT_BYTES !== '5368709120') {
    fail('CitizenChatServer 公开配置命名无效');
  }
  const upstream = JSON.parse(readFileSync(join(root, 'upstream-release.json'), 'utf8'));
  const upstreamKeys = [
    'git_commit_sha', 'instance_source_sha', 'product_id', 'release_asset_sha256',
    'release_tag', 'repository',
  ];
  if (JSON.stringify(Object.keys(upstream).sort()) !== JSON.stringify(upstreamKeys)
      || upstream.repository !== upstreamRepository || upstream.product_id !== 'tatachatserver'
      || !/^tatachatserver-cloudflare-v\d+\.\d{1,2}\.\d{1,2}$/.test(upstream.release_tag)
      || !/^[0-9a-f]{40}$/.test(upstream.git_commit_sha)
      || !/^[0-9a-f]{40}$/.test(upstream.instance_source_sha)
      || !/^[0-9a-f]{64}$/.test(upstream.release_asset_sha256)) {
    fail('CitizenChatServer 上游 Release 锚点无效');
  }
  if (sourceSHA && upstream.instance_source_sha !== sourceSHA) fail('CitizenChatServer 候选源码与当前 main 不一致');
  for (const path of ['schema.sql', 'worker/shim.mjs', 'index.js']) {
    if (!existsSync(join(root, path))) fail(`CitizenChatServer 候选缺少 ${path}`);
  }
}
function action(values) {
  const instance = resolve(values.instance ?? '');
  const output = resolve(values.output ?? '');
  const sourceSHA = values['source-sha'] ?? '';
  if (basename(instance) !== 'citizenchatserver' || !/^[0-9a-f]{40}$/.test(sourceSHA)) fail('CitizenChatServer CI 输入无效');
  const repositoryRoot = resolve(instance, '..');
  const outputRelative = relative(repositoryRoot, output);
  if (outputRelative === ''
      || (outputRelative !== '..' && !outputRelative.startsWith(`..${sep}`))) {
    fail('CitizenChatServer CI 输出不得进入源码仓库');
  }
  if (existsSync(output)) fail('CitizenChatServer CI 输出已存在');
  const temporary = mkdtempSync(join(tmpdir(), 'citizenchatserver-ci-'));
  try {
    const { release, assets } = latestFormalRelease();
    const download = join(temporary, 'download');
    mkdirSync(download, { mode: 0o700 });
    for (const name of upstreamAssets) downloadAsset(assets.get(name), join(download, name));
    const upstreamSourceSHA = verifyUpstream(download, release);
    const extracted = join(temporary, 'extracted');
    safeExtract(join(download, 'tatachatserver-cloudflare.tar.gz'), extracted);
    const build = findUnique(extracted, 'build', true);
    mkdirSync(output, { recursive: false, mode: 0o700 });
    cpSync(build, output, { recursive: true, errorOnExist: true });
    cpSync(join(instance, 'scripts', 'product.json'), join(output, 'product.json'), { force: true });
    cpSync(join(instance, 'scripts', 'wrangler.jsonc'), join(output, 'wrangler.jsonc'), { force: true });
    cpSync(findUnique(extracted, 'schema.sql'), join(output, 'schema.sql'), { force: true });
    writeFileSync(join(output, 'upstream-release.json'), `${JSON.stringify({
      repository: upstreamRepository, product_id: 'tatachatserver',
      release_tag: release.tag_name, git_commit_sha: upstreamSourceSHA,
      release_asset_sha256: sha256(join(download, 'tatachatserver-cloudflare.tar.gz')),
      instance_source_sha: sourceSHA,
    }, null, 2)}\n`);
    writeChecksums(output);
    verifyCandidate(output, sourceSHA);
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}

const isMain = process.argv[1]
  && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url));
if (isMain) {
  try {
    const { command, values } = parseArguments(process.argv.slice(2));
    if (command === 'action') action(values);
    else if (command === 'verify') verifyCandidate(resolve(values.candidate ?? ''), values['source-sha']);
    else fail('CitizenChatServer CI 命令无效');
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  }
}
