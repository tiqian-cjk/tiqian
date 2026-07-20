plugins {
    kotlin("multiplatform")
    id("com.android.kotlin.multiplatform.library")
}

kotlin {
    jvm()
    android {
        namespace = "org.tiqian.clreq"
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
            api(project(":core"))
            api(project(":linebreak"))
        }

        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
