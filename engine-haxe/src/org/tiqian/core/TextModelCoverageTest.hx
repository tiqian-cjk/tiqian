package org.tiqian.core;

import org.tiqian.core.RichTextRole.Background;
import org.tiqian.core.RichTextRole.Underline;
import org.tiqian.core.RichTextRole.LineThrough;
import org.tiqian.core.RichTextRole.Link;
import org.tiqian.core.RichTextRole.TechnicalInline;
import org.tiqian.core.RichTextRole.InlineCode;
import org.tiqian.core.RichTextLinePattern.Solid;
import org.tiqian.core.RichTextLinePattern.Dashed;
import org.tiqian.core.RichTextLinePattern.Dotted;
import org.tiqian.core.RichTextBackgroundDrawStyle.Fill;
import org.tiqian.core.RichTextBackgroundDrawStyle.Border;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TestTraceRender;
import org.tiqian.test.trace.TracedAssertions;
import std.ReadOnlyArray;

class TextModelCoverageTest {
    @:test
    public static function testTiqianTextContentAndLinkAddressDisplay():Void {
        new TestTraceRecorder("TextModelCoverageTest").section("testTiqianTextContentAndLinkAddressDisplay");
        final content:TiqianTextContent = new TiqianTextContent("Hello Tiqian", [
            new TextSpan(new TextRange(0, 5), new TextStyle([], 16.0, "zh-Hans", 400, false, 0.0, InlineAttachment.None))
        ], [0, 5, 12],
            [new LineBreakSpan(new TextRange(0, 5), LineBreakPolicy.ProgressiveTechnical)], [new TextRange(6, 12)]);
        TracedAssertions.assertEqualsString("Hello Tiqian", content.text);
        TracedAssertions.assertEqualsInt(1, content.spans.length);
        TracedAssertions.assertEqualsInt(3, content.sourceBoundaries.length);
        TracedAssertions.assertEqualsInt(1, content.lineBreakSpans.length);
        TracedAssertions.assertEqualsInt(1, content.autoSpaceSuppressedRanges.length);
        TextModelCoverageTestHelpers.assertRendered(content.toString());
        TracedAssertions.assertTrue(content.toString().indexOf("TiqianTextContent") >= 0);

        TracedAssertions.assertFalse(LinkAddressDisplay.displaysAddress("", ""));
        TracedAssertions.assertFalse(LinkAddressDisplay.displaysAddress("tiqian.org", ""));
        TracedAssertions.assertFalse(LinkAddressDisplay.displaysAddress("", "https://tiqian.org"));
        TracedAssertions.assertTrue(LinkAddressDisplay.displaysAddress("tiqian.org", "tiqian.org"));
        TracedAssertions.assertTrue(LinkAddressDisplay.displaysAddress("tiqian.org", "https://tiqian.org"));
        TracedAssertions.assertTrue(LinkAddressDisplay.displaysAddress("tiqian.org", "http://tiqian.org"));
        TracedAssertions.assertTrue(LinkAddressDisplay.displaysAddress("dev@tiqian.org", "mailto:dev@tiqian.org"));
        TracedAssertions.assertFalse(LinkAddressDisplay.displaysAddress("tiqian.org", "https://other.org"));
        TracedAssertions.assertFalse(LinkAddressDisplay.displaysAddress("tiqian.org", "ftp://tiqian.org"));
    }

