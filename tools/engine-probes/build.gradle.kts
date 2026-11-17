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
// This module is the single home for every JVM probe, including the adapter
// probes that measure the Skia shaping backend and its AWT reference shaper
// (org.tiqian.shaping.jvm.AwtTextShaper). The AWT shaper is not a product
// backend: only the AWT↔Skia comparison and these probes consume it, so it
// lives here instead of a published platform module. Each probe carries
// kotlin.test.Test methods, and runProbe below is their lane.
//
// The engine classes this module compiles against come from the
// :boring-kotlin-f32 project: boring's publication project, which the
// settings.gradle.kts points at engine-haxe/out/kotlin-f32/gen through
// kotlinGenDir in gradle.properties. Depending on :boring-kotlin-f32 consumes
// exactly that generated tree. This module declares no handwritten engine
// source set.

// Skiko publishes its native Skia library as one artifact per host, so a JVM
// runtime must name the machine running the probe. A fixed macOS classifier
// leaves every Linux host without a native library, which turns the first Skia
// call into an UnsatisfiedLinkError.
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
            implementation(project(":boring-kotlin-f32"))
            implementation(project(":platforms:compose:skia-jvm"))
            implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")
            implementation(kotlin("test-junit"))
            runtimeOnly("org.jetbrains.skiko:skiko-awt-runtime-" + skikoRuntimeClassifier() + ":0.144.6")
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
//   ./gradlew :tools:engine-probes:runProbe -PprobeClass=org.tiqian.shaping.skia.AwtSkiaShapingComparisonTest
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
