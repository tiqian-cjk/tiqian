plugins {
    kotlin("multiplatform")
}

kotlin {
    jvm()

    sourceSets {
        jvmMain.dependencies {
            api(project(":shaping:api"))
            api("org.jetbrains.skiko:skiko-awt:0.148.1")
        }

        jvmTest.dependencies {
            implementation(kotlin("test"))
            implementation(project(":shaping:jvm"))
            runtimeOnly("org.jetbrains.skiko:skiko-awt-runtime-macos-arm64:0.148.1")
        }
    }
}
