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

// Gradle产物使用CitizenWallet命名的外部目录；普通开发与CI均可直接调用。
val programBuildDir = System.getenv("CITIZENWALLET_BUILD_DIR")
    ?: "${System.getProperty("java.io.tmpdir")}/citizenwallet/android"
val programBuildFile = rootProject.file(programBuildDir).canonicalFile
val citizenWalletSourcePath = rootDir.parentFile.canonicalFile.toPath()
val newBuildDir: Directory = rootProject.layout.dir(
    rootProject.provider { programBuildFile },
).get()
if (!programBuildFile.isAbsolute || programBuildFile.toPath().startsWith(citizenWalletSourcePath)) {
    throw GradleException("CITIZENWALLET_BUILD_DIR必须是CitizenWallet源码外的绝对路径")
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
