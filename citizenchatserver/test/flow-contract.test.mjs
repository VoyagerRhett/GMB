import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  isExactSuccessfulCIRun, packageRelease, verifyPackagedRelease,
} from '../scripts/release/index.mjs';
import { verifyUpstream } from '../scripts/ci/index.mjs';

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
  mkdirSync(join(candidate, 'worker'));
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
  const upstream = {
    repository: 'VoyagerRhett/TATA',
    product_id: 'tatachatserver',
    release_tag: 'tatachatserver-cloudflare-v1.0.0',
    git_commit_sha: '89abcdef0123456789abcdef0123456789abcdef',
    release_asset_sha256: 'a'.repeat(64),
    instance_source_sha: sourceSHA,
  };
  writeFileSync(join(candidate, 'product.json'), `${JSON.stringify(product)}\n`);
  writeFileSync(join(candidate, 'wrangler.jsonc'), `${JSON.stringify(wrangler)}\n`);
  writeFileSync(join(candidate, 'upstream-release.json'), `${JSON.stringify(upstream)}\n`);
  writeFileSync(join(candidate, 'schema.sql'), '-- contract fixture\n');
  writeFileSync(join(candidate, 'worker/shim.mjs'), 'export default {};\n');
  writeFileSync(join(candidate, 'index.js'), 'export {};\n');
  const files = [
    'index.js', 'product.json', 'schema.sql', 'upstream-release.json',
    'worker/shim.mjs', 'wrangler.jsonc',
  ];
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

test('CI 与 Release 独立且只消费正式上游成品', () => {
  const ci = text('ci/index.mjs');
  const release = text('release/index.mjs');
  assert.match(ci, /VoyagerRhett\/TATA/);
  assert.match(ci, /tatachatserver-cloudflare-v/);
  assert.doesNotMatch(ci, /git clone|wrangler deploy/);
  assert.match(release, /CitizenChatServer-Cloudflare-CI/);
  assert.match(release, /version-tag/);
  assert.match(release, /next-semantic-release/);
  assert.doesNotMatch(release, /gh[^\n]+VoyagerRhett\/TATA|wrangler deploy/);
});

test('CI 只接受 TataChatServer 正式 Release 的准确三件套', () => {
  const temporary = mkdtempSync(join(tmpdir(), 'citizenchatserver-upstream-contract-'));
  const upstreamSHA = '89abcdef0123456789abcdef0123456789abcdef';
  const archive = join(temporary, 'tatachatserver-cloudflare.tar.gz');
  const manifestPath = join(temporary, 'tatachatserver-cloudflare-release.json');
  try {
    writeFileSync(archive, 'formal upstream archive\n');
    writeFileSync(manifestPath, `${JSON.stringify({
      schema: 1,
      product_id: 'tatachatserver',
      platform: 'cloudflare',
      git_commit_sha: upstreamSHA,
      software_version: '1.0.0',
      artifact: 'tatachatserver-cloudflare.tar.gz',
      ci_artifact: 'TataChatServer-Cloudflare-CI',
      files: ['build/worker/shim.mjs', 'schema.sql', 'wrangler.jsonc'],
    }, null, 2)}\n`);
    writeFileSync(join(temporary, 'SHA256SUMS'), [
      `${sha256(archive)}  tatachatserver-cloudflare.tar.gz`,
      `${sha256(manifestPath)}  tatachatserver-cloudflare-release.json`,
      '',
    ].join('\n'));
    const release = {
      tag_name: 'tatachatserver-cloudflare-v1.0.0',
      target_commitish: upstreamSHA,
      name: '塔塔聊天服务 · Release · Cloudflare',
    };
    assert.equal(verifyUpstream(temporary, release), upstreamSHA);

    const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
    manifest.unexpected = true;
    writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    writeFileSync(join(temporary, 'SHA256SUMS'), [
      `${sha256(archive)}  tatachatserver-cloudflare.tar.gz`,
      `${sha256(manifestPath)}  tatachatserver-cloudflare-release.json`,
      '',
    ].join('\n'));
    assert.throws(() => verifyUpstream(temporary, release), /上游 Release/);
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
});

test('Release 来源只接受本仓 main 的准确成功 CI', () => {
  const run = {
    status: 'completed',
    conclusion: 'success',
    event: 'workflow_dispatch',
    head_branch: 'main',
    head_sha: sourceSHA,
    path: '.github/workflows/repository.yml',
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

test('正式 Release manifest 只输出 Cloudflare 平台字段', () => {
  const release = text('release/index.mjs');
  assert.match(release, /product_id: 'citizenchatserver', platform: 'cloudflare'/);
});

test('正式 Release 三件套与原生发布器使用同一非自引用归档合同', () => {
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
    });
    const manifest = JSON.parse(readFileSync(paths.manifestPath, 'utf8'));
    assert.equal(manifest.platform, 'cloudflare');
    assert.equal(manifest.archive_sha256, sha256(paths.archive));
    const external = new Map(readFileSync(paths.sumsPath, 'utf8').trim().split('\n').map((line) => {
      const match = /^([0-9a-f]{64})  ([^\r\n]+)$/.exec(line);
      assert.ok(match);
      return [match[2], match[1]];
    }));
    assert.deepEqual(external, new Map([
      ['citizenchatserver-cloudflare.tar.gz', sha256(paths.archive)],
      ['release-manifest.json', sha256(paths.manifestPath)],
    ]));

    const extracted = join(temporary, 'extracted');
    mkdirSync(extracted);
    const archiveEntries = execFileSync('tar', ['-tvzf', paths.archive], { encoding: 'utf8' })
      .trim().split('\n').filter(Boolean);
    assert.ok(archiveEntries.length > 0);
    assert.ok(archiveEntries.every((line) => line[0] === '-'));
    execFileSync('tar', ['-xzf', paths.archive, '-C', extracted]);
    assert.equal(regularFiles(extracted).includes('release-manifest.json'), false);
    assert.deepEqual(
      regularFiles(extracted), manifest.files.map(({ path }) => path).sort(),
    );
    for (const entry of manifest.files) {
      assert.equal(sha256(join(extracted, entry.path)), entry.sha256);
    }

    manifest.archive_sha256 = 'f'.repeat(64);
    writeFileSync(paths.manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    writeFileSync(paths.sumsPath, `${sha256(paths.archive)}  citizenchatserver-cloudflare.tar.gz\n${sha256(paths.manifestPath)}  release-manifest.json\n`);
    assert.throws(
      () => verifyPackagedRelease(paths),
      /Release manifest 无效/,
    );
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

test('GMB 唯一 Workflow 只调用 CitizenChatServer 扁平流程入口', () => {
  const workflow = readFileSync(join(
    instanceRoot, '..', '.github', 'workflows', 'repository.yml',
  ), 'utf8');
  const paths = workflow.match(
    /citizenchatserver\/scripts\/(?:ci|release)\/[A-Za-z0-9./_-]+\.mjs/g,
  ) ?? [];
  assert.deepEqual(paths, [
    'citizenchatserver/scripts/ci/check/execute.mjs',
    'citizenchatserver/scripts/release/package/execute.mjs',
    'citizenchatserver/scripts/release/package/execute.mjs',
    'citizenchatserver/scripts/release/package/execute.mjs',
  ]);
});
