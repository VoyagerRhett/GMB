import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const root = new URL('../', import.meta.url);
const source = [
  readFileSync(new URL('scripts/product.json', root), 'utf8'),
  readFileSync(new URL('scripts/wrangler.jsonc', root), 'utf8'),
].join('\n');
const product = JSON.parse(readFileSync(new URL('scripts/product.json', root), 'utf8'));
const wrangler = JSON.parse(readFileSync(new URL('scripts/wrangler.jsonc', root), 'utf8'));

test('CitizenChatServer 只声明 HTTPS、WSS 与准确双端应用身份', () => {
  assert.equal(source.includes(['http', '://'].join('')), false);
  assert.equal(source.includes(['ws', '://'].join('')), false);
  assert.equal(source.includes('/v' + '1'), false);
  assert.equal(wrangler.workers_dev, false);
  assert.equal(wrangler.preview_urls, false);
  assert.equal(product.platform, 'cloudflare');
  assert.equal(wrangler.vars.CHATSERVER_IOS_APP_ID, 'ios.citizenapp');
  assert.equal(
    wrangler.vars.CHATSERVER_ANDROID_APP_ID,
    'com.crcfrcn.citizenapp',
  );
  assert.equal(wrangler.vars.CHATSERVER_AUTH_AUDIENCE, 'citizenchatserver');
  assert.equal(
    wrangler.vars.CHATSERVER_AUTH_ISSUER,
    'https://www.crcfrcn.com',
  );
});

test('生产资源编号与授权密钥不得写入产品声明', () => {
  assert.equal(source.includes('database_id'), false);
  assert.equal(source.includes('AUTH_ED25519_PUBLIC_KEY'), false);
  assert.equal(source.includes('PRIVATE_KEY'), false);
  assert.equal(source.includes('SERVICE_ACCOUNT'), false);
});

test('源码配置只声明候选入口且不自行编译 TataChatServer', () => {
  assert.equal(wrangler.main, 'worker/shim.mjs');
  assert.equal(wrangler.build, undefined);
  assert.equal(source.includes('../../TATA'), false);
  assert.equal(source.includes('/Users/'), false);
});

test('宿主配置只包含实例资源与授权验签合同', () => {
  assert.deepEqual(Object.keys(wrangler.vars).sort(), [
    'CHATSERVER_ANDROID_APP_ID',
    'CHATSERVER_APNS_ALLOWED_TOPICS',
    'CHATSERVER_APNS_SANDBOX',
    'CHATSERVER_AUTH_AUDIENCE',
    'CHATSERVER_AUTH_ISSUER',
    'CHATSERVER_IOS_APP_ID',
    'CHATSERVER_MAX_ATTACHMENT_BYTES',
  ]);
});
