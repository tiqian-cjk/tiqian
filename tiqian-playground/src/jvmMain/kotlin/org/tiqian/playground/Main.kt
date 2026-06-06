package org.tiqian.playground

import org.tiqian.text.core.LayoutInput
import org.tiqian.text.core.TiqianTextContent
import org.tiqian.text.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.text.test.EarlyLayoutFixtures

fun main() {
    val engine = ExplainableStubParagraphLayoutEngine()

    EarlyLayoutFixtures.all.forEach { fixture ->
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent(fixture.text),
                constraints = fixture.constraints,
            ),
        )

        println("${fixture.id}: lines=${result.lines.size}, clusters=${result.clusters.size}")
        println("  ${result.debug.lineDecisions.joinToString()}")
    }
}

