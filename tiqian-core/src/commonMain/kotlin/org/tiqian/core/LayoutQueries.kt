package org.tiqian.core

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * A cluster positioned in layout coordinates. The rectangle is the cluster's line box slice, not
 * glyph ink bounds: selection, hit testing, and accessibility need stable occupied text geometry.
 */
data class PositionedCluster(
    val lineIndex: Int,
    val clusterIndex: Int,
    val range: TextRange,
    /** Occupied text box left edge, used for selection, hit testing, and accessibility. */
    val left: Float,
    val top: Float,
    /** Occupied text box right edge, used for selection, hit testing, and accessibility. */
    val right: Float,
    val bottom: Float,
    val baseline: Float,
    /**
     * Glyph draw origin. This may differ from [left] when the cluster carries
     * leading autospace or consumed leading punctuation glue.
     */
    val drawX: Float = left,
) {
    val width: Float get() = right - left
    val height: Float get() = bottom - top
    val rect: Rect get() = Rect(left, top, right, bottom)
}

/**
 * A per-line occupied geometry segment covered by a [RichTextSpan]. Segments are derived from the
 * same positioned clusters used for selection/hit testing, not from renderer-side text shaping.
 */
data class RichTextLineSegment(
    val span: RichTextSpan,
    val lineIndex: Int,
    val range: TextRange,
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
    val baseline: Float,
) {
    val width: Float get() = right - left
    val height: Float get() = bottom - top
    val rect: Rect get() = Rect(left, top, right, bottom)
}

/**
 * Returns each cluster's occupied rectangle using the same line/cluster advances consumed by
 * renderers. This is the geometry bridge for links, selection, and accessibility.
 */
fun LayoutResult.positionedClusters(): List<PositionedCluster> =
    lines.flatMapIndexed { lineIndex, line -> positionedClusters(lineIndex, line) }

/** Returns the positioned clusters for [line]. */
fun LayoutResult.positionedClusters(line: LineBox): List<PositionedCluster> {
    val lineIndex = lines.indexOf(line)
    require(lineIndex >= 0) { "line must belong to this LayoutResult." }
    return positionedClusters(lineIndex, line)
}

/**
 * Returns the visible glyph-ink bounds of the laid-out lines, in layout coordinates.
 *
 * This is intentionally separate from [positionedClusters]: ink overhang (notably italic
 * Latin) may extend outside the occupied advance box, but selection, links, and hit testing
 * must continue to use stable occupied geometry. Renderers use this only to avoid clipping
 * real ink that belongs to already-emitted line boxes.
 */
fun LayoutResult.glyphInkBounds(): Rect? {
    val positionsByRange = positionedClusters().associateBy { it.range }
    var left = Float.POSITIVE_INFINITY
    var top = Float.POSITIVE_INFINITY
    var right = Float.NEGATIVE_INFINITY
    var bottom = Float.NEGATIVE_INFINITY
    for (run in glyphRuns) {
        for (glyph in run.glyphs) {
            val bounds = glyph.bounds ?: continue
            val cluster = positionsByRange[glyph.clusterRange] ?: continue
            left = minOf(left, cluster.drawX + glyph.x + bounds.left)
            top = minOf(top, cluster.baseline + glyph.y + bounds.top)
            right = maxOf(right, cluster.drawX + glyph.x + bounds.right)
            bottom = maxOf(bottom, cluster.baseline + glyph.y + bounds.bottom)
        }
    }
    if (!left.isFinite() || !top.isFinite() || !right.isFinite() || !bottom.isFinite()) return null
    return Rect(left, top, right, bottom)
}

/**
 * Compose-like line lookup backed by Tiqian line boxes. End offsets attach to the previous line so
 * a caret at paragraph end stays on the final visible line.
 */
fun LayoutResult.getLineForOffset(offset: Int): Int {
    if (lines.isEmpty()) return -1
    val clamped = offset.coerceIn(0, input.content.text.length)
    if (clamped == input.content.text.length) return lines.lastIndex
    return lines.indexOfFirst { clamped >= it.range.start && clamped < it.range.end }
        .takeIf { it >= 0 }
        ?: nearestLineForOffset(clamped)
}

