#!/usr/bin/env node

// 中文注释：单平台 RELEASE_BUILD: full，CARGO_INCREMENTAL=0。Release 只封装准确成功 CI
// 候选，禁止重新下载上游、读取增量缓存或重新构建。
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import {
  cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync,
  readdirSync, rmSync, writeFileSync,
} from 'node:fs';
import { basename, join, relative, resolve, sep } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const repository = 'VoyagerRhett/GMB';
const prefix = 'citizenchatserver-cloudflare-v';
const ciPipeline = 'gmb.citizenchatserver.cloudflare.ci';
const ciTitle = '公民聊天服务 · Cloudflare · CI';

function fail(message) { throw new Error(message); }
function sha256(path) { return createHash('sha256').update(readFileSync(path)).digest('hex'); }
function parseArguments(argv) {
  const command = argv.shift();
  const operation = command === 'version-tag' ? argv.shift() : null;
  const values = {};
  while (argv.length) {
    const key = argv.shift();
    if (!key?.startsWith('--') || !argv.length) fail('CitizenChatServer Release 参数无效');
    values[key.slice(2)] = argv.shift();
  }
  return { command, operation, values };
}
function parseSemanticVersion(value) {
  const match = /^(0|[1-9]\d*)\.(0|[1-9]\d?)\.(0|[1-9]\d?)$/.exec(String(value));
  if (!match) fail(`CitizenChatServer 软件版本无效：${value}`);
  return match.slice(1).map(Number);
}
function compareSemanticVersions(left, right) {
  const a = parseSemanticVersion(left);
  const b = parseSemanticVersion(right);
  for (let index = 0; index < 3; index += 1) {
    if (a[index] !== b[index]) return a[index] - b[index];
  }
  return 0;
}
function nextSemanticVersion(value) {
  let [major, minor, patch] = parseSemanticVersion(value);
  patch += 1;
  if (patch > 99) { patch = 0; minor += 1; }
  if (minor > 99) { minor = 0; major += 1; }
  return `${major}.${minor}.${patch}`;
}
// 中文注释：受控流程只向产品 Release 动作询问下一正式版本；这里仅读取 GitHub
// 正式 Release，不读取或写入本机版本状态，失败重试仍由受控流程锁定原候选。
function printNextSemanticRelease(operation, values) {
  if (operation !== 'next-semantic-release'
      || values.prefix !== prefix
      || Object.keys(values).sort().join(',') !== 'prefix,seed') {
    fail('CitizenChatServer 版本计算参数无效');
  }
  parseSemanticVersion(values.seed);
  const published = [];
  for (let page = 1; page <= 100; page += 1) {
    const releases = JSON.parse(execFileSync('gh', [
      'api', `repos/${repository}/releases?per_page=100&page=${page}`,
    ], { encoding: 'utf8' }));
    if (!Array.isArray(releases)) fail('GitHub Release 列表格式无效');
    for (const release of releases) {
      if (release?.draft === true || release?.prerelease === true) continue;
      const tag = String(release?.tag_name || '');
      if (!tag.startsWith(prefix)) continue;
      const version = tag.slice(prefix.length);
      parseSemanticVersion(version);
      published.push(version);
    }
    if (releases.length < 100) {
      const versions = [...new Set(published)].sort(compareSemanticVersions);
      process.stdout.write(`${versions.length ? nextSemanticVersion(versions.at(-1)) : values.seed}\n`);
      return;
    }
  }
  fail('GitHub Release 列表超过安全分页上限');
}
function regularFiles(root) {
  const rows = [];
  const walk = (directory) => {
    for (const name of readdirSync(directory).sort()) {
      const path = join(directory, name);
      const stat = lstatSync(path);
      if (stat.isSymbolicLink()) fail('Release 候选禁止符号链接');
      if (stat.isDirectory()) walk(path);
      else if (stat.isFile()) rows.push(relative(root, path).split(sep).join('/'));
      else fail('Release 候选包含非常规文件');
    }
  };
  walk(root);
  return rows;
}
function verifyCandidate(root, sourceSHA) {
  const expected = [];
  for (const line of readFileSync(join(root, 'SHA256SUMS'), 'utf8').trim().split('\n')) {
    const match = /^([0-9a-f]{64})  ([^\r\n]+)$/.exec(line);
    if (!match || match[2].split('/').includes('..') || sha256(join(root, match[2])) !== match[1]) fail('CI 候选哈希闭集无效');
    expected.push(match[2]);
  }
  const actual = regularFiles(root).filter((path) => path !== 'SHA256SUMS');
  if (JSON.stringify(actual) !== JSON.stringify([...expected].sort())) fail('CI 候选文件闭集无效');
  const product = JSON.parse(readFileSync(join(root, 'product.json'), 'utf8'));
  const productKeys = [
    'platform', 'product_id', 'public_url', 'realtime_url', 'source_product_id',
    'source_repository', 'version',
  ];
  const upstream = JSON.parse(readFileSync(join(root, 'upstream-release.json'), 'utf8'));
  const upstreamKeys = [
    'git_commit_sha', 'instance_source_sha', 'product_id', 'release_asset_sha256',
    'release_tag', 'repository',
  ];
  if (JSON.stringify(Object.keys(product).sort()) !== JSON.stringify(productKeys)
      || product.product_id !== 'citizenchatserver' || product.platform !== 'cloudflare'
      || product.source_repository !== 'VoyagerRhett/TATA'
      || product.source_product_id !== 'tatachatserver'
      || product.public_url !== 'https://chat.crcfrcn.com'
      || product.realtime_url !== 'wss://chat.crcfrcn.com/realtime'
      || JSON.stringify(Object.keys(upstream).sort()) !== JSON.stringify(upstreamKeys)
      || upstream.instance_source_sha !== sourceSHA || upstream.repository !== 'VoyagerRhett/TATA'
      || upstream.product_id !== 'tatachatserver'
      || !/^tatachatserver-cloudflare-v\d+\.\d{1,2}\.\d{1,2}$/.test(upstream.release_tag)
      || !/^[0-9a-f]{40}$/.test(upstream.git_commit_sha)
      || !/^[0-9a-f]{64}$/.test(upstream.release_asset_sha256)) {
    fail('CI 候选产品、上游或当前源码锚点无效');
  }
}
function verifyReleaseSource(values) {
  const ciRunID = values['ci-run-id'];
  const sourceSHA = values['source-sha'];
  const softwareVersion = values['software-version'];
  const versionTag = values['version-tag'];
  if (!/^[1-9][0-9]*$/.test(ciRunID ?? '') || !/^[0-9a-f]{40}$/.test(sourceSHA ?? '')
      || !/^\d+\.\d+\.\d+$/.test(softwareVersion ?? '') || versionTag !== `${prefix}${softwareVersion}`) fail('Release 身份输入无效');
  const run = JSON.parse(execFileSync('gh', ['api', `repos/${repository}/actions/runs/${ciRunID}`], { encoding: 'utf8' }));
  if (!isExactSuccessfulCIRun(run, sourceSHA)) {
    fail('Release 没有绑定准确成功 CI');
  }
  const artifacts = JSON.parse(execFileSync('gh', ['api', `repos/${repository}/actions/runs/${ciRunID}/artifacts`], { encoding: 'utf8' }));
  const matches = (artifacts.artifacts ?? []).filter((item) => item.name === 'CitizenChatServer-Cloudflare-CI' && !item.expired);
  if (matches.length !== 1) fail('成功 CI 缺少唯一 CitizenChatServer 候选');
}

