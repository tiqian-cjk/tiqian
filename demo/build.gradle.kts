plugins {
    kotlin("multiplatform")
    id("com.android.kotlin.multiplatform.library")
    id("org.jetbrains.compose")
    id("org.jetbrains.kotlin.plugin.compose")
}

kotlin {
    jvm()
    android {
        namespace = "org.tiqian.demo"
        compileSdk = 36
        minSdk = 31
    }

    sourceSets {
        commonMain.dependencies {
            implementation(project(":frontend:compose"))
            implementation("org.jetbrains.compose.runtime:runtime:1.11.1")
            implementation("org.jetbrains.compose.ui:ui:1.11.1")
            implementation("org.jetbrains.compose.foundation:foundation:1.11.1")
            implementation("org.jetbrains.compose.material:material:1.11.1")
        }

        jvmMain.dependencies {
            implementation(compose.desktop.currentOs)
        }
    }
}

tasks.register<JavaExec>("runComposeDemo") {
    group = "application"
    description = "Opens the shared Tiqian Compose demo on Desktop."
    dependsOn("jvmJar")
    mainClass.set("org.tiqian.demo.DesktopMainKt")
    classpath = files(tasks.named("jvmJar")) + configurations.named("jvmRuntimeClasspath").get()
    jvmArgs("--enable-native-access=ALL-UNNAMED")
}
