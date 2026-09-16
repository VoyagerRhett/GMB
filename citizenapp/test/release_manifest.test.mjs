import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const settings = readFileSync(new URL('../android/settings.gradle.kts', import.meta.url), 'utf8');
const root = readFileSync(new URL('../android/build.gradle.kts', import.meta.url), 'utf8');
const application = readFileSync(new URL('../android/app/build.gradle.kts', import.meta.url), 'utf8');
const properties = readFileSync(new URL('../android/gradle.properties', import.meta.url), 'utf8');
const wrapper = readFileSync(new URL('../android/gradle/wrapper/gradle-wrapper.properties', import.meta.url), 'utf8');
const runner = readFileSync(new URL('../scripts/citizenapp-run.sh', import.meta.url), 'utf8');
const iosUITestRunner = readFileSync(new URL('../scripts/citizenapp-ios-ui-test.sh', import.meta.url), 'utf8');
const iosUITests = readFileSync(new URL('../ios/RunnerUITests/RunnerUITests.swift', import.meta.url), 'utf8');
const viewScript = fileURLToPath(new URL('../scripts/citizenapp-view.mjs', import.meta.url));
const view = readFileSync(viewScript, 'utf8');
const podfile = readFileSync(new URL('../ios/Podfile', import.meta.url), 'utf8');
const testRunner = readFileSync(new URL('../scripts/citizenapp-test.sh', import.meta.url), 'utf8');
const pubspec = readFileSync(new URL('../pubspec.yaml', import.meta.url), 'utf8');
const pubLock = readFileSync(new URL('../pubspec.lock', import.meta.url), 'utf8');
const podLock = readFileSync(new URL('../ios/Podfile.lock', import.meta.url), 'utf8');
const tataChatRoot = new URL('../../../TATA/tatachatsdk/', import.meta.url);
const tataChatPubspec = readFileSync(new URL('pubspec.yaml', tataChatRoot), 'utf8');
const tataChatPubLock = readFileSync(new URL('pubspec.lock', tataChatRoot), 'utf8');
const tataChatAndroid = readFileSync(new URL('android/build.gradle.kts', tataChatRoot), 'utf8');
const tataChatAndroidPlugin = readFileSync(
  new URL('android/src/main/java/chat/tata/sdk/TataChatSdkPlugin.java', tataChatRoot), 'utf8');
const tataChatIOSPlugin = readFileSync(new URL('ios/TataChatSdkPlugin.swift', tataChatRoot), 'utf8');
const tataChatProbe = readFileSync(new URL('lib/src/attachment/probe.dart', tataChatRoot), 'utf8');
const tataChatAttachmentPlatform = readFileSync(
  new URL('lib/src/attachment/attachment_platform.dart', tataChatRoot), 'utf8');
const tataChatConversation = readFileSync(
  new URL('lib/src/ui/conversation/conversation_page.dart', tataChatRoot), 'utf8');

test('CitizenApp locks the shared Dart protocol generator exactly', () => {
  assert.match(pubspec, /^  protoc_plugin: 25[.]0[.]0$/mu);
  assert.doesNotMatch(pubspec, /^  protoc_plugin: [\^~><=]/mu);
});

