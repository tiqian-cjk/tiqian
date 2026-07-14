plugins {
    kotlin("multiplatform")
    id("com.android.kotlin.multiplatform.library")
}

kotlin {
    jvm()
    android {
        namespace = "org.tiqian.shaping.api"
        compileSdk = 36
        minSdk = 31
        withHostTest {}
    }
    js {
        browser()
        useEsModules()
    }

    sourceSets {
        commonMain.dependencies {
            api(project(":tiqian-core"))
            api(project(":tiqian-font"))
        }

        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
