plugins {
    kotlin("multiplatform")
    id("com.android.kotlin.multiplatform.library")
}

kotlin {
    jvm()
    android {
        namespace = "org.tiqian.layout"
        compileSdk = 36
        minSdk = 31
        withHostTest {}
    }
    js {
        browser()
        useEsModules()
    }

    sourceSets {
        commonMain.dependencies {
            api(project(":tiqian-core"))
            api(project(":tiqian-font"))
            api(project(":tiqian-shaping-api"))
            api(project(":tiqian-linebreak"))
            api(project(":tiqian-clreq"))
        }

        commonTest.dependencies {
            implementation(kotlin("test"))
        }

        jvmTest.dependencies {
            implementation(project(":tiqian-shaping-jvm"))
            implementation(project(":tiqian-shaping-skia"))
            implementation(project(":tiqian-test"))
            runtimeOnly("org.jetbrains.skiko:skiko-awt-runtime-macos-arm64:0.148.1")
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
    jvmArgs("--enable-native-access=ALL-UNNAMED")
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
