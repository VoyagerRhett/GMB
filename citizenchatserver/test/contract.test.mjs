import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import test from 'node:test';

const root = new URL('../', import.meta.url);
const product = JSON.parse(readFileSync(new URL('scripts/product.json', root), 'utf8'));
const wrangler = JSON.parse(readFileSync(new URL('scripts/wrangler.jsonc', root), 'utf8'));

test('CitizenChatServer 是 TataChatServer 的独立 Cloudflare 部署实例', () => {
  assert.deepEqual(product, {
    product_id: 'citizenchatserver',
    version: '1.0.0',
    source_repository: 'VoyagerRhett/TATA',
    source_product_id: 'tatachatserver',
    platform: 'cloudflare',
    public_url: 'https://chat.crcfrcn.com',
    realtime_url: 'wss://chat.crcfrcn.com/realtime',
  });
  // 中文注释：Cloudflare 是全仓平台闭集成员，产品声明必须精确匹配最终七字段合同。
  assert.equal(wrangler.name, 'citizenchatserver');
  assert.equal(wrangler.main, 'worker/shim.mjs');
  assert.equal(wrangler.build, undefined);
  assert.deepEqual(wrangler.routes, [
    { pattern: 'chat.crcfrcn.com', custom_domain: true },
  ]);
  assert.deepEqual(wrangler.d1_databases, [
    { binding: 'D1', database_name: 'citizenchatserver' },
  ]);
  assert.deepEqual(wrangler.r2_buckets, [
    { binding: 'R2', bucket_name: 'citizenchatserver' },
  ]);
  assert.deepEqual(wrangler.durable_objects.bindings, [
    { name: 'DO', class_name: 'DO' },
  ]);
  assert.deepEqual(wrangler.exports, {
    DO: { type: 'durable-object', storage: 'sqlite' },
  });
});

test('宿主目录不复制通用服务源码或构建产物', () => {
  for (const name of ['Cargo.toml', 'src', 'worker', 'worker.mjs', 'build', 'target']) {
    assert.equal(existsSync(new URL(name, root)), false, `${name} 不得进入宿主源码根`);
  }
});
