plugins {
    kotlin("multiplatform")
}

// Internal Apple Core Text renderer. Draws a LayoutResult via
// CTFontDrawGlyphs and wires the engine to the Core Text shaper + metrics
// (AppleParagraphBackend). Kotlin/Native, consuming platform.CoreText bindings.
// Named `coretext-render` (not `coretext`) so its capability differs from the
// `:shaping:coretext` adapter — same leaf name would collide under the shared group.
kotlin {
    macosArm64()
    iosArm64()
    iosSimulatorArm64()

    sourceSets {
        all {
            languageSettings.optIn("kotlinx.cinterop.ExperimentalForeignApi")
        }
        commonMain.dependencies {
            api(project(":boring-kotlin-f32"))
            api(project(":platforms:apple:shaping"))
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
