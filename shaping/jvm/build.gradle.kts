plugins {
    kotlin("multiplatform")
}

kotlin {
    jvm()

    sourceSets {
        jvmMain.dependencies {
            api(project(":shaping:api"))
        }

        jvmTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
