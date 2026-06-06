package org.tiqian.text.linebreak

import org.tiqian.text.core.TextRange

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

interface LineBreakAnalyzer {
    fun analyze(text: String): List<BreakOpportunity>
}

class SimpleCharacterLineBreakAnalyzer : LineBreakAnalyzer {
    override fun analyze(text: String): List<BreakOpportunity> {
        if (text.isEmpty()) return emptyList()

        return buildList {
            for (index in 1..text.length) {
                add(
                    BreakOpportunity(
                        index = index,
                        kind = if (index == text.length) BreakKind.Required else BreakKind.Allowed,
                        reason = "SimpleCharacterLineBreakAnalyzer",
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

