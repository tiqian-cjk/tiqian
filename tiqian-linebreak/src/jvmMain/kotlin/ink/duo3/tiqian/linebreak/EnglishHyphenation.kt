package ink.duo3.tiqian.linebreak

/**
 * The bundled American-English [Hyphenator], built from the standard TeX
 * `hyph-en-us` pattern set (Gerard D.C. Kuiken, hyph-utf8; permissive licence,
 * header preserved in the vendored resource). `leftMin`/`rightMin` follow the
 * file's `hyphenmins` (2/3).
 *
 * This is the JVM realisation of the bundled-patterns choice; Android can wire
 * its native hyphenator behind the same [Hyphenator] interface later.
 */
object EnglishHyphenation {
    private const val RESOURCE = "/hyphenation/hyph-en-us.tex"

    val enUs: Hyphenator by lazy {
        val tex = EnglishHyphenation::class.java.getResourceAsStream(RESOURCE)
            ?.bufferedReader()?.use { it.readText() }
            ?: error("Missing bundled hyphenation pattern resource: $RESOURCE")
        val (patterns, exceptions) = parseTexHyphenationPatterns(tex)
        LiangHyphenator(patterns, exceptions, leftMin = 2, rightMin = 3)
    }
}
