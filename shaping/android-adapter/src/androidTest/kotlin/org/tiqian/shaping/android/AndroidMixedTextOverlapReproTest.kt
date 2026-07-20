package org.tiqian.shaping.android

import android.graphics.Paint
import android.text.TextPaint
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith
import org.tiqian.core.Cluster
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.LineBox
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.core.ic
import org.tiqian.core.positionedClusters
import org.tiqian.font.CjkFontRoleClassifier
import org.tiqian.font.FontRole
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import kotlin.math.max
import kotlin.test.fail

@RunWith(AndroidJUnit4::class)
class AndroidMixedTextOverlapReproTest {
    private val typefaces = SystemAndroidTypefaceResolver()
    private val engine = ExplainableStubParagraphLayoutEngine(
        lineBreaker = LookaheadLineBreaker(),
        textShaper = AndroidPaintTextShaper(typefaceResolver = typefaces),
        fontMetricsResolver = AndroidFontMetricsResolver(typefaceResolver = typefaces),
    )

    @Test
    fun zhihuParagraphDoesNotOverlapAroundTerfism() {
        val fontSize = 48f
        val paragraph =
            "这也能解释为什么有femmephobia的女性主义者往往也并且也支持生物本质主义/恐跨/TERFism。如果她们认为女性气质【只能是】一种父权建构物，那就会进一步认为“真正的女性经验”应该被还原成某种未被污染的东西去。如果gender 必然是压迫性的社会建构，那么就必须强调“真正女性”的边界。"
        val failures = mutableListOf<String>()
        val candidateDumps = mutableListOf<String>()
        val directSlashRole = CjkFontRoleClassifier().classify(paragraph, TextRange(43, 44))
        if (directSlashRole != FontRole.LatinText) {
            fail("direct classifier at 43 expected LatinText, got $directSlashRole")
        }

        for (cells in 8..32) {
            val result = engine.layout(
                LayoutInput(
                    content = TiqianTextContent(paragraph),
                    textStyle = TextStyle(fontSize = fontSize, locale = "zh-Hans"),
                    paragraphStyle = ParagraphStyle(
                        firstLineIndent = 0.ic,
                        lineHeight = fontSize * 1.6f,
                    ),
                    constraints = LayoutConstraints(maxWidth = cells * fontSize),
                ),
            )
            result.clusters
                .filter { it.text.startsWith("/") && it.text.contains("TERF") }
                .forEach { cluster ->
                    val leadingGap = result.debug.autoSpaceDecisions.any {
                        it.clusterRange == cluster.range && it.side == "leading"
                    }
                    if (leadingGap) {
                        failures += buildString {
                            append("cells=").append(cells)
                            append(" unexpected leading autospace before slash-led Latin run ")
                            append(cluster.range)
                            append(" '").append(cluster.text).append("'")
                        }
                    }
                }
            for ((lineIndex, line) in result.lines.withIndex()) {
                val lineText = paragraph.substring(line.range.start, line.range.end)
                if (!lineText.contains("TERF") && !lineText.contains("如果")) continue
                val positioned = result.positionedDrawClusters(line)
                candidateDumps += buildString {
                    append("cells=").append(cells)
                    append(" line=").append(lineIndex)
                    append(" range=").append(line.range)
                    append(" text='").append(lineText).append("'\n")
                    append("role overrides:\n")
                    result.debug.roleOverrides
                        .filter { it.range.end > line.range.start && it.range.start < line.range.end }
                        .forEach { d ->
                            append("  ")
                            append(d.range)
                            append(" ").append(d.originalRole)
                            append(" -> ").append(d.overriddenRole)
                            append(" source=").append(d.source)
                            append('\n')
                        }
                    append("font decisions:\n")
                    result.debug.fontDecisions
                        .filter { it.range.end > line.range.start && it.range.start < line.range.end }
                        .forEach { d ->
                            append("  ")
                            append(d.range)
                            append(" role=").append(d.role)
                            append(" source='").append(d.sourceText).append("'")
                            append(" display='").append(d.displayText).append("'")
                            append(" reason=").append(d.reason)
                            append('\n')
                        }
                    append("autospace decisions:\n")
                    result.debug.autoSpaceDecisions
                        .filter { it.clusterRange.end > line.range.start && it.clusterRange.start < line.range.end }
                        .forEach { d ->
                            append("  ")
                            append(d.clusterRange)
                            append(" side=").append(d.side)
                            append(" mode=").append(d.mode)
                            append(" reason=").append(d.reason)
                            append('\n')
                        }
                    append("shaping decisions:\n")
                    result.debug.shapingDecisions
                        .filter { it.range.end > line.range.start && it.range.start < line.range.end }
                        .forEach { d ->
                            append("  ")
                            append(d.range)
                            append(" source=").append(d.source)
                            append(" glyphs=").append(d.glyphCount)
                            append(" advance=").append("%.2f".format(d.advance))
                            append(" text='").append(d.sourceText).append("'")
                            append(" display='").append(d.displayText).append("'")
                            append('\n')
                        }
                    positioned.forEach { p ->
                        append("  ")
                        append(p.cluster.range)
                        append(" '").append(p.cluster.text).append("'")
                        append(" role=").append(p.role)
                        append(" x=").append("%.2f".format(p.drawX))
                        append(" adv=").append("%.2f".format(p.cluster.advance))
                        append(" drawAdv=").append("%.2f".format(p.drawAdvance))
                        append(" right=").append("%.2f".format(p.drawRight))
                        append('\n')
                    }
                }
                positioned.zipWithNext().forEach { (left, right) ->
                    val overlap = left.drawRight - right.drawX
                    if (overlap > 1f && (
                            left.cluster.text.contains("TERF") ||
                                left.cluster.text.contains("TER") ||
                                left.cluster.text.contains("Fism")
                            )
                    ) {
                        failures += buildString {
                            append("cells=").append(cells)
                            append(" line=").append(lineIndex)
                            append(" overlap=").append("%.2f".format(overlap))
                            append(" left='").append(left.cluster.text).append("'")
                            append(" right='").append(right.cluster.text).append("'\n")
                            append("line='").append(lineText).append("'\n")
                            append("left drawRight=").append("%.2f".format(left.drawRight))
                            append(" right drawX=").append("%.2f".format(right.drawX))
                        }
                    }
                }
            }
        }

        if (failures.isNotEmpty()) {
            fail((failures + candidateDumps.take(12)).joinToString("\n\n"))
        }
    }

