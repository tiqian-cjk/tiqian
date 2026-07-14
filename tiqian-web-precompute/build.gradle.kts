@file:OptIn(org.jetbrains.kotlin.gradle.ExperimentalWasmDsl::class)

plugins {
    kotlin("multiplatform")
}

kotlin {
    wasmJs {
        nodejs()
        binaries.executable()
    }

    sourceSets {
        wasmJsMain.dependencies {
            implementation(project(":tiqian-core"))
            implementation(project(":tiqian-font"))
            implementation(project(":tiqian-shaping-api"))
            implementation(project(":tiqian-linebreak"))
            implementation(project(":tiqian-clreq"))
            implementation(project(":tiqian-layout"))
        }
        wasmJsTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
