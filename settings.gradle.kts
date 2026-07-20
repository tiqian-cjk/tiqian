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

rootProject.name = "Tiqian"

include(
    ":core",
    ":font",
    ":shaping:api",
    ":shaping:jvm",
    ":shaping:skia",
    ":shaping:android-adapter",
    ":shaping:web-adapter",
    ":frontend:web",
    ":frontend:web-precompute",
    ":linebreak",
    ":clreq",
    ":layout",
    ":frontend:compose",
    ":demo",
    ":demo:android",
    ":frontend:android-view",
    ":test-support",
)
