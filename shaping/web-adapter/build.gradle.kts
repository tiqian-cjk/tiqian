plugins {
    kotlin("multiplatform")
}

kotlin {
    js {
        outputModuleName.set("Tiqian-tiqian-shaping-web")
        browser()
        useEsModules()
    }

    sourceSets {
        jsMain {
            dependencies {
                api(project(":core"))
                api(project(":font"))
                api(project(":shaping:api"))
            }
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
