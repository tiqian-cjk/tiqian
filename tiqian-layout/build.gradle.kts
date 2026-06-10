plugins {
    kotlin("multiplatform")
}

kotlin {
    jvm()

    sourceSets {
        commonMain.dependencies {
            api(project(":tiqian-core"))
            api(project(":tiqian-font"))
            api(project(":tiqian-shaping-api"))
            api(project(":tiqian-linebreak"))
            api(project(":tiqian-clreq"))
        }

        commonTest.dependencies {
            implementation(kotlin("test"))
        }

        jvmTest.dependencies {
            implementation(project(":tiqian-shaping-jvm"))
            implementation(project(":tiqian-test"))
        }
    }
}

