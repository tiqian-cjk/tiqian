plugins {
    kotlin("multiplatform")
}

kotlin {
    jvm()

    sourceSets {
        jvmMain.dependencies {
            implementation(project(":tiqian-layout"))
            implementation(project(":tiqian-test"))
        }
    }
}

