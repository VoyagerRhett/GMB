#!/usr/bin/env node

// 中文注释：CI 只校验本仓实例配置并生成配置候选；不读取上游成品，不装配服务运行模块。
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const candidateFiles = ['SHA256SUMS', 'product.json', 'source-sha.txt', 'wrangler.jsonc'];
const payloadFiles = candidateFiles.filter((path) => path !== 'SHA256SUMS');
function fail(message) { throw new Error(message); }
function sha256(path) { return createHash('sha256').update(readFileSync(path)).digest('hex'); }
function parseArguments(argv) {
  const command = argv.shift();
  const values = {};
  while (argv.length) {
    const key = argv.shift();
    if (!key?.startsWith('--') || !argv.length) fail('CitizenChatServer CI 参数无效');
    values[key.slice(2)] = argv.shift();
  }
  return { command, values };
}

function requireRegularFile(path) {
  if (!existsSync(path) || !lstatSync(path).isFile() || lstatSync(path).isSymbolicLink()) {
    fail('CI 配置与候选只允许普通文件');
  }
}
export function verifyConfiguration(root) {
  for (const path of ['product.json', 'wrangler.jsonc']) requireRegularFile(join(root, path));
  const product = JSON.parse(readFileSync(join(root, 'product.json'), 'utf8'));
  const wrangler = JSON.parse(readFileSync(join(root, 'wrangler.jsonc'), 'utf8'));
  // 中文注释：Cloudflare 是平台闭集中的正式值；产品声明只接受最终七字段合同。
  const productKeys = [
    'platform', 'product_id', 'public_url', 'realtime_url',
    'source_product_id', 'source_repository', 'version',
  ];
  if (JSON.stringify(Object.keys(product).sort()) !== JSON.stringify(productKeys)
      || product.product_id !== 'citizenchatserver' || product.source_product_id !== 'tatachatserver'
      || product.source_repository !== 'VoyagerRhett/TATA'
      || product.platform !== 'cloudflare'
      || !/^\d+\.\d+\.\d+$/.test(product.version)
      || product.public_url !== 'https://chat.crcfrcn.com'
      || product.realtime_url !== 'wss://chat.crcfrcn.com/realtime') fail('CitizenChatServer 产品声明无效');
  const wranglerKeys = [
    'compatibility_date', 'd1_databases', 'durable_objects', 'exports', 'main', 'name',
    'preview_urls', 'r2_buckets', 'routes', 'triggers', 'vars', 'workers_dev',
  ];
  const variableKeys = [
    'CHATSERVER_ANDROID_APP_ID', 'CHATSERVER_APNS_ALLOWED_TOPICS',
    'CHATSERVER_APNS_SANDBOX', 'CHATSERVER_AUTH_AUDIENCE',
    'CHATSERVER_AUTH_ISSUER', 'CHATSERVER_IOS_APP_ID',
    'CHATSERVER_MAX_ATTACHMENT_BYTES',
  ];
  if (JSON.stringify(Object.keys(wrangler).sort()) !== JSON.stringify(wranglerKeys)
      || JSON.stringify(Object.keys(wrangler.vars ?? {}).sort()) !== JSON.stringify(variableKeys)) {
    fail('CitizenChatServer Wrangler 字段闭集无效');
  }
  if (wrangler.name !== 'citizenchatserver' || wrangler.main !== 'worker/shim.mjs') fail('CitizenChatServer Worker 身份无效');
  if (wrangler.d1_databases?.length !== 1 || wrangler.d1_databases[0].binding !== 'D1'
      || wrangler.d1_databases[0].database_name !== 'citizenchatserver') fail('CitizenChatServer D1 名称无效');
  if (wrangler.r2_buckets?.length !== 1 || wrangler.r2_buckets[0].binding !== 'R2'
      || wrangler.r2_buckets[0].bucket_name !== 'citizenchatserver') fail('CitizenChatServer R2 名称无效');
  if (wrangler.durable_objects?.bindings?.length !== 1
      || wrangler.durable_objects.bindings[0].name !== 'DO'
      || wrangler.durable_objects.bindings[0].class_name !== 'DO'
      || wrangler.exports?.DO?.type !== 'durable-object'
      || wrangler.exports.DO.storage !== 'sqlite') fail('CitizenChatServer Durable Object exports 无效');
  if (wrangler.compatibility_date !== '2026-08-30'
      || wrangler.workers_dev !== false || wrangler.preview_urls !== false
      || JSON.stringify(wrangler.routes) !== JSON.stringify([
        { pattern: 'chat.crcfrcn.com', custom_domain: true },
      ])
      || JSON.stringify(wrangler.triggers) !== JSON.stringify({ crons: ['* * * * *'] })
      || wrangler.vars.CHATSERVER_ANDROID_APP_ID !== 'com.crcfrcn.citizenapp'
      || wrangler.vars.CHATSERVER_APNS_ALLOWED_TOPICS !== 'ios.citizenapp'
      || wrangler.vars.CHATSERVER_APNS_SANDBOX !== 'false'
      || wrangler.vars.CHATSERVER_AUTH_AUDIENCE !== 'citizenchatserver'
      || wrangler.vars.CHATSERVER_AUTH_ISSUER !== 'https://www.crcfrcn.com'
      || wrangler.vars.CHATSERVER_IOS_APP_ID !== 'ios.citizenapp'
      || wrangler.vars.CHATSERVER_MAX_ATTACHMENT_BYTES !== '5368709120') {
    fail('CitizenChatServer 公开配置命名无效');
  }

  // 中文注释：嵌套资源句柄也按闭集校验，拒绝生产编号、额外绑定和额外导出混入候选。
  for (const [actual, expected] of [
    [wrangler.d1_databases, [{ binding: 'D1', database_name: 'citizenchatserver' }]],
    [wrangler.r2_buckets, [{ binding: 'R2', bucket_name: 'citizenchatserver' }]],
    [wrangler.durable_objects, { bindings: [{ name: 'DO', class_name: 'DO' }] }],
    [wrangler.exports, { DO: { type: 'durable-object', storage: 'sqlite' } }],
  ]) {
    // 配置允许 JSON 属性任意顺序，严格比较键与值的最终结构。
    const canonical = (value) => Array.isArray(value) ? value.map(canonical)
      : value && typeof value === 'object'
        ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])])) : value;
    if (JSON.stringify(canonical(actual)) !== JSON.stringify(canonical(expected))) fail('CitizenChatServer 资源字段闭集无效');
  }
}

