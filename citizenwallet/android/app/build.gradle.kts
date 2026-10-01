import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.FileSystemOperations
import org.gradle.api.file.RelativePath
import org.gradle.api.tasks.CacheableTask
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import javax.inject.Inject
import java.util.Properties

plugins {
    id("com.android.application")
    // AGP提供内置Kotlin；Flutter插件在Android插件之后应用。
    id("dev.flutter.flutter-gradle-plugin")
}


// 限定资源的语义由明确映射保留；输入与输出隔离，正常编译自动依赖本任务。
@CacheableTask
abstract class PrepareCitizenWalletResources @Inject constructor(
    private val files: FileSystemOperations,
) : DefaultTask() {
    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val sourceDirectory: DirectoryProperty

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun prepare() {
        val names = mapOf(
            "drawable_launch_background.xml" to "drawable/launch_background.xml",
            "drawable-v21_launch_background.xml" to "drawable-v21/launch_background.xml",
            "values-en_strings.xml" to "values-en/strings.xml",
            "values-night_styles.xml" to "values-night/styles.xml",
        )
        val source = sourceDirectory.get().asFile
        names.keys.forEach { require(source.resolve(it).isFile) { "缺少平台资源输入：$it" } }
        require(!outputDirectory.get().asFile.toPath().toAbsolutePath().normalize()
            .startsWith(source.toPath().toAbsolutePath().normalize())) { "资源输出不得回写源码" }
        files.sync {
            from(sourceDirectory)
            into(outputDirectory)
            includeEmptyDirs = false
            exclude("**/.DS_Store")
            eachFile {
                names[relativePath.pathString]?.let { mapped ->
                    relativePath = RelativePath(true, *mapped.split('/').toTypedArray())
                }
            }
        }
    }
}

val prepareCitizenWalletResources = tasks.register<PrepareCitizenWalletResources>("prepareCitizenWalletResources") {
    sourceDirectory.set(layout.projectDirectory.dir("../../resources/android"))
    outputDirectory.set(layout.buildDirectory.dir("generated/qualified-resources"))
}

val flutterProductRoot = System.getenv("CITIZENWALLET_PROJECT_ROOT")
    ?.let { file(it) }
    ?: rootProject.projectDir.parentFile
val flutterBuildProperties = Properties().apply {
    flutterProductRoot.resolve("android/local.properties").inputStream().use { load(it) }
}
val productVersionCode = flutterBuildProperties.getProperty("flutter.versionCode", "1").toInt()
val productVersionName = flutterBuildProperties.getProperty("flutter.versionName", "1.0")

android {
    // AGP 9 的 Kotlin 与 Java 源集分别登记；单测位于 app 根，仅作为单文件测试输入。
    sourceSets.getByName("main").kotlin.directories.apply { clear(); add("src") }
    // Flutter 在当轮外部工程生成插件注册表；必须显式编译它，不能依赖源码内旧生成物。
    sourceSets.getByName("main").java.directories.apply {
        clear()
        add("src")
        add(flutterProductRoot.resolve("android/app/src/main/java").absolutePath)
    }
    sourceSets.getByName("main").manifest.srcFile("src/AndroidManifest.xml")
    sourceSets.getByName("test").kotlin.directories.clear()
    sourceSets.getByName("test").java.directories.clear()
    sourceSets.getByName("main").res.directories.clear()

    namespace = "com.crcfrcn.citizenwallet"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    // 只从CitizenWallet原生输出目录打包Rust库，产品仓库不保留生成的jniLibs。
    System.getenv("CITIZENWALLET_NATIVE_ANDROID_DIR")?.takeIf { it.isNotBlank() }?.let { nativeDir ->
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
            // 所有环境只生成无私钥 Release 候选。正式JKS由产品发布环境的安全
            // 凭据存储保管，并由发布签名进程通过匿名stdin使用。
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
    source = System.getenv("CITIZENWALLET_PROJECT_ROOT") ?: "../.."
}

// 钱包内置硬件金库直接使用宿主依赖。
dependencies {
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.core:core:1.13.1")
    testImplementation("junit:junit:4.13.2")
}

// 通过 Android 官方变体 API 传递生成目录和任务依赖，避免手写任务顺序。
androidComponents {
    onVariants(selector().all()) { variant ->
        variant.sources.res?.addGeneratedSourceDirectory(
            prepareCitizenWalletResources, PrepareCitizenWalletResources::outputDirectory,
        )
    }
}

// 新 DSL 的 AndroidSourceDirectorySet 不提供 include 过滤器。单文件显式加入
// Kotlin 单测编译任务，不能把整个 app 根作为测试目录而重复编译生产源码。
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    if (name.endsWith("UnitTestKotlin")) {
        source(layout.projectDirectory.file("HardwareSecretvaultPluginTest.kt"))
    }
}
