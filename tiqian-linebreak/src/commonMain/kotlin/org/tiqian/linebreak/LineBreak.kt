package org.tiqian.linebreak

import org.tiqian.core.TextRange

data class BreakOpportunity(
    val index: Int,
    val kind: BreakKind,
    val penalty: Int = 0,
    val reason: String,
)

enum class BreakKind {
    Allowed,
    Forbidden,
    Required,
    Problematic,
}

/**
 * UAX#14 mandatory-break code points (BK / CR / LF / NL classes): a hard line
 * break the layout MUST honor (ADR 0037, source-faithful plain text). `CRLF`
 * (U+000D U+000A) is a single break — a code-point scanner should treat an LF
 * right after a CR as part of the same break, not a second one.
 */
fun isMandatoryBreakCodePoint(codePoint: Int): Boolean =
    codePoint == 0x000A || // LF  line feed
        codePoint == 0x000B || // VT  vertical tab
        codePoint == 0x000C || // FF  form feed
        codePoint == 0x000D || // CR  carriage return
        codePoint == 0x0085 || // NEL next line
        codePoint == 0x2028 || // LS  line separator
        codePoint == 0x2029    // PS  paragraph separator

interface LineBreakAnalyzer {
    fun analyze(text: String): List<BreakOpportunity>
}

class SimpleCharacterLineBreakAnalyzer : LineBreakAnalyzer {
    override fun analyze(text: String): List<BreakOpportunity> {
        if (text.isEmpty()) return emptyList()

        return buildList {
            for (index in 1..text.length) {
                val prev = text[index - 1].code
                // A mandatory-break char forces a Required break AFTER it, except the
                // CR of a CRLF pair (the break belongs after the following LF).
                val mandatory = isMandatoryBreakCodePoint(prev) &&
                    !(prev == 0x000D && index < text.length && text[index].code == 0x000A)
                add(
                    BreakOpportunity(
                        index = index,
                        kind = if (index == text.length || mandatory) BreakKind.Required else BreakKind.Allowed,
                        reason = if (mandatory) "MandatoryBreak" else "SimpleCharacterLineBreakAnalyzer",
                    ),
                )
            }
        }
    }
}

data class ForbiddenBreak(
    val range: TextRange,
    val reason: String,
)

