import groovy.json.JsonSlurper

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            val flutterProjectRoot = System.getenv("TATA_CONSOLE_FLUTTER_ROOT")
                ?.let { java.io.File(it) }
                ?: settingsDir.parentFile
            flutterProjectRoot.resolve("android/local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("com.android.application") version "9.0.1" apply false
}

// Flutter/Pub在当前产品根生成插件元数据；Gradle始终从本产品真实android根启动，
// 因此不会再把跨根符号链接设置脚本当成另一个Gradle根。
val flutterProjectRoot = System.getenv("TATA_CONSOLE_FLUTTER_ROOT")
    ?.let { java.io.File(it) }
    ?: settingsDir.parentFile
val flutterPlugins = flutterProjectRoot.resolve(".flutter-plugins-dependencies")
if (flutterPlugins.isFile) {
    val metadata = JsonSlurper().parse(flutterPlugins) as Map<*, *>
    val androidPlugins = (metadata["plugins"] as? Map<*, *>)?.get("android") as? List<*> ?: emptyList<Any>()
    androidPlugins.filterIsInstance<Map<*, *>>()
        .filter { it["native_build"] != false }
        .forEach { plugin ->
            val name = plugin["name"] as String
            include(":$name")
            project(":$name").projectDir = java.io.File(plugin["path"] as String, "android")
        }
}

include(":app")
