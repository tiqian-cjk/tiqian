plugins {
    kotlin("multiplatform")
}

kotlin {
    jvm()

    sourceSets {
        jvmMain.dependencies {
            implementation(project(":tiqian-layout"))
            implementation(project(":tiqian-shaping-jvm"))
            implementation(project(":tiqian-test"))
        }
    }
}

tasks.register<JavaExec>("runPlayground") {
    group = "application"
    description = "Runs the Tiqian layout playground dump."
    dependsOn("jvmJar")
    mainClass.set("org.tiqian.playground.MainKt")
    classpath = files(tasks.named("jvmJar")) + configurations.named("jvmRuntimeClasspath").get()
}