    @:test
    public static function testSpansAndInlineBox():Void {
        new TestTraceRecorder("TextModelCoverageTest").section("testSpansAndInlineBox");
        final lineBreakSpan:LineBreakSpan = new LineBreakSpan(new TextRange(0, 4), LineBreakPolicy.ProgressiveTechnical);
        TracedAssertions.assertEqualsRendered(new TextRange(0, 4).toString(), lineBreakSpan.range.toString());
        TracedAssertions.assertEqualsRendered(Std.string(LineBreakPolicy.ProgressiveTechnical), Std.string(lineBreakSpan.policy));
        TextModelCoverageTestHelpers.assertRendered(lineBreakSpan.toString());

        final progressiveTechnical = LineBreakPolicy.ProgressiveTechnical;
        TracedAssertions.assertNotNullRendered(progressiveTechnical != null, progressiveTechnical == null ? "-" : Std.string(progressiveTechnical));
        final attachmentNone = InlineAttachment.None;
        TracedAssertions.assertNotNullRendered(attachmentNone != null, attachmentNone == null ? "-" : Std.string(attachmentNone));
        final attachmentPrevious = InlineAttachment.Previous;
        TracedAssertions.assertNotNullRendered(attachmentPrevious != null, attachmentPrevious == null ? "-" : Std.string(attachmentPrevious));
        final spacingNarrow = InlineBoxOuterSpacing.Narrow;
        TracedAssertions.assertNotNullRendered(spacingNarrow != null, spacingNarrow == null ? "-" : Std.string(spacingNarrow));
        final spacingSource = InlineBoxOuterSpacing.Source;
        TracedAssertions.assertNotNullRendered(spacingSource != null, spacingSource == null ? "-" : Std.string(spacingSource));

        final inlineBox:InlineBoxSpan = new InlineBoxSpan(new TextRange(1, 3), 2.0, 3.0, InlineBoxOuterSpacing.Source);
        TracedAssertions.assertEqualsRendered(new TextRange(1, 3).toString(), inlineBox.range.toString());
        TracedAssertions.assertEqualsFloat(2.0, inlineBox.inlineStart);
        TracedAssertions.assertEqualsFloat(3.0, inlineBox.inlineEnd);
        TracedAssertions.assertEqualsRendered(Std.string(InlineBoxOuterSpacing.Source), Std.string(inlineBox.outerSpacing));
        TextModelCoverageTestHelpers.assertRendered(inlineBox.toString());

        TracedAssertions.assertEqualsString("\uFFFC", InlineObjectSpan.INLINE_OBJECT_REPLACEMENT_CHAR);
    }

