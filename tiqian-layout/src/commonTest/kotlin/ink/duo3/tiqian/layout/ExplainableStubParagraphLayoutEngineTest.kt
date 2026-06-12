package ink.duo3.tiqian.layout

import ink.duo3.tiqian.clreq.CjkPunctuationGlyphPolicy
import ink.duo3.tiqian.clreq.ClreqProfile
import ink.duo3.tiqian.clreq.ClreqProfileResolver
import ink.duo3.tiqian.core.Cluster
import ink.duo3.tiqian.core.Glyph
import ink.duo3.tiqian.core.GlyphRun
import ink.duo3.tiqian.core.LayoutConstraints
import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.Rect
import ink.duo3.tiqian.core.TiqianTextContent
import ink.duo3.tiqian.font.FontRole
import ink.duo3.tiqian.shaping.ExplainableStubTextShaper
import ink.duo3.tiqian.shaping.ShapingInput
import ink.duo3.tiqian.shaping.ShapingResult
import ink.duo3.tiqian.shaping.TextShaper
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class ExplainableStubParagraphLayoutEngineTest {
    @Test
    fun returnsDebuggableSingleLineResult() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                    paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("中文 CJK 段落"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        // LatinWordSegmentation: [ ][CJK][ ] — each CJK-adjacent space
        // cluster IS the gap and normalises from 1em to 0.25em.
        val spaces = result.clusters.filter { it.text == " " }
        assertEquals(2, spaces.size)
        assertTrue(spaces.all { it.advance == 4f })
        assertEquals(2, result.debug.autoSpaceDecisions.size)
        assertTrue(
            result.debug.autoSpaceDecisions.all {
                it.mode == "Replace" && it.side == "gap" && it.totalReduction == 12f
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("Hello world"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        // LatinWordSegmentation: [Hello][ ][world]. The space between two
        // Latin words is a WORD SPACE — untouched by autospace, stretchable
        // by justification.
        assertEquals(3, result.clusters.size)
        val wordSpace = result.clusters.single { it.text == " " }
        assertEquals(16f, wordSpace.advance)
        assertEquals(0, result.debug.autoSpaceDecisions.size)
    }

    @Test
    fun autoSpaceDisabledKeepsTypedSpacesAtOneEm() {
        val engine = ExplainableStubParagraphLayoutEngine(
            clreqProfileResolver = ClreqProfileResolver {
                ClreqProfile.MainlandHorizontal.copy(
                    autoSpace = ink.duo3.tiqian.clreq.AutoSpacePolicy.Disabled,
                )
            },
        )

        val result = engine.layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("中文 CJK 段落"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        // Disabled: space clusters keep their nominal 1em.
        val spaces = result.clusters.filter { it.text == " " }
        assertEquals(2, spaces.size)
        assertTrue(spaces.all { it.advance == 16f })
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("“Hello” world"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        // With U+0020 classified as Latin (ADR 0009) the run is one font
        // decision; LatinWordSegmentation then splits it into word/space
        // clusters, all still latin-primary.
        assertEquals(3, result.clusters.size)
        val quoted = result.clusters.first()
        assertEquals("“Hello”", quoted.text)
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
            range = ink.duo3.tiqian.core.TextRange(0, 1),
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
        assertEquals("ProfileDerivedWithInkDiagnostics", atom.geometrySource)
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
        assertEquals("ProfileDerivedWithInkDiagnostics", punctuation.geometrySource)

        val geometry = result.debug.geometryDecisions.single()
        assertEquals("ProfileDerivedWithInkDiagnostics", geometry.reason)
        assertEquals(8f, geometry.bodyWidth)
        assertEquals(0f, geometry.leadingGlueNatural)
        assertEquals(8f, geometry.trailingGlueNatural)
    }

    @Test
    fun recordsPunctuationAtomsInLayoutDebug() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
        // 」。 is a Closing+PauseOrStop pair — a standard CLREQ collapse.
        // (，。 was used here before, but consecutive PauseOrStop pairs are
        // now exempt from compression per ConsecutivePauseOrStopKeepsFullWidth.)
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("你好」。"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val line = result.lines.single()
        val stop = result.clusters.first { it.text == "。" }

        // Class-based glue: 」 trailing=8, 。 trailing=8.
        // Spacing compression: inner glue = 」.trailing(8) + 。.leading(0) = 8
        //   → adjusted = max(0, 8 - 0.5em) = 0 (CLREQ: closing+pause-stop bodies touch),
        //   reduction=8, target=」(has trailing glue).
        // Line-end trim: 。 trailing(8) fully consumed → 。 advance = 8.
        // 」: 16 - 8(spacing) = 8 (body only). 。: 16 - 8(edge trim) = 8.
        // Total: 16 + 16 + 8 + 8 = 48.
        assertEquals(64f, line.naturalWidth)
        assertEquals(48f, line.adjustedWidth)
        assertEquals(48f, line.visualWidth)
        assertEquals(48f, result.size.width)
        assertEquals(8f, stop.advance)
        assertEquals(48f, result.clusters.sumOf { it.advance.toDouble() }.toFloat())
        assertEquals(48f, result.glyphRuns.sumOf { it.advance.toDouble() }.toFloat())
        assertEquals(8f, result.debug.spacingDecisions.sumOf { it.reduction.toDouble() }.toFloat())
        val edgeTrim = result.debug.lineEdgeTrimDecisions.single()
        assertEquals("trailing", edgeTrim.side)
        assertEquals("LineEndHalfWidthPunctuation", edgeTrim.reason)
        assertEquals(8f, edgeTrim.trimAmount)
        assertEquals(3, edgeTrim.clusterRange.start)
        assertEquals(4, edgeTrim.clusterRange.end)

        val stopGeometry = result.debug.geometryDecisions.single { it.sourceText == "。" }
        assertEquals("PunctuationGeometryLedger", stopGeometry.source)
        assertEquals("ProfileDerivedWithShapedAdvance", stopGeometry.reason)
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
        assertEquals('」', spacing.leftChar)
        assertEquals('。', spacing.rightChar)
        assertEquals(8f, spacing.naturalInnerGlue)
        assertEquals(0f, spacing.adjustedInnerGlue)
        assertEquals(8f, spacing.reduction)
        // Reduction targets 」 (which has the trailing glue)
        assertEquals(2, spacing.reductionTargetRange.start)
        assertEquals(3, spacing.reductionTargetRange.end)
        assertEquals("collapse-adjacent-punctuation-inner-glue", spacing.reason)
    }

    @Test
    fun greedyBreakerProducesMultipleLinesWhenWidthOverflows() {
        // 8 CJK clusters * 16f = 128f natural; maxWidth=64f -> 4 clusters per line -> 2 lines.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
    fun stubShaperProducesProfileDerivedWithShapedAdvance() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("中文，世界。"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val punctuationDecisions = result.debug.punctuationDecisions
        assertTrue(punctuationDecisions.isNotEmpty())
        for (p in punctuationDecisions) {
            assertEquals(
                "ProfileDerivedWithShapedAdvance",
                p.geometrySource,
                "Stub shaper provides advance but no bounds for '${p.char}'",
            )
            // MissingInkBoundsFallback: the degradation reason is recorded.
            assertEquals("shaper-no-ink-bounds", p.inkBoundsFallback, "fallback for '${p.char}'")
            // PauseOrStop: all glue on trailing side
            assertEquals(0f, p.leadingGlueNatural, "leading glue for '${p.char}'")
            assertEquals(8f, p.trailingGlueNatural, "trailing glue for '${p.char}'")
        }
    }

    @Test
    fun shapingWithoutBoundsProducesProfileDerivedWithShapedAdvance() {
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("。"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val punctuation = result.debug.punctuationDecisions.single()
        assertEquals("ProfileDerivedWithShapedAdvance", punctuation.geometrySource)
        assertEquals("shaper-no-ink-bounds", punctuation.inkBoundsFallback)
        assertEquals(8f, punctuation.bodyWidth)
        // PauseOrStop: all glue on trailing side (class-based, not ink-based)
        assertEquals(0f, punctuation.leadingGlueNatural)
        assertEquals(8f, punctuation.trailingGlueNatural)
    }

    @Test
    fun autoSpaceGapAtLineEndIsTrimmedLikeAnyLineEdgeBlank() {
        // text = "中文 AB 中文中文中文" segments to 中 文 [ ] [AB] [ ] 中….
        // Both spaces are CJK-adjacent gaps (advance 4). maxWidth=80 →
        // greedy line 0 = [中 文 ' ' AB ' '] (16+16+4+32+4=72); the trailing
        // space cluster sits at the line END and collapses entirely:
        // line adjusted width 72 → 68.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("中文 AB 中文中文中文"),
                constraints = LayoutConstraints(maxWidth = 80f),
            ),
        )

        assertEquals(68f, result.lines.first().adjustedWidth)

        val collapse = result.debug.lineEdgeTrimDecisions
            .single { it.reason == "LineEdgeWordSpaceCollapse" }
        assertEquals("trailing", collapse.side)
        assertEquals(4f, collapse.trimAmount)
        assertEquals(5, collapse.clusterRange.start)
        assertEquals(6, collapse.clusterRange.end)
    }

    @Test
    fun haltAdvanceFromShaperDrivesPunctuationBodyEndToEnd() {
        // A shaper that reports halt=7 for 。 — the engine's punctuation
        // decision must carry the font-derived body and the FontHaltDerived
        // geometry source, and the ledger must keep resolved >= body.
        val engine = ExplainableStubParagraphLayoutEngine(
            textShaper = object : TextShaper {
                val delegate = ExplainableStubTextShaper()
                override fun shape(input: ShapingInput): ShapingResult {
                    val result = delegate.shape(input)
                    if (input.displayText != "。") return result
                    return result.copy(
                        glyphRuns = result.glyphRuns.map { run ->
                            run.copy(glyphs = run.glyphs.map { it.copy(haltAdvance = 7f, haltPlacementX = 0f) })
                        },
                    )
                }
            },
        )

        val result = engine.layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("中文。"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val stop = result.debug.punctuationDecisions.single()
        assertEquals(7f, stop.haltAdvance)
        assertEquals(7f, stop.bodyWidth)
        assertEquals("FontHaltDerived", stop.geometrySource)
        // Trailing glue grows to advance - haltBody = 9; at line end it is
        // trimmed away leaving exactly the font body.
        assertEquals(9f, stop.trailingGlueNatural)
        val stopCluster = result.clusters.single { it.text == "。" }
        assertEquals(7f, stopCluster.advance)
    }

    @Test
    fun emphasisSpanProducesDotAnchorsForHanAndSkipsPunctuation() {
        // "他强调：豆子新鲜最要紧，烘焙其次。" with emphasis over 4..16
        // (豆子新鲜最要紧，烘焙其次). Stub advances: every cluster 16f, no
        // justification → anchors at glyph centres; ， inside the span is
        // skipped per CLREQ; 。 is outside the span entirely.
        // maxWidth=128 wraps at 8 clusters/line.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("他强调：豆子新鲜最要紧，烘焙其次。"),
                constraints = LayoutConstraints(maxWidth = 128f),
                decorations = listOf(
                    ink.duo3.tiqian.core.DecorationSpan(
                        range = ink.duo3.tiqian.core.TextRange(4, 16),
                        kind = ink.duo3.tiqian.core.DecorationKind.Emphasis,
                    ),
                ),
            ),
        )

        val decisions = result.debug.decorationDecisions
        assertEquals(12, decisions.size)

        val applied = decisions.filter { it.applied }
        assertEquals(11, applied.size)
        assertTrue(applied.all { it.reason == "EmphasisDotOnHanText" })

        val comma = decisions.single { it.sourceText == "，" }
        assertEquals(false, comma.applied)
        assertEquals("clreq-no-dot-on-punctuation", comma.reason)

        // 。 (15-16) is outside the span — no decision at all.
        assertTrue(decisions.none { it.sourceText == "。" })

        // Anchor maths for 豆 (4-5): line 0 holds clusters 0..7, x offset of
        // index 4 = 4×16 = 64, glyph centre 64+8 = 72; anchorY = line 0
        // baseline + 16×0.35 (dot tucked under the character ink).
        val first = decisions.single { it.sourceText == "豆" }
        assertEquals(72f, first.anchorX)
        val line0Baseline = result.lines.first().baseline
        assertEquals(line0Baseline + 5.6f, first.anchorY, 0.01f)
    }

    @Test
    fun mourningSpanIsKeptUnbrokenAndFramedPerLine() {
        // "悼念：王小明同志、张大同同志。" maxWidth=72: greedy would break at
        // cluster 4 (inside 王小明 3..5) — MourningSpanKeptUnbroken moves the
        // break to 3. Both names end up whole on single lines with one frame
        // segment each.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("悼念：王小明同志、张大同同志。"),
                constraints = LayoutConstraints(maxWidth = 72f),
                decorations = listOf(
                    ink.duo3.tiqian.core.DecorationSpan(
                        range = ink.duo3.tiqian.core.TextRange(3, 6),
                        kind = ink.duo3.tiqian.core.DecorationKind.Mourning,
                    ),
                    ink.duo3.tiqian.core.DecorationSpan(
                        range = ink.duo3.tiqian.core.TextRange(9, 12),
                        kind = ink.duo3.tiqian.core.DecorationKind.Mourning,
                    ),
                ),
            ),
        )

        // Line 0 ends BEFORE the span (悼念： only) — the break moved.
        assertEquals(3, result.lines[0].range.end)

        val segments = result.debug.decorationSegments
        assertEquals(2, segments.size)
        for (seg in segments) {
            assertEquals("MourningSpanKeptUnbroken", seg.reason)
            assertEquals(false, seg.openStart)
            assertEquals(false, seg.openEnd)
        }
        // 王小明 starts its line: left edge at 0. The line is justified
        // (双齐 baseline): 3 boundaries share the 8px deficit (+8/3 each),
        // so the frame's right edge follows the spread glyphs — the last
        // cluster's trailing justify delta stays OUTSIDE the frame.
        val first = segments.single { it.sourceRange.start == 3 }
        assertEquals(0f, first.left)
        assertEquals(160f / 3f, first.right, 0.01f)
        // Frame hugs the CJK character face (字面, no margin):
        // baseline - 0.88em .. baseline + 0.12em.
        val line = result.lines[1]
        assertEquals(line.baseline - 14.08f, first.top, 0.01f)
        assertEquals(line.baseline + 1.92f, first.bottom, 0.01f)
    }

    @Test
    fun mourningSpanWiderThanMeasureSplitsWithOpenEdges() {
        // A 5-character name span at maxWidth=64 cannot fit one line: the
        // split fallback produces open-ended segments.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("王小明大同先生"),
                constraints = LayoutConstraints(maxWidth = 64f),
                decorations = listOf(
                    ink.duo3.tiqian.core.DecorationSpan(
                        range = ink.duo3.tiqian.core.TextRange(0, 5),
                        kind = ink.duo3.tiqian.core.DecorationKind.Mourning,
                    ),
                ),
            ),
        )

        val segments = result.debug.decorationSegments
        assertEquals(2, segments.size)
        assertTrue(segments.all { it.reason == "mourning-span-split-across-lines" })
        assertEquals(false, segments[0].openStart)
        assertEquals(true, segments[0].openEnd)
        assertEquals(true, segments[1].openStart)
        assertEquals(false, segments[1].openEnd)
    }

    @Test
    fun longLatinSentenceWrapsAtWordBoundaries() {
        // The headline LatinWordSegmentation capability: a Latin sentence
        // longer than the measure breaks BETWEEN words (previously a Latin
        // run was one unbreakable cluster and simply overflowed).
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("The quick brown fox"),
                constraints = LayoutConstraints(maxWidth = 160f),
            ),
        )

        assertTrue(result.lines.size > 1, "long Latin must wrap at word boundaries")
        // No line may begin or end with visible space width.
        for (line in result.lines) {
            val lineClusters = result.clusters.filter {
                it.range.start >= line.range.start && it.range.end <= line.range.end
            }
            val first = lineClusters.first()
            val last = lineClusters.last()
            if (first.text.all { ch -> ch == ' ' }) assertEquals(0f, first.advance)
            if (last.text.all { ch -> ch == ' ' }) assertEquals(0f, last.advance)
        }
    }

    @Test
    fun wordSpacesStretchFirstUnderJustification() {
        // "AB CD EF中文中文中" — two word spaces (Latin|space|Latin) plus a
        // mid-line EF↔中 sino-western boundary. CLREQ expansion order:
        // word spaces stretch FIRST (simultaneously, equally), then the
        // sino-western gap, hanzi spacing untouched.
        // Stub: AB=32 sp=16 CD=32 sp=16 EF=32+insert(4)=36 中=16 → line0 =
        // AB·CD·EF中 (148); 文 → 164 > 160 → deficit 12.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("AB CD EF中文中文中"),
                constraints = LayoutConstraints(maxWidth = 160f),
                paragraphStyle = ink.duo3.tiqian.core.ParagraphStyle(
                    firstLineIndentEm = 0f,
                ),
            ),
        )

        assertTrue(result.lines.size >= 2)
        val decision = result.debug.justificationDecisions.first()
        assertEquals(12f, decision.deficitBefore)
        assertEquals(0f, decision.deficitAfter)
        // Word spaces saturate first (+4 each, equal), the sino-western gap
        // takes the remaining 4; no CjkInterChar needed.
        val wordAllocs = decision.allocations.filter { it.kind == "WordSpace" }
        assertEquals(2, wordAllocs.size)
        assertTrue(wordAllocs.all { it.delta == 4f })
        val latinGapAlloc = decision.allocations.single { it.kind == "CjkLatinSpace" }
        assertEquals(4f, latinGapAlloc.delta)
        assertTrue(decision.allocations.none { it.kind == "CjkInterChar" })
        assertEquals(160f, result.lines.first().visualWidth)
    }

    @Test
    fun looseLineEndStyleKeepsFullWidthPunctuation() {
        // AdjustmentStylePolicy.lineEndPunctuation = AllowFullWidth (宽松风格):
        // the unconditional line-end half-width trim is skipped; the 字身
        // grid stays intact at line end.
        val loose = ExplainableStubParagraphLayoutEngine(
            clreqProfileResolver = ClreqProfileResolver {
                ClreqProfile.MainlandHorizontal.copy(
                    adjustment = ink.duo3.tiqian.clreq.AdjustmentStylePolicy(
                        lineEndPunctuation = ink.duo3.tiqian.clreq.LineEndPunctuationStyle.AllowFullWidth,
                    ),
                )
            },
        )
        val result = loose.layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("中文中文。"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )
        val stop = result.clusters.single { it.text == "。" }
        assertEquals(16f, stop.advance)
        assertTrue(result.debug.lineEdgeTrimDecisions.none { it.reason == "LineEndHalfWidthPunctuation" })

        // Default strict style trims to half width.
        val strict = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("中文中文。"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )
        assertEquals(8f, strict.clusters.single { it.text == "。" }.advance)
    }

    @Test
    fun inlineStopCompressionKnobLimitsPushInCapacity() {
        // "中中中。中中。" maxWidth=96: line0 = 6 clusters (96), offender 。
        // (idx 6) overflows by 16. Capacities: offender 。 tier-1 (8) +
        // mid-line 。 idx3 tier-4 (8) = 16 → PushIn succeeds by default.
        val text = "中中中。中中。"
        val default = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent(text),
                constraints = LayoutConstraints(maxWidth = 96f),
            ),
        )
        assertEquals(1, default.lines.size)
        assertTrue(default.debug.lineDecisions.single().repairDecision?.kind == "PushIn")

        // Knob off: mid-line 。 keeps full width (its glue is lineEndOnly);
        // capacity drops to the offender's own 8 < 16 → PushIn rejected,
        // CarryPrevious instead.
        val noInline = ExplainableStubParagraphLayoutEngine(
            clreqProfileResolver = ClreqProfileResolver {
                ClreqProfile.MainlandHorizontal.copy(
                    adjustment = ink.duo3.tiqian.clreq.AdjustmentStylePolicy(
                        allowInlineStopCompression = false,
                    ),
                )
            },
        ).layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent(text),
                constraints = LayoutConstraints(maxWidth = 96f),
            ),
        )
        assertTrue(noInline.lines.size > 1)
        val pushInCandidate = noInline.debug.lineDecisions
            .flatMap { it.repairCandidates }
            .first { it.kind == "PushIn" }
        assertEquals("insufficient-capacity", pushInCandidate.rejectionReason)
        assertEquals(8f, pushInCandidate.availableCapacity)
    }

    @Test
    fun sinoWesternGapKnobDisablesStretchAndShrink() {
        // allowSinoWesternGapAdjustment=false: the gap stays fixed — no
        // CjkLatinSpace stretch under justify.
        val fixedGap = ExplainableStubParagraphLayoutEngine(
            clreqProfileResolver = ClreqProfileResolver {
                ClreqProfile.MainlandHorizontal.copy(
                    adjustment = ink.duo3.tiqian.clreq.AdjustmentStylePolicy(
                        allowSinoWesternGapAdjustment = false,
                    ),
                )
            },
        ).layout(
            LayoutInput(
                content = TiqianTextContent("中文Hello文中文中文中文中"),
                constraints = LayoutConstraints(maxWidth = 160f),
                paragraphStyle = ink.duo3.tiqian.core.ParagraphStyle(
                    firstLineIndentEm = 0f,
                ),
            ),
        )
        assertTrue(fixedGap.debug.justificationDecisions.isNotEmpty())
        assertTrue(
            fixedGap.debug.justificationDecisions
                .flatMap { it.allocations }
                .none { it.kind == "CjkLatinSpace" },
        )
    }

    @Test
    fun justifyNeverStretchesPunctuationLatinBoundary() {
        // CjkOnlyInterCharBoundary:「中文标点与西文之间不加间距」also under
        // justification. Line 0 = 中文中文话：The — the ：|The boundary must
        // get no CjkInterChar share even though the colon's trailing side is
        // glue; the hanzi boundaries absorb the whole deficit instead.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("中文中文话：The quick brown fox jumps"),
                constraints = LayoutConstraints(maxWidth = 160f),
            ),
        )

        assertTrue(result.lines.size > 1)
        val line0 = result.debug.justificationDecisions
            .first { it.lineRange.start == 0 }
        val colonRange = ink.duo3.tiqian.core.TextRange(5, 6)
        assertTrue(
            line0.allocations.none { it.clusterRange == colonRange },
            "：|The boundary must not stretch: ${line0.allocations}",
        )
        assertEquals(0f, line0.deficitAfter)
    }

    @Test
    fun justifyFillsSaturatedLineWithUncappedEvenShare() {
        // CLREQ 平均拉大字距 has no upper bound: when word spaces and
        // sino-western gaps are exhausted, the remaining deficit spreads
        // evenly over hanzi boundaries past the old 0.25em cap — a justified
        // line must reach maxWidth exactly, never stop short.
        // Stub: 4 hanzi (64) then an unbreakable 12-char Latin word (192)
        // that must wrap — line 0 deficit = 160 - 64 = 96 over 3 hanzi
        // boundaries = 32 each, far past the old 4px cap.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("中文中文Considerable中文"),
                constraints = LayoutConstraints(maxWidth = 160f),
            ),
        )

        val decision = result.debug.justificationDecisions.first { it.lineRange.start == 0 }
        assertEquals(0f, decision.deficitAfter)
        assertEquals(160f, result.lines[0].visualWidth)
        // Even share: all CjkInterChar deltas equal, beyond the old cap.
        val deltas = decision.allocations.filter { it.kind == "CjkInterChar" }.map { it.delta }
        assertEquals(3, deltas.size)
        assertTrue(deltas.all { kotlin.math.abs(it - 32f) < 0.01f }, "deltas=$deltas")
    }

    @Test
    fun firstLineIndentShrinksFirstLineMeasureOnly() {
        // ParagraphFirstLineIndent: 12 hanzi at maxWidth 160, indent 2em
        // (32). Line 0 measure = 128 → 8 chars; line 1 uses the full 160.
        // LineBox carries the inset; width fields exclude it; result width
        // accounts for indent + visual.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文中文中文中文中文中文"),
                constraints = LayoutConstraints(maxWidth = 160f),
            ),
        )

        assertEquals(2, result.lines.size)
        assertEquals(32f, result.lines[0].indent)
        assertEquals(0f, result.lines[1].indent)
        assertEquals(8, result.lines[0].range.end - result.lines[0].range.start)
        assertEquals(128f, result.lines[0].visualWidth)
        // Widest extent = indent + first line visual = 160.
        assertEquals(160f, result.size.width)
    }

    @Test
    fun firstLineIndentDefaultsToTwoEmAndZeroDisables() {
        // CLREQ:「段首缩排以两个汉字的空间为标准」— the engine default.
        val indented = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文"),
                constraints = LayoutConstraints(maxWidth = 240f),
            ),
        )
        assertEquals(32f, indented.lines.single().indent)

        val disabled = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("中文"),
                constraints = LayoutConstraints(maxWidth = 240f),
            ),
        )
        assertEquals(0f, disabled.lines.single().indent)
    }

    @Test
    fun pushInConsumesWordSpaceBeforeMidLinePunctGlue() {
        // Breaker-level tier ordering with mixed channels: line
        // [A][ ][B][、][中] + offender 。. Tiers in the merged line:
        // offender 。 trailing (promoted tier 1, 8) → word space (tier 2,
        // capacity 12) → 、 trailing (tier 6, 8). Overflow 16 must consume
        // tier 1 fully then 8 of tier 2 — 、 stays untouched.
        val clusters = listOf(
            Cluster(range = ink.duo3.tiqian.core.TextRange(0, 1), text = "A", fontKey = "t", advance = 32f),
            Cluster(range = ink.duo3.tiqian.core.TextRange(1, 2), text = " ", fontKey = "t", advance = 16f),
            Cluster(range = ink.duo3.tiqian.core.TextRange(2, 3), text = "B", fontKey = "t", advance = 32f),
            Cluster(range = ink.duo3.tiqian.core.TextRange(3, 4), text = "、", fontKey = "t", advance = 16f),
            Cluster(range = ink.duo3.tiqian.core.TextRange(4, 5), text = "中", fontKey = "t", advance = 16f),
            Cluster(range = ink.duo3.tiqian.core.TextRange(5, 6), text = "。", fontKey = "t", advance = 16f),
        )
        val solution = GreedyLineBreaker().breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 112f,
            shrinkOpportunities = listOf(
                ShrinkOpportunity(1, tier = 2, capacity = 12f, channel = ShrinkChannel.RawAdvance),
                ShrinkOpportunity(3, tier = 6, capacity = 8f, channel = ShrinkChannel.TrailingGlue),
                ShrinkOpportunity(5, tier = 4, capacity = 8f, channel = ShrinkChannel.TrailingGlue),
            ),
        )

        assertEquals(1, solution.lines.size)
        val repair = solution.lines.single().repair
        assertTrue(repair is RepairOption.PushIn)
        assertEquals(16f, repair.totalShrink)
        // Tier 1 (offender 。) → tier 2 (word space); tier-6 、 untouched.
        assertEquals(listOf(5, 1), repair.allocations.map { it.clusterIndex })
        assertEquals(8f, repair.allocations[0].shrink)
        assertEquals(8f, repair.allocations[1].shrink)
        assertEquals(ShrinkChannel.RawAdvance, repair.allocations[1].channel)
        assertTrue(repair.allocations.none { it.clusterIndex == 3 })
    }

    @Test
    fun substitutionRollsBackToSourceTextWhenFontLacksTheGlyph() {
        // SubstitutionRollbackOnMissingGlyph: the CLREQ substitution `——` →
        // `⸺` only stands if the font covers U+2E3A. This shaper reports a
        // .notdef for the substituted form (like PingFang SC / Hiragino /
        // Heiti would), so the engine must re-shape with the source text.
        val engine = ExplainableStubParagraphLayoutEngine(
            textShaper = object : TextShaper {
                val delegate = ExplainableStubTextShaper()
                override fun shape(input: ShapingInput): ShapingResult {
                    val result = delegate.shape(input)
                    return if (input.displayText.contains('⸺')) {
                        result.copy(decisions = result.decisions.map { it.copy(missingGlyphs = 1) })
                    } else {
                        result
                    }
                }
            },
        )

        val result = engine.layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("中——文"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        // The dash cluster renders the SOURCE text, not the tofu substitution.
        val dashCluster = result.clusters.single { it.text == "——" }
        assertEquals("——", dashCluster.displayText)

        val dashDecision = result.debug.fontDecisions.single { it.sourceText == "——" }
        assertEquals("——", dashDecision.displayText)
        assertTrue(dashDecision.substitutionReason.endsWith("SubstitutionRollbackOnMissingGlyph"))
    }

    @Test
    fun substitutionIsKeptWhenFontCoversTheGlyph() {
        // Counterpart: the default stub shaper reports no missing glyphs, so
        // the `——` → `⸺` substitution stays in effect.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("中——文"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val dashCluster = result.clusters.single { it.text == "——" }
        assertEquals("⸺", dashCluster.displayText)
    }

    @Test
    fun ambiguousGlyphClusterMappingFallsBackToPolicyWithRecordedReason() {
        // A multi-character punctuation cluster shaped into a single glyph:
        // per-character ink cannot be attributed, so geometry must fall back
        // to pure policy AND record glyph-cluster-mapping-ambiguous instead
        // of silently looking like the no-shaping path.
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
                                advance = 32f,
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
                                        advance = 32f,
                                        bounds = Rect(left = 2f, top = -10f, right = 30f, bottom = -6f),
                                    ),
                                ),
                                advance = 32f,
                            ),
                        ),
                    )
            },
        )

        val result = engine.layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
                content = TiqianTextContent("……"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val punctuationDecisions = result.debug.punctuationDecisions
        assertEquals(2, punctuationDecisions.size)
        for (p in punctuationDecisions) {
            assertEquals("PolicyDerived", p.geometrySource, "source for '${p.char}'")
            assertEquals(
                "glyph-cluster-mapping-ambiguous",
                p.inkBoundsFallback,
                "fallback for '${p.char}'",
            )
        }
    }
}
