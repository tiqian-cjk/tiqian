package org.tiqian.text.test

import org.tiqian.text.core.LayoutConstraints

data class LayoutFixture(
    val id: String,
    val text: String,
    val constraints: LayoutConstraints,
    val notes: String,
)

object EarlyLayoutFixtures {
    val all: List<LayoutFixture> = listOf(
        LayoutFixture(
            id = "basic-pause-stop",
            text = "中文，中文。",
            constraints = LayoutConstraints(maxWidth = 160f),
            notes = "Covers pause/stop punctuation glue.",
        ),
        LayoutFixture(
            id = "ellipsis-and-dash",
            text = "中文……English——中文。",
            constraints = LayoutConstraints(maxWidth = 220f),
            notes = "Covers CJK ellipsis and dash fallback decisions.",
        ),
        LayoutFixture(
            id = "nested-quotes",
            text = "他说：“你好，世界。”",
            constraints = LayoutConstraints(maxWidth = 180f),
            notes = "Covers opening/closing punctuation and repair planning.",
        ),
        LayoutFixture(
            id = "adjacent-punctuation-spacing",
            text = "他说：“你好，世界。”！！",
            constraints = LayoutConstraints(maxWidth = 220f),
            notes = "Shows punctuation atoms and adjacent punctuation spacing compression.",
        ),
        LayoutFixture(
            id = "fallback-roles",
            text = "提椠……Hello——世界。",
            constraints = LayoutConstraints(maxWidth = 240f),
            notes = "Covers cluster font role classification for CJK text, CJK punctuation, and Latin words.",
        ),
        LayoutFixture(
            id = "greedy-multi-line",
            text = "提椠是一个面向中文正文的排版引擎，用于测试断行。",
            constraints = LayoutConstraints(maxWidth = 144f),
            notes = "Exercises greedy multi-line breaking with width tight enough to trigger several breaks.",
        ),
        LayoutFixture(
            id = "kinsoku-carry-previous",
            text = "提椠中文中文中文。",
            constraints = LayoutConstraints(maxWidth = 64f),
            notes = "Forces a kinsoku CarryPrevious repair: greedy break would put 。 at line start, so the engine pulls the preceding character down.",
        ),
    )
}
