import org.gradle.api.tasks.Sync
import org.gradle.language.jvm.tasks.ProcessResources

plugins {
    kotlin("multiplatform")
}

kotlin {
    js {
        // These generated names are package internals. Keep them stable while
        // the repository and Gradle project paths move to the shorter layout.
        outputModuleName.set("Tiqian-tiqian-web")
        browser {
            commonWebpackConfig {
                outputFileName = "tiqian-web.js"
            }
        }
        useEsModules()
        binaries.executable()
    }
    sourceSets {
        jsMain {
            dependencies {
                api(project(":core"))
                api(project(":layout"))
                api(project(":clreq"))
                implementation(project(":shaping:web-adapter"))
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
    dependsOn(":frontend:web-precompute:jsProductionExecutableCompileSync")
    from(
        project(":frontend:web-precompute")
            .layout.buildDirectory.dir("compileSync/js/main/productionExecutable/kotlin"),
    ) {
        include("*.mjs")
    }
    into(layout.projectDirectory.dir("npm/precompute-runtime"))
}