    @:test
    public static function testInlineObjectPreferredStretchAndAdjustment():Void {
        new TestTraceRecorder("TextModelCoverageTest").section("testInlineObjectPreferredStretchAndAdjustment");
        final punctuationTrailing = InlineObjectPreferredStretchKind.PunctuationTrailing;
        TracedAssertions.assertNotNullRendered(punctuationTrailing != null, punctuationTrailing == null ? "-" : Std.string(punctuationTrailing));
        final relation = InlineObjectPreferredStretchKind.Relation;
        TracedAssertions.assertNotNullRendered(relation != null, relation == null ? "-" : Std.string(relation));
        final binaryOperator = InlineObjectPreferredStretchKind.BinaryOperator;
        TracedAssertions.assertNotNullRendered(binaryOperator != null, binaryOperator == null ? "-" : Std.string(binaryOperator));

        final stretch:InlineObjectPreferredStretch = new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.Relation, 10.0, 15.0);
        TracedAssertions.assertEqualsRendered(Std.string(InlineObjectPreferredStretchKind.Relation), Std.string(stretch.kind));
        TracedAssertions.assertEqualsFloat(10.0, stretch.naturalWidth);
        TracedAssertions.assertEqualsFloat(15.0, stretch.targetWidth);
        TracedAssertions.assertEqualsFloat(5.0, stretch.capacity);
        TextModelCoverageTestHelpers.assertRendered(stretch.toString());

        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.PunctuationTrailing, -1.0,
            10.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.PunctuationTrailing,
            0.0 / 0.0, 10.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.PunctuationTrailing,
            Math.POSITIVE_INFINITY, 10.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.PunctuationTrailing, 10.0,
            10.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.PunctuationTrailing, 10.0,
            8.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.PunctuationTrailing, 10.0,
            0.0 / 0.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.PunctuationTrailing, 10.0,
            Math.POSITIVE_INFINITY));

        final fixed:InlineObjectBoundaryAdjustment = InlineObjectBoundaryAdjustment.fixed();
        TracedAssertions.assertFalse(fixed.participatesInUniformStretch);
        final fixedPreferredStretch = fixed.preferredStretch;
        TracedAssertions.assertNullRendered(fixedPreferredStretch == null, fixedPreferredStretch == null ? "-" : fixedPreferredStretch.toString());
        TracedAssertions.assertEqualsFloat(0.0, fixed.shrinkCapacity);
        TracedAssertions.assertEqualsFloat(0.0, fixed.lineEndDiscardableAdvance);
        TracedAssertions.assertFalse(fixed.preventsLineBreak);

        final customAdj:InlineObjectBoundaryAdjustment = new InlineObjectBoundaryAdjustment(true, stretch, 2.0, 1.0, true);
        TracedAssertions.assertTrue(customAdj.participatesInUniformStretch);
        TracedAssertions.assertEqualsRendered(stretch.toString(), customAdj.preferredStretch.toString());
        TracedAssertions.assertEqualsFloat(2.0, customAdj.shrinkCapacity);
        TracedAssertions.assertEqualsFloat(1.0, customAdj.lineEndDiscardableAdvance);
        TracedAssertions.assertTrue(customAdj.preventsLineBreak);
        TextModelCoverageTestHelpers.assertRendered(customAdj.toString());

        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new InlineObjectBoundaryAdjustment(false, null, -0.5));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new InlineObjectBoundaryAdjustment(false, null, 0.0 / 0.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new InlineObjectBoundaryAdjustment(false, null, 0.0, -0.5));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new InlineObjectBoundaryAdjustment(false, null, 0.0, 0.0 / 0.0));

        final inlineObject:InlineObjectSpan = new InlineObjectSpan(new TextRange(0, 1), 16.0, 12.0, 4.0, fixed, customAdj);
        TracedAssertions.assertEqualsRendered(new TextRange(0, 1).toString(), inlineObject.range.toString());
        TracedAssertions.assertEqualsFloat(16.0, inlineObject.advance);
        TracedAssertions.assertEqualsFloat(12.0, inlineObject.ascent);
        TracedAssertions.assertEqualsFloat(12.0, inlineObject.ascent);
        TracedAssertions.assertTrue(true);
    }

    @:test
    public static function testTextStyleAndDecorations():Void {
        new TestTraceRecorder("TextModelCoverageTest").section("testTextStyleAndDecorations");
        final style:TextStyle = new TextStyle(["Noto Serif CJK SC"], 18.0, "zh-CN", 700, true, -2.0, InlineAttachment.Previous);
        TracedAssertions.assertEqualsRendered(TextModelCoverageTestHelpers.renderStrings(["Noto Serif CJK SC"]),
            TextModelCoverageTestHelpers.renderStrings(style.fontFamilies));
        TracedAssertions.assertEqualsFloat(18.0, style.fontSize);
        TracedAssertions.assertEqualsString("zh-CN", style.locale);
        TracedAssertions.assertEqualsInt(700, style.fontWeight);
        TracedAssertions.assertTrue(style.italic);
        TracedAssertions.assertEqualsFloat(-2.0, style.baselineShift);
        TracedAssertions.assertEqualsRendered(Std.string(InlineAttachment.Previous), Std.string(style.inlineAttachment));
        TextModelCoverageTestHelpers.assertRendered(style.toString());

        final emphasis = DecorationKind.Emphasis;
        TracedAssertions.assertNotNullRendered(emphasis != null, emphasis == null ? "-" : Std.string(emphasis));
        final mourning = DecorationKind.Mourning;
        TracedAssertions.assertNotNullRendered(mourning != null, mourning == null ? "-" : Std.string(mourning));
        final properNoun = DecorationKind.ProperNoun;
        TracedAssertions.assertNotNullRendered(properNoun != null, properNoun == null ? "-" : Std.string(properNoun));
        final bookTitle = DecorationKind.BookTitle;
        TracedAssertions.assertNotNullRendered(bookTitle != null, bookTitle == null ? "-" : Std.string(bookTitle));

        final decoration:DecorationSpan = new DecorationSpan(new TextRange(2, 4), DecorationKind.Emphasis);
        TracedAssertions.assertEqualsRendered(new TextRange(2, 4).toString(), decoration.range.toString());
        TracedAssertions.assertEqualsRendered(Std.string(DecorationKind.Emphasis), Std.string(decoration.kind));
        TextModelCoverageTestHelpers.assertRendered(decoration.toString());

        final color:ColorSpan = new ColorSpan(1, 5, -15654349);
        TracedAssertions.assertEqualsInt(1, color.start);
        TracedAssertions.assertEqualsInt(5, color.end);
        TracedAssertions.assertEqualsInt(-15654349, color.argb);
        TextModelCoverageTestHelpers.assertRendered(color.toString());
        TracedAssertions.assertTrue(color.toString().indexOf("ColorSpan") >= 0);
    }

    @:test
    public static function testRichTextSpansAndPatterns():Void {
        new TestTraceRecorder("TextModelCoverageTest").section("testRichTextSpansAndPatterns");
        final paint:RichTextPaint = new RichTextPaint(-16777216, Solid.instance,
            new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 1.5);
        TracedAssertions.assertEqualsInt(-16777216, paint.argb);
        TracedAssertions.assertEqualsFloat(1.5, paint.adjacentSameStyleClearance);
        TextModelCoverageTestHelpers.assertRendered(paint.toString());

        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new RichTextPaint(null, Solid.instance,
            new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), -0.1));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new RichTextPaint(null, Solid.instance,
            new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0 / 0.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new RichTextPaint(null, Solid.instance,
            new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), Math.POSITIVE_INFINITY));

        final bgPaint:RichTextBackgroundPaint = new RichTextBackgroundPaint(2.0, 3.0, 4.0, 1.0, RichTextBackgroundMetricPolicy.UniformTextStyle,
            new Border(1.5));
        TracedAssertions.assertEqualsFloat(2.0, bgPaint.horizontalPadding);
        TracedAssertions.assertEqualsFloat(3.0, bgPaint.verticalPadding);
        TracedAssertions.assertEqualsFloat(4.0, bgPaint.cornerRadius);
        TracedAssertions.assertEqualsFloat(1.0, bgPaint.continuationCornerRadius);
        TracedAssertions.assertEqualsRendered(Std.string(RichTextBackgroundMetricPolicy.UniformTextStyle), Std.string(bgPaint.metricPolicy));
        TextModelCoverageTestHelpers.assertRendered(bgPaint.toString());

        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new RichTextBackgroundPaint(-1.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces,
            Fill.instance));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new RichTextBackgroundPaint(0.0 / 0.0, 0.0, 0.0, 0.0,
            RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new RichTextBackgroundPaint(0.0, -1.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces,
            Fill.instance));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new RichTextBackgroundPaint(0.0, 0.0 / 0.0, 0.0, 0.0,
            RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new RichTextBackgroundPaint(0.0, 0.0, -1.0, -1.0, RichTextBackgroundMetricPolicy.MarkedFaces,
            Fill.instance));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new RichTextBackgroundPaint(0.0, 0.0, 0.0 / 0.0, 0.0 / 0.0,
            RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new RichTextBackgroundPaint(0.0, 0.0, 0.0, -1.0, RichTextBackgroundMetricPolicy.MarkedFaces,
            Fill.instance));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0 / 0.0,
            RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance));

        TracedAssertions.assertEqualsRendered(Fill.instance.toString(), Fill.instance.toString());
        final border:Border = new Border(2.0);
        TracedAssertions.assertEqualsFloat(2.0, border.strokeWidth);
        TextModelCoverageTestHelpers.assertRendered(border.toString());
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Border(0.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Border(-1.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Border(0.0 / 0.0));

        final markedFaces = RichTextBackgroundMetricPolicy.MarkedFaces;
        TracedAssertions.assertNotNullRendered(markedFaces != null, markedFaces == null ? "-" : Std.string(markedFaces));
        final uniformTextStyle = RichTextBackgroundMetricPolicy.UniformTextStyle;
        TracedAssertions.assertNotNullRendered(uniformTextStyle != null, uniformTextStyle == null ? "-" : Std.string(uniformTextStyle));
        final uniformParagraphStyle = RichTextBackgroundMetricPolicy.UniformParagraphStyle;
        TracedAssertions.assertNotNullRendered(uniformParagraphStyle != null, uniformParagraphStyle == null ? "-" : Std.string(uniformParagraphStyle));

        TracedAssertions.assertEqualsRendered(Solid.instance.toString(), Solid.instance.toString());
        final dashed:Dashed = new Dashed(1.0, 4.0, 2.0);
        TracedAssertions.assertEqualsFloat(1.0, dashed.strokeWidth);
        TracedAssertions.assertEqualsFloat(4.0, dashed.dashLength);
        TracedAssertions.assertEqualsFloat(2.0, dashed.gapLength);
        TextModelCoverageTestHelpers.assertRendered(dashed.toString());

        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dashed(0.0, 4.0, 2.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dashed(-1.0, 4.0, 2.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dashed(0.0 / 0.0, 4.0, 2.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dashed(Math.POSITIVE_INFINITY, 4.0, 2.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dashed(1.0, 0.0, 2.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dashed(1.0, -1.0, 2.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dashed(1.0, 0.0 / 0.0, 2.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dashed(1.0, Math.POSITIVE_INFINITY, 2.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dashed(1.0, 4.0, 0.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dashed(1.0, 4.0, -1.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dashed(1.0, 4.0, 0.0 / 0.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dashed(1.0, 4.0, Math.POSITIVE_INFINITY));

        final dotted:Dotted = new Dotted(2.0, 3.0);
        TracedAssertions.assertEqualsFloat(2.0, dotted.dotDiameter);
        TracedAssertions.assertEqualsFloat(3.0, dotted.gapLength);
        TextModelCoverageTestHelpers.assertRendered(dotted.toString());
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dotted(0.0, 3.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dotted(-1.0, 3.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dotted(0.0 / 0.0, 3.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dotted(Math.POSITIVE_INFINITY, 3.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dotted(2.0, 0.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dotted(2.0, -1.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dotted(2.0, 0.0 / 0.0));
        TextModelCoverageTestHelpers.expectArgumentFailure(() -> new Dotted(2.0, Math.POSITIVE_INFINITY));

        final linkRole:RichTextRole = new Link("https://tiqian.org");
        TracedAssertions.assertEqualsString("https://tiqian.org", TextModelCoverageTestHelpers.linkTarget(linkRole));
        TracedAssertions.assertEqualsRendered("Link(target=https://tiqian.org)", TextModelCoverageTestHelpers.roleName(linkRole));
        TracedAssertions.assertTrue(true);

        final roles:Array<RichTextRole> = [
            Background.instance,
            Underline.instance,
            LineThrough.instance,
            linkRole,
            TechnicalInline.instance,
            InlineCode.instance
        ];
        var roleIndex:Int = 0;
        while (roleIndex < roles.length) {
            final role:RichTextRole = roles[roleIndex];
            final span:RichTextSpan = new RichTextSpan(new TextRange(0, 2), role, paint);
            TracedAssertions.assertEqualsRendered(TextModelCoverageTestHelpers.roleName(role), TextModelCoverageTestHelpers.roleName(span.role));
            TextModelCoverageTestHelpers.assertRendered(span.toString());
            roleIndex += 1;
        }
    }

    @:test
    public static function testRubyAndParagraphModels():Void {
        new TestTraceRecorder("TextModelCoverageTest").section("testRubyAndParagraphModels");
        final pinyin = RubyKind.Pinyin;
        TracedAssertions.assertNotNullRendered(pinyin != null, pinyin == null ? "-" : Std.string(pinyin));
        final bopomofo = RubyKind.Bopomofo;
        TracedAssertions.assertNotNullRendered(bopomofo != null, bopomofo == null ? "-" : Std.string(bopomofo));
        final perLine = RubyLineHeightMode.PerLine;
        TracedAssertions.assertNotNullRendered(perLine != null, perLine == null ? "-" : Std.string(perLine));
        final uniformParagraph = RubyLineHeightMode.UniformParagraph;
        TracedAssertions.assertNotNullRendered(uniformParagraph != null, uniformParagraph == null ? "-" : Std.string(uniformParagraph));

        final pinyinRuby:RubySpan = new RubySpan(new TextRange(0, 1), "h\u00E0n", ["CustomFont"], RubyKind.Pinyin, null);
        TracedAssertions.assertEqualsRendered(Std.string(RubyKind.Pinyin), Std.string(pinyinRuby.kind));
        final pinyinLocale = pinyinRuby.locale;
        TracedAssertions.assertNullRendered(pinyinLocale == null, pinyinLocale == null ? "-" : TestTraceRender.renderString(pinyinLocale));

        final bopomofoRuby:RubySpan = new RubySpan(new TextRange(0, 1), "\u310F\u3122\u02CB", [], RubyKind.Bopomofo, null);
        TracedAssertions.assertEqualsRendered(Std.string(RubyKind.Bopomofo), Std.string(bopomofoRuby.kind));
        TracedAssertions.assertEqualsString("zh-TW", bopomofoRuby.locale);
        TextModelCoverageTestHelpers.assertRendered(bopomofoRuby.toString());

        TracedAssertions.assertEqualsFloat(0.1, ParagraphStyle.DEFAULT_EMPHASIS_DOT_GAP_EM);
        TracedAssertions.assertEqualsFloat(0.1, ParagraphStyle.DEFAULT_INLINE_OBJECT_MINIMUM_CLEARANCE_EM);

        final alignmentStart = LastLineAlignment.Start;
        TracedAssertions.assertNotNullRendered(alignmentStart != null, alignmentStart == null ? "-" : Std.string(alignmentStart));
        final alignmentCenter = LastLineAlignment.Center;
        TracedAssertions.assertNotNullRendered(alignmentCenter != null, alignmentCenter == null ? "-" : Std.string(alignmentCenter));
        final alignmentEnd = LastLineAlignment.End;
        TracedAssertions.assertNotNullRendered(alignmentEnd != null, alignmentEnd == null ? "-" : Std.string(alignmentEnd));
        final horizontalTb = WritingMode.HorizontalTb;
        TracedAssertions.assertNotNullRendered(horizontalTb != null, horizontalTb == null ? "-" : Std.string(horizontalTb));
        final verticalRl = WritingMode.VerticalRl;
        TracedAssertions.assertNotNullRendered(verticalRl != null, verticalRl == null ? "-" : Std.string(verticalRl));

        final adaptiveIndent:MeasureAdaptiveFirstLineIndent = new MeasureAdaptiveFirstLineIndent(14.0, 1.0, 2.0);
        TracedAssertions.assertEqualsFloat(1.0, adaptiveIndent.resolveEm(10.0));
        TracedAssertions.assertEqualsFloat(2.0, adaptiveIndent.resolveEm(14.0));
        TracedAssertions.assertEqualsFloat(2.0, adaptiveIndent.resolveEm(20.0));
        TextModelCoverageTestHelpers.assertRendered(adaptiveIndent.toString());

        final grid:LineLengthGrid = new LineLengthGrid(true, LastLineAlignment.Center);
        TracedAssertions.assertTrue(grid.enabled);
        final gridAlignment = grid.bodyAlignment;
        TracedAssertions.assertEqualsRendered(Std.string(LastLineAlignment.Center), gridAlignment == null ? "null" : Std.string(gridAlignment));
        TextModelCoverageTestHelpers.assertRendered(grid.toString());

        final paraStyle:ParagraphStyle = new ParagraphStyle(LastLineAlignment.End, WritingMode.VerticalRl, 32.0, null, Ic.Zero, adaptiveIndent, grid,
            RubyLineHeightMode.UniformParagraph, 0.2, 0.15);
        TracedAssertions.assertEqualsRendered(Std.string(LastLineAlignment.End), Std.string(paraStyle.lastLineAlignment));
        TracedAssertions.assertEqualsRendered(Std.string(WritingMode.VerticalRl), Std.string(paraStyle.writingMode));
        TracedAssertions.assertEqualsFloat(32.0, paraStyle.lineHeight);
        TracedAssertions.assertEqualsRendered(Std.string(RubyLineHeightMode.UniformParagraph), Std.string(paraStyle.rubyLineHeightMode));
        TextModelCoverageTestHelpers.assertRendered(paraStyle.toString());

        final profileId:LayoutProfileId = new LayoutProfileId("custom-profile");
        TracedAssertions.assertEqualsString("custom-profile", profileId.value);
        TracedAssertions.assertEqualsString("clreq-horizontal", BuiltInLayoutProfiles.ClreqHorizontal.value);
        TextModelCoverageTestHelpers.assertRendered(profileId.toString());

        final layoutInput:LayoutInput = new LayoutInput(new TiqianTextContent("Test", [], [], [], []),
            new TextStyle([], 16.0, "zh-Hans", 400, false, 0.0, InlineAttachment.None), paraStyle,
            new LayoutConstraints(300.0, Math.POSITIVE_INFINITY, 2147483647), profileId, [new DecorationSpan(new TextRange(0, 2), DecorationKind.Emphasis)],
            [pinyinRuby], [new InlineBoxSpan(new TextRange(0, 1), 0.0, 0.0, InlineBoxOuterSpacing.Narrow)], [
                new InlineObjectSpan(new TextRange(0, 1), 10.0, 8.0, 2.0, InlineObjectBoundaryAdjustment.fixed(), InlineObjectBoundaryAdjustment.fixed())
            ]);
        TracedAssertions.assertEqualsRendered(profileId.toString(), layoutInput.profileId.toString());
        TextModelCoverageTestHelpers.assertRendered(layoutInput.toString());
    }
}

class TextModelCoverageTestHelpers {
    public static function expectArgumentFailure(block:() -> Void):Void {
        TracedAssertions.assertFailsWith(null, block);
    }

    public static function assertRendered(rendered:String):Void {
        TracedAssertions.assertEqualsRendered(rendered, rendered);
        TracedAssertions.assertTrue(true);
    }

    public static function renderStrings(values:ReadOnlyArray<String>):String {
        var output:String = "[";
        var index:Int = 0;
        while (index < values.length) {
            if (index > 0) {
                output += ", ";
            }
            output += "'" + values[index] + "'";
            index += 1;
        }
        return output + "]";
    }

    public static function roleName(role:RichTextRole):String {
        if (Std.isOfType(role, Background))
            return "Background";
        if (Std.isOfType(role, Underline))
            return "Underline";
        if (Std.isOfType(role, LineThrough))
            return "LineThrough";
        if (Std.isOfType(role, Link))
            return "Link(target=" + (cast(role, Link)).target + ")";
        if (Std.isOfType(role, TechnicalInline))
            return "TechnicalInline";
        return "InlineCode";
    }

    public static function linkTarget(role:RichTextRole):String {
        if (Std.isOfType(role, Link))
            return (cast(role, Link)).target;
        return "";
    }
}
