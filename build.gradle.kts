import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinMultiplatformExtension

plugins {
    kotlin("multiplatform") version "2.3.20" apply false
    kotlin("android") version "2.3.20" apply false
    id("com.android.library") version "9.2.1" apply false
    id("com.android.kotlin.multiplatform.library") version "9.2.1" apply false
    id("com.android.application") version "9.2.1" apply false
    id("org.jetbrains.compose") version "1.11.1" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.20" apply false
}

group = "org.tiqian"
version = "0.1.0-SNAPSHOT"

subprojects {
    group = rootProject.group
    version = rootProject.version

    plugins.withId("org.jetbrains.kotlin.multiplatform") {
        extensions.configure<KotlinMultiplatformExtension>("kotlin") {
            // Uniform JDK 25 toolchain (provisioned via foojay resolver) so
            // compile and test always run on the same JVM regardless of the
            // daemon's own Java version.
            jvmToolchain(25)
            jvm {
                compilerOptions {
                    jvmTarget.set(JvmTarget.JVM_25)
                }
            }
        }
    }
}

tasks.register("runComposeDemo") {
    group = "application"
    description = "Opens the shared Tiqian Compose demo on Desktop."
    dependsOn(":demo:runComposeDemo")
}
