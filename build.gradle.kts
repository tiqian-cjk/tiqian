import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.publish.PublishingExtension
import org.gradle.api.publish.maven.MavenPublication
import org.gradle.api.publish.maven.tasks.PublishToMavenRepository
import org.gradle.jvm.tasks.Jar
import org.gradle.plugins.signing.SigningExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinMultiplatformExtension

plugins {
    kotlin("multiplatform") version "2.3.20" apply false
    kotlin("android") version "2.3.20" apply false
    id("com.android.library") version "9.3.1" apply false
    id("com.android.kotlin.multiplatform.library") version "9.3.1" apply false
    id("com.android.application") version "9.3.1" apply false
    id("com.android.test") version "9.3.1" apply false
    id("org.jetbrains.compose") version "1.11.1" apply false
    kotlin("plugin.serialization") version "2.3.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.20" apply false
}

group = "org.tiqian"
version = providers.gradleProperty("tiqianVersion")
    .orElse(providers.environmentVariable("TIQIAN_VERSION"))
    .getOrElse("0.1.0-SNAPSHOT")

data class PublishedModule(
    val artifactId: String,
    val displayName: String,
    val description: String,
)

val publishedModules = mapOf(
    ":engine" to PublishedModule(
        "tiqian-engine",
        "Tiqian Engine",
        "The Tiqian CJK paragraph layout engine: document and layout data types, font " +
            "and shaping contracts, line breaking, and Chinese composition rules.",
    ),
    ":platforms:jvm:shaping" to PublishedModule("tiqian-jvm-shaping", "Tiqian JVM Shaping", "JVM shaping support for Tiqian."),
    ":platforms:jvm:skia" to PublishedModule("tiqian-jvm-skia", "Tiqian Skia Shaping", "Skia shaping and glyph replay support for Tiqian."),
    ":platforms:android:shaping" to PublishedModule(
        "tiqian-android-shaping",
        "Tiqian Android Shaping",
        "Android shaping and glyph replay adapter for Tiqian.",
    ),
    ":platforms:android:native-font" to PublishedModule(
        "tiqian-android-native-font",
        "Tiqian Android Native Font",
        "Native Android font discovery and shaping support for Tiqian.",
    ),
    ":platforms:compose:compose" to PublishedModule("tiqian-compose", "Tiqian Compose", "Compose frontend for the Tiqian CJK paragraph layout engine."),
    ":platforms:compose:material3" to PublishedModule(
        "tiqian-compose-material3",
        "Tiqian Compose Material 3",
        "Material 3 context adapter for the Tiqian Compose frontend.",
    ),
)

