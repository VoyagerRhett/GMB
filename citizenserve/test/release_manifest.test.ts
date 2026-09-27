import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import { describe, expect, test } from 'vitest';

const projectPath = resolve(import.meta.dirname, '..');
const require = createRequire(import.meta.url);

// 在源码外运行真实 npm/Wrangler 生成链；测试不修改产品类型文件，也不伪造生成器输出。
function withTypesProject(run: (directory: string, execute: (script: string) => ReturnType<typeof spawnSync>) => void) {
  const directory = mkdtempSync(join(tmpdir(), 'citizenserve-types-'));
  try {
    mkdirSync(join(directory, 'scripts'));
    copyFileSync(join(projectPath, 'package.json'), join(directory, 'package.json'));
    for (const name of ['wrangler.toml', 'worker-configuration.d.ts']) {
      copyFileSync(join(projectPath, 'scripts', name), join(directory, 'scripts', name));
    }
    symlinkSync(join(projectPath, 'src'), join(directory, 'src'), 'dir');
    symlinkSync(dirname(dirname(require.resolve('wrangler/package.json'))), join(directory, 'node_modules'), 'dir');
    const npm = process.env.npm_execpath;
    if (!npm) throw new Error('类型生成合同测试必须经 npm test 执行');
    run(directory, (script) => spawnSync(process.execPath, [npm, 'run', script], {
      cwd: directory,
      env: { ...process.env, CI: '1', WRANGLER_SEND_METRICS: 'false' },
      encoding: 'utf8',
      timeout: 30_000,
    }));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

describe('CitizenServe产品发布输入', () => {
  test('真实重复生成保持完整类型和唯一中文职责注释一致', () => {
    withTypesProject((directory, execute) => {
      const types = join(directory, 'scripts/worker-configuration.d.ts');
      const original = readFileSync(types, 'utf8');
      for (let attempt = 0; attempt < 2; attempt++) {
        const result = execute('types:check');
        expect(result.status, `${result.stdout}\n${result.stderr}`).toBe(0);
        expect(readFileSync(types, 'utf8')).toBe(original);
      }
      expect(original.match(/本生成文件把CitizenServe正式Wrangler绑定/g)).toHaveLength(1);
    });
  }, 60_000);

  test('真实字段漂移仍失败且重新生成后恢复一致', () => {
    withTypesProject((directory, execute) => {
      const types = join(directory, 'scripts/worker-configuration.d.ts');
      const original = readFileSync(types, 'utf8');
      expect(original).toContain('CHAT_SERVER_URL: "https://chat.crcfrcn.com"');
      writeFileSync(types, original.replace('CHAT_SERVER_URL: "https://chat.crcfrcn.com"', 'CHAT_SERVER_URL: "https://invalid.example.test"'));
      const failed = execute('types:check');
      expect(failed.status).toBe(1);
      expect(`${failed.stdout}\n${failed.stderr}`).toContain('已过期');
      expect(readFileSync(types, 'utf8')).toBe(original);
      const repaired = execute('types:check');
      expect(repaired.status, `${repaired.stdout}\n${repaired.stderr}`).toBe(0);
    });
  }, 60_000);

  test('生成器失败即使文件摘要未变化也必须失败', () => {
    withTypesProject((directory, execute) => {
      const types = join(directory, 'scripts/worker-configuration.d.ts');
      const original = readFileSync(types, 'utf8');
      writeFileSync(join(directory, 'scripts/wrangler.toml'), 'name = [\n');
      const result = execute('types:check');
      expect(result.error).toBeUndefined();
      expect(result.status).not.toBe(0);
      expect(readFileSync(types, 'utf8')).toBe(original);
    });
  }, 60_000);

  test('Cloudflare配置保持唯一产品身份和独立凭据声明', () => {
    const wrangler = readFileSync(resolve(projectPath, 'scripts/wrangler.toml'), 'utf8');
    expect(wrangler).toContain('name = "citizenserve"');
    expect(wrangler).toContain('binding = "CITIZENCHAIN_DOWNLOAD_DB"');
    expect(wrangler).toContain('database_name = "citizenserve"');
    expect(wrangler).toContain('database_name = "citizenweb-download"');
    expect(wrangler).toContain('bucket_name = "citizenserve-private"');
    expect(wrangler).toContain('bucket_name = "citizenserve-media"');
    expect(wrangler.match(/queue = "citizenserve"/gu)).toHaveLength(2);
    expect(wrangler).toContain('id = "d632942d82c94e45ab4058fa69268ce1"');
    expect(wrangler).toContain('"CITIZENCHAIN_DOWNLOAD_PUBLISH_SECRET"');
    expect(wrangler).not.toMatch(/\.\.\/\.\.\/|\/Users\//);
  });

  test('发布指针认证使用CitizenChain产品头且没有第二套请求头', () => {
    const source = readFileSync(resolve(projectPath, 'src/downloads/citizenchain.ts'), 'utf8');
    expect(source).toContain("request.headers.get('x-citizenserve-request-time')");
    expect(source).toContain("request.headers.get('x-citizenserve-request-nonce')");
    expect(source).toContain("request.headers.get('x-citizenserve-request-signature')");
    expect(source.match(/x-citizenserve-request-/g)).toHaveLength(3);
  });
});
