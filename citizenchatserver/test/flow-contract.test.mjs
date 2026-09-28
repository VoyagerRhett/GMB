import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  isExactSuccessfulCIRun, packageRelease, verifyPackagedRelease,
} from '../scripts/release/index.mjs';
import { verifyCandidate } from '../scripts/ci/index.mjs';

const root = new URL('../scripts/', import.meta.url);
const instanceRoot = fileURLToPath(new URL('../', import.meta.url));
const text = (path) => readFileSync(new URL(path, root), 'utf8');
const ciPath = fileURLToPath(new URL('ci/index.mjs', root));
const sourceSHA = '0123456789abcdef0123456789abcdef01234567';

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function regularFiles(rootPath) {
  const files = [];
  const walk = (directory) => {
    for (const name of readdirSync(directory).sort()) {
      const path = join(directory, name);
      const stat = lstatSync(path);
      assert.equal(stat.isSymbolicLink(), false);
      if (stat.isDirectory()) walk(path);
      else if (stat.isFile()) files.push(relative(rootPath, path).split(sep).join('/'));
    }
  };
  walk(rootPath);
  return files;
}

function createCandidate(identity, wranglerIdentity = {}) {
  const candidate = mkdtempSync(join(tmpdir(), 'citizenchatserver-flow-contract-'));
  const product = {
    product_id: 'citizenchatserver',
    version: '1.0.0',
    source_repository: 'VoyagerRhett/TATA',
    source_product_id: 'tatachatserver',
    public_url: 'https://chat.crcfrcn.com',
    realtime_url: 'wss://chat.crcfrcn.com/realtime',
    ...identity,
  };
  const wrangler = {
    name: 'citizenchatserver',
    main: 'worker/shim.mjs',
    compatibility_date: '2026-08-30',
    workers_dev: false,
    preview_urls: false,
    routes: [{ pattern: 'chat.crcfrcn.com', custom_domain: true }],
    d1_databases: [{ binding: 'D1', database_name: 'citizenchatserver' }],
    r2_buckets: [{ binding: 'R2', bucket_name: 'citizenchatserver' }],
    durable_objects: { bindings: [{ name: 'DO', class_name: 'DO' }] },
    exports: { DO: { type: 'durable-object', storage: 'sqlite' } },
    triggers: { crons: ['* * * * *'] },
    vars: {
      CHATSERVER_IOS_APP_ID: 'ios.citizenapp',
      CHATSERVER_ANDROID_APP_ID: 'com.crcfrcn.citizenapp',
      CHATSERVER_AUTH_ISSUER: 'https://www.crcfrcn.com',
      CHATSERVER_AUTH_AUDIENCE: 'citizenchatserver',
      CHATSERVER_MAX_ATTACHMENT_BYTES: '5368709120',
      CHATSERVER_APNS_ALLOWED_TOPICS: 'ios.citizenapp',
      CHATSERVER_APNS_SANDBOX: 'false',
    },
    ...wranglerIdentity,
  };
  writeFileSync(join(candidate, 'product.json'), `${JSON.stringify(product)}\n`);
  writeFileSync(join(candidate, 'wrangler.jsonc'), `${JSON.stringify(wrangler)}\n`);
  writeFileSync(join(candidate, 'source-sha.txt'), sourceSHA + '\n');
  const files = regularFiles(candidate);
  writeFileSync(join(candidate, 'SHA256SUMS'), `${files.map((path) => (
    `${sha256(join(candidate, path))}  ${path}`
  )).join('\n')}\n`);
  return candidate;
}

// 中文注释：用最小但完整的 CI 候选执行真实 verify 命令，使产品声明的正常、缺失
// 与额外字段边界都经过候选哈希闭集，而不是只检查容易漂移的源码字符串。
function verifyProductIdentity(identity, wranglerIdentity = {}) {
  const candidate = createCandidate(identity, wranglerIdentity);
  try {
    return spawnSync(process.execPath, [
      ciPath, 'verify', '--candidate', candidate, '--source-sha', sourceSHA,
    ], { encoding: 'utf8' });
  } finally {
    rmSync(candidate, { recursive: true, force: true });
  }
}

