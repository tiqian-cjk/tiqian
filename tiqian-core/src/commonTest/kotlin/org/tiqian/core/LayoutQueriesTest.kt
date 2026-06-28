package org.tiqian.core

import kotlin.test.Test
import kotlin.test.assertEquals

class LayoutQueriesTest {

    @Test
    fun positionedClustersFollowLineIndentAndAdvance() {
        val result = sampleResult()

        val positioned = result.positionedClusters()

        assertEquals(Rect(4f, 0f, 14f, 20f), positioned[0].rect)
        assertEquals(Rect(14f, 0f, 34f, 20f), positioned[1].rect)
        assertEquals(Rect(0f, 20f, 10f, 40f), positioned[2].rect)
    }

    @Test
    fun positionedClustersSeparateOccupiedBoxFromAutoSpaceDrawOrigin() {
        val result = LayoutResult(
            input = LayoutInput(
                content = TiqianTextContent("中Hi"),
                textStyle = TextStyle(fontSize = 10f),
                constraints = LayoutConstraints(maxWidth = 40f),
            ),
            size = Size(32.5f, 20f),
            clusters = listOf(
                Cluster(TextRange(0, 1), "中", fontKey = "cjk", advance = 10f),
                Cluster(TextRange(1, 3), "Hi", fontKey = "latin", advance = 22.5f),
            ),
            glyphRuns = emptyList(),
            lines = listOf(
                LineBox(
                    range = TextRange(0, 3),
                    clusterRange = 0..1,
                    baseline = 15f,
                    top = 0f,
                    bottom = 20f,
                    naturalWidth = 32.5f,
                    adjustedWidth = 32.5f,
                    visualWidth = 32.5f,
                ),
            ),
            debug = LayoutDebugInfo(
                autoSpaceDecisions = listOf(
                    AutoSpaceDecisionInfo(
                        clusterRange = TextRange(1, 3),
                        side = "leading",
                        boundaryRole = "CjkLatin",
                        mode = "Insert",
                        charactersAffected = 1,
                        reductionPerChar = -2.5f,
                        totalReduction = -2.5f,
                        reason = "TextAutoSpaceInsert:ideograph-alpha:quarter-em",
                    ),
                ),
            ),
        )

        val positioned = result.positionedClusters()

        assertEquals(Rect(10f, 0f, 32.5f, 20f), positioned[1].rect)
        assertEquals(12.5f, positioned[1].drawX)
        assertEquals(Rect(10f, 0f, 32.5f, 20f), result.getBoundingBox(1))
        assertEquals(1, result.getOffsetForPosition(11f, 5f))
    }

    @Test
    fun positionedClustersSeparateOccupiedBoxFromConsumedLeadingGlueDrawOrigin() {
        val result = LayoutResult(
            input = LayoutInput(
                content = TiqianTextContent("（"),
                textStyle = TextStyle(fontSize = 10f),
                constraints = LayoutConstraints(maxWidth = 10f),
            ),
            size = Size(6f, 20f),
            clusters = listOf(
                Cluster(TextRange(0, 1), "（", fontKey = "cjk", advance = 6f),
            ),
            glyphRuns = emptyList(),
            lines = listOf(
                LineBox(
                    range = TextRange(0, 1),
                    clusterRange = 0..0,
                    baseline = 15f,
                    top = 0f,
                    bottom = 20f,
                    naturalWidth = 6f,
                    adjustedWidth = 6f,
                    visualWidth = 6f,
                ),
            ),
            debug = LayoutDebugInfo(
                geometryDecisions = listOf(
                    ClusterGeometryDecisionInfo(
                        range = TextRange(0, 1),
                        sourceText = "（",
                        displayText = "（",
                        baseAdvance = 10f,
                        bodyWidth = 6f,
                        leadingGlueNatural = 4f,
                        leadingGlueConsumed = 4f,
                        trailingGlueNatural = 0f,
                        trailingGlueConsumed = 0f,
                        justificationDelta = 0f,
                        resolvedAdvance = 6f,
                        source = "test",
                        reason = "LineStartOpeningPunctuationTrim",
                    ),
                ),
            ),
        )

        val positioned = result.positionedClusters().single()

        assertEquals(Rect(0f, 0f, 6f, 20f), positioned.rect)
        assertEquals(-4f, positioned.drawX)
        assertEquals(Rect(0f, 0f, 1f, 20f), result.getCursorRect(0))
        assertEquals(0, result.getOffsetForPosition(-3f, 5f))
    }