/**
 * Returns the occupied cluster box containing [offset]. A paragraph-end offset returns the final
 * caret rectangle so accessibility callers still get a concrete position.
 */
fun LayoutResult.getBoundingBox(offset: Int): Rect {
    if (lines.isEmpty()) return Rect(0f, 0f, 0f, 0f)
    val clamped = offset.coerceIn(0, input.content.text.length)
    if (clamped == input.content.text.length) return getCursorRect(clamped)
    val positioned = positionedClusters().firstOrNull { clamped >= it.range.start && clamped < it.range.end }
        ?: return getCursorRect(clamped)
    return positioned.rect
}

/**
 * Returns one or more line-box slices covered by [range]. When a source range cuts through a
 * multi-code-unit display cluster, `SourceRangeLinearClusterSplit` divides the cluster box
 * proportionally by source UTF-16 offsets until glyph-level source mapping lands.
 */
fun LayoutResult.getBoundingBoxes(range: TextRange): List<Rect> {
    if (range.isEmpty || lines.isEmpty()) return emptyList()
    val start = range.start.coerceIn(0, input.content.text.length)
    val end = range.end.coerceIn(start, input.content.text.length)
    if (start == end) return emptyList()
    return positionedClusters().mapNotNull { cluster ->
        val sliceStart = max(start, cluster.range.start)
        val sliceEnd = minOf(end, cluster.range.end)
        if (sliceStart >= sliceEnd) return@mapNotNull null
        cluster.sliceRect(sliceStart, sliceEnd)
    }
}

fun LayoutResult.getBoundingBoxes(start: Int, end: Int): List<Rect> =
    getBoundingBoxes(TextRange(start, end))

/**
 * Returns continuous line-local geometry for rich-text spans. A span crossing lines is split at
 * line boundaries; a span cutting through a multi-code-unit display cluster uses the same
 * proportional source split as [getBoundingBoxes].
 */
fun LayoutResult.positionedRichTextSegments(spans: List<RichTextSpan>): List<RichTextLineSegment> {
    if (spans.isEmpty() || lines.isEmpty()) return emptyList()
    val clusters = positionedClusters()
    val textLength = input.content.text.length
    val out = mutableListOf<RichTextLineSegment>()
    for (span in spans) {
        val start = span.range.start.coerceIn(0, textLength)
        val end = span.range.end.coerceIn(start, textLength)
        if (start == end) continue
        // One normalized span instance for ALL of this span's slices — allocated once
        // (not per overlapping cluster) so the merge check compares by identity.
        val normalized = span.copy(range = TextRange(start, end))
        var pending: RichTextLineSegment? = null
        fun flushPending() {
            pending?.let(out::add)
            pending = null
        }
        // Clusters are source-ordered: binary-search the first cluster that reaches
        // the span, and stop past its end — each span scans only its own window.
        var lo = 0
        var hi = clusters.size
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            if (clusters[mid].range.end <= start) lo = mid + 1 else hi = mid
        }
        for (i in lo until clusters.size) {
            val cluster = clusters[i]
            if (cluster.range.start >= end) break
            val sliceStart = max(start, cluster.range.start)
            val sliceEnd = minOf(end, cluster.range.end)
            if (sliceStart >= sliceEnd) continue
            val rect = cluster.sliceRect(sliceStart, sliceEnd)
            val next = RichTextLineSegment(
                span = normalized,
                lineIndex = cluster.lineIndex,
                range = TextRange(sliceStart, sliceEnd),
                left = rect.left,
                top = rect.top,
                right = rect.right,
                bottom = rect.bottom,
                baseline = cluster.baseline,
            )
            val current = pending
            if (
                current != null &&
                current.lineIndex == next.lineIndex &&
                current.span === next.span &&
                current.range.end == next.range.start &&
                abs(current.right - next.left) <= 0.5f
            ) {
                pending = current.copy(
                    range = TextRange(current.range.start, next.range.end),
                    right = next.right,
                    top = minOf(current.top, next.top),
                    bottom = max(current.bottom, next.bottom),
                )
            } else {
                flushPending()
                pending = next
            }
        }
        flushPending()
    }
    return out
}

