import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { afterEach, describe, expect, test } from 'vitest';
const projectPath = resolve(import.meta.dirname, '..');
const flowRoot = process.env.TATA_CONSOLE_FLOW_ROOT;
if (!flowRoot) throw new Error('缺少 TATA_CONSOLE_FLOW_ROOT');
const gitCommitSha = '1234567890abcdef1234567890abcdef12345678';
const temporaryRoots: string[] = [];

// 中文注释：GitHub 动作入口把唯一实现内嵌为 JSON 字符串。测试只把该实现解包到临时目录，
// 不维护第二份 TypeScript 镜像，因而覆盖的仍是 Workflow 真正执行的代码。
function unpackActionImplementation(wrapperPath: string): string {
  const source = readFileSync(wrapperPath, 'utf8');
  const prefix = 'const implementations = Object.freeze(';
  const start = source.indexOf(prefix);
  const end = source.indexOf(');\nconst [command', start + prefix.length);
  if (start < 0 || end < 0) throw new Error(`动作入口结构无效：${wrapperPath}`);
  const implementations = JSON.parse(source.slice(start + prefix.length, end));
  if (typeof implementations.action !== 'string') throw new Error('动作入口缺少 action 实现');
  const root = mkdtempSync(join(tmpdir(), 'gmb-action-test-'));
  temporaryRoots.push(root);
  const path = join(root, 'implementation.mjs');
  writeFileSync(path, implementations.action);
  return path;
}

const ciImplementationPath = unpackActionImplementation(resolve(
  flowRoot,
  'gmb/citizenserve/cloudflare/ci.mjs',
));
const ciModule = await import(ciImplementationPath);
const { buildCitizenServeCloudflareRelease: buildCitizenServeCloudflareCI } = ciModule;
const releaseImplementationPath = unpackActionImplementation(resolve(
  flowRoot,
  'gmb/citizenserve/cloudflare/release.mjs',
));
const releaseModule = await import(releaseImplementationPath);
const {
  buildCitizenServeCloudflareRelease,
  extractCitizenServeCloudflareArchive,
  verifyCitizenServeCloudflareRelease,
} = releaseModule;

function temporaryRoot(): string {
  const path = mkdtempSync(join(tmpdir(), 'gmb-cloudflare-release-'));
  temporaryRoots.push(path);
  return path;
}

function buildCandidate(root: string, name: string, sourceProject = projectPath) {
  const bundlePath = join(root, `${name}.mjs`);
  const outputPath = join(root, name);
  writeFileSync(bundlePath, 'export default { fetch() { return new Response("ok"); } };\n');
  const manifest = buildCitizenServeCloudflareRelease({
    projectPath: sourceProject,
    bundlePath,
    outputPath,
    gitCommitSha,
  });
  return { manifest, outputPath };
}

function fixtureProject(root: string): string {
  const fixture = join(root, 'project');
  mkdirSync(join(fixture, 'schema'), { recursive: true });
  mkdirSync(join(fixture, 'scripts'), { recursive: true });
  for (const path of ['package.json', 'package-lock.json', 'scripts/wrangler.toml']) {
    copyFileSync(join(projectPath, path), join(fixture, path));
  }
  copyFileSync(join(projectPath, 'schema/citizenserve.sql'), join(fixture, 'schema/citizenserve.sql'));
  copyFileSync(join(projectPath, 'schema/download.sql'), join(fixture, 'schema/download.sql'));
  return fixture;
}

afterEach(() => {
  for (const path of temporaryRoots.splice(0)) rmSync(path, { recursive: true, force: true });
});

