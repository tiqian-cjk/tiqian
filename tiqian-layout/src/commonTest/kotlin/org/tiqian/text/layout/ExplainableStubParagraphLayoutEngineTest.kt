package org.tiqian.text.layout

import org.tiqian.text.clreq.CjkPunctuationGlyphPolicy
import org.tiqian.text.clreq.ClreqProfile
import org.tiqian.text.clreq.ClreqProfileResolver
import org.tiqian.text.core.Cluster
import org.tiqian.text.core.Glyph
import org.tiqian.text.core.GlyphRun
import org.tiqian.text.core.LayoutConstraints
import org.tiqian.text.core.LayoutInput
import org.tiqian.text.core.Rect
import org.tiqian.text.core.TiqianTextContent
import org.tiqian.text.font.FontRole
import org.tiqian.text.shaping.ShapingInput
import org.tiqian.text.shaping.ShapingResult
import org.tiqian.text.shaping.TextShaper
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class ExplainableStubParagraphLayoutEngineTest {
    @Test
    fun returnsDebuggableSingleLineResult() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("提椠"),
                constraints = LayoutConstraints(maxWidth = 240f),
            ),
        )

        assertEquals(2, result.clusters.size)
        assertEquals(1, result.lines.size)
        assertEquals("greedy", result.debug.lineDecisions.single().kind)
    }

    @Test
    fun recordsInjectedLineBreakerStrategyInDebugDecisions() {
        val result = ExplainableStubParagraphLayoutEngine(
            lineBreaker = LookaheadLineBreaker(),
        ).layout(
            LayoutInput(
                content = TiqianTextContent("提椠"),
                constraints = LayoutConstraints(maxWidth = 240f),
            ),
        )

        assertEquals("lookahead", result.debug.lineDecisions.single().kind)
    }

    @Test
    fun rejectsShaperClustersThatDoNotCoverFontDecisionRange() {
        val engine = ExplainableStubParagraphLayoutEngine(
            textShaper = object : TextShaper {
                override fun shape(input: ShapingInput): ShapingResult =
                    ShapingResult(clusters = emptyList(), glyphRuns = emptyList())
            },
        )

        assertFailsWith<IllegalArgumentException> {
            engine.layout(
                LayoutInput(
                    content = TiqianTextContent("提椠"),
                    constraints = LayoutConstraints(maxWidth = 240f),
                ),
            )
        }
    }

    @Test
    fun preservesShaperGlyphBoundsInLayoutGlyphRuns() {
        val shapedBounds = Rect(left = 1f, top = -10f, right = 12f, bottom = 2f)
        val engine = ExplainableStubParagraphLayoutEngine(
            textShaper = object : TextShaper {
                override fun shape(input: ShapingInput): ShapingResult =
                    ShapingResult(
                        clusters = listOf(
                            Cluster(
                                range = input.range,
                                text = input.text.substring(input.range.start, input.range.end),
                                displayText = input.displayText,
                                fontKey = input.fontDecision.candidate.key,
                                advance = 20f,
                            ),
                        ),
                        glyphRuns = listOf(
                            GlyphRun(
                                range = input.range,
                                fontKey = input.fontDecision.candidate.key,
                                glyphs = listOf(
                                    Glyph(
                                        id = 42u,
                                        clusterRange = input.range,
                                        advance = 20f,
                                        bounds = shapedBounds,
                                    ),
                                ),
                                advance = 20f,
                            ),
                        ),
                    )
            },
        )

        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("A"),
                constraints = LayoutConstraints(maxWidth = 240f),
            ),
        )

        val glyph = result.glyphRuns.single().glyphs.single()
        assertEquals(42u, glyph.id)
        assertEquals(shapedBounds, glyph.bounds)
        assertEquals(20f, glyph.advance)
    }

    @Test
    fun recordsFallbackDecisionsPerCluster() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("提椠……English——世界。"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        assertTrue(
            result.debug.fontDecisions.any {
                it.sourceText == "……" &&
                    it.displayText == "⋯⋯" &&
                    it.role == FontRole.CjkPunctuation.name &&
                    it.fontKey == "cjk-primary"
            },
        )
        assertTrue(
            result.debug.fontDecisions.any {
                it.sourceText == "——" &&
                    it.displayText == "⸺" &&
                    it.role == FontRole.CjkPunctuation.name &&
                    it.fontKey == "cjk-primary"
            },
        )
        assertTrue(
            result.debug.shapingDecisions.any {
                it.sourceText == "——" &&
                    it.displayText == "⸺" &&
                    it.advance == 32f &&
                    it.source == "Stub"
            },
        )
        assertTrue(
            result.debug.fontDecisions.any {
                it.sourceText == "English" &&
                    it.role == FontRole.LatinText.name &&
                    it.fontKey == "latin-primary"
            },
        )
        assertEquals("English", result.clusters.first { it.text == "English" }.text)
    }

    @Test
    fun preservesSourceTextWhenUsingClreqRecommendedDisplayGlyphs() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("……——・／"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val ellipsis = result.clusters.first { it.text == "……" }
        val dash = result.clusters.first { it.text == "——" }
        val interpunct = result.clusters.first { it.text == "・" }
        val solidus = result.clusters.first { it.text == "／" }

        assertEquals("……", ellipsis.text)
        assertEquals("⋯⋯", ellipsis.displayText)
        assertEquals("——", dash.text)
        assertEquals("⸺", dash.displayText)
        assertEquals("・", interpunct.text)
        assertEquals("·", interpunct.displayText)
        assertEquals("／", solidus.text)
        assertEquals("／", solidus.displayText)
        assertEquals("cjk-primary", ellipsis.fontKey)
        assertEquals("cjk-primary", dash.fontKey)
        assertEquals("cjk-primary", interpunct.fontKey)
        assertEquals("cjk-primary", solidus.fontKey)
    }

    @Test
    fun honorsProfilePunctuationGlyphPolicy() {
        val engine = ExplainableStubParagraphLayoutEngine(
            clreqProfileResolver = ClreqProfileResolver {
                ClreqProfile.MainlandHorizontal.copy(
                    punctuationGlyphPolicy = CjkPunctuationGlyphPolicy.PreserveInput,
                )
            },
        )

        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("……——"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        assertEquals("……", result.clusters.first { it.text == "……" }.displayText)
        assertEquals("——", result.clusters.first { it.text == "——" }.displayText)
    }

    @Test
    fun coalesceSetIsDrivenByProfile() {
        // Profile with empty coalesce set should split "——" into two clusters of "—"
        val engine = ExplainableStubParagraphLayoutEngine(
            clreqProfileResolver = ClreqProfileResolver {
                ClreqProfile.MainlandHorizontal.copy(
                    punctuationGlyphPolicy = CjkPunctuationGlyphPolicy.PreserveInput,
                    coalesceRepeatablePunctuation = emptySet(),
                )
            },
        )

        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("——"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        assertEquals(2, result.clusters.size)
        assertEquals("—", result.clusters[0].text)
        assertEquals("—", result.clusters[1].text)
    }

    @Test
    fun usesTwoEmAdvanceForRecommendedDashCodepoint() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("⸺"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        assertEquals(32f, result.clusters.single().advance)
        assertEquals(32f, result.size.width)
    }

    @Test
    fun keepsLatinTechnicalPunctuationInLatinRun() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("well-known/path"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        assertEquals("well-known/path", result.clusters.single().text)
        assertEquals("latin-primary", result.clusters.single().fontKey)
    }

    @Test
    fun autoSpaceReplacesTypedSpaceAtCjkLatinBoundary() {
        // " CJK " becomes one Latin cluster (5 chars * 16 = 80px nominal).
        // At maxWidth large enough, default AutoSpacePolicy.Replace shrinks
        // each boundary space from 1em (16) to 0.25em (4), saving 24px total.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文 CJK 段落"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val cjkSpaced = result.clusters.single { it.text == " CJK " }
        // 5 chars * 16 nominal = 80; minus 2 boundary-space replacements of
        // (16 - 4) = 12 each → 80 - 24 = 56.
        assertEquals(56f, cjkSpaced.advance)
        assertEquals(2, result.debug.autoSpaceDecisions.size)
        assertTrue(
            result.debug.autoSpaceDecisions.all {
                it.mode == "Replace" && it.charactersAffected == 1 && it.reductionPerChar == 12f
            },
        )
    }

    @Test
    fun autoSpaceDoesNotShrinkSpacesBetweenLatinWords() {
        // "Hello world" — space between two Latin words, no CJK boundary.
        // AutoSpace.Replace only applies at CJK boundaries; word-internal
        // spaces stay at their nominal 1em.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("Hello world"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val latin = result.clusters.single()
        assertEquals("Hello world", latin.text)
        assertEquals(176f, latin.advance) // 11 chars * 16 = 176, no reduction
        assertEquals(0, result.debug.autoSpaceDecisions.size)
    }

    @Test
    fun autoSpaceDisabledKeepsTypedSpacesAtOneEm() {
        val engine = ExplainableStubParagraphLayoutEngine(
            clreqProfileResolver = ClreqProfileResolver {
                ClreqProfile.MainlandHorizontal.copy(
                    autoSpace = org.tiqian.text.clreq.AutoSpacePolicy.Disabled,
                )
            },
        )

        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中文 CJK 段落"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val cjkSpaced = result.clusters.single { it.text == " CJK " }
        // No shrink: 5 chars * 16 = 80.
        assertEquals(80f, cjkSpaced.advance)
        assertEquals(0, result.debug.autoSpaceDecisions.size)
    }

    @Test
    fun classifiesAsciiBracketsAsLatinRegardlessOfSurroundingContext() {
        // ASCII parens/brackets do NOT share a code point with CJK fullwidth
        // forms (（）「」 etc), so they are always Latin by typed intent.
        // (English) joins the surrounding Latin run and renders in latin font;
        // the CJK text on either side is unaffected.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文(English)中文"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val latinCluster = result.clusters.single { it.text == "(English)" }
        assertEquals("latin-primary", latinCluster.fontKey)
        assertEquals(
            "LatinText",
            result.debug.fontDecisions.single { it.sourceText == "(English)" }.role,
        )
    }

    @Test
    fun classifiesAsciiBracketsAsLatinInsidePureCjkContent() {
        // Even with CJK on both sides AND inside, ASCII brackets stay Latin —
        // the author chose ASCII; if they wanted fullwidth they would type
        // U+FF08/FF09 (which is already CjkPunctuation by code point).
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文(中文)"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val openParen = result.clusters.single { it.text == "(" }
        val closeParen = result.clusters.single { it.text == ")" }
        assertEquals("latin-primary", openParen.fontKey)
        assertEquals("latin-primary", closeParen.fontKey)
    }

    @Test
    fun keepsTextStartLatinQuotePairInLatinRun() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("“Hello” world"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        // With U+0020 now classified as Latin (ADR 0009 autospace model), the
        // entire `"Hello" world` aggregates into a single Latin cluster.
        val quoted = result.clusters.single()
        assertEquals("“Hello” world", quoted.text)
        assertEquals("latin-primary", quoted.fontKey)
        assertTrue(
            result.debug.fontDecisions.any {
                it.sourceText == "“Hello” world" && it.role == FontRole.LatinText.name
            },
        )
    }

    @Test
    fun skipsNeutralDashBeforeLatinQuotePairInLayout() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("English — “hello”"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        // With autospace, the trailing space before — joins "English", and
        // the leading space after — joins " “hello”". The em-dash sits between
        // these two Latin clusters as a CJK punctuation cluster of its own.
        val quoted = result.clusters.first { it.text.contains("“hello”") }
        assertEquals("latin-primary", quoted.fontKey)
    }

    @Test
    fun recordsRoleOverridesForResolvedQuotePairs() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("“Hello” world"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        // QuotePair resolves both quotes to LatinText. Without the override the
        // standalone classifier would label "“" at position 0 as CjkPunctuation
        // (text boundary, no Latin context).
        val openQuoteOverride = result.debug.roleOverrides.firstOrNull { it.range.start == 0 }
        val closeQuoteOverride = result.debug.roleOverrides.firstOrNull { it.range.start == 6 }
        assertEquals("LatinText", openQuoteOverride?.overriddenRole)
        assertEquals("CjkPunctuation", openQuoteOverride?.originalRole)
        assertEquals("QuotePairAwareLatinContext", openQuoteOverride?.source)
        assertEquals("LatinText", closeQuoteOverride?.overriddenRole)
    }

    @Test
    fun buildsTwoEmPunctuationAtomForRecommendedDashCodepoint() {
        val atom = PunctuationAtomBuilder().build("⸺", index = 0, em = 16f)

        requireNotNull(atom)
        assertEquals(32f, atom.advance)
        assertEquals(32f, atom.bodyWidth)
    }

    @Test
    fun inkBoundsAreDiagnosticOnlyAndDoNotAffectGlue() {
        val atom = PunctuationAtomBuilder().build(
            char = '，',
            range = org.tiqian.text.core.TextRange(0, 1),
            em = 16f,
            inkInput = PunctuationInkInput(
                advance = 16f,
                inkBounds = Rect(left = 9f, top = -2f, right = 11f, bottom = 2f),
            ),
        )

        requireNotNull(atom)
        assertEquals(16f, atom.advance)
        assertEquals(8f, atom.bodyWidth)
        // PauseOrStop: all glue on trailing side (class-derived, not ink-derived)
        assertEquals(0f, atom.leadingGlue.natural)
        assertEquals(8f, atom.trailingGlue.natural)
        assertEquals("ClassDerivedWithInkDiagnostics", atom.geometrySource)
        // Ink fields are retained as diagnostics
        assertEquals(2f, atom.inkWidth)
        assertEquals(10f, atom.inkCenter)
    }

    @Test
    fun recordsInkCalibratedPunctuationGeometryInLayoutDebug() {
        val inkBounds = Rect(left = 9f, top = -2f, right = 11f, bottom = 2f)
        val engine = ExplainableStubParagraphLayoutEngine(
            textShaper = object : TextShaper {
                override fun shape(input: ShapingInput): ShapingResult =
                    ShapingResult(
                        clusters = listOf(
                            Cluster(
                                range = input.range,
                                text = input.text.substring(input.range.start, input.range.end),
                                displayText = input.displayText,
                                fontKey = input.fontDecision.candidate.key,
                                advance = 16f,
                            ),
                        ),
                        glyphRuns = listOf(
                            GlyphRun(
                                range = input.range,
                                fontKey = input.fontDecision.candidate.key,
                                glyphs = listOf(
                                    Glyph(
                                        id = 7u,
                                        clusterRange = input.range,
                                        advance = 16f,
                                        bounds = inkBounds,
                                    ),
                                ),
                                advance = 16f,
                            ),
                        ),
                    )
            },
        )

        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("。"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val punctuation = result.debug.punctuationDecisions.single()
        assertEquals(inkBounds, punctuation.inkBounds)
        assertEquals(8f, punctuation.bodyWidth)
        // 。 is PauseOrStop: all glue on trailing side
        assertEquals(0f, punctuation.leadingGlueNatural)
        assertEquals(8f, punctuation.trailingGlueNatural)
        assertEquals("ClassDerivedWithInkDiagnostics", punctuation.geometrySource)

        val geometry = result.debug.geometryDecisions.single()
        assertEquals("ClassDerivedWithInkDiagnostics", geometry.reason)
        assertEquals(8f, geometry.bodyWidth)
        assertEquals(0f, geometry.leadingGlueNatural)
        assertEquals(8f, geometry.trailingGlueNatural)
    }

    @Test
    fun recordsPunctuationAtomsInLayoutDebug() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("你好，世界。——"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val comma = result.debug.punctuationDecisions.single { it.char == '，' }
        assertEquals(2, comma.range.start)
        assertEquals(3, comma.range.end)
        assertEquals("PauseOrStop", comma.punctuationClass)
        assertEquals(16f, comma.advance)
        assertEquals(8f, comma.bodyWidth)
        // PauseOrStop: all glue on trailing side
        assertEquals(0f, comma.leadingGlueNatural)
        assertEquals(8f, comma.trailingGlueNatural)
        assertEquals("Leading", comma.anchor)

        val stop = result.debug.punctuationDecisions.single { it.char == '。' }
        assertEquals(5, stop.range.start)
        assertEquals(6, stop.range.end)

        val dash = result.debug.punctuationDecisions.single { it.char == '⸺' }
        assertEquals(6, dash.range.start)
        assertEquals(8, dash.range.end)
        assertEquals("Dash", dash.punctuationClass)
        assertEquals(32f, dash.advance)

        assertEquals(3, result.debug.punctuationDecisions.size)
    }

    @Test
    fun traditionalProfileCentresPauseStopGlueOnBothSides() {
        // Per CLREQ 3.1.3, Traditional Chinese places 。 ， at the centre of
        // the em box, so 。's glue is split symmetrically: 4 leading + 4
        // trailing, anchor = Center. This is the regional behaviour the
        // hardcoded Mainland-style assumption used to miss.
        val engine = ExplainableStubParagraphLayoutEngine(
            clreqProfileResolver = ClreqProfileResolver { ClreqProfile.TaiwanHorizontal },
        )

        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("你好。"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val stop = result.debug.punctuationDecisions.single { it.char == '。' }
        assertEquals("PauseOrStop", stop.punctuationClass)
        assertEquals(8f, stop.bodyWidth)
        assertEquals(4f, stop.leadingGlueNatural)
        assertEquals(4f, stop.trailingGlueNatural)
        assertEquals("Center", stop.anchor)
    }

    @Test
    fun appliesAdjacentPunctuationCompressionToDrawableGeometry() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("你好，。"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val line = result.lines.single()
        val stop = result.clusters.first { it.text == "。" }

        // Class-based glue: ， trailing=8, 。 trailing=8.
        // Spacing compression: inner glue = ，.trailing(8) + 。.leading(0) = 8
        //   → adjusted=4, reduction=4, target=，(has trailing glue).
        // Line-end trim: 。 trailing(8) fully consumed → 。 advance = 8.
        // ，: 16 - 4(spacing) = 12. 。: 16 - 8(edge trim) = 8.
        // Total: 16 + 16 + 12 + 8 = 52.
        assertEquals(64f, line.naturalWidth)
        assertEquals(52f, line.adjustedWidth)
        assertEquals(52f, line.visualWidth)
        assertEquals(52f, result.size.width)
        assertEquals(8f, stop.advance)
        assertEquals(52f, result.clusters.sumOf { it.advance.toDouble() }.toFloat())
        assertEquals(52f, result.glyphRuns.sumOf { it.advance.toDouble() }.toFloat())
        assertEquals(4f, result.debug.spacingDecisions.sumOf { it.reduction.toDouble() }.toFloat())
        val edgeTrim = result.debug.lineEdgeTrimDecisions.single()
        assertEquals("trailing", edgeTrim.side)
        assertEquals("LineEndHalfWidthPunctuation", edgeTrim.reason)
        assertEquals(8f, edgeTrim.trimAmount)
        assertEquals(3, edgeTrim.clusterRange.start)
        assertEquals(4, edgeTrim.clusterRange.end)

        val stopGeometry = result.debug.geometryDecisions.single { it.sourceText == "。" }
        assertEquals("PunctuationGeometryLedger", stopGeometry.source)
        assertEquals("ClassDerivedWithShapedAdvance", stopGeometry.reason)
        assertEquals(16f, stopGeometry.baseAdvance)
        assertEquals(8f, stopGeometry.bodyWidth)
        // PauseOrStop: all glue on trailing side, fully consumed by edge trim
        assertEquals(0f, stopGeometry.leadingGlueNatural)
        assertEquals(0f, stopGeometry.leadingGlueConsumed)
        assertEquals(8f, stopGeometry.trailingGlueNatural)
        assertEquals(8f, stopGeometry.trailingGlueConsumed)
        assertEquals(0f, stopGeometry.justificationDelta)
        assertEquals(8f, stopGeometry.resolvedAdvance)

        val spacing = result.debug.spacingDecisions.single()
        assertEquals(2, spacing.range.start)
        assertEquals(4, spacing.range.end)
        assertEquals('，', spacing.leftChar)
        assertEquals('。', spacing.rightChar)
        assertEquals(8f, spacing.naturalInnerGlue)
        assertEquals(4f, spacing.adjustedInnerGlue)
        assertEquals(4f, spacing.reduction)
        // Reduction targets ， (which has the trailing glue)
        assertEquals(2, spacing.reductionTargetRange.start)
        assertEquals(3, spacing.reductionTargetRange.end)
        assertEquals("collapse-adjacent-punctuation-inner-glue", spacing.reason)
    }

    @Test
    fun greedyBreakerProducesMultipleLinesWhenWidthOverflows() {
        // 8 CJK clusters * 16f = 128f natural; maxWidth=64f -> 4 clusters per line -> 2 lines.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文排版引擎测试"),
                constraints = LayoutConstraints(maxWidth = 64f),
            ),
        )

        assertEquals(2, result.lines.size)
        assertEquals(8, result.clusters.size)

        val first = result.lines[0]
        val second = result.lines[1]
        assertEquals(0, first.range.start)
        assertEquals(4, first.range.end)
        assertEquals(64f, first.adjustedWidth)
        assertEquals(0f, first.top)
        assertEquals(16f, first.bottom)

        assertEquals(4, second.range.start)
        assertEquals(8, second.range.end)
        assertEquals(64f, second.adjustedWidth)
        assertEquals(16f, second.top)
        assertEquals(32f, second.bottom)

        assertEquals(2, result.debug.lineDecisions.size)
        assertTrue(result.debug.lineDecisions.all { it.kind == "greedy" })
        assertEquals(32f, result.size.height)
    }

    @Test
    fun greedyBreakerKeepsLatinRunAsSingleClusterEvenWhenLineOverflows() {
        // "中" (16f) + "English" cluster (7*16=112f) > maxWidth=80f.
        // First line should be "中" alone (16f), "English" goes to line 2 (overflows but
        // can't be split further at cluster level in this slice).
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中English"),
                constraints = LayoutConstraints(maxWidth = 80f),
            ),
        )

        assertEquals(2, result.lines.size)
        assertEquals("中", result.clusters[result.lines[0].range.start.coerceAtMost(0)].text)
        assertEquals("English", result.clusters.first { it.text == "English" }.text)
    }

    @Test
    fun kinsokuCarriesPreviousClusterWhenLineWouldStartWithForbiddenPunctuation() {
        // Pure greedy at maxWidth=64 -> line 0: 中文中文 (clusters 0..3), line 1: 。
        // 。 is PauseOrStop, forbidden at line start, so CarryPrevious pulls
        // 文 (cluster 3) to line 1: line 0 = 中文中, line 1 = 文。.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文中文。"),
                constraints = LayoutConstraints(maxWidth = 64f),
            ),
        )

        assertEquals(2, result.lines.size)
        assertEquals(0, result.lines[0].range.start)
        assertEquals(3, result.lines[0].range.end)
        assertEquals(3, result.lines[1].range.start)
        assertEquals(5, result.lines[1].range.end)
        assertEquals(48f, result.lines[0].adjustedWidth)
        // Line 1 ends with 。 → LineEndGlueTrim takes full trailing=8.
        // 文(16) + 。(16-8) = 24.
        assertEquals(24f, result.lines[1].adjustedWidth)

        assertEquals(null, result.debug.lineDecisions[0].repair)
        assertEquals("CarryPrevious", result.debug.lineDecisions[1].repair)
        assertEquals(10, result.debug.lineDecisions[1].repairPenalty)
        val repairDecision = result.debug.lineDecisions[1].repairDecision
        assertEquals("CarryPrevious", repairDecision?.kind)
        assertEquals("ForbiddenAtLineStart", repairDecision?.reasonCode)
        assertEquals(4, repairDecision?.offenderRange?.start)
        assertEquals(5, repairDecision?.offenderRange?.end)
        assertEquals(3, repairDecision?.carriedClusterIndex)
        val repairCandidates = result.debug.lineDecisions[1].repairCandidates
        assertEquals(2, repairCandidates.size)
        assertEquals("PushIn", repairCandidates[0].kind)
        assertEquals(false, repairCandidates[0].accepted)
        assertEquals("insufficient-capacity", repairCandidates[0].rejectionReason)
        assertEquals("CarryPrevious", repairCandidates[1].kind)
        assertEquals(true, repairCandidates[1].accepted)
        assertTrue(
            result.debug.lineDecisions[1].notes.any {
                it.contains("ForbiddenAtLineStart:。") && it.contains("carried=文")
            },
        )
    }

    @Test
    fun kinsokuPushesLineStartPunctuationIntoPreviousLineWhenTrailingGlueCanShrink() {
        // Pure greedy at maxWidth=60 -> line 0: 中文中 (48f), line 1: 。
        // 。 can be pushed into previous line by shrinking its trailing glue.
        // PushIn shrinks 4f (overflow), then edge trim takes remaining 4f.
        // 。 trailing=8, PushIn uses 4, edge trim uses 4 → 。 advance=8.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文中。"),
                constraints = LayoutConstraints(maxWidth = 60f),
            ),
        )

        assertEquals(1, result.lines.size)
        val line = result.lines.single()
        assertEquals(0, line.range.start)
        assertEquals(4, line.range.end)
        assertEquals(64f, line.naturalWidth)
        // PushIn shrinks 4, edge trim shrinks 4 more → 64 - 8 = 56.
        assertEquals(56f, line.adjustedWidth)
        assertEquals(56f, line.visualWidth)
        assertEquals(56f, result.clusters.sumOf { it.advance.toDouble() }.toFloat())
        assertEquals(56f, result.glyphRuns.sumOf { it.advance.toDouble() }.toFloat())

        val stop = result.clusters.single { it.text == "。" }
        assertEquals(8f, stop.advance)
        val stopGeometry = result.debug.geometryDecisions.single { it.sourceText == "。" }
        assertEquals(8f, stopGeometry.trailingGlueConsumed)
        assertEquals(8f, stopGeometry.resolvedAdvance)
        assertEquals(1, result.debug.lineEdgeTrimDecisions.size)
        assertEquals("PushIn", result.debug.lineDecisions.single().repair)
        assertEquals(2, result.debug.lineDecisions.single().repairPenalty)
        val repairDecision = result.debug.lineDecisions.single().repairDecision
        assertEquals("PushIn", repairDecision?.kind)
        assertEquals("ForbiddenAtLineStart", repairDecision?.reasonCode)
        assertEquals(3, repairDecision?.offenderRange?.start)
        assertEquals(4, repairDecision?.offenderRange?.end)
        assertEquals(3, repairDecision?.targetClusterIndex)
        assertEquals(4f, repairDecision?.shrink)
        assertEquals(8f, repairDecision?.availableCapacity)
        val repairCandidates = result.debug.lineDecisions.single().repairCandidates
        assertEquals(1, repairCandidates.size)
        assertEquals("PushIn", repairCandidates.single().kind)
        assertEquals(true, repairCandidates.single().accepted)
        assertEquals(4f, repairCandidates.single().requiredShrink)
        assertEquals(8f, repairCandidates.single().availableCapacity)
        assertTrue(
            result.debug.lineDecisions.single().notes.any {
                it.contains("ForbiddenAtLineStart:。") && it.contains("pushed-in=4.0")
            },
        )
    }

    @Test
    fun kinsokuLeavesGreedyBreakAloneWhenNoForbiddenPunctAtLineStart() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文中文哈哈"),
                constraints = LayoutConstraints(maxWidth = 64f),
            ),
        )

        assertEquals(2, result.lines.size)
        assertEquals(0, result.lines[0].range.start)
        assertEquals(4, result.lines[0].range.end)
        assertEquals(4, result.lines[1].range.start)
        assertEquals(6, result.lines[1].range.end)
        assertEquals(null, result.debug.lineDecisions[0].repair)
        assertEquals(null, result.debug.lineDecisions[1].repair)
    }

    @Test
    fun kinsokuFallsBackToLeaveRaggedWhenPreviousLineCannotSpareACluster() {
        // English is one cluster (7 chars, 112f). At maxWidth=96, greedy keeps it on
        // line 0 alone (i > lineStart guard) and pushes 。 to line 1. Previous line
        // has only one cluster, so CarryPrevious cannot apply -> LeaveRagged.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("English。"),
                constraints = LayoutConstraints(maxWidth = 96f),
            ),
        )

        assertEquals(2, result.lines.size)
        assertEquals("English", result.clusters.first { it.text == "English" }.text)
        assertEquals("LeaveRagged", result.debug.lineDecisions[1].repair)
        assertEquals(20, result.debug.lineDecisions[1].repairPenalty)
        assertTrue(
            result.debug.lineDecisions[1].notes.any {
                it.contains("ForbiddenAtLineStart:。") && it.contains("no-room-to-carry")
            },
        )
    }

    @Test
    fun usesNormalizedIdeographicMetricsForCjkLineBox() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("提椠"),
                constraints = LayoutConstraints(maxWidth = 240f),
            ),
        )

        val line = result.lines.single()
        assertEquals(8f, line.baseline)
        assertEquals(16f, line.bottom)
        val cjk = result.debug.metricDecisions.first { it.role == "CjkText" }
        assertEquals(18.4f, cjk.rawAscent)
        assertEquals(8f, cjk.layoutAscent)
        assertEquals(8f, cjk.layoutDescent)
        assertEquals("IdeographicCentered", cjk.baselineClass)
        assertEquals("IdeographicEmBox", cjk.metricBox)
    }

    @Test
    fun stubShaperProducesClassDerivedWithShapedAdvance() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文，世界。"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val punctuationDecisions = result.debug.punctuationDecisions
        assertTrue(punctuationDecisions.isNotEmpty())
        for (p in punctuationDecisions) {
            assertEquals(
                "ClassDerivedWithShapedAdvance",
                p.geometrySource,
                "Stub shaper provides advance but no bounds for '${p.char}'",
            )
            // PauseOrStop: all glue on trailing side
            assertEquals(0f, p.leadingGlueNatural, "leading glue for '${p.char}'")
            assertEquals(8f, p.trailingGlueNatural, "trailing glue for '${p.char}'")
        }
    }

    @Test
    fun shapingWithoutBoundsProducesClassDerivedWithShapedAdvance() {
        val engine = ExplainableStubParagraphLayoutEngine(
            textShaper = object : TextShaper {
                override fun shape(input: ShapingInput): ShapingResult =
                    ShapingResult(
                        clusters = listOf(
                            Cluster(
                                range = input.range,
                                text = input.text.substring(input.range.start, input.range.end),
                                displayText = input.displayText,
                                fontKey = input.fontDecision.candidate.key,
                                advance = 16f,
                            ),
                        ),
                        glyphRuns = listOf(
                            GlyphRun(
                                range = input.range,
                                fontKey = input.fontDecision.candidate.key,
                                glyphs = listOf(
                                    Glyph(
                                        id = 0u,
                                        clusterRange = input.range,
                                        advance = 16f,
                                        bounds = null,
                                    ),
                                ),
                                advance = 16f,
                            ),
                        ),
                    )
            },
        )

        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("。"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val punctuation = result.debug.punctuationDecisions.single()
        assertEquals("ClassDerivedWithShapedAdvance", punctuation.geometrySource)
        assertEquals(8f, punctuation.bodyWidth)
        // PauseOrStop: all glue on trailing side (class-based, not ink-based)
        assertEquals(0f, punctuation.leadingGlueNatural)
        assertEquals(8f, punctuation.trailingGlueNatural)
    }
}
