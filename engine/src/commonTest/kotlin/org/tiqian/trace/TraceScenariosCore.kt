package org.tiqian.trace

import org.tiqian.core.EastAsianSpacingData
import org.tiqian.core.SourceBoundaryBias
import org.tiqian.core.TextRange
import org.tiqian.core.UnicodeEastAsianSpacing
import org.tiqian.core.UnicodeScriptEvidenceClassifier
import org.tiqian.core.UnicodeWordCharacter
import org.tiqian.core.codePointAtCompat
import org.tiqian.core.coerceToInteractionBoundary
import org.tiqian.core.interactionBoundaries
import org.tiqian.core.sourceGraphemeBoundaries
import org.tiqian.test.trace.TraceFormat
import org.tiqian.test.trace.TraceRecorder

/**
 * Process-trace scenarios for the core cluster: East Asian spacing tables
 * and the source interaction-boundary grouping rules. Every non-ASCII input
 * is written as escapes; lone surrogates are built from char codes at run
 * time (a lone surrogate inside a string literal is rewritten to '?' by the
 * JS test bundler) and identified by label only.
 */
internal object CoreTraceScenarios {

    val all: List<TraceScenario> = listOf(
        eastAsianSpacing(),
        interactionBoundaries(),
    )

    private fun header(id: String): String = "scenario: $id\n"

    private fun surrogateText(vararg codes: Int): String =
        CharArray(codes.size) { codes[it].toChar() }.concatToString()

    private fun rejected(action: () -> Unit): Boolean =
        try {
            action()
            false
        } catch (e: RuntimeException) {
            true
        }

    private fun eastAsianSpacing(): TraceScenario = TraceScenario(
        id = "core.east-asian-spacing",
        notes = "word-character set, script evidence, spacing lookup, Chinese context, cluster and edge resolution",
    ) {
        val t = TraceRecorder()
        t.event("word-contains", "cp" to "0x41", "contains" to UnicodeWordCharacter.contains(0x41))
        t.event("word-contains", "cp" to "0x4E2D", "contains" to UnicodeWordCharacter.contains(0x4E2D))
        t.event("word-contains", "cp" to "0x20", "contains" to UnicodeWordCharacter.contains(0x20))
        t.event("word-contains", "cp" to "0x21", "contains" to UnicodeWordCharacter.contains(0x21))
        t.event("word-contains", "cp" to "-1", "rejected" to rejected { UnicodeWordCharacter.contains(-1) })
        t.event("word-contains", "cp" to "0x110000", "rejected" to rejected { UnicodeWordCharacter.contains(0x110000) })
        t.event("word-contains", "cp" to "0xD800", "rejected" to rejected { UnicodeWordCharacter.contains(0xD800) })
        t.event("word-contains", "cp" to "0xDFFF", "rejected" to rejected { UnicodeWordCharacter.contains(0xDFFF) })

        t.event("script-classify", "cp" to "0x4E00", "evidence" to UnicodeScriptEvidenceClassifier.classify(0x4E00).name)
        t.event("script-classify", "cp" to "0x41", "evidence" to UnicodeScriptEvidenceClassifier.classify(0x41).name)
        t.event("script-classify", "cp" to "0x20", "evidence" to UnicodeScriptEvidenceClassifier.classify(0x20).name)
        t.event("script-classify", "cp" to "-1", "rejected" to rejected { UnicodeScriptEvidenceClassifier.classify(-1) })
        t.event("script-classify", "cp" to "0x110000", "rejected" to rejected { UnicodeScriptEvidenceClassifier.classify(0x110000) })
        t.event("script-classify", "cp" to "0xD800", "rejected" to rejected { UnicodeScriptEvidenceClassifier.classify(0xD800) })
        t.event("script-classify", "cp" to "0xDFFF", "rejected" to rejected { UnicodeScriptEvidenceClassifier.classify(0xDFFF) })

        val lookups = listOf("0x02C7" to 0x02C7, "0x0030" to 0x30, "0x0021" to 0x21, "0x0000" to 0x0, "0x10FFFF" to 0x10FFFF)
        for ((label, cp) in lookups) {
            t.event("spacing-lookup", "cp" to label, "value" to EastAsianSpacingData.lookup(cp).name)
        }
        t.event("property-reject", "cp" to "-1", "rejected" to rejected { UnicodeEastAsianSpacing.propertyOf(-1) })
        t.event("property-reject", "cp" to "0x110000", "rejected" to rejected { UnicodeEastAsianSpacing.propertyOf(0x110000) })
        t.event("property-reject", "cp" to "0xD800", "rejected" to rejected { UnicodeEastAsianSpacing.propertyOf(0xD800) })
        t.event("property-reject", "cp" to "0xDFFF", "rejected" to rejected { UnicodeEastAsianSpacing.propertyOf(0xDFFF) })

        val chinese = listOf("zh", "zh-Hans", "zh-Hant", "zh-CN", "zh_TW", "cmn", "gan", "nan", "yue", "yue-HK", "lzh", "cmn-Hans-CN")
        for (locale in chinese) {
            t.event("chinese-context", "locale" to locale, "chinese" to UnicodeEastAsianSpacing.isChineseLanguageContext(locale))
        }
        for (locale in listOf("en", "en-US", "ja", "ko", "fr", "de", "es")) {
            t.event("chinese-context", "locale" to locale, "chinese" to UnicodeEastAsianSpacing.isChineseLanguageContext(locale))
        }

        val clusters = listOf(
            "empty" to Pair("", "zh"),
            "enclosing-mark" to Pair("A\u20DD", "zh"),
            "conditional-chinese" to Pair("!", "zh-CN"),
            "conditional-western" to Pair("!", "en-US"),
            "wide" to Pair("\u4E2D", "zh"),
            "narrow" to Pair("A", "zh"),
            "nul" to Pair("\u0000", "zh"),
            "supplementary" to Pair("\uD83D\uDE00", "zh"),
        )
        for ((label, input) in clusters) {
            val (cluster, locale) = input
            t.event(
                "cluster-resolve", "case" to label, "locale" to locale,
                "value" to UnicodeEastAsianSpacing.resolvedForGraphemeCluster(cluster, locale).name,
            )
        }
        t.event("cluster-reject", "case" to "lone-high", "rejected" to rejected {
            UnicodeEastAsianSpacing.resolvedForGraphemeCluster(surrogateText(0xD800), "zh")
        })
        t.event("cluster-reject", "case" to "high-then-letter", "rejected" to rejected {
            UnicodeEastAsianSpacing.resolvedForGraphemeCluster(surrogateText(0xD800, 0x41), "zh")
        })
        t.event("cluster-reject", "case" to "high-then-private", "rejected" to rejected {
            UnicodeEastAsianSpacing.resolvedForGraphemeCluster(surrogateText(0xD800, 0xE000), "zh")
        })

        val edgeSets = listOf(
            "empty" to Pair("", "zh"),
            "mixed" to Pair("\u4E2Da\u6587", "zh"),
            "western" to Pair("hello", "en"),
        )
        for ((label, input) in edgeSets) {
            val (text, locale) = input
            val edges = UnicodeEastAsianSpacing.resolvedEdges(text, locale)
            t.event(
                "edges-resolve", "case" to label,
                "leading" to edges.leading.name, "trailing" to edges.trailing.name,
                "contains-wide" to edges.containsWide,
            )
        }
        header("core.east-asian-spacing") + t.text()
    }