describe('CitizenServe Cloudflare Release 候选', () => {
  test('CI 与 Release 使用独立动作文件并保持 CitizenServe 产品身份', () => {
    const root = temporaryRoot();
    const bundlePath = join(root, 'ci-worker.mjs');
    writeFileSync(bundlePath, 'export default { fetch() { return new Response("ok"); } };\n');
    const ciManifest = buildCitizenServeCloudflareCI({
      projectPath,
      bundlePath,
      outputPath: join(root, 'ci-candidate'),
      gitCommitSha,
    });
    const releaseCandidate = buildCandidate(root, 'release-candidate');

    expect(readFileSync(ciImplementationPath))
      .toEqual(readFileSync(releaseImplementationPath));
    expect(readFileSync(releaseImplementationPath, 'utf8')).not.toMatch(/\bplatform\s*:/);
    expect(ciManifest.product_id).toBe('citizenserve');
    expect(ciManifest.deployment_provider).toBe('cloudflare');
    expect(ciManifest).toEqual(releaseCandidate.manifest);
    expect(releaseCandidate.manifest.product_id).toBe('citizenserve');
    expect(releaseCandidate.manifest.deployment_provider).toBe('cloudflare');
  });

  test('相同代码、工具和 Git SHA 重复生成完全一致的候选', () => {
    const root = temporaryRoot();
    const first = buildCandidate(root, 'first');
    const second = buildCandidate(root, 'second');

    expect(first.manifest).toEqual(second.manifest);
    expect(readFileSync(join(first.outputPath, 'release-manifest.json'), 'utf8'))
      .toBe(readFileSync(join(second.outputPath, 'release-manifest.json'), 'utf8'));
    expect(readFileSync(join(first.outputPath, 'SHA256SUMS'), 'utf8'))
      .toBe(readFileSync(join(second.outputPath, 'SHA256SUMS'), 'utf8'));
    expect(Object.keys(first.manifest).sort()).toEqual(
      [
        "deployment_provider", "files", "git_commit_sha", "product_id", "resources",
        "software_version", "tools",
      ].sort(),
    );
    expect(first.manifest.deployment_provider).toBe('cloudflare');
    expect(
      first.manifest.files.find(({ path }: { path: string }) => path === 'schema/download.sql')?.sha256,
    ).toMatch(/^[0-9a-f]{64}$/);
  });

  test('规范 tar.gz 归档可重复生成并安全解包复核', () => {
    const root = temporaryRoot();
    const first = buildCandidate(root, 'archive-source');
    const firstArchive = join(root, 'first.tgz');
    const secondArchive = join(root, 'second.tgz');
    releaseModule.writeCitizenServeCloudflareArchive(first.outputPath, firstArchive);
    releaseModule.writeCitizenServeCloudflareArchive(first.outputPath, secondArchive);

    expect(readFileSync(firstArchive)).toEqual(readFileSync(secondArchive));
    const extracted = join(root, 'extracted');
    const manifest = extractCitizenServeCloudflareArchive(firstArchive, extracted, gitCommitSha);
    expect(manifest).toEqual(first.manifest);
    expect(readFileSync(join(extracted, 'SHA256SUMS'), 'utf8'))
      .toBe(readFileSync(join(first.outputPath, 'SHA256SUMS'), 'utf8'));
  });

  test('候选只接受准确 Git SHA，任何 payload 篡改立即拒绝', () => {
    const root = temporaryRoot();
    const { outputPath } = buildCandidate(root, 'candidate');

    expect(() => verifyCitizenServeCloudflareRelease(outputPath, '0'.repeat(40)))
      .toThrow('候选 Git SHA 与期望提交不一致');
    writeFileSync(join(outputPath, 'worker.mjs'), 'export default {};\n');
    expect(() => verifyCitizenServeCloudflareRelease(outputPath, gitCommitSha))
      .toThrow('候选文件哈希不一致：worker.mjs');
  });

  test('manifest 拒绝缺失、错误、旧 platform、双写和额外部署供应商字段', () => {
    const root = temporaryRoot();
    const cases: Array<[
      string,
      (manifest: Record<string, unknown>) => void,
      string,
    ]> = [
      ['missing', (manifest) => { delete manifest.deployment_provider; }, 'release manifest 字段集合不正确'],
      ['wrong', (manifest) => { manifest.deployment_provider = 'other'; }, '候选部署供应商不正确'],
      ['legacy', (manifest) => {
        delete manifest.deployment_provider;
        manifest.platform = 'cloudflare';
      }, 'release manifest 字段集合不正确'],
      ['dual', (manifest) => { manifest.platform = 'cloudflare'; }, 'release manifest 字段集合不正确'],
      ['extra', (manifest) => { manifest.provider = 'cloudflare'; }, 'release manifest 字段集合不正确'],
    ];

    // 身份闭集先于 SHA256SUMS 校验，确保每个失败都准确落在部署供应商合同。
    for (const [name, mutate, expected] of cases) {
      const { outputPath } = buildCandidate(root, `manifest-${name}`);
      const manifestPath = join(outputPath, 'release-manifest.json');
      const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
      mutate(manifest);
      writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
      expect(() => verifyCitizenServeCloudflareRelease(outputPath, gitCommitSha)).toThrow(expected);
    }
  });

  test('manifest 未登记文件和候选中的私钥均失败关闭', () => {
    const root = temporaryRoot();
    const first = buildCandidate(root, 'unknown-file');
    writeFileSync(join(first.outputPath, 'extra.txt'), 'extra\n');
    expect(() => verifyCitizenServeCloudflareRelease(first.outputPath, gitCommitSha))
      .toThrow('候选包含未登记文件');

    const bundlePath = join(root, 'private.mjs');
    writeFileSync(
      bundlePath,
      '-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----\n',
    );
    expect(() => buildCitizenServeCloudflareRelease({
      projectPath,
      bundlePath,
      outputPath: join(root, 'private-material'),
      gitCommitSha,
    })).toThrow('候选疑似包含私密材料：worker.mjs');
  });
});
