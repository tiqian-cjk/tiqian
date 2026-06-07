pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
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
    ":tiqian-linebreak",
    ":tiqian-clreq",
    ":tiqian-layout",
    ":tiqian-compose",
    ":tiqian-android-view",
    ":tiqian-playground",
    ":tiqian-test",
)
