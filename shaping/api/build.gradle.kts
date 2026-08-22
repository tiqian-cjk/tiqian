import org.jetbrains.kotlin.gradle.plugin.mpp.KotlinNativeTarget

plugins {
    kotlin("multiplatform")
    id("com.android.kotlin.multiplatform.library")
}

kotlin {
    jvm()
    android {
        namespace = "org.tiqian.shaping.api"
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

    // Font backend vtable protocol (ADR 0050): the same C header feeds
    // cinterop here and the Rust binding, so both sides share one layout.
    targets.withType<KotlinNativeTarget>().configureEach {
        compilations.getByName("main").cinterops.create("tiqianFontBackend") {
            defFile(project.file("src/nativeInterop/cinterop/tiqianFontBackend.def"))
            includeDirs(project.file("src/nativeInterop/cinterop"))
        }
    }

    sourceSets {
        commonMain.dependencies {
            api(project(":core"))
            api(project(":font"))
        }

        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
