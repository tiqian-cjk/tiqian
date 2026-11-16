plugins {
    kotlin("multiplatform")
}

kotlin {
    jvm()

    sourceSets {
        jvmMain.dependencies {
            api(project(":platforms:engine"))
        }

        jvmTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