    private data class DrawPositionedCluster(
        val cluster: Cluster,
        val role: FontRole,
        val drawX: Float,
        val drawAdvance: Float,
    ) {
        val drawRight: Float get() = drawX + drawAdvance
    }

    private fun LayoutResult.positionedDrawClusters(line: LineBox): List<DrawPositionedCluster> =
        positionedClusters(line).map { positioned ->
            val cluster = clusters[positioned.clusterIndex]
            val role = debug.fontDecisions.firstOrNull {
                cluster.range.start >= it.range.start && cluster.range.end <= it.range.end
            }?.role.toFontRole()
            DrawPositionedCluster(
                cluster = cluster,
                role = role,
                drawX = positioned.drawX,
                drawAdvance = measureDrawAdvance(cluster.displayText, role, input.textStyle),
            )
        }

    private fun String?.toFontRole(): FontRole =
        runCatching { if (this == null) null else FontRole.valueOf(this) }.getOrNull() ?: FontRole.CjkText

    private fun measureDrawAdvance(text: String, role: FontRole, style: TextStyle): Float {
        if (text.isEmpty()) return 0f
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = style.fontSize
            textLocale = java.util.Locale.forLanguageTag(style.locale)
            typeface = typefaces.resolve(role, style.fontFamilies, style.fontWeight, style.italic)
        }
        return if (role == FontRole.CjkText || role == FontRole.CjkPunctuation) {
            val buffer = "中${text}中"
            val start = 1
            val end = 1 + text.length
            max(
                0f,
                paint.getRunAdvance(buffer, 0, buffer.length, 0, buffer.length, false, end) -
                    paint.getRunAdvance(buffer, 0, buffer.length, 0, buffer.length, false, start),
            )
        } else {
            paint.getRunAdvance(text, 0, text.length, 0, text.length, false, text.length)
        }
    }
}
