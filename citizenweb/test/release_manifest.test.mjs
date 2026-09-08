import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { afterEach, test } from 'node:test';
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const projectPath = resolve(import.meta.dirname, '..');
const downloadButtonSource = readFileSync(join(projectPath, 'src', 'components', 'DownloadButton.tsx'), 'utf8');
const ecosystemSource = readFileSync(join(projectPath, 'src', 'pages', 'Ecosystem.tsx'), 'utf8');
const appSource = readFileSync(join(projectPath, 'src', 'App.tsx'), 'utf8');
const privacySource = readFileSync(join(projectPath, 'src', 'pages', 'Privacy.tsx'), 'utf8');
const supportSource = readFileSync(join(projectPath, 'src', 'pages', 'Support.tsx'), 'utf8');
const termsSource = readFileSync(join(projectPath, 'src', 'pages', 'Terms.tsx'), 'utf8');
const gitCommitSha = '1234567890abcdef1234567890abcdef12345678';
const temporaryRoots = [];
const flowRoot = process.env.TATA_CONSOLE_FLOW_ROOT;
if (!flowRoot) throw new Error('缺少 TATA_CONSOLE_FLOW_ROOT');
// TataConsole 重构后每个产品只暴露自己的完整动作入口，测试不得恢复旧共享脚本路径。
const releaseAction = resolve(flowRoot, 'gmb/citizenweb/web/release.mjs');

function runRelease(argumentsList) {
  const result = spawnSync(process.execPath, [releaseAction, 'citizenweb-release', ...argumentsList], {
    cwd: resolve(import.meta.dirname, '../..'),
    encoding: 'utf8',
  });
  if (result.status !== 0) throw new Error((result.stderr || result.stdout).trim());
}

function buildCitizenWebRelease({ projectPath, distPath, outputPath, gitCommitSha, archivePath = null }) {
  const args = ['--project', projectPath, '--dist', distPath, '--output', outputPath, '--git-sha', gitCommitSha];
  if (archivePath) args.push('--archive', archivePath);
  runRelease(args);
  return JSON.parse(readFileSync(join(outputPath, 'release-manifest.json'), 'utf8'));
}

function extractCitizenWebArchive(archivePath, outputPath, expectedGitCommitSha = null) {
  const args = ['--extract', archivePath, '--output', outputPath];
  if (expectedGitCommitSha) args.push('--expected-git-sha', expectedGitCommitSha);
  runRelease(args);
  return JSON.parse(readFileSync(join(outputPath, 'release-manifest.json'), 'utf8'));
}

function verifyCitizenWebRelease(candidatePath, expectedGitCommitSha = null) {
  const args = ['--verify', candidatePath];
  if (expectedGitCommitSha) args.push('--expected-git-sha', expectedGitCommitSha);
  runRelease(args);
  return JSON.parse(readFileSync(join(candidatePath, 'release-manifest.json'), 'utf8'));
}

function writeCitizenWebArchive(candidatePath, archivePath) {
  runRelease(['--verify', candidatePath, '--archive', archivePath]);
}

