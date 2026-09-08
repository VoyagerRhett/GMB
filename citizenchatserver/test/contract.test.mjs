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
    deployment_provider: 'cloudflare',
    public_url: 'https://chat.crcfrcn.com',
    realtime_url: 'wss://chat.crcfrcn.com/realtime',
  });
  // 中文注释：服务没有宿主 OS 平台；这里显式拒绝旧字段，避免仅增加新字段形成双写。
  assert.equal(Object.hasOwn(product, 'platform'), false);
  assert.equal(wrangler.name, 'citizenchatserver-workers');
  assert.equal(wrangler.main, 'worker/shim.mjs');
  assert.equal(wrangler.build, undefined);
  assert.deepEqual(wrangler.routes, [
    { pattern: 'chat.crcfrcn.com', custom_domain: true },
  ]);
  assert.equal(wrangler.d1_databases[0].database_name, 'citizenchatserver-d1');
  assert.equal(wrangler.r2_buckets[0].bucket_name, 'citizenchatserver-r2');
  assert.equal(wrangler.migrations, undefined);
  assert.deepEqual(wrangler.exports, {
    TataChatRealtime: { type: 'durable-object', storage: 'sqlite' },
  });
});

test('宿主目录不复制通用服务源码或构建产物', () => {
  for (const name of ['Cargo.toml', 'src', 'worker', 'worker.mjs', 'build', 'target']) {
    assert.equal(existsSync(new URL(name, root)), false, `${name} 不得进入宿主源码根`);
  }
});
