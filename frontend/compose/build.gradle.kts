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
        minSdk = 31
    }

    sourceSets {
        commonMain.dependencies {
            api(project(":core"))
            api(project(":layout"))
            // runtime + ui carry public-signature types (@Composable, Modifier,
            // AnnotatedString, TextUnit/Color/FontFamily via CjkTextStyle) → api
            // so consumers resolve the Tiqian API without re-declaring them.
            api(compose.runtime)
            api(compose.ui)
            implementation(compose.foundation)
        }

        jvmMain.dependencies {
            implementation(project(":shaping:skia"))
            implementation(compose.desktop.currentOs)
        }

        androidMain.dependencies {
            implementation(project(":shaping:android-adapter"))
        }

        jvmTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