export function isExactSuccessfulCIRun(run, sourceSHA) {
  return run?.status === 'completed' && run.conclusion === 'success'
      && run.event === 'workflow_dispatch' && run.head_branch === 'main'
      && run.head_sha === sourceSHA && String(run.path || '').endsWith('/repository.yml')
      && String(run.display_title || '') === ciTitle;
}

function checksumMap(path) {
  const values = new Map();
  const source = readFileSync(path, 'utf8');
  if (!source.endsWith('\n') || source.includes('\r')) fail('Release SHA256SUMS 编码无效');
  for (const line of source.slice(0, -1).split('\n')) {
    const match = /^([0-9a-f]{64})  ([A-Za-z0-9._/-]+)$/.exec(line);
    if (!match || match[2].startsWith('/') || match[2].split('/').includes('..')
        || values.has(match[2])) fail('Release SHA256SUMS 格式无效');
    values.set(match[2], match[1]);
  }
  return values;
}

function assertChecksumClosure(actual, expected, label) {
  if (actual.size !== expected.size) fail(`${label} 文件闭集无效`);
  for (const [path, hash] of expected) {
    if (actual.get(path) !== hash) fail(`${label} 哈希无效：${path}`);
  }
}

/// 正式三件套的 manifest 与外部 SHA256SUMS 位于归档外，避免把归档自身哈希写入归档形成
/// 不可解的自引用。归档内只保存候选和候选自己的 SHA256SUMS，两层闭集分别验真。
export function verifyPackagedRelease({ archive, manifestPath, sumsPath }) {
  for (const path of [archive, manifestPath, sumsPath]) {
    if (!existsSync(path) || !lstatSync(path).isFile() || lstatSync(path).isSymbolicLink()) {
      fail('CitizenChatServer Release 三件套缺失或类型无效');
    }
  }
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const manifestKeys = [
    'archive_sha256', 'files', 'git_commit_sha', 'platform', 'product_id', 'schema',
    'software_version', 'upstream_git_commit_sha', 'upstream_product_id',
    'upstream_release_tag', 'upstream_repository',
  ];
  const archiveSHA256 = sha256(archive);
  if (JSON.stringify(Object.keys(manifest).sort()) !== JSON.stringify(manifestKeys)
      || manifest.schema !== 1 || manifest.product_id !== 'citizenchatserver'
      || manifest.platform !== 'cloudflare'
      || !/^\d+\.\d+\.\d+$/.test(manifest.software_version)
      || !/^[0-9a-f]{40}$/.test(manifest.git_commit_sha)
      || manifest.upstream_repository !== 'VoyagerRhett/TATA'
      || manifest.upstream_product_id !== 'tatachatserver'
      || !/^tatachatserver-cloudflare-v\d+\.\d+\.\d+$/.test(manifest.upstream_release_tag)
      || !/^[0-9a-f]{40}$/.test(manifest.upstream_git_commit_sha)
      || manifest.archive_sha256 !== archiveSHA256
      || !Array.isArray(manifest.files) || !manifest.files.length) {
    fail('CitizenChatServer Release manifest 无效');
  }
  assertChecksumClosure(checksumMap(sumsPath), new Map([
    [basename(archive), archiveSHA256],
    ['release-manifest.json', sha256(manifestPath)],
  ]), 'Release 外部 SHA256SUMS');

  const rows = execFileSync('tar', ['-tzf', archive], { encoding: 'utf8' })
    .trim().split('\n').filter(Boolean);
  const detailRows = execFileSync('tar', ['-tvzf', archive], { encoding: 'utf8' })
    .trim().split('\n').filter(Boolean);
  if (!rows.length || rows.some((path) => path.startsWith('/') || path.split('/').includes('..'))
      || detailRows.length !== rows.length || detailRows.some((line) => line[0] !== '-')) {
    fail('CitizenChatServer Release 归档路径或文件类型无效');
  }
  const temporary = mkdtempSync(join(tmpdir(), 'citizenchatserver-release-verify-'));
  try {
    const extracted = join(temporary, 'candidate');
    mkdirSync(extracted, { mode: 0o700 });
    execFileSync('tar', ['-xzf', archive, '-C', extracted]);
    const files = new Map();
    for (const entry of manifest.files) {
      if (JSON.stringify(Object.keys(entry).sort()) !== JSON.stringify(['path', 'sha256'])
          || typeof entry.path !== 'string' || typeof entry.sha256 !== 'string'
          || entry.path.startsWith('/') || entry.path.split('/').includes('..')
          || !/^[A-Za-z0-9._/-]+$/.test(entry.path) || !/^[0-9a-f]{64}$/.test(entry.sha256)
          || files.has(entry.path) || sha256(join(extracted, entry.path)) !== entry.sha256) {
        fail('CitizenChatServer Release 文件清单无效');
      }
      files.set(entry.path, entry.sha256);
    }
    if (JSON.stringify([...files.keys()]) !== JSON.stringify([...files.keys()].sort())
        || JSON.stringify(regularFiles(extracted)) !== JSON.stringify([...files.keys()].sort())
        || !files.has('SHA256SUMS')) fail('CitizenChatServer Release 归档文件闭集无效');
    const payload = new Map(files);
    payload.delete('SHA256SUMS');
    assertChecksumClosure(
      checksumMap(join(extracted, 'SHA256SUMS')), payload, '候选内部 SHA256SUMS',
    );
    const product = JSON.parse(readFileSync(join(extracted, 'product.json'), 'utf8'));
    const productKeys = [
      'platform', 'product_id', 'public_url', 'realtime_url', 'source_product_id',
      'source_repository', 'version',
    ];
    const upstream = JSON.parse(readFileSync(join(extracted, 'upstream-release.json'), 'utf8'));
    const upstreamKeys = [
      'git_commit_sha', 'instance_source_sha', 'product_id', 'release_asset_sha256',
      'release_tag', 'repository',
    ];
    if (JSON.stringify(Object.keys(product).sort()) !== JSON.stringify(productKeys)
        || product.product_id !== manifest.product_id || product.platform !== manifest.platform
        || product.version !== manifest.software_version
        || product.source_repository !== manifest.upstream_repository
        || product.source_product_id !== manifest.upstream_product_id
        || product.public_url !== 'https://chat.crcfrcn.com'
        || product.realtime_url !== 'wss://chat.crcfrcn.com/realtime'
        || JSON.stringify(Object.keys(upstream).sort()) !== JSON.stringify(upstreamKeys)
        || upstream.repository !== manifest.upstream_repository
        || upstream.product_id !== manifest.upstream_product_id
        || upstream.release_tag !== manifest.upstream_release_tag
        || upstream.git_commit_sha !== manifest.upstream_git_commit_sha
        || upstream.instance_source_sha !== manifest.git_commit_sha
        || !/^[0-9a-f]{64}$/.test(upstream.release_asset_sha256)) {
      fail('CitizenChatServer Release 内外身份不一致');
    }
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
  return manifest;
}

/// 只负责从准确 CI 候选生成可离线验证的正式三件套；GitHub 正式分发仍只由 action() 执行。
export function packageRelease(values) {
  const candidate = resolve(values.candidate ?? '');
  const output = resolve(values.output ?? '');
  const sourceSHA = values['source-sha'];
  const softwareVersion = values['software-version'];
  const versionTag = values['version-tag'];
  if (!existsSync(candidate) || existsSync(output) || !/^[0-9a-f]{40}$/.test(sourceSHA ?? '')
      || !/^\d+\.\d+\.\d+$/.test(softwareVersion ?? '') || versionTag !== `${prefix}${softwareVersion}`) fail('Release 封装输入无效');
  const outputFromCandidate = relative(candidate, output);
  const candidateFromOutput = relative(output, candidate);
  const inside = (value) => value === '' || (value !== '..' && !value.startsWith(`..${sep}`));
  if (inside(outputFromCandidate) || inside(candidateFromOutput)) fail('Release 候选与输出目录不得重叠');
  verifyCandidate(candidate, sourceSHA);
  const temporary = mkdtempSync(join(tmpdir(), 'citizenchatserver-release-'));
  try {
    const stage = join(temporary, 'stage');
    cpSync(candidate, stage, { recursive: true, errorOnExist: true });
    const productPath = join(stage, 'product.json');
    const product = JSON.parse(readFileSync(productPath, 'utf8'));
    product.version = softwareVersion;
    writeFileSync(productPath, `${JSON.stringify(product, null, 2)}\n`);
    const checksumFiles = regularFiles(stage).filter((path) => path !== 'SHA256SUMS');
    writeFileSync(join(stage, 'SHA256SUMS'), `${checksumFiles.map((path) => `${sha256(join(stage, path))}  ${path}`).join('\n')}\n`);
    mkdirSync(output, { mode: 0o700 });
    const archive = join(output, 'citizenchatserver-cloudflare.tar.gz');
    const archiveFiles = regularFiles(stage);
    if (!archiveFiles.length || archiveFiles.some((path) => (
      path.startsWith('/') || path.split('/').includes('..') || !/^[A-Za-z0-9._/-]+$/.test(path)
    ))) fail('CitizenChatServer Release 归档文件名无效');
    // 中文注释：NUL 文件清单只加入普通文件；--no-recursion 防止 tar 自动写入目录条目，
    // 与原生发布器“每个 tar 条目首字符必须为 -”的安全合同逐项一致。
    const archiveList = join(temporary, 'archive-files.list');
    writeFileSync(archiveList, Buffer.from(`${archiveFiles.join('\0')}\0`));
    execFileSync('tar', [
      '-czf', archive, '-C', stage, '--no-recursion', '--null', '-T', archiveList,
    ]);
    const upstream = JSON.parse(readFileSync(join(stage, 'upstream-release.json'), 'utf8'));
    // 中文注释：正式 manifest 使用平台闭集中的 Cloudflare；作业 ID、Tag 前缀与
    // 资产名继续由同一 Release 合同固定。
    const manifest = {
      schema: 1, product_id: 'citizenchatserver', platform: 'cloudflare',
      software_version: softwareVersion, git_commit_sha: sourceSHA,
      upstream_repository: upstream.repository, upstream_product_id: upstream.product_id,
      upstream_release_tag: upstream.release_tag, upstream_git_commit_sha: upstream.git_commit_sha,
      archive_sha256: sha256(archive),
      files: archiveFiles.map((path) => ({ path, sha256: sha256(join(stage, path)) })),
    };
    const manifestPath = join(output, 'release-manifest.json');
    writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    const sumsPath = join(output, 'SHA256SUMS');
    writeFileSync(sumsPath, `${sha256(archive)}  citizenchatserver-cloudflare.tar.gz\n${sha256(manifestPath)}  release-manifest.json\n`);
    verifyPackagedRelease({ archive, manifestPath, sumsPath });
    return { archive, manifestPath, sumsPath };
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}

function action(values) {
  const sourceSHA = values['source-sha'];
  const softwareVersion = values['software-version'];
  const versionTag = values['version-tag'];
  const { archive, manifestPath, sumsPath } = packageRelease(values);
  let exists = true;
  try { execFileSync('gh', ['release', 'view', versionTag, '--repo', repository], { stdio: 'ignore' }); }
  catch { exists = false; }
  if (exists) fail('同名 CitizenChatServer 正式 Release 已存在');
  execFileSync('gh', [
    'release', 'create', versionTag, archive, manifestPath, sumsPath,
    '--repo', repository, '--target', sourceSHA, '--title', `CitizenChatServer ${softwareVersion}`,
    '--notes', `GMB_RELEASE_SOURCE_SHA:${sourceSHA}`,
  ], { stdio: 'inherit' });
}

const isMain = process.argv[1]
  && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url));
if (isMain) {
  try {
    const { command, operation, values } = parseArguments(process.argv.slice(2));
    if (command === 'version-tag') printNextSemanticRelease(operation, values);
    else if (command === 'verify-release-source') verifyReleaseSource(values);
    else if (command === 'action') action(values);
    else fail('CitizenChatServer Release 命令无效');
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  }
}
