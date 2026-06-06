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
    )
}

