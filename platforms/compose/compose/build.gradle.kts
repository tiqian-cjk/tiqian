plugins {
    kotlin("multiplatform")
    id("com.android.kotlin.multiplatform.library")
    id("org.jetbrains.compose")
    id("org.jetbrains.kotlin.plugin.compose")
}

kotlin {
    jvm()
    android {
        namespace = "org.tiqian.compose"
        compileSdk = 36
        minSdk = 23
        androidResources.enable = true
        withDeviceTest {
            instrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        }
    }

    sourceSets {
        commonMain.dependencies {
            api(project(":boring-kotlin-f32"))
            // runtime + ui carry public-signature types (@Composable, Modifier,
            // AnnotatedString, TextUnit/Color/FontFamily via CjkTextStyle) → api
            // so consumers resolve the Tiqian API without re-declaring them.
            api("org.jetbrains.compose.runtime:runtime:1.11.1")
            api("org.jetbrains.compose.ui:ui:1.11.1")
            // ScrollState is part of CjkSelectionContainer's public auto-scroll contract.
            api("org.jetbrains.compose.foundation:foundation:1.11.1")
        }

        jvmMain.dependencies {
            implementation(project(":platforms:jvm:skia"))
        }

        androidMain.dependencies {
            implementation(project(":platforms:android:shaping"))
            implementation(project(":platforms:android:rendering"))
        }

        getByName("androidDeviceTest").dependencies {
            implementation(kotlin("test"))
            implementation("androidx.test:runner:1.7.0")
            implementation("androidx.test.ext:junit:1.3.0")
        }

        jvmTest.dependencies {
            implementation(kotlin("test"))
            // Native Skiko runtime belongs to the test/application runtime, not the library POM.
            implementation(compose.desktop.currentOs)
        }
    }
}
