pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        // Kotlin/JS downloads a Node toolchain for webpack; under
        // FAIL_ON_PROJECT_REPOS the download source must be declared here. These
        // exclusive-content ivy repos serve ONLY org.nodejs:node / com.yarnpkg:yarn.
        exclusiveContent {
            forRepository {
                ivy("https://nodejs.org/dist/") {
                    name = "Node Distributions"
                    patternLayout { artifact("v[revision]/[artifact](-v[revision]-[classifier]).[ext]") }
                    metadataSources { artifact() }
                    content { includeModule("org.nodejs", "node") }
                }
            }
            filter { includeGroup("org.nodejs") }
        }
        exclusiveContent {
            forRepository {
                ivy("https://github.com/yarnpkg/yarn/releases/download") {
                    name = "Yarn Distributions"
                    patternLayout { artifact("v[revision]/[artifact](-v[revision]).[ext]") }
                    metadataSources { artifact() }
                    content { includeModule("com.yarnpkg", "yarn") }
                }
            }
            filter { includeGroup("com.yarnpkg") }
        }
    }
}

rootProject.name = "tiqian"

// ============================================================================
// engine-haxe is the only active source for the engine: ":platforms:engine"
// compiles the Kotlin that boring generates from engine-haxe/src. The
// handwritten Kotlin implementation is gone; the module keeps only the Gradle
// configuration for the generated tree. Do not add engine code to
// ":platforms:engine"; edit engine-haxe/src instead.
// ============================================================================
logger.info("tiqian: :platforms:engine compiles the Kotlin generated from engine-haxe")

include(
    ":platforms:engine", // generated from engine-haxe
    ":platforms:jvm:shaping",
    ":platforms:jvm:skia",
    ":platforms:android:shaping",
    ":platforms:android:native-font",
    ":platforms:android:rendering",
    ":platforms:android:view",
    ":platforms:android:benchmark",
    ":platforms:apple:shaping",
    ":platforms:apple:frontend",
    ":platforms:apple:frontend:coretext-render",
    ":platforms:compose:compose",
    ":platforms:compose:material3",
    ":demo",
    ":demo:android",
    ":demo:font-diagnostics",
    // Developer probes (measurement and regression tools) and the README sample
    // generator live outside the engine module; see platforms/engine/build.gradle.kts.
    ":tools:engine-probes",
)
