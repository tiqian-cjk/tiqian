package org.tiqian.linebreak

private const val EN_US_RESOURCE = "/hyphenation/hyph-en-us.tex"

internal actual fun loadBundledEnglishHyphenationPatterns(): String =
    EnglishHyphenation::class.java.getResourceAsStream(EN_US_RESOURCE)
        ?.bufferedReader()?.use { it.readText() }
        ?: error("Missing bundled hyphenation pattern resource: $EN_US_RESOURCE")
