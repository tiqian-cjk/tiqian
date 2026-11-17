plugins {
    kotlin("multiplatform")
}

kotlin {
    jvm()

    sourceSets {
        jvmMain.dependencies {
            api(project(":boring-kotlin-f32"))
        }

        jvmTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
