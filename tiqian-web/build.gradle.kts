@file:OptIn(org.jetbrains.kotlin.gradle.ExperimentalWasmDsl::class)

import org.gradle.api.tasks.Sync

plugins {
    kotlin("multiplatform")
}

kotlin {
    wasmJs {
        browser()
        binaries.executable() // ADR 0039 web demo entry
    }
    sourceSets {
        wasmJsMain.dependencies {
            api(project(":tiqian-core"))
            api(project(":tiqian-layout"))
            api(project(":tiqian-clreq"))
            implementation(project(":tiqian-shaping-web"))
            implementation("org.jetbrains.kotlinx:kotlinx-browser:0.3")
        }
        wasmJsTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}

tasks.register<Sync>("assembleNpmPackage") {
    group = "distribution"
    description = "Builds the @tiqian/web ESM package runtime."
    dependsOn("wasmJsProductionExecutableCompileSync")
    from(layout.buildDirectory.dir("compileSync/wasmJs/main/productionExecutable/optimized")) {
        include("*.mjs", "*.wasm")
    }
    into(layout.projectDirectory.dir("npm/runtime"))
}
