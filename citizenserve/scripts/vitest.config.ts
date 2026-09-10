import { isAbsolute, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

// 测试生成物只消费中央任务编译目录；缺失时停止，不回退到源码 node_modules/.vite。
const remote = process.env.GITHUB_ACTIONS === 'true';
const work = process.env.TATA_CONSOLE_CACHE_DIR;
const cache = remote ? process.env.XDG_CACHE_HOME : process.env.TATA_CONSOLE_BUILD_CACHE_DIR;
const ownerRoot = remote ? process.env.RUNNER_TEMP : process.env.TATA_WORKSPACE_ROOT;
if (!ownerRoot || !isAbsolute(ownerRoot) || !cache || !isAbsolute(cache)
  || resolve(cache) !== cache || (remote
    ? !cache.startsWith(resolve(ownerRoot) + sep)
    : !work || resolve(work) !== work
      || !work.startsWith(resolve(ownerRoot, 'tataconsole/cache/gmb/citizenserve') + sep)
      || cache !== resolve(work, 'build') || !process.env.TATA_CONSOLE_RUN_ID)) {
  throw new Error('CitizenServe 测试必须由塔塔控制台提供中央任务及编译目录');
}

export default {
  root: fileURLToPath(new URL('..', import.meta.url)),
  cacheDir: resolve(cache, 'vitest'),
  test: {
    environment: 'node',
    globals: true,
    coverage: { reportsDirectory: resolve(cache, 'vitest/coverage') }
  }
};
