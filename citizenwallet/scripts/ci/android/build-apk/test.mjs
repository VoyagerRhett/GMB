import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, copyFileSync, mkdirSync, mkdtempSync, realpathSync, lstatSync, existsSync, rmSync } from 'node:fs';
import test from 'node:test';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

test('gmb.citizenwallet.android.ci的build-apk远端Job物理独立', () => {
  const source = readFileSync(new URL('./execute.mjs', import.meta.url), 'utf8');
  assert.ok(source.includes('{"pipeline":"gmb.citizenwallet.android.ci","job":"build-apk"}'));
  assert.match(source, /function runExactWorkflowStep\(index\)/u);
  assert.match(source, /function requireExactRemoteJobEnvironment\(\)/u);
});

test('钱包CI调用实际存在的Debug原生单测任务', () => {
  const source = readFileSync(new URL('./execute.mjs', import.meta.url), 'utf8');
  assert.match(source, /:app:testDebugUnitTest/u);
  assert.doesNotMatch(source, /:app:testReleaseUnitTest/u);
});

test('钱包远端工程使用Flutter工具原件并隔离iOS注册生成文件', () => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'citizenwallet-layout-')));
  const source = join(root, 'citizenwallet'), flutter = join(root, 'flutter');
  const script = join(source, 'scripts/citizenwallet-run.sh');
  const put = (path, text) => { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, text); };
  try {
    mkdirSync(dirname(script), { recursive: true });
    copyFileSync(fileURLToPath(new URL('../../../citizenwallet-run.sh', import.meta.url)), script);
    put(join(source, 'pubspec.yaml'), 'name: citizenwallet\\n');
    put(join(source, 'android/gradle-wrapper.properties'), 'locked wrapper properties');
    put(join(source, 'android/settings.gradle.kts'), '// fixture settings');
    put(join(source, 'ios/Runner.xcscheme'), '<Scheme/>');
    for (const name of ['GeneratedPluginRegistrant.h', 'GeneratedPluginRegistrant.m']) {
      put(join(source, 'ios/Runner', name), 'old generated file');
    }
    const names = ['gradlew', 'gradlew.bat', 'gradle/wrapper/gradle-wrapper.jar'];
    for (const name of names) put(join(flutter, 'bin/cache/artifacts/gradle_wrapper', name), 'tool original ' + name);
    const run = (platform, work, toolRoot = flutter) => spawnSync('/bin/bash', [script, 'prepare-' + platform], {
      encoding: 'utf8', env: { ...process.env, CITIZENWALLET_PROJECT_ROOT: '',
        CITIZENWALLET_WORK_DIR: work, FLUTTER_ROOT: toolRoot },
    });
    const result = run('android', join(root, 'android'));
    assert.equal(result.status, 0, result.stderr);
    const project = result.stdout.trim();
    for (const name of names) {
      assert.deepEqual(readFileSync(join(project, 'android', name)), readFileSync(join(flutter, 'bin/cache/artifacts/gradle_wrapper', name)));
      assert.equal(lstatSync(join(project, 'android', name)).isSymbolicLink(), false);
    }
    assert.ok(lstatSync(join(project, 'android/gradlew')).mode & 0o100);
    for (const name of ['GeneratedPluginRegistrant.h', 'GeneratedPluginRegistrant.m']) {
      assert.equal(existsSync(join(project, 'ios/Runner', name)), false);
      assert.equal(readFileSync(join(source, 'ios/Runner', name), 'utf8'), 'old generated file');
    }
    assert.notEqual(run('android', join(root, 'missing'), join(root, 'absent')).status, 0);
    const ios = run('ios', join(root, 'ios'), '');
    assert.equal(ios.status, 0, ios.stderr);
    assert.equal(existsSync(join(ios.stdout.trim(), 'android/gradlew')), false);
    put(join(source, 'android/gradlew'), 'forbidden product tool copy');
    assert.match(run('android', join(root, 'duplicate')).stderr, /源码残留Wrapper/u);
    for (const name of names) assert.equal(readFileSync(join(flutter, 'bin/cache/artifacts/gradle_wrapper', name), 'utf8'), 'tool original ' + name);
  } finally { rmSync(root, { recursive: true, force: true }); }
});