/**
 * Returns a caret rectangle for [offset]. The x position is derived from Tiqian's cluster advances;
 * inside a multi-code-unit cluster, `SourceRangeLinearClusterSplit` places the caret proportionally.
 */
fun LayoutResult.getCursorRect(offset: Int): Rect {
    if (lines.isEmpty()) return Rect(0f, 0f, 0f, 0f)
    val clamped = offset.coerceIn(0, input.content.text.length)
    val lineIndex = getLineForOffset(clamped).coerceAtLeast(0)
    val line = lines[lineIndex]
    val clusters = positionedClusters(lineIndex, line)
    val caretWidth = 1f
    val x = when {
        clusters.isEmpty() -> line.indent
        clamped <= clusters.first().range.start -> clusters.first().left
        clamped >= clusters.last().range.end -> clusters.last().right
        else -> {
            val cluster = clusters.first { clamped >= it.range.start && clamped <= it.range.end }
            cluster.xForOffset(clamped)
        }
    }
    return Rect(x, line.top, x + caretWidth, line.bottom)
}

/**
 * Hit-tests a point against Tiqian line/cluster geometry. `ClusterAdvanceLinearHitTest` chooses the
 * nearest source offset inside a cluster using its occupied advance until glyph-level source maps
 * are available.
 */
fun LayoutResult.getOffsetForPosition(x: Float, y: Float): Int {
    if (lines.isEmpty()) return 0
    val lineIndex = lines.indices.minBy { index ->
        val line = lines[index]
        when {
            y < line.top -> line.top - y
            y > line.bottom -> y - line.bottom
            else -> 0f
        }
    }
    val clusters = positionedClusters(lineIndex, lines[lineIndex])
    if (clusters.isEmpty()) return lines[lineIndex].range.start
    if (x <= clusters.first().left) return clusters.first().range.start
    if (x >= clusters.last().right) return clusters.last().range.end
    val cluster = clusters.firstOrNull { x >= it.left && x <= it.right }
        ?: clusters.minBy { minOf(abs(x - it.left), abs(x - it.right)) }
    return cluster.offsetForX(x)
}

private fun LayoutResult.positionedClusters(lineIndex: Int, line: LineBox): List<PositionedCluster> {
    val leadingConsumed = debug.geometryDecisions
        .filter { it.leadingGlueConsumed > 0f }
        .associate { it.range to it.leadingGlueConsumed }
    // The applied autospace width is recorded on the decision (an Insert gap is a
    // negative reduction, `AutoSpacePolicy.gapEm` at apply time) — geometry reads
    // the recorded value instead of re-deriving a constant (ADR 0009 amendment).
    val leadingAutoSpaceGaps = debug.autoSpaceDecisions
        .filter { it.side == "leading" }
        .associate { it.clusterRange to -it.totalReduction }

    var x = line.indent
    val positioned = line.clusterRange.mapIndexed { indexInLine, clusterIndex ->
        val cluster = clusters[clusterIndex]
        val leadingGap = if (indexInLine != 0) leadingAutoSpaceGaps[cluster.range] ?: 0f else 0f
        val drawX = x + cluster.leadingLayoutAdvance + cluster.glyphInlineShift + leadingGap -
            (leadingConsumed[cluster.range] ?: 0f)
        val positioned = PositionedCluster(
            lineIndex = lineIndex,
            clusterIndex = clusterIndex,
            range = cluster.range,
            left = x,
            top = line.top,
            right = x + cluster.advance,
            bottom = line.bottom,
            baseline = line.baseline + cluster.baselineShift,
            drawX = drawX,
        )
        x += cluster.advance
        positioned
    }
    return withRubySelectionGeometry(positioned, lineIndex)
}

private fun LayoutResult.nearestLineForOffset(offset: Int): Int =
    lines.indices.minBy { index ->
        val line = lines[index]
        when {
            offset < line.range.start -> line.range.start - offset
            offset > line.range.end -> offset - line.range.end
            else -> 0
        }
    }

