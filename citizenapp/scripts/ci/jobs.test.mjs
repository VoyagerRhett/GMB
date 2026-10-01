import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, realpathSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';
import { jobIdentity as android, workflowSteps as androidSteps } from './android.mjs';
import { jobIdentity as androidCheck, workflowSteps as androidCheckSteps } from './android-check.mjs';
import { jobIdentity as ios, workflowSteps as iosSteps } from './ios.mjs';
import { jobIdentity as iosCheck, workflowSteps as iosCheckSteps } from './ios-check.mjs';
import { runWorkflow } from '../workflow.mjs';

const jobs = [
  [android, androidSteps], [androidCheck, androidCheckSteps],
  [ios, iosSteps], [iosCheck, iosCheckSteps],
];

test('CitizenApp四个CI Job保留准确独立身份且共用唯一执行器', async () => {
  assert.deepEqual(jobs.map(([identity]) => `${identity.pipeline}:${identity.job}`).sort(), [
    'gmb.citizenapp.android.ci:android', 'gmb.citizenapp.android.ci:check',
    'gmb.citizenapp.ios.ci:check', 'gmb.citizenapp.ios.ci:ios',
  ]);
  for (const [, steps] of jobs) {
    for (const step of Object.values(steps)) {
      const result = spawnSync('/bin/bash', ['-n'], { input: step.source, encoding: 'utf8' });
      assert.equal(result.status, 0, result.stderr);
    }
  }
  await assert.rejects(runWorkflow(ios, iosSteps, {}, {
    argumentsList: ['workflow-step', '999'], environment: { GITHUB_REPOSITORY: 'VoyagerRhett/GMB' },
  }), /阶段无效/u);
  await assert.rejects(runWorkflow(ios, iosSteps, {}, {
    argumentsList: ['workflow-step', '0'], environment: { GITHUB_REPOSITORY: 'VoyagerRhett/TATA' },
  }), /仓库身份/u);
});

test('CitizenApp CI Workflow只引用六层内的唯一扁平文件', () => {
  for (const [platform, names] of [['android', ['android.mjs', 'android-check.mjs']], ['ios', ['ios.mjs', 'ios-check.mjs']]]) {
    const workflow = readFileSync(new URL(`../../../.github/workflows/citizenapp-${platform}-ci.yml`, import.meta.url), 'utf8');
    for (const name of names) assert.match(workflow, new RegExp(`citizenapp/scripts/ci/${name.replace('.', '[.]')}`, 'u'));
    assert.doesNotMatch(workflow, /citizenapp\/scripts\/ci\/(?:android|ios)\//u);
  }
  for (const source of ['./android.mjs', './android-check.mjs', './ios.mjs', './ios-check.mjs']
    .map(path => readFileSync(new URL(path, import.meta.url), 'utf8'))) {
    assert.doesNotMatch(source, /function cacheIdentity|function runExactWorkflowStep/u);
  }
});


test('CitizenApp消费视图实际绑定SDK标准入口且CI重用不丢失Pub状态', () => {
  const source = fileURLToPath(new URL('../../', import.meta.url)).replace(/\/$/u, '');
  const sdk = fileURLToPath(new URL('../../../citizensdk/', import.meta.url)).replace(/\/$/u, '');
  const work = realpathSync(mkdtempSync(join(tmpdir(), 'citizenapp-view-')));
  const script = join(source, 'scripts/citizenapp-view.mjs');
  const flutter = join(work, 'flutter');
  for (const name of ['gradlew', 'gradlew.bat', 'gradle/wrapper/gradle-wrapper.jar']) {
    const path = join(flutter, 'bin/cache/artifacts/gradle_wrapper', name);
    mkdirSync(join(path, '..'), { recursive: true });
    writeFileSync(path, 'synthetic wrapper ' + name);
  }
  const run = command => spawnSync(process.execPath, [script, command,
    '--source-root', source, '--work-root', work], { encoding: 'utf8',
      env: { ...process.env, FLUTTER_ROOT: flutter } });
  try {
    const created = run('create-android');
    assert.equal(created.status, 0, created.stderr);
    const project = created.stdout.trim();
    const sdkView = join(work, 'source-view', sdk.replace(/^\/+/, ''));
    const entry = join(sdkView, 'android/src/main/kotlin/org/citizen/sdk/CitizenSdkPlugin.kt');
    assert.equal(realpathSync(entry), join(sdk, 'android/src/main/kotlin/CitizenSdkPlugin.kt'));
    assert.equal(existsSync(join(sdkView, 'android/src/main/kotlin/CitizenSdkPlugin.kt')), false);
    for (const name of ['gradlew', 'gradlew.bat', 'gradle/wrapper/gradle-wrapper.jar']) {
      const output = join(project, 'android', name);
      assert.equal(lstatSync(output).isSymbolicLink(), false);
      assert.deepEqual(readFileSync(output), readFileSync(join(flutter, 'bin/cache/artifacts/gradle_wrapper', name)));
    }
    const settings = join(project, 'android/settings.gradle.kts');
    assert.equal(lstatSync(settings).isSymbolicLink(), false);
    assert.deepEqual(readFileSync(settings), readFileSync(join(source, 'android/settings.gradle.kts')));
    mkdirSync(join(project, '.dart_tool'));
    const config = join(project, '.dart_tool/package_config.json');
    const chatSource = join(source, '../../TATA/tatachatsdk');
    const chatView = existsSync(chatSource)
      ? join(work, 'source-view', realpathSync(chatSource).replace(/^\/+/, '')) : null;
    if (chatView) {
      const plugin = join(chatView, 'android/src/main/java/chat/tata/sdk/TataChatSdkPlugin.java');
      assert.equal(realpathSync(plugin), join(realpathSync(chatSource), 'android/TataChatSdkPlugin.java'));
      assert.equal(existsSync(join(chatView, 'android/TataChatSdkPlugin.java')), false);
    }
    const contents = JSON.stringify({ configVersion: 2, packages: [
      { name: 'citizen_sdk', rootUri: pathToFileURL(sdkView + '/').href },
      ...(chatView ? [{ name: 'tatachat_sdk', rootUri: pathToFileURL(chatView + '/').href }] : []),
    ] });
    writeFileSync(config, contents);
    assert.equal(run('verify').status, 0);
    assert.equal(readFileSync(config, 'utf8'), contents);
    writeFileSync(config, JSON.stringify({ packages: [
      { name: 'citizen_sdk', rootUri: pathToFileURL(sdk + '/').href },
    ] }));
    const rejected = run('verify');
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, /实际SDK依赖未绑定/u);
  } finally { rmSync(work, { recursive: true }); }
});

