plugins {
    kotlin("multiplatform")
    id("org.jetbrains.compose")
    id("org.jetbrains.kotlin.plugin.compose")
}

kotlin {
    jvm()

    sourceSets {
        commonMain.dependencies {
            api(project(":tiqian-core"))
            api(project(":tiqian-layout"))
        }

        jvmMain.dependencies {
            implementation(project(":tiqian-shaping-skia"))
            // runtime + ui carry public-signature types (@Composable, Modifier,
            // AnnotatedString, TextUnit/Color/FontFamily via CjkTextStyle) → api
            // so consumers resolve the Tiqian API without re-declaring them.
            api(compose.runtime)
            api(compose.ui)
            implementation(compose.foundation)
            implementation(compose.desktop.currentOs)
        }

        jvmTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}

tasks.register<JavaExec>("runComposeDemo") {
    group = "application"
    description = "Opens a desktop window rendering fixtures via CjkParagraph."
    dependsOn("jvmJar")
    mainClass.set("ink.duo3.tiqian.compose.DemoMainKt")
    classpath = files(tasks.named("jvmJar")) + configurations.named("jvmRuntimeClasspath").get()
}
