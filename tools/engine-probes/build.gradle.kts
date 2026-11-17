plugins {
    kotlin("multiplatform")
}

// Developer probes and the README sample generator for the generated engine.
//
// The probes are measurement and regression tools, not part of a test suite, so
// they live in jvmMain and are compiled by :tools:engine-probes:compileKotlinJvm.
// They used to sit in a private "tools" compilation of the engine module; they
// moved here so the engine module keeps only its build configuration and the
// generated commonMain tree.
//
// The engine classes this module compiles against come from the
// :boring-kotlin-f32 project: boring's publication project, which the
// settings.gradle.kts points at engine-haxe/out/kotlin-f32/gen through
// kotlinGenDir in gradle.properties. Depending on :boring-kotlin-f32 consumes
// exactly that generated tree. This module declares no handwritten engine
// source set.
kotlin {
    jvm()

    sourceSets {
        jvmMain.dependencies {
            implementation(project(":boring-kotlin-f32"))
            implementation(project(":platforms:jvm:shaping"))
            implementation(project(":platforms:jvm:skia"))
            implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")
            implementation(kotlin("test-junit"))
            runtimeOnly("org.jetbrains.skiko:skiko-awt-runtime-macos-arm64:0.144.6")
        }
    }
}

val jvmMainCompilation = kotlin.targets.getByName("jvm").compilations.getByName("main")

val readmeSampleBlackSvg = rootProject.layout.projectDirectory.file("docs/images/sample-paragraph-black.svg")
val readmeSampleWhiteSvg = rootProject.layout.projectDirectory.file("docs/images/sample-paragraph-white.svg")

tasks.register<JavaExec>("generateReadmeSample") {
    group = "documentation"
    description = "Generates the README paragraph sample from a real Tiqian LayoutResult."
    dependsOn("compileKotlinJvm")
    mainClass.set("org.tiqian.layout.tooling.ReadmeSampleMainKt")
    classpath = files(jvmMainCompilation.output.allOutputs) +
        configurations.named("jvmRuntimeClasspath").get()
    jvmArgs("--enable-native-access=ALL-UNNAMED")
    args(
        readmeSampleBlackSvg.asFile.absolutePath,
        readmeSampleWhiteSvg.asFile.absolutePath,
    )
    outputs.files(readmeSampleBlackSvg, readmeSampleWhiteSvg)
}

// Runs one probe class by its fully-qualified name, for example:
//   ./gradlew :tools:engine-probes:runProbe -PprobeClass=org.tiqian.layout.KinsokuHangingExperimentProbe
// Every probe carries kotlin.test.Test methods, so JUnit 4 discovers them. The
// reporting-only matrices keep their own TIQIAN_RUN_EXPERIMENTS=1 gate.
tasks.register<JavaExec>("runProbe") {
    group = "verification"
    description = "Runs one probe class: -PprobeClass=org.tiqian.layout.KinsokuHangingExperimentProbe"
    dependsOn("compileKotlinJvm")
    mainClass.set("org.junit.runner.JUnitCore")
    classpath = files(jvmMainCompilation.output.allOutputs) +
        configurations.named("jvmRuntimeClasspath").get()
    jvmArgs("--enable-native-access=ALL-UNNAMED")
    doFirst {
        val probeClass = (project.findProperty("probeClass") as String?)
            ?: error("-PprobeClass=<fully.qualified.ProbeClass> is required")
        args(probeClass)
    }
}
