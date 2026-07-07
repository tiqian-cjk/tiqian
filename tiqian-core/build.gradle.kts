plugins {
    kotlin("multiplatform")
    id("com.android.kotlin.multiplatform.library")
}

kotlin {
    jvm()
    android {
        namespace = "org.tiqian.core"
        compileSdk = 36
        minSdk = 31
        withHostTest {}
    }
    // ADR 0039 web port: pure-model modules gain a browser (Wasm) target.
    wasmJs { browser() }

    sourceSets {
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
