plugins {
    kotlin("multiplatform")
    id("com.android.kotlin.multiplatform.library")
}

kotlin {
    jvm()
    android {
        namespace = "org.tiqian.layout"
        compileSdk = 36
        minSdk = 23
        withHostTest {}
    }
    js {
        browser()
        useEsModules()
    }
    macosArm64()
    iosArm64()
    iosSimulatorArm64()
    linuxX64()
    linuxArm64()
    mingwX64()

    sourceSets {
        commonMain.dependencies {
            api(project(":core"))
            api(project(":font"))
            api(project(":shaping:api"))
            api(project(":linebreak"))
            api(project(":clreq"))
        }

        commonTest.dependencies {
            implementation(kotlin("test"))
        }

        jvmTest.dependencies {
            implementation(project(":shaping:jvm"))
            implementation(project(":shaping:skia"))
            implementation(project(":test-support"))
            runtimeOnly("org.jetbrains.skiko:skiko-awt-runtime-macos-arm64:0.144.6")
        }
    }
}

val jvmTestCompilation = kotlin.targets.getByName("jvm").compilations.getByName("test")

tasks.register<JavaExec>("generateLayoutReport") {
    group = "verification"
    description = "Generates the layout decision dump and diagnostic HTML report."
    dependsOn("jvmTestClasses")
    mainClass.set("org.tiqian.layout.tooling.LayoutReportMainKt")
    classpath = files(jvmTestCompilation.output.allOutputs) +
        configurations.named("jvmTestRuntimeClasspath").get()
    // BufferedImage/font probing is fully off-screen. Headless mode prevents macOS AWT's
    // non-daemon auto-shutdown thread from keeping the completed CI task alive indefinitely.
    jvmArgs("-Djava.awt.headless=true", "--enable-native-access=ALL-UNNAMED")
}

val readmeSampleBlackSvg = rootProject.layout.projectDirectory.file("docs/images/sample-paragraph-black.svg")
val readmeSampleWhiteSvg = rootProject.layout.projectDirectory.file("docs/images/sample-paragraph-white.svg")

tasks.register<JavaExec>("generateReadmeSample") {
    group = "documentation"
    description = "Generates the README paragraph sample from a real Tiqian LayoutResult."
    dependsOn("jvmTestClasses")
    mainClass.set("org.tiqian.layout.tooling.ReadmeSampleMainKt")
    classpath = files(jvmTestCompilation.output.allOutputs) +
        configurations.named("jvmTestRuntimeClasspath").get()
    jvmArgs("--enable-native-access=ALL-UNNAMED")
    args(
        readmeSampleBlackSvg.asFile.absolutePath,
        readmeSampleWhiteSvg.asFile.absolutePath,
    )
    outputs.files(readmeSampleBlackSvg, readmeSampleWhiteSvg)
}
