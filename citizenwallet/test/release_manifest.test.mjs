import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const settings = readFileSync(new URL('../android/settings.gradle.kts', import.meta.url), 'utf8');
const root = readFileSync(new URL('../android/build.gradle.kts', import.meta.url), 'utf8');
const application = readFileSync(new URL('../android/app/build.gradle.kts', import.meta.url), 'utf8');
const properties = readFileSync(new URL('../android/gradle.properties', import.meta.url), 'utf8');
const wrapper = readFileSync(new URL('../android/gradle/wrapper/gradle-wrapper.properties', import.meta.url), 'utf8');
const runner = readFileSync(new URL('../scripts/citizenwallet-run.sh', import.meta.url), 'utf8');

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
  assert.match(runner, /CITIZENWALLET_FLUTTER_GRADLE_ROOT="\$flutter_sdk\/packages\/flutter_tools\/gradle"/u);
  assert.match(runner, /cp "\$ANDROID_APK" "\$ARTIFACT_ROOT\/android\.apk"/u);
});

test('CitizenWallet依赖准备默认联网且离线模式必须显式选择', () => {
  assert.match(runner, /PUB_GET_ARGS=\(--enforce-lockfile\)/u);
  assert.match(runner, /CITIZENWALLET_OFFLINE:-false/u);
  assert.match(runner, /flutter pub get "\$\{PUB_GET_ARGS\[@\]\}"/u);
});
