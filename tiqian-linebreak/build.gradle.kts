plugins {
    kotlin("multiplatform")
}

kotlin {
    jvm()

    sourceSets {
        commonMain.dependencies {
            api(project(":tiqian-core"))
        }

        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}

