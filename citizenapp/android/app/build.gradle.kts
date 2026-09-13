import java.util.Properties

plugins {
    id("com.android.application")
    // AGP提供内置Kotlin；Flutter插件在Android插件之后应用。
    id("dev.flutter.flutter-gradle-plugin")
}

val flutterProductRoot = System.getenv("TATA_CONSOLE_FLUTTER_ROOT")
    ?.let { file(it) }
    ?: rootProject.projectDir.parentFile
val flutterBuildProperties = Properties().apply {
    flutterProductRoot.resolve("android/local.properties").inputStream().use { load(it) }
}
val productVersionCode = flutterBuildProperties.getProperty("flutter.versionCode", "1").toInt()
val productVersionName = flutterBuildProperties.getProperty("flutter.versionName", "1.0")

android {
    namespace = "com.crcfrcn.citizenapp"
    compileSdk = 36
    ndkVersion = "28.2.13676358"
    // 设备测试必须挂到正式 Release 变体，禁止为验收生成影子 Debug 应用。
    testBuildType = "release"

    // TataConsole本机编译只从中央工作目录打包Rust库，产品仓库不得保留生成的jniLibs。
    System.getenv("TATA_CONSOLE_NATIVE_ANDROID_DIR")?.takeIf { it.isNotBlank() }?.let { nativeDir ->
        sourceSets.getByName("main").jniLibs.directories.apply {
            clear()
            add(nativeDir)
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Google Play 永久应用标识与 Kotlin namespace 保持一致，禁止恢复不可用旧包名。
        applicationId = "com.crcfrcn.citizenapp"
        minSdk = 24
        targetSdk = 36
        versionCode = productVersionCode
        versionName = productVersionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk {
            // CitizenApp Android 唯一支持 64 位 ARM；禁止恢复其他 ABI。
            abiFilters.add("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // 所有环境只生成无私钥 Release 候选。正式 JKS 只存在 TataConsole 的
            // Data Protection Keychain，并由原生安全进程在 Touch ID 后通过匿名 stdin 使用。
            signingConfig = null
            // Release 包不保留本地调试符号；CitizenSDK 原生库的构建与
            // 符号归档由 CitizenSDK 自己的产品流程负责。
        }
    }

    packaging {
        jniLibs {
            // 第三方插件可能携带非 ARM64 预编译库；打包阶段统一排除，确保 APK
            // 物理上只保留 defaultConfig 声明的 arm64-v8a。
            excludes.addAll(listOf("lib/armeabi*/**", "lib/x86/**", "lib/x86_64/**"))
        }
    }
}

dependencies {
    implementation("androidx.core:core:1.13.1")
    // 广场视频只走系统硬件 MediaCodec；Media3 提供受控的解码、缩放和 HEVC 编码帧管线。
    implementation("androidx.media3:media3-transformer:1.10.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}

// 统一使用Kotlin公开编译配置，与Java 17字节码保持一致。
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    // 本机任务从缓存Flutter根读取生成状态；普通产品构建仍以本工程根为Flutter根。
    source = System.getenv("TATA_CONSOLE_FLUTTER_ROOT") ?: "../.."
}
