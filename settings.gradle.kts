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
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "Tiqian"

include(
    ":tiqian-core",
    ":tiqian-font",
    ":tiqian-shaping-api",
    ":tiqian-shaping-jvm",
    ":tiqian-shaping-skia",
    ":tiqian-shaping-android",
    ":tiqian-linebreak",
    ":tiqian-clreq",
    ":tiqian-layout",
    ":tiqian-compose",
    ":tiqian-android-view",
    ":tiqian-playground",
    ":tiqian-test",
)
