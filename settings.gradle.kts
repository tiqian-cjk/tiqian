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
// The generated Kotlin tree has exactly one Gradle owner: boring's publication
// project. boring (bundle kotlin-f32) writes engine-haxe/out/kotlin-f32/gen and
// gen-tests; the project that compiles them ships with the driver, which copies
// it to <outRoot>/<id>/gradle/project on every pack run. tiqian includes that
// project's :engine module here instead of keeping its own adapter module, so
// the target set, compiler options, Android namespace and publication POM are
// written once, in boring's file.
//
// The project directory is the devShell's staged copy of that project:
// Gradle 9 refuses to configure a project whose directory is read-only, so the
// flake install (BORING_PUBLICATION_PROJECT / BORING_SOURCE) cannot be the
// project directory even though it holds the same files. kotlinGenDir and
// kotlinGenTestsDir in gradle.properties point the project at tiqian's
// emission, exactly as the driver's -P arguments do on a pack run.
//
// The generated tree is gitignored, so a checkout has no engine sources until
// 'boring gen kotlin-f32' writes them: the resolution below fails with that
// exact command instead of configuring an empty source set.
// ============================================================================
val generatedEngineTree = settingsDir.resolve("engine-haxe/out/kotlin-f32/gen")
val publicationProjectRoot = settingsDir.resolve(".haxelib/boring/git/tools/kotlin-publication")
val stagedEngineProject = publicationProjectRoot
    .takeIf { it.resolve("engine/build.gradle.kts").isFile }

val ownerUnavailable = listOf(
    "The Kotlin engine tree has no Gradle owner.",
    "",
    "boring generates the tree and ships the only Gradle project that compiles it.",
    "Run this before any tiqian Gradle invocation, from the flake devShell:",
    "",
    "    nix develop -c bash -c 'bash tools/setup-haxe-env.sh && boring gen kotlin-f32 --project boring.json'",
    "",
    "generated sources: " + generatedEngineTree.path +
        " (" + (if (generatedEngineTree.isDirectory) "present" else "missing") + ")",
    "publication project: " + publicationProjectRoot.path +
        " (" + (if (stagedEngineProject != null) "present" else "missing") + "); the flake devShell stages it",
).joinToString("\n")

if (!generatedEngineTree.isDirectory || stagedEngineProject == null) {
    throw GradleException(ownerUnavailable)
}
val engineProject = stagedEngineProject ?: throw GradleException(ownerUnavailable)
logger.info("tiqian: :boring-kotlin-f32 compiles the Kotlin boring generates from engine-haxe")

include(
    ":boring-kotlin-f32", // boring's publication project, see above
    ":platforms:android:shaping",
    ":platforms:android:native-font",
    ":platforms:android:rendering",
    ":platforms:android:view",
    ":platforms:android:benchmark",
    ":platforms:apple:shaping",
    ":platforms:apple:frontend",
    ":platforms:apple:frontend:coretext-render",
    ":platforms:compose:compose",
    ":platforms:compose:skia-jvm",
    ":platforms:compose:material3",
    ":demo",
    ":demo:android",
    ":demo:font-diagnostics",
    // Developer probes (measurement and regression tools) and the README sample
    // generator live outside the generated engine project; see
    // tools/engine-probes/build.gradle.kts.
    ":tools:engine-probes",
)

// The included project supplies its own settings file; tiqian points Gradle at
// the :engine module directory boring ships in that project.
project(":boring-kotlin-f32").projectDir = engineProject.resolve("engine")