    @Test
    fun lineAndBoxQueriesUseTiqianLineGeometry() {
        val result = sampleResult()

        assertEquals(0, result.getLineForOffset(1))
        assertEquals(1, result.getLineForOffset(3))
        assertEquals(Rect(14f, 0f, 34f, 20f), result.getBoundingBox(1))
        assertEquals(Rect(10f, 20f, 11f, 40f), result.getCursorRect(4))
    }

    @Test
    fun rangeBoxesSplitMultiUnitClustersBySourceRange() {
        val result = sampleResult()

        val boxes = result.getBoundingBoxes(TextRange(2, 4))

        assertEquals(
            listOf(
                Rect(24f, 0f, 34f, 20f),
                Rect(0f, 20f, 10f, 40f),
            ),
            boxes,
        )
    }

    @Test
    fun richTextSegmentsReusePositionedClusterGeometryAndSplitLines() {
        val result = sampleResult()
        val span = RichTextSpan(
            TextRange(1, 4),
            RichTextRole.Background,
            RichTextPaint(0x33FF0000),
        )

        val segments = result.positionedRichTextSegments(listOf(span))

        assertEquals(2, segments.size)
        assertEquals(TextRange(1, 3), segments[0].range)
        assertEquals(Rect(14f, 0f, 34f, 20f), segments[0].rect)
        assertEquals(TextRange(3, 4), segments[1].range)
        assertEquals(Rect(0f, 20f, 10f, 40f), segments[1].rect)
        assertEquals(span, segments[0].span)
    }

    @Test
    fun hitTestingChoosesOffsetFromTiqianClusterAdvances() {
        val result = sampleResult()

        assertEquals(0, result.getOffsetForPosition(3f, 5f))
        assertEquals(1, result.getOffsetForPosition(18f, 5f))
        assertEquals(2, result.getOffsetForPosition(24f, 5f))
        assertEquals(3, result.getOffsetForPosition(4f, 25f))
        assertEquals(4, result.getOffsetForPosition(30f, 25f))
    }

    private fun sampleResult(): LayoutResult =
        LayoutResult(
            input = LayoutInput(
                content = TiqianTextContent("甲——乙"),
                textStyle = TextStyle(fontSize = 10f),
                constraints = LayoutConstraints(maxWidth = 40f),
            ),
            size = Size(34f, 40f),
            clusters = listOf(
                Cluster(TextRange(0, 1), "甲", fontKey = "cjk", advance = 10f),
                Cluster(TextRange(1, 3), "——", "⸺", fontKey = "cjk", advance = 20f),
                Cluster(TextRange(3, 4), "乙", fontKey = "cjk", advance = 10f),
            ),
            glyphRuns = emptyList(),
            lines = listOf(
                LineBox(
                    range = TextRange(0, 3),
                    clusterRange = 0..1,
                    baseline = 15f,
                    top = 0f,
                    bottom = 20f,
                    naturalWidth = 30f,
                    adjustedWidth = 30f,
                    visualWidth = 30f,
                    indent = 4f,
                ),
                LineBox(
                    range = TextRange(3, 4),
                    clusterRange = 2..2,
                    baseline = 35f,
                    top = 20f,
                    bottom = 40f,
                    naturalWidth = 10f,
                    adjustedWidth = 10f,
                    visualWidth = 10f,
                ),
            ),
        )
}