test('CitizenChatServer 是独立 GMB Cloudflare 产品', () => {
  const product = JSON.parse(text('product.json'));
  assert.equal(product.product_id, 'citizenchatserver');
  assert.equal(product.platform, 'cloudflare');
});

// 中文注释：执行真实 CLI，清空 PATH 且不传入任何 GitHub 认证环境，证明配置 CI 不调用取包工具。
test('CI 无凭据、无外部工具即可生成并回读本仓四文件候选', () => {
  const temporary = mkdtempSync(join(tmpdir(), 'citizenchatserver-ci-run-'));
  const output = join(temporary, 'candidate');
  const args = [ciPath, 'action', '--instance', instanceRoot, '--output', output, '--source-sha', sourceSHA];
  const options = { encoding: 'utf8', env: { PATH: '', TMPDIR: temporary } };
  try {
    const result = spawnSync(process.execPath, args, options);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(readdirSync(output).sort(), ['SHA256SUMS', 'product.json', 'source-sha.txt', 'wrangler.jsonc']);
    for (const path of ['product.json', 'wrangler.jsonc']) {
      assert.deepEqual(readFileSync(join(output, path)), readFileSync(join(instanceRoot, 'scripts', path)));
    }
    assert.equal(readFileSync(join(output, 'source-sha.txt'), 'utf8'), sourceSHA + '\n');
    const verify = spawnSync(process.execPath, [ciPath, 'verify', '--candidate', output, '--source-sha', sourceSHA], options);
    assert.equal(verify.status, 0, verify.stderr);
    const repeat = spawnSync(process.execPath, args, options);
    assert.notEqual(repeat.status, 0);
    assert.match(repeat.stderr, /输出已存在/u);
    verifyCandidate(output, sourceSHA);
    const packaged = packageRelease({
      candidate: output, output: join(temporary, 'release'), 'source-sha': sourceSHA,
      'software-version': '1.0.0', 'version-tag': 'citizenchatserver-cloudflare-v1.0.0', 'ci-run-id': '1',
    });
    const manifest = verifyPackagedRelease(packaged);
    assert.deepEqual(manifest.files.map((file) => file.path), ['product.json', 'source-sha.txt', 'wrangler.jsonc']);
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
});

test('CI 拒绝篡改、来源冲突、额外文件与符号链接候选', () => {
  for (const change of [
    (root) => writeFileSync(join(root, 'product.json'), '{}\n'),
    (root) => writeFileSync(join(root, 'source-sha.txt'), 'f'.repeat(40) + '\n'),
    (root) => writeFileSync(join(root, 'unexpected'), 'fixture'),
    (root) => { rmSync(join(root, 'wrangler.jsonc')); symlinkSync(join(instanceRoot, 'scripts', 'wrangler.jsonc'), join(root, 'wrangler.jsonc')); },
  ]) {
    const candidate = createCandidate({ platform: 'cloudflare' });
    try {
      change(candidate);
      assert.throws(() => verifyCandidate(candidate, sourceSHA));
    } finally { rmSync(candidate, { recursive: true, force: true }); }
  }
  const candidate = createCandidate({ platform: 'cloudflare' });
  try {
    assert.throws(() => verifyCandidate(candidate, 'f'.repeat(40)), /源码与当前 main 不一致/u);
    for (const value of [undefined, '', 'invalid']) assert.throws(() => verifyCandidate(candidate, value), /来源 SHA 无效/u);
  } finally { rmSync(candidate, { recursive: true, force: true }); }
});

test('CI action 拒绝错误配置、输入链接、源码内输出与未知阶段', () => {
  const temporary = mkdtempSync(join(tmpdir(), 'citizenchatserver-ci-errors-'));
  const fixture = join(temporary, 'repository', 'citizenchatserver');
  const scripts = join(fixture, 'scripts');
  const output = join(temporary, 'candidate');
  const run = (instance, destination, sha = sourceSHA) => spawnSync(process.execPath, [
    ciPath, 'action', '--instance', instance, '--output', destination, '--source-sha', sha,
  ], { encoding: 'utf8', env: { PATH: '', TMPDIR: temporary } });
  try {
    mkdirSync(scripts, { recursive: true });
    writeFileSync(join(scripts, 'product.json'), '{}\n');
    writeFileSync(join(scripts, 'wrangler.jsonc'), text('wrangler.jsonc'));
    assert.notEqual(run(fixture, output).status, 0);
    assert.equal(existsSync(output), false);
    rmSync(join(scripts, 'product.json'));
    symlinkSync(join(instanceRoot, 'scripts', 'product.json'), join(scripts, 'product.json'));
    assert.match(run(fixture, output).stderr, /只允许普通文件/u);
    assert.equal(existsSync(output), false);
    const linkedParent = join(temporary, 'source-link');
    symlinkSync(instanceRoot, linkedParent);
    assert.match(run(instanceRoot, join(linkedParent, 'candidate-output')).stderr, /不得进入源码仓库/u);
    assert.match(run(instanceRoot, output, 'invalid').stderr, /CI 输入无效/u);
    const obsoleteStep = spawnSync(process.execPath, [
      fileURLToPath(new URL('ci/check/execute.mjs', root)), 'workflow-step', '1',
    ], { encoding: 'utf8', env: { PATH: '', GITHUB_REPOSITORY: 'VoyagerRhett/GMB' } });
    assert.notEqual(obsoleteStep.status, 0);
    assert.match(obsoleteStep.stderr, /阶段无效/u);
  } finally { rmSync(temporary, { recursive: true, force: true }); }
});

// 中文注释：远端只发布本仓配置，任何服务程序装配或跨仓读取都会破坏产品边界。
test('CI 与 Release 只处理本仓配置，保留自身正式版本计算', () => {
  const ci = text('ci/index.mjs');
  const release = text('release/index.mjs');
  assert.doesNotMatch(ci, /child_process|fetch\(|GH_TOKEN|GITHUB_TOKEN/u);
  assert.doesNotMatch(release, /upstream-release[.]json|selectLatestFormalRelease|verifyUpstream|tatachatserver-cloudflare|wrangler deploy/u);
  assert.match(release, /CitizenChatServer-Cloudflare-CI/u);
  assert.match(release, /next-semantic-release/u);
});

test('Release 来源只接受本仓 main 的准确成功 CI', () => {
  const run = {
    status: 'completed',
    conclusion: 'success',
    event: 'workflow_dispatch',
    head_branch: 'main',
    head_sha: sourceSHA,
    path: '.github/workflows/citizenchatserver-cloudflare-ci.yml',
    display_title: '公民聊天服务 · Cloudflare · CI',
  };
  assert.equal(isExactSuccessfulCIRun(run, sourceSHA), true);
  for (const patch of [
    { conclusion: 'failure' },
    { event: 'push' },
    { head_branch: 'feature' },
    { head_sha: 'f'.repeat(40) },
    { path: '.github/workflows/other.yml' },
    { display_title: 'gmb.citizenchatserver.cloudflare.ci' },
  ]) {
    assert.equal(isExactSuccessfulCIRun({ ...run, ...patch }, sourceSHA), false);
  }
});

test('产品声明只接受 Cloudflare 平台与精确七字段闭集', () => {
  const accepted = verifyProductIdentity({ platform: 'cloudflare' });
  assert.equal(accepted.status, 0, accepted.stderr);

  const extra = verifyProductIdentity({
    platform: 'cloudflare', unexpected: true,
  });
  assert.notEqual(extra.status, 0);
  assert.match(extra.stderr, /产品声明无效/);

  const missing = verifyProductIdentity({
    platform: 'cloudflare', public_url: undefined,
  });
  assert.notEqual(missing.status, 0);
  assert.match(missing.stderr, /产品声明无效/);
});

test('CI 与 Release 拒绝把生成内容写回产品输入目录', () => {
  const ciOutput = join(instanceRoot, 'candidate-output');
  const ci = spawnSync(process.execPath, [
    ciPath, 'action', '--instance', instanceRoot, '--output', ciOutput,
    '--source-sha', sourceSHA,
  ], { encoding: 'utf8' });
  assert.notEqual(ci.status, 0);
  assert.match(ci.stderr, /不得进入源码仓库/);

  const candidate = createCandidate({ platform: 'cloudflare' });
  try {
    assert.throws(() => packageRelease({
      candidate,
      output: join(candidate, 'release-output'),
      'source-sha': sourceSHA,
      'software-version': '1.0.0',
      'version-tag': 'citizenchatserver-cloudflare-v1.0.0',
      'ci-run-id': '1',
    }), /不得重叠/);
  } finally {
    rmSync(candidate, { recursive: true, force: true });
  }
});

test('CI 拒绝资源与配置闭集外的值', () => {
  const product = { platform: 'cloudflare' };
  for (const wrangler of [
    { name: 'other-worker' },
    { d1_databases: [{ binding: 'D1', database_name: 'other-database' }] },
    { r2_buckets: [{ binding: 'R2', bucket_name: 'other-bucket' }] },
    { d1_databases: [{ binding: 'D1', database_name: 'citizenchatserver', database_id: 'fixture-only' }] },
    { r2_buckets: [{ binding: 'R2', bucket_name: 'citizenchatserver', extra: true }] },
    { exports: { DO: { type: 'durable-object', storage: 'sqlite' }, Extra: { type: 'durable-object', storage: 'sqlite' } } },
    {
      durable_objects: { bindings: [{ name: 'DX', class_name: 'DX' }] },
      exports: { DX: { type: 'durable-object', storage: 'sqlite' } },
    },
    { vars: { CHATSERVER_AUTH_AUDIENCE: 'other-audience' } },
  ]) {
    const rejected = verifyProductIdentity(product, wrangler);
    assert.notEqual(rejected.status, 0);
  }
});

test('配置 Release 拒绝额外程序、来源漂移及链接输出边界', () => {
  const candidate = createCandidate({ platform: 'cloudflare' });
  const temporary = mkdtempSync(join(tmpdir(), 'citizenchatserver-release-reject-'));
  const output = join(temporary, 'release');
  const values = { candidate, output, 'source-sha': sourceSHA, 'software-version': '1.0.1',
    'version-tag': 'citizenchatserver-cloudflare-v1.0.1', 'ci-run-id': '1' };
  try {
    assert.throws(() => packageRelease({ ...values, 'source-sha': 'f'.repeat(40) }));
    assert.equal(existsSync(output), false);
    writeFileSync(join(candidate, 'index.js'), 'export {};');
    assert.throws(() => packageRelease(values), /四文件闭集/u);
    assert.equal(existsSync(output), false);
    rmSync(join(candidate, 'index.js'));
    const link = join(temporary, 'source-link');
    symlinkSync(instanceRoot, link);
    assert.throws(() => packageRelease({ ...values, output: join(link, 'release-output') }), /不得进入源码仓库/u);
    const paths = packageRelease(values);
    assert.equal(verifyPackagedRelease(paths).software_version, '1.0.1');
    assert.throws(() => packageRelease(values), /封装输入无效/u);
    assert.equal(verifyPackagedRelease(paths).software_version, '1.0.1');
  } finally {
    rmSync(candidate, { recursive: true, force: true });
    rmSync(temporary, { recursive: true, force: true });
  }
});

test('正式 Release manifest 只输出 Cloudflare 平台字段', () => {
  const release = text('release/index.mjs');
  assert.match(release, /product_id: 'citizenchatserver', platform: 'cloudflare'/);
});

test('正式 Release 只产出一个自描述归档', () => {
  const candidate = createCandidate({ platform: 'cloudflare' });
  const temporary = mkdtempSync(join(tmpdir(), 'citizenchatserver-release-contract-'));
  const output = join(temporary, 'release');
  try {
    const paths = packageRelease({
      candidate,
      output,
      'source-sha': sourceSHA,
      'software-version': '1.0.0',
      'version-tag': 'citizenchatserver-cloudflare-v1.0.0',
      'ci-run-id': '1',
    });
    const extracted = join(temporary, 'extracted');
    mkdirSync(extracted);
    const archiveEntries = execFileSync('tar', ['-tvzf', paths.archive], { encoding: 'utf8' })
      .trim().split('\n').filter(Boolean);
    assert.ok(archiveEntries.length > 0);
    assert.ok(archiveEntries.every((line) => line[0] === '-'));
    execFileSync('tar', ['-xzf', paths.archive, '-C', extracted]);
    const manifestPath = join(extracted, 'release-manifest.json');
    const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
    assert.equal(manifest.platform, 'cloudflare');
    assert.equal(manifest.ci_run_id, 1);
    assert.deepEqual(manifest.files.map((entry) => entry.path), ['product.json', 'source-sha.txt', 'wrangler.jsonc']);
    assert.deepEqual(Object.keys(manifest).sort(), ['ci_run_id', 'files', 'git_commit_sha', 'platform', 'product_id', 'schema', 'software_version']);
    assert.equal(verifyPackagedRelease(paths).git_commit_sha, sourceSHA);
    assert.equal(regularFiles(extracted).includes('release-manifest.json'), true);
    assert.equal(regularFiles(extracted).includes('SHA256SUMS'), true);
    assert.deepEqual(
      regularFiles(extracted), [...manifest.files.map(({ path }) => path), 'release-manifest.json', 'SHA256SUMS'].sort(),
    );
    for (const entry of manifest.files) {
      assert.equal(sha256(join(extracted, entry.path)), entry.sha256);
    }

    writeFileSync(paths.archive, 'changed');
    assert.throws(() => verifyPackagedRelease(paths), /归档|格式|文件类型/);
  } finally {
    rmSync(candidate, { recursive: true, force: true });
    rmSync(temporary, { recursive: true, force: true });
  }
});

test('数据字典把 Cloudflare 固定为唯一发布平台', () => {
  const product = JSON.parse(text('product.json'));
  assert.equal(product.platform, 'cloudflare');
});

test('流程不引入 GitHub 产品子工作流或非加密协议', () => {
  for (const path of ['product.json', 'ci/index.mjs', 'release/index.mjs']) {
    const source = text(path);
    assert.doesNotMatch(source, /\.github\/workflows\/citizenchatserver/);
    assert.doesNotMatch(source, /(?<!s)http:\/\//);
    assert.doesNotMatch(source, /(?<!s)ws:\/\//);
    assert.doesNotMatch(source, /\/v1(?:\/|\b)/);
  }
});

test('CitizenChatServer 独立 Workflow 只调用本产品扁平流程入口', () => {
  const workflow = ['citizenchatserver-cloudflare-ci.yml', 'citizenchatserver-cloudflare-release.yml']
    .map((name) => readFileSync(join(instanceRoot, '..', '.github', 'workflows', name), 'utf8'))
    .join('\n');
  const paths = workflow.match(
    /citizenchatserver\/scripts\/(?:ci|release)\/[A-Za-z0-9./_-]+\.mjs/g,
  ) ?? [];
  assert.deepEqual(paths, [
    'citizenchatserver/scripts/ci/check/execute.mjs',
    'citizenchatserver/scripts/release/package/execute.mjs',
    'citizenchatserver/scripts/release/package/execute.mjs',
    'citizenchatserver/scripts/release/package/execute.mjs',
    'citizenchatserver/scripts/release/package/execute.mjs',
  ]);
});
