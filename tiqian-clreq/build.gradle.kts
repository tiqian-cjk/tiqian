plugins {
    kotlin("multiplatform")
}

kotlin {
    jvm()

    sourceSets {
        commonMain.dependencies {
            api(project(":tiqian-core"))
            api(project(":tiqian-linebreak"))
        }

        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
