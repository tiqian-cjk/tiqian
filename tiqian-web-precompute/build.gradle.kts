plugins {
    kotlin("multiplatform")
}

kotlin {
    js {
        nodejs()
        useEsModules()
        binaries.executable()
    }

    sourceSets {
        jsMain.dependencies {
            implementation(project(":tiqian-core"))
            implementation(project(":tiqian-font"))
            implementation(project(":tiqian-shaping-api"))
            implementation(project(":tiqian-linebreak"))
            implementation(project(":tiqian-clreq"))
            implementation(project(":tiqian-layout"))
        }
        jsTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
