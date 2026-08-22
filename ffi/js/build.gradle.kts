plugins {
    kotlin("multiplatform")
}

kotlin {
    js {
        // Generated names are package internals consumed by
        // `frontend/web/npm` (`precompute.js`, `layout-worker.js`) and the
        // plan parity oracle (ADR 0050).
        outputModuleName.set("Tiqian-tiqian-ffi-js")
        nodejs()
        useEsModules()
        binaries.executable()
    }

    sourceSets {
        jsMain.dependencies {
            implementation(project(":core"))
            implementation(project(":font"))
            implementation(project(":shaping:api"))
            implementation(project(":linebreak"))
            implementation(project(":clreq"))
            implementation(project(":layout"))
        }
        jsTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