test('CitizenApp与TataChatSDK只装配AGP9内置Kotlin兼容的移动插件闭包', () => {
  assert.match(pubspec, /^  mobile_scanner: 7[.]4[.]2$/mu);
  assert.match(pubspec, /^  saver_gallery: 5[.]1[.]0$/mu);
  assert.doesNotMatch(pubspec, /^  (?:file_picker|video_compress):/mu);
  assert.match(tataChatPubspec, /^  emoji_picker_flutter: 4[.]5[.]4$/mu);
  assert.match(tataChatPubspec, /^  saver_gallery: 5[.]1[.]0$/mu);
  assert.doesNotMatch(tataChatPubspec, /^  (?:file_picker|video_compress):/mu);
  assert.doesNotMatch(tataChatProbe, /package:video_compress|VideoCompress/u);

  for (const [name, version] of [
    ['emoji_picker_flutter', '4.5.4'],
    ['flutter_image_compress_common', '1.1.1'],
    ['mobile_scanner', '7.4.2'],
    ['quill_native_bridge', '11.2.0'],
    ['quill_native_bridge_android', '0.0.2'],
    ['saver_gallery', '5.1.0'],
    ['shared_preferences_android', '2.4.28'],
  ]) {
    assert.match(pubLock, new RegExp(`^  ${name}:\\n(?:    .*\\n)+?    version: "${version.replaceAll('.', '[.]')}"$`, 'mu'));
  }
  for (const source of [pubLock, tataChatPubLock]) {
    assert.doesNotMatch(source, /^  (?:android_file_picker|file_picker|file_picker_darwin|file_picker_linux|file_picker_platform_interface|file_picker_web|video_compress|windows_file_picker):/mu);
  }
  assert.doesNotMatch(podLock, /(?:^|\n)  - file_picker_darwin\b|file_picker_darwin:/u);

  assert.match(tataChatAndroid, /id\("com[.]android[.]library"\)/u);
  assert.doesNotMatch(tataChatAndroid, /kotlin-android|org[.]jetbrains[.]kotlin[.]android/u);
  assert.match(tataChatAndroidPlugin, /MediaMetadataRetriever/u);
  assert.match(tataChatAndroidPlugin, /getScaledFrameAtTime/u);
  assert.match(tataChatAndroidPlugin, /Build[.]VERSION[.]SDK_INT < Build[.]VERSION_CODES[.]O_MR1/u);
  assert.match(tataChatAndroidPlugin, /implements FlutterPlugin, ActivityAware/u);
  assert.match(tataChatAndroidPlugin, /Intent[.]ACTION_OPEN_DOCUMENT/u);
  assert.match(tataChatAndroidPlugin, /MAX_SELECTED_BYTES = 512L \* 1024L \* 1024L/u);
  assert.match(tataChatIOSPlugin, /AVAssetImageGenerator/u);
  assert.match(tataChatIOSPlugin, /maximumSize = CGSize\(width: 64, height: 64\)/u);
  assert.match(tataChatIOSPlugin, /UIDocumentPickerViewController/u);
  assert.match(tataChatAttachmentPlatform, /chat[.]tata[.]sdk\/attachment/u);
  assert.match(tataChatConversation, /ChatAttachmentPlatform\(\)[.]pickFile\(\)/u);
  assert.match(tataChatConversation, /finally \{[\s\S]*temporary[.]delete\(\)/u);
  assert.doesNotMatch(tataChatConversation, /FilePicker|package:file_picker/u);
  assert.doesNotMatch(`${tataChatAttachmentPlatform}\n${tataChatAndroidPlugin}\n${tataChatIOSPlugin}`, /media_probe/u);
});

test('Android从真实产品源码根启动Gradle并把可写状态放入外部工作目录', () => {
  assert.match(settings, /System\.getenv\("CITIZENAPP_PROJECT_ROOT"\)/u);
  assert.match(settings, /settingsDir\.parentFile/u);
  assert.match(settings, /resolve\("android\/local\.properties"\)/u);
  assert.match(settings, /\.flutter-plugins-dependencies/u);
  assert.doesNotMatch(settings, /dev\.flutter\.flutter-plugin-loader|System\.getProperty\("user\.dir"\)/u);
  assert.doesNotMatch(settings, /id\("com\.android\.(?:application|library)"\)\s+version/u);
  assert.match(root, /classpath\("com\.android\.tools\.build:gradle:9\.0\.1"\)/u);
  assert.match(root, /classpath\("org\.jetbrains\.kotlin:kotlin-gradle-plugin:2\.2\.20"\)/u);
  assert.doesNotMatch(root, /com\.android\.tools\.build:gradle:8\./u);
  assert.match(root, /System\.getenv\("CITIZENAPP_BUILD_DIR"\)/u);
  assert.match(root, /System\.getProperty\("java\.io\.tmpdir"\)/u);
  assert.match(application, /import java\.util\.Properties/u);
  assert.doesNotMatch(application, /java\.util\.Properties\(\)|setSrcDirs\(/u);
  assert.match(application, /compileSdk = 36/u);
  assert.match(application, /ndkVersion = "28\.2\.13676358"/u);
  assert.match(application, /minSdk = 24/u);
  assert.match(application, /targetSdk = 36/u);
  assert.doesNotMatch(application, /(?:compileSdk|ndkVersion|minSdk|targetSdk)\s*=.*\bflutter\./u);
  assert.deepEqual(properties.split('\n').filter((line) => /^android\.(?:builtInKotlin|newDsl)=/u.test(line)), [
    'android.builtInKotlin=true', 'android.newDsl=true',
  ]);
  const pluginBlock = application.slice(application.indexOf('plugins {'), application.indexOf('\n}'));
  assert.ok(pluginBlock.indexOf('id("com.android.application")')
    < pluginBlock.indexOf('id("dev.flutter.flutter-gradle-plugin")'));
  assert.doesNotMatch(pluginBlock, /org\.jetbrains\.kotlin\.android|kotlin-android/u);
  assert.match(application, /kotlin \{[\s\S]*compilerOptions[\s\S]*JvmTarget\.JVM_17/u);
  assert.match(wrapper, /distributionUrl=https\\:\/\/services\.gradle\.org\/distributions\/gradle-9\.1\.0-bin\.zip/u);
  assert.match(wrapper, /distributionSha256Sum=a17ddd85a26b6a7f5ddb71ff8b05fc5104c0202c6e64782429790c933686c806/u);
  assert.doesNotMatch(wrapper, /gradle-8\./u);
  assert.match(application, /System\.getenv\("CITIZENAPP_PROJECT_ROOT"\) \?: "\.\.\/\.\."/u);
  assert.match(runner, /cd "\$APP_ROOT\/android"/u);
  assert.match(runner, /--no-problems-report/u);
  assert.match(runner, /--init-script "\$CITIZENAPP_GRADLE_INIT_SCRIPT"/u);
  assert.match(runner, /retain_android_local_artifact\(\)/u);
  assert.match(runner, /android[.]apk[.]pending/u);
  assert.match(runner, /destination="\$ARTIFACT_ROOT\/android[.]apk"/u);
  assert.match(runner, /retain_android_local_artifact "\$ANDROID_APK"/u);
  assert.match(runner, /gradle\.beforeSettings \{ settings ->/u);
  assert.match(runner, /settings\.settingsDir\.canonicalPath == new File\(source\)\.canonicalPath/u);
  const includedBuildRepositories = runner.slice(
    runner.indexOf('settings.pluginManagement.repositories'),
    runner.indexOf("'gradle.beforeProject"),
  );
  assert.ok(includedBuildRepositories.indexOf('mavenCentral()')
    < includedBuildRepositories.indexOf('google()'));
  assert.ok(includedBuildRepositories.indexOf('google()')
    < includedBuildRepositories.indexOf('gradlePluginPortal()'));
  assert.doesNotMatch(includedBuildRepositories, /resolutionStrategy|force\(|PUB_CACHE|TATA_CONSOLE/u);
  assert.match(runner, /CITIZENAPP_FLUTTER_GRADLE_ROOT="\$flutter_sdk\/packages\/flutter_tools\/gradle"/u);
  assert.match(runner, /java_home="\$ANDROID_JAVA_HOME"/u);
  assert.match(runner, /ANDROID_JAVA_HOME="\$\{JAVA_HOME:-\/Applications\/Android Studio\.app\/Contents\/jbr\/Contents\/Home\}"/u);
  assert.match(runner, /ANDROID_SDK_HOME="\$\{ANDROID_HOME:-\$\{ANDROID_SDK_ROOT:-\$HOME\/Library\/Android\/sdk\}\}"/u);
  assert.match(runner, /ANDROID_HOME与ANDROID_SDK_ROOT必须一致/u);
  assert.match(runner, /ANDROID_SDK_HOME\/ndk\/28\.2\.13676358/u);
  assert.match(runner, /-x "\$ANDROID_JAVA_HOME\/bin\/java"/u);
  assert.match(runner, /ANDROID_HOME="\$android_sdk" ANDROID_SDK_ROOT="\$android_sdk" JAVA_HOME="\$java_home" PATH="\$java_home\/bin:\$PATH"/u);
  assert.match(runner, /"\$APP_ROOT\/android\/gradlew"[\s\S]*--project-cache-dir "\$BUILD_WORK_DIR\/gradle-project"/u);
  assert.match(runner, /CITIZENSDK_GRADLE="\$APP_ROOT\/android\/gradlew"[\s\S]*build-native\.sh" android/u);
  assert.match(runner, /CITIZENSDK_GRADLE="\$APP_ROOT\/android\/gradlew"[\s\S]*JAVA_HOME="\$ANDROID_JAVA_HOME" PATH="\$ANDROID_JAVA_HOME\/bin:\$PATH"/u);
  assert.match(runner, /CITIZENAPP_GRADLE_OFFLINE="\$\{CITIZENAPP_GRADLE_OFFLINE:-\$\{CITIZENAPP_OFFLINE:-false\}\}"/u);
  assert.match(runner, /gradle_network_arg=''/u);
  assert.match(runner, /true\) gradle_network_arg='--offline'/u);
  assert.match(runner, /\$\{gradle_network_arg:\+"\$gradle_network_arg"\}/u);
  assert.doesNotMatch(runner, /GRADLE_NETWORK_ARGS/u);
  assert.match(runner, /CITIZENSDK_OFFLINE="\$CITIZENAPP_GRADLE_OFFLINE"/u);
  assert.match(runner, /ANDROID_HOME="\$ANDROID_SDK_HOME" ANDROID_SDK_ROOT="\$ANDROID_SDK_HOME"[\s\S]*build-native\.sh" android/u);
});

test('iOS Pod装配保留调用方工程路径且不把生成状态写回源码', () => {
  assert.match(podfile, /flutter_install_all_ios_pods File\.dirname\(File\.expand_path\(__FILE__\)\)/u);
  assert.doesNotMatch(podfile, /flutter_install_all_ios_pods File\.dirname\(File\.realpath\(__FILE__\)\)/u);
});

test('CitizenApp直接开发自建源码外视图并只投影当轮Framework', () => {
  const fixture = realpathSync(mkdtempSync(join(tmpdir(), 'citizenapp-view-test-')));
  try {
    const workspace = join(fixture, 'workspace');
    const app = join(workspace, 'GMB', 'citizenapp');
    const sdk = join(workspace, 'GMB', 'citizensdk');
    const chat = join(workspace, 'TATA', 'tatachatsdk');
    const formalChatSource = join(workspace, 'packages', 'tatachatsdk');
    const formalChat = join(workspace, 'FORMAL', 'tatachatsdk');
    const work = join(fixture, 'work');
    for (const directory of [join(app, 'lib'), join(app, '.dart_tool'), join(app, 'android'),
      join(sdk, 'darwin'), join(chat, 'ios'), formalChatSource, join(workspace, 'FORMAL')]) {
      mkdirSync(directory, { recursive: true });
    }
    symlinkSync(formalChatSource, formalChat, 'dir');
    writeFileSync(join(app, 'pubspec.yaml'), [
      'name: app', 'dependencies:', '  citizen_sdk:', '    path: ../citizensdk',
      '  tatachat_sdk:', '    path: ../../TATA/tatachatsdk',
      '  formal_chat_sdk:', '    path: ../../FORMAL/tatachatsdk', '',
    ].join('\n'));
    writeFileSync(join(app, 'lib/main.dart'), 'void main() {}\n');
    writeFileSync(join(app, '.dart_tool/forbidden'), 'generated\n');
    writeFileSync(join(app, 'android/settings.gradle'), 'generated by caller\n');
    writeFileSync(join(sdk, 'pubspec.yaml'), 'name: citizen_sdk\n');
    writeFileSync(join(sdk, 'darwin/citizen_sdk.podspec'), 'podspec\n');
    writeFileSync(join(chat, 'pubspec.yaml'), 'name: tatachat_sdk\n');
    writeFileSync(join(chat, 'ios/tatachat_sdk.podspec'), 'podspec\n');
    writeFileSync(join(formalChatSource, 'pubspec.yaml'), 'name: formal_chat_sdk\n');
    const project = execFileSync(process.execPath, [viewScript, 'create',
      '--source-root', app, '--work-root', work], { encoding: 'utf8' }).trim();
    assert.equal(project, join(work, 'source-view', app.replace(/^\/+/, '')));
    assert.equal(lstatSync(join(project, 'lib/main.dart')).isSymbolicLink(), true);
    assert.equal(lstatSync(join(work, 'source-view', sdk.replace(/^\/+/, ''),
      'pubspec.yaml')).isSymbolicLink(), true);
    assert.equal(lstatSync(join(work, 'source-view', chat.replace(/^\/+/, ''),
      'pubspec.yaml')).isSymbolicLink(), true);
    const formalManifest = join(work, 'source-view', formalChat.replace(/^\/+/, ''),
      'pubspec.yaml');
    assert.equal(lstatSync(formalManifest).isSymbolicLink(), true);
    assert.equal(realpathSync(formalManifest), join(formalChatSource, 'pubspec.yaml'));
    assert.equal(lstatSync(join(project, '.dart_tool'), { throwIfNoEntry: false }), undefined);
    assert.equal(lstatSync(join(project, 'android/settings.gradle'), { throwIfNoEntry: false }), undefined);

    const citizenFramework = join(work, 'native/CitizenSDK.xcframework');
    const chatFramework = join(work, 'native/TataChatSDK.xcframework');
    mkdirSync(citizenFramework, { recursive: true });
    mkdirSync(chatFramework, { recursive: true });
    const projectFramework = (packageRoot, packageSubpath, framework) => execFileSync(
      process.execPath, [viewScript, 'project-framework', '--source-root', app,
        '--project-root', project, '--work-root', work, '--package-root', packageRoot,
        '--package-subpath', packageSubpath, '--framework', framework], { encoding: 'utf8' }).trim();
    const citizenProjection = projectFramework(sdk,
      'darwin/CitizenSDK.xcframework', citizenFramework);
    const chatProjection = projectFramework(chat,
      'ios/TataChatSDK.xcframework', chatFramework);
    assert.equal(lstatSync(citizenProjection).isSymbolicLink(), true);
    assert.equal(realpathSync(citizenProjection), citizenFramework);
    assert.equal(lstatSync(chatProjection).isSymbolicLink(), true);
    assert.equal(realpathSync(chatProjection), chatFramework);
    assert.equal(projectFramework(sdk, 'darwin/CitizenSDK.xcframework', citizenFramework),
      citizenProjection);

    const outside = join(fixture, 'outside/CitizenSDK.xcframework');
    mkdirSync(outside, { recursive: true });
    const rejected = spawnSync(process.execPath, [viewScript, 'project-framework',
      '--source-root', app, '--project-root', project, '--work-root', work,
      '--package-root', sdk, '--package-subpath', 'darwin/Outside.xcframework',
      '--framework', outside], { encoding: 'utf8' });
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, /必须归属同一产品工作根/u);
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test('CitizenApp依赖准备默认联网且离线模式必须由调用方显式选择', () => {
  assert.match(runner, /PUB_GET_ARGS=\(--enforce-lockfile\)/u);
  assert.match(runner, /CITIZENAPP_OFFLINE:-false/u);
  assert.match(runner, /CITIZENAPP_GRADLE_OFFLINE只接受true或false/u);
  assert.match(runner, /flutter pub get "\$\{PUB_GET_ARGS\[@\]\}"/u);
});

test('CitizenApp测试只在源码外工程视图生成Flutter状态', () => {
  assert.match(testRunner, /node "\$VIEW_SCRIPT" create/u);
  assert.match(testRunner, /--source-root "\$CITIZENAPP_DIR" --work-root "\$CITIZENAPP_TEST_WORK_DIR"/u);
  assert.match(testRunner, /FLUTTER_ROOT="\$\(node/u);
  assert.doesNotMatch(testRunner, /FLUTTER_ROOT="\$CITIZENAPP_DIR"/u);
  assert.match(testRunner, /cd "\$FLUTTER_ROOT"/u);
});

test('CitizenApp Apple Build只调用产品视图投影且不向podspec传外部路径', () => {
  assert.match(runner, /node "\$VIEW_SCRIPT" create/u);
  assert.equal((runner.match(/node "\$VIEW_SCRIPT" project-framework/gu) ?? []).length, 2);
  assert.match(runner, /darwin\/CitizenSDK[.]xcframework/u);
  assert.match(runner, /ios\/TataChatSDK[.]xcframework/u);
  assert.doesNotMatch(runner, /CITIZENSDK_APPLE_FRAMEWORK_DIR|TATACHATSDK_APPLE_FRAMEWORK_DIR/u);
  assert.match(view, /generatedDirectories/u);
  assert.match(view, /project-framework/u);
});

test('iOS Release黑盒UI验收使用主动真机探测且不改变正式App', () => {
  assert.match(iosUITestRunner, /DEVICECTL = \["\/usr\/bin\/xcrun", "devicectl"\]/u);
  assert.match(iosUITestRunner, /command_json\(\["list", "devices"\]/u);
  assert.match(iosUITestRunner, /"device", "info", "details", "--device", identifier/u);
  assert.match(iosUITestRunner, /hardware[.]get\("reality"\) == "physical"/u);
  assert.match(iosUITestRunner, /connection[.]get\("pairingState"\) == "paired"/u);
  assert.match(iosUITestRunner, /developer_mode_enabled\(state[.]get\("developerModeStatus"\)\)/u);
  assert.match(iosUITestRunner, /for attempt in range\(ATTEMPTS\)/u);
  assert.match(iosUITestRunner, /time[.]sleep\(2\)/u);
  assert.doesNotMatch(iosUITestRunner, /get\("connection", \{\}\)[.]get\("state"\) != "connected"/u);
  assert.match(iosUITestRunner, /bundleContainerPath/u);
  assert.match(iosUITestRunner, /dataContainerPath/u);
  assert.match(iosUITestRunner, /relative[.]endswith\("[.]isar"\)/u);
  assert.match(iosUITestRunner, /set\(before\) - set\(after\)/u);
  assert.doesNotMatch(iosUITestRunner, /CitizenApp Isar 数据库必须且只能有一个/u);
  assert.doesNotMatch(iosUITestRunner, /uninstall app[^\n]*\$TARGET_BUNDLE_ID/u);

  assert.match(iosUITests, /testTransactionTabPreservesLiveChainHeaderAndEmptyPaymentForm/u);
  assert.match(iosUITests, /最终区块 \[0-9\]\+/u);
  assert.match(iosUITests, /XCTAssertGreaterThanOrEqual\(secondHeight, firstHeight/u);
  assert.match(iosUITests, /testWalletPagePreservesPublicSurfaceAndAvailableSdkEntry/u);
  assert.match(iosUITests, /testWalletGateLaunchesCitizenSdkCreateAndImportWithoutSecretInput/u);
  assert.match(iosUITests, /throw XCTSkip\("正式App尚无钱包/u);
  assert.match(iosUITests, /不输入助记词\/密码/u);
  assert.doesNotMatch(iosUITests, /typeText\(/u);
});