private fun PositionedCluster.xForOffset(offset: Int): Float {
    if (range.length <= 0 || width <= 0f) return left
    val ratio = (offset - range.start).toFloat() / range.length.toFloat()
    return left + width * ratio.coerceIn(0f, 1f)
}

private fun PositionedCluster.offsetForX(x: Float): Int {
    if (range.length <= 0 || width <= 0f) return range.start
    val ratio = ((x - left) / width).coerceIn(0f, 1f)
    return (range.start + (ratio * range.length).roundToInt()).coerceIn(range.start, range.end)
}

private fun PositionedCluster.sliceRect(start: Int, end: Int): Rect {
    if (range.length <= 0 || width <= 0f) return rect
    val l = xForOffset(start)
    val r = xForOffset(end)
    return Rect(l, top, r, bottom)
}

private fun LayoutResult.naturalAdvanceByRange(): Map<TextRange, Float> {
    val out = HashMap<TextRange, Float>()
    for (run in glyphRuns) {
        for (glyph in run.glyphs) {
            out[glyph.clusterRange] = (out[glyph.clusterRange] ?: 0f) + glyph.advance
        }
    }
    return out
}

private fun LayoutResult.rubySpreadByRange(): Map<TextRange, Float> =
    debug.geometryDecisions
        .filter { it.rubySpread != 0f }
        .associate { it.range to it.rubySpread }

private data class SelectionBounds(
    var left: Float,
    var right: Float,
)

private fun LayoutResult.withRubySelectionGeometry(
    positioned: List<PositionedCluster>,
    lineIndex: Int,
): List<PositionedCluster> {
    val rubies = debug.rubyDecisions.filter { it.lineIndex == lineIndex && it.width > 0f }
    if (rubies.isEmpty()) return positioned

    val naturalAdvanceByRange = naturalAdvanceByRange()
    val rubySpreadByRange = rubySpreadByRange()
    val bounds = positioned.map { pc ->
        val rubySpread = rubySpreadByRange[pc.range] ?: 0f
        SelectionBounds(pc.left, (pc.right - rubySpread).coerceAtLeast(pc.left))
    }
    fun centerOf(pc: PositionedCluster): Float {
        val natural = naturalAdvanceByRange[pc.range] ?: (pc.width - (rubySpreadByRange[pc.range] ?: 0f))
        return pc.drawX + natural.coerceAtLeast(0f) / 2f
    }

    for (ruby in rubies) {
        val baseIndices = positioned.indices.filter { index ->
            val range = positioned[index].range
            range.start >= ruby.baseRange.start && range.end <= ruby.baseRange.end
        }
        if (baseIndices.isEmpty()) continue

        val centers = baseIndices.map { centerOf(positioned[it]) }
        val rubyLeft = ruby.centerX - ruby.width / 2f
        val rubyRight = ruby.centerX + ruby.width / 2f
        for (i in baseIndices.indices) {
            val segmentLeft = if (i == 0) {
                rubyLeft
            } else {
                maxOf(rubyLeft, (centers[i - 1] + centers[i]) / 2f)
            }
            val segmentRight = if (i == baseIndices.lastIndex) {
                rubyRight
            } else {
                minOf(rubyRight, (centers[i] + centers[i + 1]) / 2f)
            }
            val bound = bounds[baseIndices[i]]
            bound.left = minOf(bound.left, segmentLeft)
            bound.right = maxOf(bound.right, segmentRight)
        }
    }

    for (i in 0 until bounds.lastIndex) {
        val left = bounds[i]
        val right = bounds[i + 1]
        if (left.right <= right.left) continue
        val boundary = ((centerOf(positioned[i]) + centerOf(positioned[i + 1])) / 2f)
            .coerceIn(minOf(left.left, right.left), maxOf(left.right, right.right))
        left.right = minOf(left.right, boundary).coerceAtLeast(left.left)
        right.left = maxOf(right.left, boundary).coerceAtMost(right.right)
    }

    return positioned.mapIndexed { index, pc ->
        val bound = bounds[index]
        pc.copy(left = bound.left, right = bound.right)
    }
}