export function verifyCandidate(root, sourceSHA) {
  if (!/^[0-9a-f]{40}$/.test(sourceSHA ?? '')) fail('CitizenChatServer CI 来源 SHA 无效');
  if (lstatSync(root).isSymbolicLink() || !lstatSync(root).isDirectory()
      || JSON.stringify(readdirSync(root).sort()) !== JSON.stringify(candidateFiles)) {
    fail('CitizenChatServer CI 候选四文件闭集无效');
  }
  for (const path of candidateFiles) requireRegularFile(join(root, path));
  const expected = payloadFiles.map((path) => sha256(join(root, path)) + '  ' + path).join('\n') + '\n';
  if (readFileSync(join(root, 'SHA256SUMS'), 'utf8') !== expected) fail('CitizenChatServer CI 候选哈希闭集无效');
  if (readFileSync(join(root, 'source-sha.txt'), 'utf8') !== sourceSHA + '\n') fail('CitizenChatServer 候选源码与当前 main 不一致');
  verifyConfiguration(root);
}

export function action(values) {
  const instance = resolve(values.instance ?? '');
  const output = resolve(values.output ?? '');
  const sourceSHA = values['source-sha'] ?? '';
  if (basename(instance) !== 'citizenchatserver' || !/^[0-9a-f]{40}$/.test(sourceSHA)) fail('CitizenChatServer CI 输入无效');
  // 中文注释：同时检查逻辑与物理父目录，防止符号链接把产物绕写回源码；拒绝覆盖既有输出。
  const repositoryRoot = realpathSync(resolve(instance, '..'));
  for (const path of [output, join(realpathSync(dirname(output)), basename(output))]) {
    const difference = relative(repositoryRoot, path);
    if (difference === '' || (difference !== '..' && !difference.startsWith('..' + sep))) {
      fail('CitizenChatServer CI 输出不得进入源码仓库');
    }
  }
  if (existsSync(output)) fail('CitizenChatServer CI 输出已存在');
  verifyConfiguration(join(instance, 'scripts'));
  mkdirSync(output, { mode: 0o700 });
  try {
    for (const path of ['product.json', 'wrangler.jsonc']) copyFileSync(join(instance, 'scripts', path), join(output, path));
    writeFileSync(join(output, 'source-sha.txt'), sourceSHA + '\n');
    writeFileSync(join(output, 'SHA256SUMS'), payloadFiles.map((path) => sha256(join(output, path)) + '  ' + path).join('\n') + '\n');
    verifyCandidate(output, sourceSHA);
  } catch (error) {
    // 只清理本次成功取得所有权的输出；已有目录在 mkdir 之前就已拒绝。
    rmSync(output, { recursive: true, force: true });
    throw error;
  }
}
const isMain = process.argv[1]
  && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url));
if (isMain) {
  try {
    const { command, values } = parseArguments(process.argv.slice(2));
    if (command === 'action') action(values);
    else if (command === 'verify') verifyCandidate(resolve(values.candidate ?? ''), values['source-sha']);
    else fail('CitizenChatServer CI 命令无效');
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  }
}
