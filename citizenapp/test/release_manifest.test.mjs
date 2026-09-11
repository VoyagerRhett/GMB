import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { afterEach, test } from 'node:test';

const flowRoot = process.env.TATA_CONSOLE_FLOW_ROOT;
if (!flowRoot) throw new Error('缺少 TATA_CONSOLE_FLOW_ROOT');

const actionPath = resolve(flowRoot, 'gmb/citizenapp/action.yml');
const actionSource = readFileSync(actionPath, 'utf8');
const temporaryRoots = [];
const version = '3.4.5';
const runNumber = '2718';
const sourceSha = '1234567890abcdef1234567890abcdef12345678';
const topLevelFields = [
  'assets',
  'bundle_id',
  'github_run_number',
  'head_sha',
  'package_name',
  'product_id',
  'version',
];
const assetFields = ['asset_name', 'asset_sha256', 'platform'];
// 中文注释：只在负向测试运行时组合已废弃字段，以真实验证七字段闭集失败关闭；
// 这不是兼容读取、回退路径或生产 manifest 字段。
const deprecatedVersionTagField = ['release', 'tag'].join('_');

test('Android从真实源码根启动Gradle并读取缓存Flutter配置', () => {
  const settings = readFileSync(new URL('../android/settings.gradle.kts', import.meta.url), 'utf8');
  const root = readFileSync(new URL('../android/build.gradle.kts', import.meta.url), 'utf8');
  const application = readFileSync(new URL('../android/app/build.gradle.kts', import.meta.url), 'utf8');
  const properties = readFileSync(new URL('../android/gradle.properties', import.meta.url), 'utf8');
  const runner = readFileSync(new URL('../scripts/citizenapp-run.sh', import.meta.url), 'utf8');
  const flutterPatch = readFileSync(resolve(flowRoot, '../tools/flutter.patch'), 'utf8');
  const kotlin = /^\+\s*implementation\("org\.jetbrains\.kotlin:kotlin-gradle-plugin:([\d.]+)"\)$/mu.exec(flutterPatch)?.[1];
  const agp = /^\+\s*compileOnly\("com\.android\.tools\.build:gradle:([\d.]+)"\)$/mu.exec(flutterPatch)?.[1];
  assert.ok(kotlin && agp, '中央 Flutter 修订必须唯一登记 AGP/KGP');
  assert.match(settings, /System\.getenv\("TATA_CONSOLE_FLUTTER_ROOT"\)/u);
  assert.match(settings, /settingsDir\.parentFile/u);
  assert.match(settings, /resolve\("android\/local\.properties"\)/u);
  assert.match(settings, /\.flutter-plugins-dependencies/u);
  assert.doesNotMatch(settings, /dev\.flutter\.flutter-plugin-loader|System\.getProperty\("user\.dir"\)/u);
  assert.doesNotMatch(settings, /id\("com\.android\.(?:application|library)"\)\s+version/u);
  assert.ok(root.includes(`classpath("com.android.tools.build:gradle:${agp}")`));
  assert.ok(root.includes(`classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:${kotlin}")`));
  assert.match(application, /import java\.util\.Properties/u);
  assert.doesNotMatch(application, /java\.util\.Properties\(\)|setSrcDirs\(/u);
  assert.match(application, /compileSdk = 36/u);
  assert.match(application, /ndkVersion = "28\.2\.13676358"/u);
  assert.match(application, /minSdk = 24/u);
  assert.match(application, /targetSdk = 36/u);
  assert.doesNotMatch(application, /(?:compileSdk|ndkVersion|minSdk|targetSdk)\s*=.*\bflutter\./u);
  assert.deepEqual(properties.split('\n').filter((line) => /^android\.(?:builtInKotlin|newDsl)=/u.test(line)), [
    'android.builtInKotlin=true',
    'android.newDsl=true',
  ]);
  assert.match(application, /source = System\.getenv\("TATA_CONSOLE_FLUTTER_ROOT"\) \?: "\.\.\/\.\."/u);
  assert.match(runner, /cd "\$APP_ROOT\/android"/u);
  assert.match(runner, /--no-problems-report/u);
  assert.match(runner, /--init-script "\$\{TATA_CONSOLE_GRADLE_INIT_SCRIPT/u);
  assert.match(runner, /TATA_CONSOLE_FLUTTER_GRADLE_ROOT="\$flutter_sdk\/packages\/flutter_tools\/gradle"/u);
  assert.match(runner, /java_home="\$\{JAVA_HOME:-\/Applications\/Android Studio\.app\/Contents\/jbr\/Contents\/Home\}"/u);
  assert.match(runner, /ANDROID_HOME="\$android_sdk" ANDROID_SDK_ROOT="\$android_sdk" JAVA_HOME="\$java_home" PATH="\$java_home\/bin:\$PATH"/u);
  assert.match(runner, /"\$APP_ROOT\/android\/gradlew"[\s\S]*--project-cache-dir "\$BUILD_WORK_DIR\/gradle-project"/u);
});

function actionStep(name) {
  const marker = `      name: ${name}\n`;
  const start = actionSource.indexOf(marker);
  assert.notEqual(start, -1, `中央 action 缺少步骤：${name}`);
  assert.equal(
    actionSource.indexOf(marker, start + marker.length),
    -1,
    `中央 action 存在重复步骤：${name}`,
  );
  const end = actionSource.indexOf('\n    - if:', start + marker.length);
  assert.notEqual(end, -1, `中央 action 步骤没有结束边界：${name}`);
  return actionSource.slice(start, end);
}

// 中文注释：测试执行中央 action 中真正随 Release 上线的 heredoc；不得在 GMB
// 另写一份清单生成器，否则生产 writer 漂移时测试仍可能虚假通过。
function manifestWriter(stepName) {
  const match = /(?:^|\n)[ \t]*node(?:[ \t]+-)?[ \t]+<<'NODE'\r?\n([\s\S]*?)\r?\n[ \t]*NODE(?:\r?\n|$)/.exec(
    actionStep(stepName),
  );
  assert.ok(match, `中央 action 的 ${stepName} 缺少 Node writer`);
  return match[1];
}

const writers = {
  android: manifestWriter('生成并核验 Android 正式清单'),
  ios: manifestWriter('生成并核验 iOS 正式清单'),
};

function temporaryRoot() {
  const path = mkdtempSync(join(tmpdir(), 'gmb-citizenapp-release-manifest-'));
  temporaryRoots.push(path);
  return path;
}

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function runManifestWriter(platform) {
  const root = temporaryRoot();
  const releasePath = join(root, 'citizenapp', 'build', 'release');
  mkdirSync(releasePath, { recursive: true });

  const assetNames = platform === 'android'
    ? ['citizenapp.apk', 'citizenapp.aab']
    : ['citizenapp.ipa'];
  for (const assetName of assetNames) {
    writeFileSync(join(releasePath, assetName), `${assetName} fixture\n`);
  }

  const result = spawnSync(process.execPath, ['-'], {
    cwd: root,
    encoding: 'utf8',
    env: {
      ...process.env,
      GITHUB_RUN_NUMBER: runNumber,
      GMB_SOFTWARE_VERSION: version,
      GMB_SOURCE_SHA: sourceSha,
    },
    input: writers[platform],
  });
  assert.equal(
    result.status,
    0,
    result.stderr || result.stdout || result.error?.message || `${platform} writer 执行失败`,
  );

  const manifestName = `citizenapp-release-${platform}.json`;
  const manifest = JSON.parse(readFileSync(join(releasePath, manifestName), 'utf8'));
  return { assetNames, manifest, releasePath };
}

function expectedManifest({ assetNames, releasePath }, platform) {
  const publicPlatform = platform === 'android' ? 'Android' : 'iOS';
  return {
    product_id: 'citizenapp',
    version,
    github_run_number: Number(runNumber),
    head_sha: sourceSha,
    bundle_id: 'ios.citizenapp',
    package_name: 'com.crcfrcn.citizenapp',
    assets: assetNames.map((assetName) => ({
      platform: publicPlatform,
      asset_name: assetName,
      asset_sha256: sha256(join(releasePath, assetName)),
    })),
  };
}

function assertManifestContract(manifest, expected) {
  assert.deepEqual(Object.keys(manifest).sort(), topLevelFields);
  assert.ok(Array.isArray(manifest.assets), 'assets 必须是数组');
  for (const asset of manifest.assets) {
    assert.deepEqual(Object.keys(asset).sort(), assetFields);
  }
  assert.deepEqual(manifest, expected);
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

afterEach(() => {
  for (const path of temporaryRoots.splice(0)) {
    rmSync(path, { force: true, recursive: true });
  }
});

test('中央 Release writer 生成固定七字段清单与三字段公开资产', () => {
  for (const platform of ['android', 'ios']) {
    const written = runManifestWriter(platform);
    assertManifestContract(written.manifest, expectedManifest(written, platform));
  }
});

test('公开平台拒绝小写，清单和资产字段或值漂移均失败', () => {
  const android = runManifestWriter('android');
  const ios = runManifestWriter('ios');
  const cases = [
    ['Android 小写', android, (value) => { value.assets[0].platform = 'android'; }],
    ['iOS 小写', ios, (value) => { value.assets[0].platform = 'ios'; }],
    ['顶层字段缺失', android, (value) => { delete value.bundle_id; }],
    ['顶层字段增加', android, (value) => {
      value[deprecatedVersionTagField] = 'citizenapp-android-v3.4.5';
    }],
    ['资产字段缺失', ios, (value) => { delete value.assets[0].asset_sha256; }],
    ['资产字段增加', ios, (value) => { value.assets[0].download_url = 'https://example.invalid'; }],
    ['资产名称漂移', android, (value) => { value.assets[0].asset_name = 'CitizenApp.apk'; }],
    ['资产数量漂移', android, (value) => { value.assets.pop(); }],
  ];

  for (const [name, written, mutate] of cases) {
    const candidate = clone(written.manifest);
    mutate(candidate);
    assert.throws(
      () => assertManifestContract(candidate, expectedManifest(written, written === android ? 'android' : 'ios')),
      { name: 'AssertionError' },
      name,
    );
  }
});

test('正式版本 Tag 前缀与内部 target 继续使用既有小写身份', () => {
  const identities = [
    {
      name: '验证公民 Android Release 的正式版本 Tag',
      command: '--prefix citizenapp-android-v --product-id citizenapp --target android --workflow gmb.citizenapp.android.ci',
    },
    {
      name: '验证公民 iOS Release 的正式版本 Tag',
      command: '--prefix citizenapp-ios-v --product-id citizenapp --target ios --workflow gmb.citizenapp.ios.ci',
    },
  ];

  for (const { name, command } of identities) {
    const compactStep = actionStep(name).replace(/\s+/g, ' ');
    assert.ok(compactStep.includes('--version-tag "$GMB_VERSION_TAG"'));
    assert.ok(compactStep.includes(command));
  }
});
