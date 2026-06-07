plugins {
    kotlin("multiplatform")
}

kotlin {
    jvm()

    sourceSets {
        jvmMain.dependencies {
            api(project(":tiqian-shaping-api"))
        }

        jvmTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
