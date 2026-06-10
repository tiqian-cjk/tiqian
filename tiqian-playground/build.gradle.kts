plugins {
    kotlin("multiplatform")
}

kotlin {
    jvm()

    sourceSets {
        jvmMain.dependencies {
            implementation(project(":tiqian-layout"))
            implementation(project(":tiqian-shaping-jvm"))
            implementation(project(":tiqian-shaping-skia"))
            implementation(project(":tiqian-test"))
            // Skiko natives for the local playground machine; other hosts
            // fall back to TIQIAN_PLAYGROUND_SHAPER=jvm-awt.
            runtimeOnly("org.jetbrains.skiko:skiko-awt-runtime-macos-arm64:0.148.1")
        }
    }
}

tasks.register<JavaExec>("runPlayground") {
    group = "application"
    description = "Runs the Tiqian layout playground dump."
    dependsOn("jvmJar")
    mainClass.set("ink.duo3.tiqian.playground.MainKt")
    classpath = files(tasks.named("jvmJar")) + configurations.named("jvmRuntimeClasspath").get()
}
