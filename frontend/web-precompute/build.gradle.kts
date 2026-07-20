plugins {
    kotlin("multiplatform")
}

kotlin {
    js {
        outputModuleName.set("Tiqian-tiqian-web-precompute")
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
