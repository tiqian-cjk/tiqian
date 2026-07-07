package org.tiqian.linebreak

/**
 * The bundled American-English [Hyphenator], built from the standard TeX
 * `hyph-en-us` pattern set (Gerard D.C. Kuiken, hyph-utf8; permissive licence,
 * header preserved in the vendored resource). `leftMin`/`rightMin` follow the
 * file's `hyphenmins` (2/3).
 *
 * This is the shared bundled-patterns hyphenator for platforms where Tiqian
 * needs deterministic, enumerable English hyphenation opportunities.
 */
object EnglishHyphenation {
    val enUs: Hyphenator by lazy {
        val tex = loadBundledEnglishHyphenationPatterns()
        val (patterns, exceptions) = parseTexHyphenationPatterns(tex)
        LiangHyphenator(patterns, exceptions, leftMin = 2, rightMin = 3)
    }
}

internal expect fun loadBundledEnglishHyphenationPatterns(): String