function sha256File(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

// 中文注释：公开版本标记是已登记候选文件；负向测试修改它时必须同步更新文件清单与
// SHA256SUMS，确保失败真正来自渠道身份合同，而不是更早的通用文件哈希检查。
function rewriteReleaseMarker(candidatePath, mutate) {
  const markerPath = join(candidatePath, 'dist', 'citizenweb-release.json');
  const manifestPath = join(candidatePath, 'release-manifest.json');
  const marker = JSON.parse(readFileSync(markerPath, 'utf8'));
  mutate(marker);
  writeFileSync(markerPath, `${JSON.stringify(marker, null, 2)}\n`);

  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const markerEntry = manifest.files.find(({ path }) => path === 'dist/citizenweb-release.json');
  assert.ok(markerEntry, 'Release manifest 缺少官网公开版本标记');
  markerEntry.sha256 = sha256File(markerPath);
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

  const checksums = [
    ...manifest.files,
    { path: 'release-manifest.json', sha256: sha256File(manifestPath) },
  ].sort((left, right) => left.path.localeCompare(right.path));
  writeFileSync(
    join(candidatePath, 'SHA256SUMS'),
    `${checksums.map(({ sha256, path }) => `${sha256}  ${path}`).join('\n')}\n`,
  );
}

function temporaryRoot() {
  const path = mkdtempSync(join(tmpdir(), 'gmb-citizenweb-release-'));
  temporaryRoots.push(path);
  return path;
}

function fixture(root, name = 'fixture') {
  const path = join(root, name);
  mkdirSync(join(path, 'dist', 'assets'), { recursive: true });
  cpSync(join(projectPath, 'package.json'), join(path, 'package.json'));
  cpSync(join(projectPath, 'package-lock.json'), join(path, 'package-lock.json'));
  writeFileSync(join(path, 'dist', 'index.html'), '<!doctype html><script src="/assets/app.js"></script>\n');
  writeFileSync(join(path, 'dist', 'assets', 'app.js'), 'console.log("citizenweb");\n');
  return path;
}

function build(root, name = 'candidate', source = fixture(root)) {
  const outputPath = join(root, name);
  const archivePath = join(root, `${name}.tgz`);
  const manifest = buildCitizenWebRelease({
    projectPath: source,
    distPath: join(source, 'dist'),
    outputPath,
    gitCommitSha,
    archivePath,
  });
  return { archivePath, manifest, outputPath };
}

afterEach(() => {
  for (const path of temporaryRoots.splice(0)) rmSync(path, { recursive: true, force: true });
});

test('公民链四端下载固定走后端白名单代理，不受 Runtime Release 影响', () => {
  assert.match(downloadButtonSource, /href=\{`\/api\$\{option\.downloadPath\}`\}/);
  const citizenChainDownloads = /name: '公民链'[\s\S]*?downloads: \[([\s\S]*?)\n    \],/.exec(ecosystemSource);
  assert.ok(citizenChainDownloads, '缺少公民链下载项');
  assert.deepEqual(
    citizenChainDownloads[1].trim().split('\n').map((line) => line.trim()),
    [
      "{ label: 'macOS', kind: 'file', downloadPath: '/download/citizenchain/macOS' },",
      "{ label: 'Windows', kind: 'file', downloadPath: '/download/citizenchain/Windows' },",
      "{ label: 'LinuxARM', kind: 'file', downloadPath: '/download/citizenchain/LinuxARM' },",
      "{ label: 'LinuxAMD', kind: 'file', downloadPath: '/download/citizenchain/LinuxAMD' },",
    ],
  );
  assert.doesNotMatch(ecosystemSource, /label: 'Linux-(?:arm|amd)'/);
  for (const oldPath of [
    '/download/citizenchain/macos' + '-arm64',
    '/download/citizenchain/windows-x86_64',
    '/download/citizenchain/linux-arm64',
    '/download/citizenchain/linux-amd64',
    '/download/citizenchain/linux-arm',
    '/download/citizenchain/linux-amd',
  ]) assert.doesNotMatch(ecosystemSource, new RegExp(oldPath));
  assert.doesNotMatch(ecosystemSource, /citizenchain-release|releaseTag:/);
});

test('官网问题渠道仅指向准确GitHub仓库并保护新窗口', () => {
  // 精确解析该链接的属性，拒绝错账号、错仓、明文地址或只在注释中出现的正确字符串。
  const links = [...supportSource.matchAll(/<a\s+([^>]+)>/gu)]
    .map((match) => Object.fromEntries([...match[1].matchAll(/([\w-]+)="([^"]*)"/gu)]
      .map((attribute) => [attribute[1], attribute[2]])));
  assert.equal(links.length, 1);
  assert.equal(links[0].href, 'https://github.com/VoyagerRhett/GMB/issues');
  assert.equal(links[0].target, '_blank');
  assert.ok(links[0].rel.split(/\s+/u).includes('noreferrer'));
});

test('App Store 前置公开页面固定提供用户协议、隐私政策和技术支持路由', () => {
  assert.match(appSource, /path="\/terms" element=\{<Terms \/>\}/);
  assert.match(appSource, /path="\/privacy" element=\{<Privacy \/>\}/);
  assert.match(appSource, /path="\/support" element=\{<Support \/>\}/);
  assert.match(privacySource, /公民钱包是离线冷钱包，不声明网络权限/);
  assert.match(privacySource, /不出售个人数据/);
  assert.match(privacySource, /选择“注销用户”/);
  assert.match(privacySource, /立即硬删除该 CID 在 Cloudflare 中可清除的账户投影/);
  assert.match(privacySource, /链上已经最终确认的 CID 注册、绑定、交易、发布或治理记录/);
  assert.match(supportSource, /禁止附带助记词、私钥、密码、验证码/);
  assert.match(termsSource, /用户保留其合法拥有/);
  assert.match(termsSource, /举报违法、侵权或违反本协议的内容/);
  assert.match(termsSource, /链上已经最终确认的公开记录不能由运营方单方面篡改或删除/);
});

test('相同官网构建与 Git SHA 生成完全一致的候选和归档', () => {
  const root = temporaryRoot();
  const source = fixture(root);
  const first = build(root, 'first', source);
  const second = build(root, 'second', source);

  assert.deepEqual(first.manifest, second.manifest);
  assert.deepEqual(readFileSync(first.archivePath), readFileSync(second.archivePath));
  assert.equal(
    readFileSync(join(first.outputPath, 'release-manifest.json'), 'utf8'),
    readFileSync(join(second.outputPath, 'release-manifest.json'), 'utf8'),
  );
  assert.deepEqual(Object.keys(first.manifest).sort(), [
    'assets_sha256',
    'delivery_channel',
    'files',
    'git_commit_sha',
    'product_id',
    'software_version',
    'tools',
  ]);
  assert.equal(first.manifest.delivery_channel, 'web');
  assert.equal(Object.hasOwn(first.manifest, 'platform'), false);
});

test('官网公开版本标记绑定 Web 交付渠道、软件版本、Git SHA 和全部静态资源摘要', () => {
  const root = temporaryRoot();
  const candidate = build(root);
  const marker = JSON.parse(readFileSync(
    join(candidate.outputPath, 'dist', 'citizenweb-release.json'),
    'utf8',
  ));

  assert.deepEqual(marker, {
    product_id: 'citizenweb',
    delivery_channel: 'web',
    software_version: candidate.manifest.software_version,
    git_commit_sha: gitCommitSha,
    assets_sha256: candidate.manifest.assets_sha256,
  });
  assert.equal(Object.hasOwn(marker, 'platform'), false);
  assert.ok(candidate.manifest.files.some(({ path }) => path === 'dist/assets/app.js'));
});

test('Release manifest 拒绝缺失、错误、旧 platform、双写和额外渠道字段', () => {
  const root = temporaryRoot();
  const cases = [
    ['missing', (manifest) => delete manifest.delivery_channel, /release manifest 字段集合不正确/],
    ['wrong', (manifest) => { manifest.delivery_channel = 'other'; }, /候选交付渠道不正确/],
    ['legacy', (manifest) => {
      delete manifest.delivery_channel;
      manifest.platform = 'web';
    }, /release manifest 字段集合不正确/],
    ['dual', (manifest) => { manifest.platform = 'web'; }, /release manifest 字段集合不正确/],
    ['extra', (manifest) => { manifest.surface = 'web'; }, /release manifest 字段集合不正确/],
  ];

  for (const [name, mutate, expected] of cases) {
    const candidate = build(root, `manifest-${name}`);
    const path = join(candidate.outputPath, 'release-manifest.json');
    const manifest = JSON.parse(readFileSync(path, 'utf8'));
    mutate(manifest);
    writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`);
    assert.throws(() => verifyCitizenWebRelease(candidate.outputPath, gitCommitSha), expected);
  }
});

test('官网公开版本标记拒绝缺失、错误、旧 platform、双写和额外渠道字段', () => {
  const root = temporaryRoot();
  const cases = [
    ['missing', (marker) => delete marker.delivery_channel, /官网版本标记 字段集合不正确/],
    ['wrong', (marker) => { marker.delivery_channel = 'other'; }, /官网版本标记与 Release 候选不一致/],
    ['legacy', (marker) => {
      delete marker.delivery_channel;
      marker.platform = 'web';
    }, /官网版本标记 字段集合不正确/],
    ['dual', (marker) => { marker.platform = 'web'; }, /官网版本标记 字段集合不正确/],
    ['extra', (marker) => { marker.surface = 'web'; }, /官网版本标记 字段集合不正确/],
  ];

  for (const [name, mutate, expected] of cases) {
    const candidate = build(root, `marker-${name}`);
    rewriteReleaseMarker(candidate.outputPath, mutate);
    assert.throws(() => verifyCitizenWebRelease(candidate.outputPath, gitCommitSha), expected);
  }
});

test('官网依赖 Cloudflare Pages 原生 SPA 回退，不发布全局资源改写规则', () => {
  assert.equal(existsSync(join(projectPath, 'public', '_redirects')), false);
});

test('规范归档可安全解包并复核为原候选', () => {
  const root = temporaryRoot();
  const candidate = build(root);
  const output = join(root, 'extracted');
  const manifest = extractCitizenWebArchive(candidate.archivePath, output, gitCommitSha);

  assert.deepEqual(manifest, candidate.manifest);
  assert.deepEqual(
    readFileSync(join(output, 'SHA256SUMS')),
    readFileSync(join(candidate.outputPath, 'SHA256SUMS')),
  );
});

test('文件篡改、未知文件和错误 Git SHA 均失败关闭', () => {
  const root = temporaryRoot();
  const first = build(root, 'tampered');
  assert.throws(
    () => verifyCitizenWebRelease(first.outputPath, '0'.repeat(40)),
    /候选 Git SHA 与期望提交不一致/,
  );
  writeFileSync(join(first.outputPath, 'dist', 'assets', 'app.js'), 'tampered\n');
  assert.throws(() => verifyCitizenWebRelease(first.outputPath, gitCommitSha), /候选文件哈希不一致/);

  const second = build(root, 'unknown', fixture(root, 'unknown-source'));
  writeFileSync(join(second.outputPath, 'dist', 'extra.txt'), 'extra\n');
  assert.throws(() => verifyCitizenWebRelease(second.outputPath, gitCommitSha), /候选包含未登记文件/);
});

test('候选拒绝私钥、符号链接和上一次构建遗留的版本标记', () => {
  const root = temporaryRoot();
  const privateSource = fixture(root, 'private-source');
  writeFileSync(
    join(privateSource, 'dist', 'private.pem'),
    '-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----\n',
  );
  assert.throws(() => buildCitizenWebRelease({
    projectPath: privateSource,
    distPath: join(privateSource, 'dist'),
    outputPath: join(root, 'private-output'),
    gitCommitSha,
  }), /候选包含禁止的本地或密钥文件/);

  const linkSource = fixture(root, 'link-source');
  symlinkSync(join(linkSource, 'dist', 'index.html'), join(linkSource, 'dist', 'linked.html'));
  assert.throws(() => buildCitizenWebRelease({
    projectPath: linkSource,
    distPath: join(linkSource, 'dist'),
    outputPath: join(root, 'link-output'),
    gitCommitSha,
  }), /候选禁止符号链接/);

  const staleSource = fixture(root, 'stale-source');
  writeFileSync(join(staleSource, 'dist', 'citizenweb-release.json'), '{}\n');
  assert.throws(() => buildCitizenWebRelease({
    projectPath: staleSource,
    distPath: join(staleSource, 'dist'),
    outputPath: join(root, 'stale-output'),
    gitCommitSha,
  }), /含上次构建的版本标记/);
});

test('同一候选归档只接受新路径，拒绝覆盖既有文件', () => {
  const root = temporaryRoot();
  const candidate = build(root);
  assert.throws(
    () => writeCitizenWebArchive(candidate.outputPath, candidate.archivePath),
    /Release 归档已存在，拒绝覆盖/,
  );
});
