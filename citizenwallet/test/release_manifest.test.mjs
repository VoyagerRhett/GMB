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

const actionPath = resolve(flowRoot, 'gmb/citizenwallet/action.yml');
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
const platforms = {
  android: {
    assetNames: ['citizenwallet.apk', 'citizenwallet.aab'],
    manifestName: 'citizenwallet-release-android.json',
    publicName: 'Android',
  },
  ios: {
    assetNames: ['citizenwallet.ipa'],
    manifestName: 'citizenwallet-release-ios.json',
    publicName: 'iOS',
  },
};

test('Android从真实源码根启动Gradle并读取缓存Flutter配置', () => {
  const settings = readFileSync(new URL('../android/settings.gradle.kts', import.meta.url), 'utf8');
  const root = readFileSync(new URL('../android/build.gradle.kts', import.meta.url), 'utf8');
  const application = readFileSync(new URL('../android/app/build.gradle.kts', import.meta.url), 'utf8');
  const properties = readFileSync(new URL('../android/gradle.properties', import.meta.url), 'utf8');
  const runner = readFileSync(new URL('../scripts/citizenwallet-run.sh', import.meta.url), 'utf8');
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
  assert.match(runner, /cd "\$CITIZENWALLET_DIR\/android"/u);
  assert.match(runner, /--no-problems-report/u);
  assert.match(runner, /--init-script "\$\{TATA_CONSOLE_GRADLE_INIT_SCRIPT/u);
  assert.match(runner, /TATA_CONSOLE_FLUTTER_GRADLE_ROOT="\$flutter_sdk\/packages\/flutter_tools\/gradle"/u);
  assert.match(runner, /java_home="\$\{JAVA_HOME:-\/Applications\/Android Studio\.app\/Contents\/jbr\/Contents\/Home\}"/u);
  assert.match(runner, /ANDROID_HOME="\$android_sdk" ANDROID_SDK_ROOT="\$android_sdk" JAVA_HOME="\$java_home" PATH="\$java_home\/bin:\$PATH"[\s\S]*"\$CITIZENWALLET_DIR\/android\/gradlew"/u);
  assert.doesNotMatch(runner, /\/usr\/libexec\/java_home|java --version|java -version/u);
  assert.match(runner, /"\$CITIZENWALLET_DIR\/android\/gradlew"[\s\S]*--project-cache-dir "\$BUILD_WORK_DIR\/gradle-project"/u);
  assert.match(runner, /cp "\$ANDROID_APK" "\$TATA_CONSOLE_CACHE_DIR\/android\.apk"/u);
});

function actionStep(name) {
  const marker = `      name: ${name}\n`;
  const nameStart = actionSource.indexOf(marker);
  assert.notEqual(nameStart, -1, `中央 action 缺少步骤：${name}`);
  assert.equal(
    actionSource.indexOf(marker, nameStart + marker.length),
    -1,
    `中央 action 存在重复步骤：${name}`,
  );
  // 中文边界：步骤所属 job 与 writer 同属发布合同；切片必须保留前置 if，
  // 避免实现内容正确却被误接到另一个 Release job 时测试仍然通过。
  const startBoundary = actionSource.lastIndexOf('\n    - if:', nameStart);
  assert.notEqual(startBoundary, -1, `中央 action 步骤缺少 job 条件：${name}`);
  const start = startBoundary + 1;
  const end = actionSource.indexOf('\n    - if:', nameStart + marker.length);
  assert.notEqual(end, -1, `中央 action 步骤没有结束边界：${name}`);
  return actionSource.slice(start, end);
}

// 中文边界：测试必须执行中央 action 真正上线的 heredoc，禁止在产品仓复制 writer，
// 否则中央清单发生漂移时会形成虚假通过。
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
  const path = mkdtempSync(join(tmpdir(), 'gmb-citizenwallet-release-manifest-'));
  temporaryRoots.push(path);
  return path;
}

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function runManifestWriter(platform) {
  const spec = platforms[platform];
  const root = temporaryRoot();
  const releasePath = join(root, 'citizenwallet', 'build', 'release');
  mkdirSync(releasePath, { recursive: true });

  for (const assetName of spec.assetNames) {
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

  const manifest = JSON.parse(readFileSync(join(releasePath, spec.manifestName), 'utf8'));
  return { manifest, platform, releasePath };
}

function expectedManifest({ platform, releasePath }) {
  const spec = platforms[platform];
  return {
    product_id: 'citizenwallet',
    version,
    github_run_number: Number(runNumber),
    head_sha: sourceSha,
    bundle_id: 'ios.citizenwallet',
    package_name: 'com.crcfrcn.citizenwallet',
    assets: spec.assetNames.map((assetName) => ({
      platform: spec.publicName,
      asset_name: assetName,
      asset_sha256: sha256(join(releasePath, assetName)),
    })),
  };
}

function assertManifestContract(written, candidate = written.manifest) {
  const expected = expectedManifest(written);
  assert.deepEqual(Object.keys(candidate).sort(), topLevelFields);
  assert.ok(Array.isArray(candidate.assets), 'assets 必须是数组');
  for (const asset of candidate.assets) {
    assert.deepEqual(Object.keys(asset).sort(), assetFields);
  }
  assert.deepEqual(
    candidate.assets.map(({ asset_name: name }) => name).sort(),
    expected.assets.map(({ asset_name: name }) => name).sort(),
    '正式资产必须是无缺失、无重复、无增加的精确闭集',
  );
  assert.deepEqual(candidate, expected);
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

afterEach(() => {
  for (const path of temporaryRoots.splice(0)) {
    rmSync(path, { force: true, recursive: true });
  }
});

test('中央真实 writer 生成七顶层字段、三资产字段、真实 SHA 与精确资产闭集', () => {
  for (const platform of ['android', 'ios']) {
    const written = runManifestWriter(platform);
    assertManifestContract(written);
    const job = platform === 'android'
      ? "citizenwallet_release_android__build_apk"
      : "citizenwallet_release_ios__ios";
    assert.ok(
      actionStep(`生成并核验 ${platforms[platform].publicName} 正式清单`)
        .includes(`if: \${{ inputs.job == '${job}' }}`),
      `${platform} writer 必须绑定到对应正式 Release job`,
    );
  }
});

test('公开 platform、字段和资产闭集的负向漂移全部被拒绝', () => {
  const android = runManifestWriter('android');
  const ios = runManifestWriter('ios');
  const cases = [
    ['Android 小写', android, (value) => { value.assets[0].platform = 'android'; }],
    ['iOS 小写', ios, (value) => { value.assets[0].platform = 'ios'; }],
    ['Android 错误大小写', android, (value) => { value.assets[0].platform = 'ANDROID'; }],
    ['iOS 错误大小写', ios, (value) => { value.assets[0].platform = 'IOS'; }],
    ['顶层字段缺失', android, (value) => { delete value.bundle_id; }],
    ['顶层字段增加', android, (value) => { value.version_tag = 'citizenwallet-android-v3.4.5'; }],
    ['产品身份漂移', android, (value) => { value.product_id = 'citizenapp'; }],
    ['Apple 身份漂移', ios, (value) => { value.bundle_id = 'ios.citizenapp'; }],
    ['Android 身份漂移', android, (value) => { value.package_name = 'com.crcfrcn.citizenapp'; }],
    ['资产字段缺失', ios, (value) => { delete value.assets[0].asset_sha256; }],
    ['资产字段增加', ios, (value) => { value.assets[0].download_url = 'https://example.invalid'; }],
    ['资产摘要漂移', ios, (value) => { value.assets[0].asset_sha256 = '0'.repeat(64); }],
    ['资产名错误大小写', android, (value) => { value.assets[0].asset_name = 'CitizenWallet.apk'; }],
    ['资产缺失', android, (value) => { value.assets.pop(); }],
    ['资产重复', android, (value) => { value.assets.push(clone(value.assets[0])); }],
    ['资产增加', ios, (value) => {
      value.assets.push({
        platform: 'iOS',
        asset_name: 'citizenwallet.zip',
        asset_sha256: '0'.repeat(64),
      });
    }],
  ];

  for (const [name, written, mutate] of cases) {
    const candidate = clone(written.manifest);
    mutate(candidate);
    assert.throws(
      () => assertManifestContract(written, candidate),
      { name: 'AssertionError' },
      name,
    );
  }
});

test('正式 Tag 与内部 target/workflow 继续使用既有小写 wire', () => {
  const identities = [
    {
      name: '验证公民钱包 Android Release 的正式版本 Tag',
      command: '--prefix citizenwallet-android-v --product-id citizenwallet --target android --workflow gmb.citizenwallet.android.ci',
    },
    {
      name: '验证公民钱包 iOS Release 的正式版本 Tag',
      command: '--prefix citizenwallet-ios-v --product-id citizenwallet --target ios --workflow gmb.citizenwallet.ios.ci',
    },
  ];

  for (const { name, command } of identities) {
    const compactStep = actionStep(name).replace(/\s+/g, ' ');
    assert.ok(compactStep.includes('--version-tag "$GMB_VERSION_TAG"'));
    assert.ok(compactStep.includes(command));
  }
});
