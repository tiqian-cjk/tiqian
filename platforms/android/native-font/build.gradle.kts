import org.gradle.api.tasks.testing.Test
import org.gradle.jvm.toolchain.JavaLanguageVersion

plugins {
    id("com.android.library")
}

tasks.withType<Test>().configureEach {
    javaLauncher.set(
        javaToolchains.launcherFor {
            languageVersion.set(JavaLanguageVersion.of(25))
        },
    )
}

android {
    namespace = "org.tiqian.shaping.android.nativefont"
    compileSdk = 36
    ndkVersion = "29.0.13599879-rc2"

    defaultConfig {
        minSdk = 23
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_STL=c++_shared")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    androidResources {
        // Keeps the instrumentation probe asset stored, so the region-mapping path is exercised.
        noCompress.add("tiqianprobe")
    }
}

dependencies {
    api(project(":boring-kotlin-f32"))
    implementation(project(":platforms:android:shaping"))

    testImplementation(kotlin("test-junit"))
    androidTestImplementation(project(":platforms:android:shaping"))
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:core:1.6.1")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation(kotlin("test"))
}
