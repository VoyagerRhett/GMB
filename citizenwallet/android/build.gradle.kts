// AGP与KGP必须由同一个根classpath解析，避免settings先锁定AGP内置的另一版KGP。
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.20")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 本机编译必须由TataConsole把Gradle输出导向中央工作目录；GitHub临时Runner仍使用其短命工作区。
val programTataConsoleBuildDir = System.getenv("TATA_CONSOLE_BUILD_DIR")
val newBuildDir: Directory =
    if (!programTataConsoleBuildDir.isNullOrBlank()) {
        rootProject.layout.dir(rootProject.provider { rootProject.file(programTataConsoleBuildDir) }).get()
    } else {
        if (System.getenv("CI") != "true") {
            throw GradleException("本机Android编译必须由TataConsole提供TATA_CONSOLE_BUILD_DIR")
        }
        rootProject.layout.buildDirectory.dir("../../build").get()
    }
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// 所有子工程使用Java 17字节码目标，避免与Kotlin编译目标分离。
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
