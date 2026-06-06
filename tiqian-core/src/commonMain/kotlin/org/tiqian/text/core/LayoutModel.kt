package org.tiqian.text.core

data class Cluster(
    val range: TextRange,
    val text: String,
    val displayText: String = text,
    val fontKey: String,
    val advance: Float,
)

data class GlyphRun(
    val range: TextRange,
    val fontKey: String,
    val glyphs: List<Glyph>,
    val advance: Float,
)

data class Glyph(
    val id: UInt,
    val clusterRange: TextRange,
    val advance: Float,
    val bounds: Rect? = null,
)

data class LineBox(
    val range: TextRange,
    val baseline: Float,
    val top: Float,
    val bottom: Float,
    val naturalWidth: Float,
    val adjustedWidth: Float,
    val visualWidth: Float,
    val debug: LineDebugInfo = LineDebugInfo(),
)

data class LineDebugInfo(
    val repair: String? = null,
    val notes: List<String> = emptyList(),
)

data class LayoutResult(
    val input: LayoutInput,
    val size: Size,
    val clusters: List<Cluster>,
    val glyphRuns: List<GlyphRun>,
    val lines: List<LineBox>,
    val debug: LayoutDebugInfo = LayoutDebugInfo(),
)

data class LayoutDebugInfo(
    val fontDecisions: List<String> = emptyList(),
    val metricDecisions: List<String> = emptyList(),
    val lineDecisions: List<String> = emptyList(),
)
