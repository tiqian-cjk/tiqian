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
    }
}
