import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Build configuration for the Kotlin that boring generates from engine-haxe.
//
// The module holds no sources: commonMain points at
// engine-haxe/out/kotlin-f32/gen, which .gitignore excludes, so a clean
// checkout has no inputs until boring generates the tree. The module exists to
// compile that tree for every consumer in this repository and to publish the
// nine tiqian-engine Maven coordinates (the kotlinMultiplatform root plus one
// module per target).
//
// The generated test suite (bundle kotlin-f32, gen-tests) does not live here:
// every case carries @boring.test.Test and the driver's test lane runs it from
// engine-haxe/out/kotlin-f32/gen-tests.
plugins {
    kotlin("multiplatform")
    id("com.android.kotlin.multiplatform.library")
    // Haxe port coverage baseline for the pre-refactor engine.
    id("org.jetbrains.kotlinx.kover") version "0.9.9"
}

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
            kotlin.setSrcDirs(listOf(layout.projectDirectory.dir("../../engine-haxe/out/kotlin-f32/gen")))
        }
    }
}
