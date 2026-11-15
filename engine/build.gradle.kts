import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    kotlin("multiplatform")
    id("com.android.kotlin.multiplatform.library")
    // Haxe port coverage baseline for the pre-refactor engine.
    id("org.jetbrains.kotlinx.kover") version "0.9.9"
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

// commonTest is shared with the Android host-test compilation. AGP's lint model tasks do not
// infer the generated-source task dependency from Kotlin's source-set provider, so declare it.
kotlin {
    // Project-wide Kotlin compiler options. KT-61573: 'expect'/'actual'
    // classes are Beta; TestTracePlatform (org.tiqian.test.trace) is an
    // intentional JVM-only golden-writing hook, so the language-feature
    // notice is silenced instead of restructuring the hook.
    compilerOptions {
        freeCompilerArgs.add("-Xexpect-actual-classes")
    }
    jvm()
    android {
        namespace = "org.tiqian.engine"
        compileSdk = 36
        minSdk = 23
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
        withHostTest {}
    }
    macosArm64()
    iosArm64()
    iosSimulatorArm64()
    linuxX64()
    linuxArm64()
    mingwX64()

    sourceSets {
        // The Kotlin implementation is generated from engine-haxe/ by boring
        // (bundle kotlin-f32). setSrcDirs replaces the default
        // src/commonMain/kotlin instead of adding to it, so the handwritten
        // tree stays on disk untouched and removing this block rolls back.
        commonMain {
            kotlin.setSrcDirs(listOf(layout.projectDirectory.dir("../engine-haxe/out/kotlin-f32/gen")))
        }

        commonTest {
            dependencies {
                implementation(kotlin("test"))
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")
            }
            // commonTest carries no sources after the cutover: the generated suite
            // carries @boring.test.Test cases, is not JUnit, and has no Test task, so
            // it lives in the jvmGeneratedTest compilation below and runs through
            // :engine:generatedTestSuite. Keeping it in commonTest made :engine:jvmTest
            // fail with "test sources present ... did not discover any tests".
        }

        jvmTest.dependencies {
            implementation(project(":platforms:jvm:shaping"))
            implementation(project(":platforms:jvm:skia"))
            runtimeOnly("org.jetbrains.skiko:skiko-awt-runtime-" + skikoRuntimeClassifier() + ":0.144.6")
        }
    }
}

// :engine keeps this build configuration, the generated tree under
// ../engine-haxe/out/kotlin-f32 and src/androidMain/baselineProfiles only. The
// developer probes and the README sample generator live in :tools:engine-probes.
//
// The generated test suite (bundle kotlin-f32, gen-tests) is not a JUnit suite:
// every case carries @boring.test.Test and the generated TestMainKt drives them.
// Its own JVM compilation keeps it out of jvmTest (which has no test classes
// after the cutover) while :engine:generatedTestSuite still builds and runs it.
val jvmGeneratedTestCompilation = kotlin.targets.getByName("jvm").compilations.create("generatedTest") {
    defaultSourceSet.dependsOn(kotlin.sourceSets.getByName("commonMain"))
}
jvmGeneratedTestCompilation.associateWith(kotlin.targets.getByName("jvm").compilations.getByName("main"))
jvmGeneratedTestCompilation.defaultSourceSet.kotlin.setSrcDirs(
    listOf(layout.projectDirectory.dir("../engine-haxe/out/kotlin-f32/gen-tests")),
)
jvmGeneratedTestCompilation.defaultSourceSet.dependencies {
    implementation(kotlin("test"))
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")
    implementation(project(":platforms:jvm:shaping"))
    implementation(project(":platforms:jvm:skia"))
}

// The generated test suite (bundle kotlin-f32, gen-tests) is not a JUnit suite:
// every case carries @boring.test.Test and the generated TestMainKt drives them,
// exiting non-zero when any case throws. Run it through JavaExec so Gradle
// reports the same verdict the boring driver does.
tasks.register<JavaExec>("generatedTestSuite") {
    group = "verification"
    description = "Runs the generated Kotlin test suite through gen-tests/TestMainKt."
    dependsOn(jvmGeneratedTestCompilation.compileTaskProvider)
    mainClass.set("TestMainKt")
    // The generated golden constants load their text from the bundle resource
    // directory, so it has to sit on the classpath exactly as the driver puts it.
    classpath = files(jvmGeneratedTestCompilation.output.allOutputs) +
        files(layout.projectDirectory.dir("../engine-haxe/out/kotlin-f32/gen/resources")) +
        configurations.named("jvmTestRuntimeClasspath").get()
    // The generated runner reads these two host edges; the driver sets the same
    // values (boring.json run.env). Without the budget, eleven cases time out.
    environment("BORING_TEST_TIMEOUT_MS", "600000")
    environment(
        "BORING_TEST_RESULTS",
        layout.buildDirectory.file("test-results/generated-suite.jsonl").get().asFile.absolutePath,
    )
    // Trace goldens are written to a repository-relative path.
    workingDir = rootProject.projectDir
}
