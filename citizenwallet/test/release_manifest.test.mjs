import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const settings = readFileSync(new URL('../android/settings.gradle.kts', import.meta.url), 'utf8');
const root = readFileSync(new URL('../android/build.gradle.kts', import.meta.url), 'utf8');
const application = readFileSync(new URL('../android/app/build.gradle.kts', import.meta.url), 'utf8');
const properties = readFileSync(new URL('../android/gradle.properties', import.meta.url), 'utf8');
const wrapper = readFileSync(new URL('../android/gradle/wrapper/gradle-wrapper.properties', import.meta.url), 'utf8');
const runner = readFileSync(new URL('../scripts/citizenwallet-run.sh', import.meta.url), 'utf8');
const signerPodspec = readFileSync(new URL('../ios/signer/citizenwallet_signer.podspec', import.meta.url), 'utf8');

test('钱包真实入口只在源码外工程执行Pub，缺参和链接逃逸必须在写入前失败', context => {
  const fixture = mkdtempSync(join(tmpdir(), 'wallet-project-boundary-'));
  context.after(() => rmSync(fixture, { recursive: true, force: true }));
  const source = fileURLToPath(new URL('..', import.meta.url));
  const script = fileURLToPath(new URL('../scripts/citizenwallet-run.sh', import.meta.url));
  const project = join(fixture, 'project');
  const bin = join(fixture, 'bin');
  mkdirSync(project);
  mkdirSync(bin);
  symlinkSync(join(source, 'pubspec.yaml'), join(project, 'pubspec.yaml'));
  // 真实执行产品入口和路径校验；只替换Flutter，记录Pub实际工作目录后停止昂贵编译。
  writeFileSync(join(bin, 'flutter'), '#!/bin/bash\ncase "$1" in\nconfig) exit 0;;\npub) mkdir .dart_tool; printf "%s" "$PWD" > "$TRACE"; exit 73;;\n*) exit 90;;\nesac\n', { mode: 0o755 });
  const trace = join(fixture, 'trace');
  const env = {
    PATH: `${bin}:${process.env.PATH}`,
    TMPDIR: fixture,
    CITIZENWALLET_WORK_DIR: join(fixture, 'work'),
    TRACE: trace,
  };
  function run(projectRoot, platform = 'ios') {
    return spawnSync('/bin/bash', [script, platform], {
      env: { ...env, ...(projectRoot === undefined ? {} : { CITIZENWALLET_PROJECT_ROOT: projectRoot }) },
      encoding: 'utf8', timeout: 10000,
    });
  }
  for (const platform of ['ios', 'android']) {
    const missing = run(undefined, platform);
    assert.notEqual(missing.status, 0);
    assert.match(missing.stderr, /必须提供源码外/u);
    for (const root of [source, resolve(source, 'ios', '..'), '.']) {
      const rejected = run(root, platform);
      assert.notEqual(rejected.status, 0);
      assert.equal(existsSync(trace), false);
    }
  }
  const sourceLink = join(fixture, 'source-link');
  symlinkSync(source, sourceLink);
  assert.match(run(sourceLink).stderr, /源码外绝对路径/u);
  symlinkSync(source, join(project, '.dart_tool'));
  assert.match(run(project).stderr, /源码外绝对路径/u);
  assert.equal(existsSync(trace), false);
  unlinkSync(join(project, '.dart_tool'));
  // Kotlin持久目录同样不能通过已有链接把状态写回源码，且拒绝必须早于Pub。
  const kotlinState = join(fixture, 'work', 'work', 'kotlin-project');
  mkdirSync(join(fixture, 'work', 'work'), { recursive: true });
  symlinkSync(source, kotlinState);
  for (const platform of ['ios', 'android']) {
    assert.match(run(project, platform).stderr, /源码外绝对路径/u);
    assert.equal(existsSync(trace), false);
  }
  unlinkSync(kotlinState);
  for (const platform of ['ios', 'android']) {
    const accepted = run(project, platform);
    assert.equal(accepted.status, 73, accepted.stderr);
    assert.equal(readFileSync(trace, 'utf8'), project);
    assert.equal(existsSync(join(project, '.dart_tool')), true);
    rmSync(join(project, '.dart_tool'), { recursive: true });
  }
});

