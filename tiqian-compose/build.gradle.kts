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
            implementation(compose.runtime)
            implementation(compose.foundation)
            implementation(compose.ui)
            implementation(compose.desktop.currentOs)
        }

        jvmTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}

tasks.register<JavaExec>("runComposeDemo") {
    group = "application"
    description = "Opens a desktop window rendering fixtures via TiqianParagraph."
    dependsOn("jvmJar")
    mainClass.set("ink.duo3.tiqian.compose.DemoMainKt")
    classpath = files(tasks.named("jvmJar")) + configurations.named("jvmRuntimeClasspath").get()
}
