plugins {
    kotlin("multiplatform")
}

// Skiko publishes its native Skia library as one artifact per host, so a JVM
// runtime must name the machine running the build. A fixed macOS classifier
// leaves every Linux and x64 macOS host without a native library, which turns
// the first Skia call into an UnsatisfiedLinkError.
fun skikoRuntimeClassifier(): String {
    val osName = System.getProperty("os.name").lowercase()
    val archName = System.getProperty("os.arch").lowercase()
    val arch = when (archName) {
        "x86_64", "amd64" -> "x64"
        "aarch64", "arm64" -> "arm64"
        else -> error("skiko has no runtime artifact for host architecture '" + archName + "'")
    }
    return when {
        osName.startsWith("linux") -> "linux-" + arch
        osName.startsWith("mac") -> "macos-" + arch
        osName.startsWith("windows") -> "windows-" + arch
        else -> error("skiko has no runtime artifact for host OS '" + osName + "'")
    }
}

kotlin {
    jvm()

    sourceSets {
        jvmMain.dependencies {
            api(project(":boring-kotlin-f32"))
            api("org.jetbrains.skiko:skiko-awt:0.144.6")
        }

        jvmTest.dependencies {
            implementation(kotlin("test"))
            runtimeOnly("org.jetbrains.skiko:skiko-awt-runtime-" + skikoRuntimeClassifier() + ":0.144.6")
        }
    }
}
