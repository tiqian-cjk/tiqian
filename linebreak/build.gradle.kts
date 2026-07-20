plugins {
    kotlin("multiplatform")
    id("com.android.kotlin.multiplatform.library")
}

// Web has no synchronous resource loading, so the bundled en-US TeX patterns are
// embedded into JavaScript as a generated Kotlin constant, built from the SAME .tex the
// JVM/Android resource path reads (single source of truth). ADR 0039.
val generateJsHyphenationPatterns = tasks.register("generateJsHyphenationPatterns") {
    val patternFile = layout.projectDirectory.file("src/commonMain/resources/hyphenation/hyph-en-us.tex")
    val outputDir = layout.buildDirectory.dir("generated/hyphenation-js/kotlin")
    inputs.file(patternFile)
    outputs.dir(outputDir)
    doLast {
        val tex = patternFile.asFile.readText()
        // The raw-string embedding is only safe if the .tex has no `$` (Kotlin template)
        // or `"""` (raw-string terminator). The vendored file has neither; fail loudly if a
        // future update introduces them rather than silently corrupting the patterns.
        require(!tex.contains("\"\"\"") && !tex.contains('$')) {
            "hyph-en-us.tex contains a \$ or triple-quote — the raw-string embedding needs escaping"
        }
        val file = outputDir.get().file("org/tiqian/linebreak/EnUsHyphenationPatterns.kt").asFile
        file.parentFile.mkdirs()
        file.writeText(
            "package org.tiqian.linebreak\n\n" +
                "// GENERATED from src/commonMain/resources/hyphenation/hyph-en-us.tex — do not edit.\n" +
                "internal val EN_US_HYPHENATION_PATTERNS: String = \"\"\"\n" +
                tex +
                "\"\"\"\n",
        )
    }
}

kotlin {
    jvm()
    android {
        namespace = "org.tiqian.linebreak"
        compileSdk = 36
        minSdk = 31
        withHostTest {}
    }
    js {
        browser()
        useEsModules()
    }

    sourceSets {
        commonMain.dependencies {
            api(project(":core"))
        }

        commonTest.dependencies {
            implementation(kotlin("test"))
        }

        jsMain {
            kotlin.srcDir(generateJsHyphenationPatterns)
        }
    }
}
