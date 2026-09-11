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
    // 钱包所有资源统一归属 resources；Android 只读取其中的平台资源。
    sourceSets.getByName("main").res.directories.apply {
        clear()
        add("../../resources/android")
    }

    namespace = "com.crcfrcn.citizenwallet"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

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
        // Google Play 永久应用标识与 Kotlin namespace 保持一致，不改变现有安装数据。
        applicationId = "com.crcfrcn.citizenwallet"
        // local_auth 3.x 与新 SecureStorage 加固配置统一要求 API ≥ 24。
        minSdk = 24
        targetSdk = 36
        versionCode = productVersionCode
        versionName = productVersionName
        ndk {
            // CitizenWallet Android 唯一支持 64 位 ARM；禁止恢复其他 ABI。
            abiFilters.add("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // 所有环境只生成无私钥 Release 候选。正式 JKS 只存在 TataConsole 的
            // Data Protection Keychain，并由原生安全进程在 Touch ID 后通过匿名 stdin 使用。
            signingConfig = null
            // release 不加 keepDebugSymbols：APK 保持精简，也不把内部符号随包发出。
            // 线上崩溃的反解依赖构建时留档的未剥离产物
            // android/app/src/main/jniLibs/arm64-v8a/libcitizenwallet_signer.so
            // （Cargo 侧 strip=false 保证它始终带符号），剥离只发生在打包阶段。
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

// 统一使用Kotlin公开编译配置，与Java 17字节码保持一致。
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    // Gradle根保持在产品源码，Flutter输入根按当前产品执行环境选择。
    source = System.getenv("TATA_CONSOLE_FLUTTER_ROOT") ?: "../.."
}

// 钱包内置硬件金库直接使用宿主依赖。
dependencies {
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.core:core:1.13.1")
    testImplementation("junit:junit:4.13.2")
}
