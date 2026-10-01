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
    // AGP 9提供内置Kotlin；Flutter插件在Android插件之后接入唯一工具链。
    id("dev.flutter.flutter-gradle-plugin")
}


// 限定资源的语义由明确映射保留；输入与输出隔离，正常编译自动依赖本任务。
@CacheableTask
abstract class PrepareCitizenAppResources @Inject constructor(
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

val prepareCitizenAppResources = tasks.register<PrepareCitizenAppResources>("prepareCitizenAppResources") {
    sourceDirectory.set(layout.projectDirectory.dir("src/main/res"))
    outputDirectory.set(layout.buildDirectory.dir("generated/qualified-resources"))
}

val flutterProductRoot = System.getenv("CITIZENAPP_PROJECT_ROOT")
    ?.let { file(it) }
    ?: rootProject.projectDir.parentFile
val flutterBuildProperties = Properties().apply {
    flutterProductRoot.resolve("android/local.properties").inputStream().use { load(it) }
}
val productVersionCode = flutterBuildProperties.getProperty("flutter.versionCode", "1").toInt()
val productVersionName = flutterBuildProperties.getProperty("flutter.versionName", "1.0")

android {
    // AGP 9 的 Kotlin 与 Java 源集独立；必须显式登记，否则可生成缺少入口类的 APK。
    sourceSets.getByName("main").kotlin.directories.apply { clear(); add("src/main") }
    sourceSets.getByName("androidTest").kotlin.directories.apply { clear(); add("src/androidTest") }
    // Flutter 在当轮外部工程生成插件注册表；必须显式编译它，不能依赖源码内旧生成物。
    sourceSets.getByName("main").java.directories.apply {
        clear()
        add("src/main")
        add(flutterProductRoot.resolve("android/app/src/main/java").absolutePath)
    }
    sourceSets.getByName("androidTest").java.directories.apply { clear(); add("src/androidTest") }
    sourceSets.getByName("debug").manifest.srcFile("src/debug_manifest.xml")
    sourceSets.getByName("profile").manifest.srcFile("src/profile_manifest.xml")
    sourceSets.getByName("main").res.directories.clear()
    namespace = "com.crcfrcn.citizenapp"
    compileSdk = 36
    ndkVersion = "28.2.13676358"
    // 设备测试必须挂到正式 Release 变体，禁止为验收生成影子 Debug 应用。
    testBuildType = "release"

    // 调用方只从本次源码外目录打包原生库，产品仓库不得保留生成的jniLibs。
    System.getenv("CITIZENAPP_NATIVE_ANDROID_DIR")?.takeIf { it.isNotBlank() }?.let { nativeDir ->
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
            // 所有环境只生成无私钥 Release 候选。正式 JKS 只进入产品安全发布执行器，
            // 并在完成产品要求的本机授权后通过匿名 stdin 使用。
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
    // 调用方可以提供源码外Flutter工程视图；普通产品构建仍以本工程根为Flutter根。
    source = System.getenv("CITIZENAPP_PROJECT_ROOT") ?: "../.."
}

// 通过 Android 官方变体 API 传递生成目录和任务依赖，避免手写任务顺序。
androidComponents {
    onVariants(selector().all()) { variant ->
        variant.sources.res?.addGeneratedSourceDirectory(
            prepareCitizenAppResources, PrepareCitizenAppResources::outputDirectory,
        )
    }
}
