plugins {
    kotlin("multiplatform")
    id("com.android.kotlin.multiplatform.library")
}

kotlin {
    jvm()
    android {
        namespace = "org.tiqian.layout"
        compileSdk = 36
        minSdk = 31
        withHostTest {}
    }
    wasmJs { browser() } // ADR 0039 web port

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
