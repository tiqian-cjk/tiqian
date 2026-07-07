package org.tiqian.linebreak

/**
 * Finds the offsets inside a single Western word where a soft hyphen may be
 * inserted. An offset `k` means a break between `word[k-1]` and `word[k]`; at a
 * line end a hyphen is drawn after `word[k-1]`. Offsets are codepoint indices,
 * sorted ascending, already excluding the left/right margins.
 *
 * This is the CLREQ「可使用连字符处」for mixed Western (§换行与断词连字): the
 * general rule permits splitting a Western word only at these points. Real
 * hyphenation is a platform/data capability — see [NoHyphenator] (data-free)
 * and [EnglishHyphenation] (bundled TeX patterns). Each instance is bound to
 * one language.
 */
interface Hyphenator {
    fun hyphenate(word: String): List<Int>
}

/**
 * No hyphenation opportunities. The default everywhere a real hyphenator is not
 * wired (core stays data-free): a Western word is then only ever broken at
 * existing break characters / word boundaries, never mid-word.
 */
object NoHyphenator : Hyphenator {
    override fun hyphenate(word: String): List<Int> = emptyList()
}

/**
 * Frank Liang's hyphenation algorithm — the one TeX, LibreOffice and browsers
 * use. [patterns] maps a pattern key (lowercase letters, optionally bounded by
 * the word-boundary marker '.') to its inter-letter level array (length
 * key.length + 1). [exceptions] maps a lowercased whole word to explicit break
 * offsets (an entry with no breaks forbids hyphenating that word). A break is
 * allowed where the merged level is odd and outside the [leftMin]/[rightMin]
 * margins.
 */
class LiangHyphenator(
    private val patterns: Map<String, IntArray>,
    private val exceptions: Map<String, List<Int>> = emptyMap(),
    private val leftMin: Int = 2,
    private val rightMin: Int = 3,
) : Hyphenator {
    override fun hyphenate(word: String): List<Int> {
        if (word.length < leftMin + rightMin) return emptyList()
        val lower = word.lowercase()
        exceptions[lower]?.let { explicit ->
            return explicit.filter { it in leftMin..(word.length - rightMin) }
        }

        // levels[p] is the merged hyphenation level in the gap before work[p],
        // where work = ".<word>." (the dots are pattern boundary markers).
        val work = ".$lower."
        val levels = IntArray(work.length + 1)
        for (i in work.indices) {
            val key = StringBuilder()
            for (j in (i + 1)..work.length) {
                key.append(work[j - 1])
                val pattern = patterns[key.toString()] ?: continue
                for (k in pattern.indices) {
                    if (pattern[k] > levels[i + k]) levels[i + k] = pattern[k]
                }
            }
        }

        // A break after word char m (offset m+1) lives in the gap before
        // work[m+2] (work has the leading '.'). Odd level ⇒ break allowed.
        val result = mutableListOf<Int>()
        for (m in 0 until word.length - 1) {
            val offset = m + 1
            if (offset < leftMin || offset > word.length - rightMin) continue
            if (levels[m + 2] % 2 == 1) result += offset
        }
        return result
    }
}

/**
 * Parses a TeX `hyph-*.tex` pattern file (the `\patterns{…}` and optional
 * `\hyphenation{…}` exception blocks) into ([patterns], [exceptions]) ready for
 * [LiangHyphenator]. `%` comments are stripped.
 */
fun parseTexHyphenationPatterns(tex: String): Pair<Map<String, IntArray>, Map<String, List<Int>>> {
    val noComments = tex.lineSequence().joinToString("\n") { line ->
        val comment = line.indexOf('%')
        if (comment >= 0) line.substring(0, comment) else line
    }
    fun block(macro: String): String {
        val start = noComments.indexOf(macro)
        if (start < 0) return ""
        val open = noComments.indexOf('{', start)
        val close = noComments.indexOf('}', open + 1)
        if (open < 0 || close < 0) return ""
        return noComments.substring(open + 1, close)
    }

    val whitespace = Regex("\\s+")
    val patterns = HashMap<String, IntArray>()
    for (token in block("\\patterns").split(whitespace)) {
        if (token.isBlank()) continue
        val key = StringBuilder()
        val levels = ArrayList<Int>().apply { add(0) }
        for (ch in token) {
            if (ch in '0'..'9') {
                levels[levels.size - 1] = ch - '0'
            } else {
                key.append(ch)
                levels.add(0)
            }
        }
        patterns[key.toString()] = levels.toIntArray()
    }

    val exceptions = HashMap<String, List<Int>>()
    for (token in block("\\hyphenation").split(whitespace)) {
        if (token.isBlank()) continue
        val offsets = mutableListOf<Int>()
        var pos = 0
        for (ch in token) {
            if (ch == '-') offsets += pos else pos += 1
        }
        exceptions[token.replace("-", "").lowercase()] = offsets
    }
    return patterns to exceptions
}