    private fun interactionBoundaries(): TraceScenario = TraceScenario(
        id = "core.interaction-boundaries",
        notes = "grapheme grouping rules (CRLF, flags, Hangul jamo, extenders, modifiers, ZWJ), window ranges, and coercion biases",
    ) {
        val t = TraceRecorder()
        val cases = listOf(
            "crlf" to "\r\n",
            "lone-cr" to "\r",
            "lf-after-text" to "a\n",
            "flag-pair" to "\uD83C\uDDE6\uD83C\uDDE8",
            "flag-odd-run" to "\uD83C\uDDE6\uD83C\uDDE6\uD83C\uDDE6",
            "flag-then-letter" to "\uD83C\uDDE6A",
            "flag-single" to "\uD83C\uDDE6",
            "hangul-llv" to "\u1100\u1100\u1161",
            "hangul-lvt" to "\u1100\u1161\u11A8",
            "hangul-lvtt" to "\u1100\u1161\u11A8\u11A8",
            "hangul-l-then-letter" to "\u1100A",
            "hangul-lv-then-letter" to "\u1100\u1161A",
            "hangul-ext-l" to "\uA960\u1161",
            "hangul-ext-v" to "\u1100\uD7B0",
            "hangul-ext-t" to "\u1100\u1161\uD7CB",
            "precomposed-absorbs-jamo" to "\uAC00\u1161\u11A8",
            "precomposed-lvt-merges-t" to "\uAC01\u11A8",
            "precomposed-lvt-then-letter" to "\uAC01A",
            "precomposed-lv-plus-t" to "\uAC00\u11A8",
            "extender-accent" to "a\u0301",
            "extender-selector" to "a\uFE0F",
            "extender-selector-supplementary" to "a\uDB40\uDD00",
            "flag-tag-block" to "\uD83C\uDFF4\uDB40\uDC67\uDB40\uDC62\uDB40\uDC65\uDB40\uDC6E\uDB40\uDC67",
            "zwnj-sticks" to "\uAC00\u200C",
            "extender-then-letter" to "aA",
            "cr-then-letter" to "\rA",
            "letter-then-l-jamo" to "a\u1100",
            "t-band-upper-miss" to "\u1100\u1161\uE000",
            "vs-band-upper-miss" to "a\uDB40\uDDF0",
            "tag-band-upper-miss" to "a\uDB40\uDCA0",
            "base-then-han" to "\uD83D\uDC4D\u7532",
            "base-then-supplementary" to "\uD83D\uDC4D\uD83D\uDE00",
            "modifier-attaches" to "\uD83D\uDC4D\uD83C\uDFFB",
            "modifier-then-extender" to "\uD83D\uDC4D\uD83C\uDFFB\uFE0F",
            "modifier-without-base" to "a\uD83C\uDFFB",
            "base-alone" to "\uD83D\uDC4D",
            "zwj-chain" to "\uD83D\uDC69\u200D\uD83D\uDC69\u200D\uD83D\uDC66",
            "zwj-trailing" to "a\u200D",
            "zwj-then-letter" to "\uD83D\uDC69\u200Da",
            "letter-zwj-letter" to "a\u200Da",
            "zwj-member-with-modifier" to "\uD83D\uDC4D\u200D\uD83D\uDC4D\uD83C\uDFFB",
            "pair-then-letter" to "\uD83D\uDE00A",
        )
        for ((label, text) in cases) {
            t.event(
                "boundaries", "case" to label, "len" to TraceFormat.i(text.length),
                "units" to text.interactionBoundaries(TextRange(0, text.length)).joinToString("|"),
            )
        }
        t.event(
            "boundaries", "case" to "lone-high-at-end", "len" to TraceFormat.i(2),
            "units" to surrogateText(0x61, 0xD800).interactionBoundaries(TextRange(0, 2)).joinToString("|"),
        )
        t.event(
            "boundaries", "case" to "lone-high-then-letter", "len" to TraceFormat.i(3),
            "units" to surrogateText(0x61, 0xD800, 0x41).interactionBoundaries(TextRange(0, 3)).joinToString("|"),
        )

        t.event(
            "window", "case" to "inner-range",
            "units" to "abcd".interactionBoundaries(TextRange(1, 3)).joinToString("|"),
        )
        t.event(
            "window", "case" to "range-past-end",
            "units" to "ab".interactionBoundaries(TextRange(5, 9)).joinToString("|"),
        )
        t.event(
            "window", "case" to "source-grapheme",
            "units" to "\uD83D\uDE00b".sourceGraphemeBoundaries(TextRange(0, 3)).joinToString("|"),
        )

        t.event("code-point-at", "case" to "plain", "cp" to TraceFormat.i("a".codePointAtCompat(0, 1)))
        t.event("code-point-at", "case" to "pair", "cp" to TraceFormat.i("\uD83D\uDE00".codePointAtCompat(0, 2)))
        t.event("code-point-at", "case" to "lone-high-at-end", "cp" to TraceFormat.i(surrogateText(0x61, 0xD800).codePointAtCompat(1, 2)))
        t.event("code-point-at", "case" to "lone-high-mid", "cp" to TraceFormat.i(surrogateText(0x61, 0xD800, 0x41).codePointAtCompat(1, 3)))

        val family = "\uD83D\uDC68\u200D\uD83D\uDC69\u200D\uD83D\uDC67\u200D\uD83D\uDC67"
        t.event("coerce", "case" to "family-nearest", "offset" to TraceFormat.i(2), "bias" to SourceBoundaryBias.Nearest.name, "to" to TraceFormat.i(family.coerceToInteractionBoundary(2, TextRange(0, family.length), SourceBoundaryBias.Nearest)))
        t.event("coerce", "case" to "family-backward", "offset" to TraceFormat.i(2), "bias" to SourceBoundaryBias.Backward.name, "to" to TraceFormat.i(family.coerceToInteractionBoundary(2, TextRange(0, family.length), SourceBoundaryBias.Backward)))
        t.event("coerce", "case" to "family-forward", "offset" to TraceFormat.i(2), "bias" to SourceBoundaryBias.Forward.name, "to" to TraceFormat.i(family.coerceToInteractionBoundary(2, TextRange(0, family.length), SourceBoundaryBias.Forward)))
        t.event("coerce", "case" to "already-on-boundary", "offset" to TraceFormat.i(2), "bias" to SourceBoundaryBias.Nearest.name, "to" to TraceFormat.i("\uD83D\uDE00b".coerceToInteractionBoundary(2, TextRange(0, 3), SourceBoundaryBias.Nearest)))
        t.event("coerce", "case" to "endpoint-high", "offset" to TraceFormat.i(9), "bias" to SourceBoundaryBias.Backward.name, "to" to TraceFormat.i("\uD83D\uDE00b".coerceToInteractionBoundary(9, TextRange(0, 3), SourceBoundaryBias.Backward)))
        t.event("coerce", "case" to "endpoint-low", "offset" to TraceFormat.i(-1), "bias" to SourceBoundaryBias.Forward.name, "to" to TraceFormat.i("\uD83D\uDE00b".coerceToInteractionBoundary(-1, TextRange(0, 3), SourceBoundaryBias.Forward)))
        header("core.interaction-boundaries") + t.text()
    }
}