test('Android从真实产品源码根启动Gradle并把可写状态放入外部工作目录', () => {
  assert.match(settings, /System\.getenv\("CITIZENWALLET_PROJECT_ROOT"\)/u);
  assert.match(settings, /settingsDir\.parentFile/u);
  assert.match(settings, /resolve\("android\/local\.properties"\)/u);
  assert.match(settings, /\.flutter-plugins-dependencies/u);
  assert.doesNotMatch(settings, /dev\.flutter\.flutter-plugin-loader|System\.getProperty\("user\.dir"\)/u);
  assert.doesNotMatch(settings, /id\("com\.android\.(?:application|library)"\)\s+version/u);
  assert.match(root, /System\.getenv\("CITIZENWALLET_BUILD_DIR"\)/u);
  assert.match(root, /System\.getProperty\("java\.io\.tmpdir"\)/u);
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
  assert.match(root, /classpath\("com\.android\.tools\.build:gradle:9\.0\.1"\)/u);
  assert.match(root, /classpath\("org\.jetbrains\.kotlin:kotlin-gradle-plugin:2\.2\.20"\)/u);
  assert.match(wrapper, /gradle-9\.1\.0-bin\.zip/u);
  assert.match(wrapper, /distributionSha256Sum=a17ddd85a26b6a7f5ddb71ff8b05fc5104c0202c6e64782429790c933686c806/u);
  assert.doesNotMatch(`${root}\n${wrapper}`, /gradle-(?:8\.|9\.1\.0-all)/u);
  assert.match(application, /System\.getenv\("CITIZENWALLET_PROJECT_ROOT"\) \?: "\.\.\/\.\."/u);
  assert.match(application, /System\.getenv\("CITIZENWALLET_NATIVE_ANDROID_DIR"\)/u);
  assert.match(runner, /cd "\$CITIZENWALLET_DIR\/android"/u);
  assert.match(runner, /--init-script "\$CITIZENWALLET_GRADLE_INIT_SCRIPT"/u);
  assert.match(runner, /-Pkotlin\.project\.persistent\.dir="\$BUILD_WORK_DIR\/kotlin-project"/u);
  assert.match(runner, /CITIZENWALLET_FLUTTER_GRADLE_ROOT="\$flutter_sdk\/packages\/flutter_tools\/gradle"/u);
  assert.match(runner, /cp "\$ANDROID_APK" "\$ARTIFACT_ROOT\/android\.apk"/u);
});

test('CitizenWallet依赖准备默认联网且离线模式必须显式选择', () => {
  assert.match(runner, /PUB_GET_ARGS=\(--enforce-lockfile\)/u);
  assert.match(runner, /CITIZENWALLET_OFFLINE:-false/u);
  assert.match(runner, /CITIZENWALLET_PUB_OFFLINE:-false/u);
  assert.match(runner, /GRADLE_ARGS=\(--no-daemon\)/u);
  assert.match(runner, /project\.extensions\.extraProperties\.set\("kotlin\.project\.persistent\.dir", new File\(output, suffix \+ "\/kotlin-project"\)\.path\)/u);
  assert.match(runner, /true\) PUB_OFFLINE=true; GRADLE_ARGS\+=\(--offline\); export CARGO_NET_OFFLINE=true/u);
  assert.match(runner, /gradlew" "\$\{GRADLE_ARGS\[@\]\}" --stacktrace/u);
  assert.match(runner, /if \[\[ "\$PUB_OFFLINE" == true \]\]; then PUB_GET_ARGS\+=\(--offline\); fi/u);
  assert.match(runner, /flutter pub get "\$\{PUB_GET_ARGS\[@\]\}"/u);
});

test('iOS签名库由外部构建路径强制链接且保留全部FFI符号', () => {
  assert.match(signerPodspec, /library_path = File\.expand_path\('libcitizenwallet_signer\.a', native_dir\)/u);
  assert.doesNotMatch(signerPodspec, /s\.vendored_libraries\s*=/u);
  assert.match(signerPodspec, /'OTHER_LDFLAGS' => "-force_load #\{library_path\} /u);
  for (const symbol of [
    'citizen_sr25519_derive_hard',
    'citizen_sr25519_public_key',
    'citizen_sr25519_sign',
    'citizen_sr25519_verify',
    'account_crypto_derive_key',
    'account_crypto_x25519_public_key',
    'account_crypto_seal',
    'account_crypto_open',
  ]) {
    assert.ok(signerPodspec.includes(`-Wl,-u,_${symbol}`), `缺少链接符号 ${symbol}`);
  }
});
