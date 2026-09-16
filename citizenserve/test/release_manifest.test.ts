import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, test } from 'vitest';

const projectPath = resolve(import.meta.dirname, '..');

describe('CitizenServe产品发布输入', () => {
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
