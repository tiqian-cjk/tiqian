import org.gradle.api.tasks.Sync
import org.gradle.language.jvm.tasks.ProcessResources

plugins {
    kotlin("multiplatform")
}

kotlin {
    js {
        browser()
        useEsModules()
        binaries.executable()
    }
    sourceSets {
        jsMain {
            dependencies {
                api(project(":tiqian-core"))
                api(project(":tiqian-layout"))
                api(project(":tiqian-clreq"))
                implementation(project(":tiqian-shaping-web"))
            }
        }
        jsTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}

tasks.named<ProcessResources>("jsProcessResources") {
    from(layout.projectDirectory.file("npm/styles.css"))
}

tasks.register<Sync>("assembleNpmPackage") {
    group = "distribution"
    description = "Builds the @tiqian/prose ESM package runtime."
    dependsOn("jsBrowserProductionWebpack", "assemblePrecomputeNpmRuntime")
    from(layout.buildDirectory.dir("kotlin-webpack/js/productionExecutable")) {
        include("tiqian-web.js")
    }
    into(layout.projectDirectory.dir("npm/runtime"))
}

tasks.register<Sync>("assemblePrecomputeNpmRuntime") {
    group = "distribution"
    description = "Builds the Node-only @tiqian/prose/precompute runtime."
    dependsOn(":tiqian-web-precompute:jsProductionExecutableCompileSync")
    from(
        project(":tiqian-web-precompute")
            .layout.buildDirectory.dir("compileSync/js/main/productionExecutable/kotlin"),
    ) {
        include("*.mjs")
    }
    into(layout.projectDirectory.dir("npm/precompute-runtime"))
}