fun Project.configureMavenPublishing(module: PublishedModule) {
    pluginManager.apply("maven-publish")
    pluginManager.apply("signing")

    extensions.configure<PublishingExtension>("publishing") {
        repositories {
            maven {
                name = "central"
                url = uri("https://ossrh-staging-api.central.sonatype.com/service/local/staging/deploy/maven2/")
                credentials {
                    username = providers.gradleProperty("mavenCentralUsername")
                        .orElse(providers.environmentVariable("MAVEN_CENTRAL_USERNAME"))
                        .orNull
                    password = providers.gradleProperty("mavenCentralPassword")
                        .orElse(providers.environmentVariable("MAVEN_CENTRAL_PASSWORD"))
                        .orNull
                }
            }
            maven {
                name = "centralSnapshots"
                url = uri("https://central.sonatype.com/repository/maven-snapshots/")
                credentials {
                    username = providers.gradleProperty("mavenCentralUsername")
                        .orElse(providers.environmentVariable("MAVEN_CENTRAL_USERNAME"))
                        .orNull
                    password = providers.gradleProperty("mavenCentralPassword")
                        .orElse(providers.environmentVariable("MAVEN_CENTRAL_PASSWORD"))
                        .orNull
                }
            }
        }
    }

    // Kotlin/Native klibs are not uploaded to the remote Central repositories.
    tasks.withType(PublishToMavenRepository::class.java).configureEach {
        val toRemoteCentral = name.endsWith("PublicationToCentralRepository") ||
            name.endsWith("PublicationToCentralSnapshotsRepository")
        val nativePublication = Regex("^publish(Ios|Macos|Watchos|Tvos|Linux|Mingw)").containsMatchIn(name)
        if (toRemoteCentral && nativePublication) {
            enabled = false
        }
    }

    pluginManager.withPlugin("com.android.library") {
        extensions.configure<LibraryExtension>("android") {
            publishing {
                singleVariant("release") {
                    withSourcesJar()
                }
            }
        }
        afterEvaluate {
            extensions.configure<PublishingExtension>("publishing") {
                if (publications.findByName("release") == null) {
                    publications.create<MavenPublication>("release") {
                        from(components["release"])
                    }
                }
            }
        }
    }

    afterEvaluate {
        extensions.configure<PublishingExtension>("publishing") {
            publications.withType(MavenPublication::class.java).configureEach {
                val publicationName = name
                val targetSuffix = artifactId.removePrefix(project.name)
                artifactId = module.artifactId + targetSuffix
                artifact(
                    tasks.register<Jar>("${publicationName}PublicationJavadocJar") {
                        archiveBaseName.set("${project.name}-$publicationName")
                        archiveClassifier.set("javadoc")
                        from(rootProject.file("LICENSE")) {
                            into("META-INF")
                        }
                    },
                )
                pom {
                    name.set(module.displayName)
                    description.set(module.description)
                    url.set("https://github.com/tiqian-cjk/tiqian")
                    licenses {
                        license {
                            name.set("Mozilla Public License 2.0")
                            url.set("https://www.mozilla.org/MPL/2.0/")
                            distribution.set("repo")
                        }
                    }
                    developers {
                        developer {
                            id.set("123Duo3")
                            name.set("123Duo3")
                            email.set("123duo3@gmail.com")
                        }
                    }
                    scm {
                        connection.set("scm:git:https://github.com/tiqian-cjk/tiqian.git")
                        developerConnection.set("scm:git:ssh://git@github.com/tiqian-cjk/tiqian.git")
                        url.set("https://github.com/tiqian-cjk/tiqian")
                    }
                }
            }
        }

        val signingKey = providers.gradleProperty("signingKey")
            .orElse(providers.environmentVariable("SIGNING_KEY"))
            .orNull
        if (!signingKey.isNullOrBlank()) {
            extensions.configure<SigningExtension>("signing") {
                useInMemoryPgpKeys(
                    providers.gradleProperty("signingKeyId")
                        .orElse(providers.environmentVariable("SIGNING_KEY_ID"))
                        .orNull,
                    signingKey,
                    providers.gradleProperty("signingPassword")
                        .orElse(providers.environmentVariable("SIGNING_PASSWORD"))
                        .orNull,
                )
                sign(extensions.getByType(PublishingExtension::class.java).publications)
            }
        }
    }
}

subprojects {
    group = rootProject.group
    version = rootProject.version

    plugins.withId("org.jetbrains.kotlin.multiplatform") {
        extensions.configure<KotlinMultiplatformExtension>("kotlin") {
            // Compile and test with the uniform provisioned JDK 25 toolchain, but emit Java 17
            // bytecode so published JVM libraries do not impose the build JDK on consumers.
            jvmToolchain(25)
            jvm {
                compilerOptions {
                    jvmTarget.set(JvmTarget.JVM_17)
                }
            }
        }
    }

    val publishedModule = publishedModules[path]
    if (publishedModule != null) {
        configureMavenPublishing(publishedModule)
    }
}

tasks.register("publishTiqianToMavenLocal") {
    group = "publishing"
    description = "Publishes every public Tiqian module to Maven Local with one lockstep version."
    dependsOn(publishedModules.keys.map { "$it:publishToMavenLocal" })
}

tasks.register("publishTiqianToCentral") {
    group = "publishing"
    description = "Uploads every public Tiqian module to the Central Portal staging API."
    dependsOn(publishedModules.keys.map { "$it:publishAllPublicationsToCentralRepository" })
}

tasks.register("publishTiqianToCentralSnapshots") {
    group = "publishing"
    description = "Uploads every public Tiqian module to the Central Portal SNAPSHOT repository."
    dependsOn(publishedModules.keys.map { "$it:publishAllPublicationsToCentralSnapshotsRepository" })
}

tasks.register("runComposeDemo") {
    group = "application"
    description = "Opens the shared Tiqian Compose demo on Desktop."
    dependsOn(":demo:runComposeDemo")
}
