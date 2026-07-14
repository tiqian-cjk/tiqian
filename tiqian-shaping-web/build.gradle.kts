plugins {
    kotlin("multiplatform")
}

kotlin {
    js {
        browser()
        useEsModules()
    }

    sourceSets {
        jsMain {
            dependencies {
                api(project(":tiqian-core"))
                api(project(":tiqian-font"))
                api(project(":tiqian-shaping-api"))
            }
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
