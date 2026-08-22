plugins {
    kotlin("multiplatform")
    id("com.android.kotlin.multiplatform.library")
}

kotlin {
    jvm()
    android {
        namespace = "org.tiqian.clreq"
        compileSdk = 36
        minSdk = 23
        withHostTest {}
    }
    js {
        browser()
        useEsModules()
    }
    macosArm64()
    iosArm64()
    iosSimulatorArm64()
    linuxX64()
    linuxArm64()
    mingwX64()

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
