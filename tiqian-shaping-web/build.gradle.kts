plugins {
    kotlin("multiplatform")
}

kotlin {
    wasmJs { browser() } // ADR 0039 web port: OffscreenMeasureTextShaping

    sourceSets {
        wasmJsMain.dependencies {
            api(project(":tiqian-core"))
            api(project(":tiqian-font"))
            api(project(":tiqian-shaping-api"))
            implementation("org.jetbrains.kotlinx:kotlinx-browser:0.3")
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