test('CitizenApp各CI的Pub及构建使用同轮视图', () => {
  for (const steps of [androidCheckSteps, iosCheckSteps]) {
    assert.match(steps['8'].source, /citizenapp-view\.mjs.*create/u);
    assert.match(steps['8'].source, /CITIZENAPP_TEST_PROJECT_ROOT/u);
    assert.match(steps['9'].source, /citizenapp-test\.sh/u);
  }
  assert.match(androidSteps['8'].source, /create-android/u);
  assert.match(androidSteps['9'].source, /project="\$CITIZENAPP_PROJECT_ROOT"/u);
  assert.match(androidSteps['10'].source, /cd "\$CITIZENAPP_PROJECT_ROOT"/u);
  const runner = readFileSync(new URL('../citizenapp-test.sh', import.meta.url), 'utf8');
  assert.match(runner, /"\$VIEW_SCRIPT" verify/u);
});

// 直接执行视图装配，覆盖缺少输入、旧平台入口冲突和源目录回写三个失败边界。
test('CitizenApp扁平平台输入缺失或重复时拒绝生成工程', () => {
  const fixture = realpathSync(mkdtempSync(join(tmpdir(), 'citizenapp-platform-')));
  const source = join(fixture, 'source'), work = join(fixture, 'work');
  const script = fileURLToPath(new URL('../citizenapp-view.mjs', import.meta.url));
  mkdirSync(join(source, 'ios'), { recursive: true });
  mkdirSync(join(source, 'android'));
  writeFileSync(join(source, 'pubspec.yaml'), 'name: fixture\n');
  const run = output => spawnSync(process.execPath, [script, 'create', '--source-root', source,
    '--work-root', output], { encoding: 'utf8' });
  try {
    assert.match(run(work).stderr, /平台输入缺少/u);
    for (const name of ['Runner', 'RunnerUITests']) writeFileSync(join(source, `ios/${name}.xcscheme`), '<Scheme/>');
    for (const name of ['gradle-wrapper.properties']) writeFileSync(join(source, 'android', name), 'fixture');
    assert.equal(run(work).status, 0);
    const projected = join(work, 'source-view', source.replace(/^\/+/, ''));
    assert.equal(existsSync(join(projected, 'android/gradlew')), false);
    const missingTools = spawnSync(process.execPath, [script, 'create-android',
      '--source-root', source, '--work-root', work], { encoding: 'utf8',
        env: { ...process.env, FLUTTER_ROOT: join(fixture, 'absent-flutter') } });
    assert.notEqual(missingTools.status, 0);
    assert.match(run(join(source, 'output')).stderr, /必须分离/u);
    const legacy = join(source, 'ios/Runner.xcodeproj/xcshareddata/xcschemes');
    mkdirSync(legacy, { recursive: true });
    writeFileSync(join(legacy, 'Runner.xcscheme'), '<Scheme/>');
    assert.match(run(work).stderr, /平台入口重复/u);
  } finally { rmSync(fixture, { recursive: true }); }
});
