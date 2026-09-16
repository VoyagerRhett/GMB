import assert from 'node:assert/strict';
import test from 'node:test';
import {
  cacheIdentity, cacheKeys, cachePathPlan, parseCacheKey, planCachePrune,
} from './cache.mjs';

const identity = cacheIdentity({
  repository: 'VoyagerRhett/GMB', product: 'citizenapp', platform: 'ios',
  architecture: 'arm64', component: 'citizenapp-ci-ios--ios',
  runnerOs: 'macos', runnerArch: 'arm64', toolchainFingerprint: 'a'.repeat(64),
});

test('CitizenApp CI缓存身份、键和路径使用唯一共享实现', () => {
  const keys = cacheKeys(identity, '10', '2');
  assert.deepEqual(parseCacheKey(identity, keys.successKey), {
    toolchain: 'a'.repeat(16), state: 'success', runId: '10', attempt: '2',
  });
  const paths = cachePathPlan(identity, '/runner/temp', 'cargo-home\nflutter-build');
  assert.equal(paths.successPaths.length, 2);
  assert.ok(paths.successPaths.every(path => path.startsWith('/runner/temp/ci-cache/')));
});

test('CitizenApp CI缓存只保留成功与失败各自最新一份', () => {
  const make = (id, state, runId) => ({ id: String(id), ref: 'refs/heads/main',
    key: `${identity.baseKey}-${state}-${runId}-1` });
  const plan = planCachePrune(identity, [
    make(1, 'success', 1), make(2, 'success', 2),
    make(3, 'failure', 1), make(4, 'failure', 3),
  ], 'refs/heads/main');
  assert.deepEqual(plan.retain.map(value => value.id), ['2', '4']);
  assert.deepEqual(plan.remove.map(value => value.id), ['1', '3']);
});

test('CitizenApp CI缓存拒绝身份、指纹和相对路径越界', () => {
  assert.throws(() => cacheIdentity({ ...identity, repository: '../GMB' }), /身份越界/u);
  assert.throws(() => cacheIdentity({ ...identity, toolchainFingerprint: 'bad' }), /SHA-256/u);
  assert.throws(() => cachePathPlan(identity, '/runner/temp', '../outside'), /路径无效/u);
});
