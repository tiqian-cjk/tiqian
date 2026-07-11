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
            api(project(":tiqian-core"))
            api(project(":tiqian-layout"))
            // runtime + ui carry public-signature types (@Composable, Modifier,
            // AnnotatedString, TextUnit/Color/FontFamily via CjkTextStyle) → api
            // so consumers resolve the Tiqian API without re-declaring them.
            api(compose.runtime)
            api(compose.ui)
            implementation(compose.foundation)
        }

        jvmMain.dependencies {
            implementation(project(":tiqian-shaping-skia"))
            implementation(compose.desktop.currentOs)
        }

        androidMain.dependencies {
            implementation(project(":tiqian-shaping-android"))
        }

        jvmTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
