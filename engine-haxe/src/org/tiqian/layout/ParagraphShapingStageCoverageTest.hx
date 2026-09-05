package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.layout.ClusterRoleResolution.ResolvedClusterRange;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.ParagraphShapingStageCoverageTestSupport.ParagraphCoverageHyphenator;
import org.tiqian.layout.ParagraphShapingStageCoverageTestSupport.ParagraphDeficientDashShaper;
import org.tiqian.layout.ParagraphShapingStageCoverageTestSupport.ParagraphEmptyClusterShaper;
import org.tiqian.layout.ParagraphShapingStageCoverageTestSupport.ParagraphEmptyHyphenShaper;
import org.tiqian.layout.ParagraphShapingStageCoverageTestSupport.ParagraphMultiClusterShaper;
import org.tiqian.layout.ParagraphShapingStageCoverageTestSupport.ParagraphMultiGlyphShaper;
import org.tiqian.layout.ParagraphShapingStageCoverageTestSupport.ParagraphRollbackShaper;
import org.tiqian.layout.ParagraphShapingStageCoverageTestSupport.ParagraphSufficientDashShaper;
import org.tiqian.layout.ParagraphShapingStageCoverageTestSupport.ParagraphTierHyphenator;
import org.tiqian.layout.ParagraphShapingStageCoverageTestSupport.ParagraphWordShaper;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.WidthIndependentAnnotationCache.WidthIndependentAnnotationCacheFns;
import std.SortedMap;
import std.SortedSet;
import org.tiqian.font.FontPolicy.FontCandidate;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.font.FontRole;
import org.tiqian.shaping.TextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.shaping.TextShaper.ExplainableStubTextShaper;
import org.tiqian.clreq.ClreqPunctuationGlyphSubstitutor;
import org.tiqian.linebreak.Hyphenator;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TestTraceRender;
import org.tiqian.test.trace.TracedAssertions;

class ParagraphShapingStageCoverageTest {
    @:test public static function clusterPredicatesAndCurlyQuoteFeatures():Void {
        var r = ParagraphShapingStageCoverageTestSupport.begin("clusterPredicatesAndCurlyQuoteFeatures");
        var a = new Cluster(new TextRange(0, 1), "\n", "mandatory-break", 0.0, "");
        TracedAssertions.assertTrue(ParagraphShapingStage.isMandatoryBreakCluster(a));
        TracedAssertions.assertFalse(ParagraphShapingStage.isZeroWidthSoftBreakCluster(a));
        TracedAssertions.assertFalse(ParagraphShapingStage.isInlineObjectCluster(a));
        var b = new Cluster(new TextRange(0, 1), "\u200B", "zero-width-space", 0.0, "");
        TracedAssertions.assertTrue(ParagraphShapingStage.isZeroWidthSoftBreakCluster(b));
        TracedAssertions.assertFalse(ParagraphShapingStage.isMandatoryBreakCluster(b));
        var c = new Cluster(new TextRange(0, 1), "x", "inline-object", 20.0, "");
        TracedAssertions.assertTrue(ParagraphShapingStage.isInlineObjectCluster(c));
        TracedAssertions.assertFalse(ParagraphShapingStage.isMandatoryBreakCluster(c));
        var d = new Cluster(new TextRange(0, 1), "\u4E2D", "font", 16.0, "\u4E2D");
        TracedAssertions.assertFalse(ParagraphShapingStage.isMandatoryBreakCluster(d));
        TracedAssertions.assertFalse(ParagraphShapingStage.isZeroWidthSoftBreakCluster(d));
        TracedAssertions.assertFalse(ParagraphShapingStage.isInlineObjectCluster(d));
        ParagraphShapingStageCoverageTestSupport.layout(ParagraphShapingStageCoverageTestSupport.engine(),
            "\u201C\u53CC\u5F15\u53F7\u201D\u4E0E\u2018\u5355\u5F15\u53F7\u2019", 300.0);
    }

    @:test public static function dashSubstitutionRollbackAndCoverageBranches():Void {
        var r = ParagraphShapingStageCoverageTestSupport.begin("dashSubstitutionRollbackAndCoverageBranches");
        for (e in [
            ParagraphShapingStageCoverageTestSupport.engine(new ParagraphDeficientDashShaper()),
            ParagraphShapingStageCoverageTestSupport.engine(new ParagraphSufficientDashShaper()),
            ParagraphShapingStageCoverageTestSupport.engine(new ParagraphRollbackShaper()),
            ParagraphShapingStageCoverageTestSupport.engine(new ParagraphMultiGlyphShaper()),
            ParagraphShapingStageCoverageTestSupport.engine(new ParagraphMultiGlyphShaper()),
            ParagraphShapingStageCoverageTestSupport.engine(new ParagraphMultiGlyphShaper()),
            ParagraphShapingStageCoverageTestSupport.engine(new ParagraphMultiGlyphShaper())
        ])
            ParagraphShapingStageCoverageTestSupport.layout(e, e.textShaper is ParagraphRollbackShaper ? "\u2026\u2026" : "\u2014\u2014", 300.0);
    }

    @:test public static function directShapeParagraphEdgeCases():Void {
        var r = ParagraphShapingStageCoverageTestSupport.begin("directShapeParagraphEdgeCases");
        var text = "abcdef abcdeg antidisestablishmentarianism singlecluster Machine2Machine /a/b/c 12(3):. 12a(3):45 12(3a):45 12(3):-45 12(3):45- 12(3):45-6a 12(3):4a-65 12(3):abc aaaaaa111111 a1b2c3d4e5f6 http://example.com/foo https://example.com/foo?a=1&b=2#x%20~y abc.d abc.12 abc.de abc.de12 --.com foo.-bar /start end/ a/b a//b";
        var e = ParagraphShapingStageCoverageTestSupport.engine(new ParagraphEmptyClusterShaper(), new ParagraphCoverageHyphenator());
        var i = ParagraphShapingStageCoverageTestSupport.input(text, 1, [new LineBreakSpan(new TextRange(0, 10), LineBreakPolicy.ProgressiveTechnical)]);
        var p1 = ParagraphShapingStageCoverageTestSupport.paragraph(e, i, text, 1, FontRole.LatinText, true);
        TracedAssertions.assertNotNullRendered(p1 != null, TestTraceRender.cap(p1 == null ? "null" : Std.string(p1)));
        var p2 = ParagraphShapingStageCoverageTestSupport.paragraph(e, i, text, 40, FontRole.CjkText);
        TracedAssertions.assertNotNullRendered(p2 != null, TestTraceRender.cap(p2 == null ? "null" : Std.string(p2)));
        var si = ParagraphShapingStageCoverageTestSupport.input(" ", 100);
        var p3 = ParagraphShapingStageCoverageTestSupport.paragraph(e, si, " ", 100, FontRole.LatinText);
        TracedAssertions.assertNotNullRendered(p3 != null, TestTraceRender.cap(p3 == null ? "null" : Std.string(p3)));
    }

    @:test public static function hyphenAdvanceFallbackWhenShaperReturnsEmptyClusters():Void {
        var r = ParagraphShapingStageCoverageTestSupport.begin("hyphenAdvanceFallbackWhenShaperReturnsEmptyClusters");
        ParagraphShapingStageCoverageTestSupport.layout(ParagraphShapingStageCoverageTestSupport.engine(new ParagraphEmptyHyphenShaper()),
            "supercalifragilisticexpialidocious", 50.0);
    }

    @:test public static function latinSegmentationAndCutsBranches():Void {
        var r = ParagraphShapingStageCoverageTestSupport.begin("latinSegmentationAndCutsBranches");
        var e = ParagraphShapingStageCoverageTestSupport.engine(null, new ParagraphCoverageHyphenator(1));
        ParagraphShapingStageCoverageTestSupport.layout(e,
            "Text with ,Hello Machine2Machine XMLHttp HTTPServer TeX/LaTeX /start end/ /a a/ a/b https://example.com/path www.test.org sub.domain.co .com a. a..b a.b --.com test.-com test.c test.123 test.co123 12(3):45 12(3):45. 12(3):45-50 12(3):45\u201350 (1):2 a(1):2 1():2 1(2)a:3 1(2): 1(2):a-b 1(2):-5 1(2):5- 1(2):a 12():34 12(34): a(b):c-d 12(3):. 12a(3):45 12(3a):45 12(3):-45 12(3):45- 12(3):45-6a 12(3):4a-65 12(3):abc hyphenatedword VERYLONGALLCAPSWORDTHATISNOTANABBREVIATIONANDSHOULDBEOPAQ",
            80);
        ParagraphShapingStageCoverageTestSupport.layout(e, "antidisestablishmentarianism abc def xyz", 30);
        ParagraphShapingStageCoverageTestSupport.layout(e, "semi-conductor co-19 a-b 3-4 COVID-19 cross-module-link", 80);
        ParagraphShapingStageCoverageTestSupport.layout(e, "aaaaaaaaaaaaaaaa 0123456789abcdef a1b2c3d4e5f6g7h8 aaaaaa111111 aaaaaaaaaaaa1 a1", 100);
        ParagraphShapingStageCoverageTestSupport.layout(e, "aBc ABc abC myIdentifier XML fooBAR aBC XMLHTTP", 100);
    }

    @:test public static function latinSeparatorCutsAndSolidusBranches():Void {
        var r = ParagraphShapingStageCoverageTestSupport.begin("latinSeparatorCutsAndSolidusBranches");
        var e = ParagraphShapingStageCoverageTestSupport.engine();
        var t = "http://example.com/path a/b /start end/ a//b foo_bar";
        ParagraphShapingStageCoverageTestSupport.layout(e, t, 500);
        ParagraphShapingStageCoverageTestSupport.layout(e, t, 1);
    }

    @:test public static function latinSeparatorCutsExhaustiveBranches():Void {
        var r = ParagraphShapingStageCoverageTestSupport.begin("latinSeparatorCutsExhaustiveBranches");
        var t = "12(3):45-67 12(3):45\u201367 12(3):45\u201467 12(3):45 12(3):. 12():45 12(3): :(3):45 12(3):- 12(3):45- 12(3):4a-65 12(3):45-6a 12(3):abc http://example.com/a/b/c https://test.org:8080/foo?bar=1&baz=2#frag%20~val+1*2|3;4,5.6-7_8";
        var e = ParagraphShapingStageCoverageTestSupport.engine(null, new ParagraphCoverageHyphenator(1));
        ParagraphShapingStageCoverageTestSupport.layout(e, t, 500);
        ParagraphShapingStageCoverageTestSupport.layout(e, t, 10);
    }

    @:test public static function latinSeparatorTokensCoverUrlLeadingSlashAndDashLocators():Void {
        var r = ParagraphShapingStageCoverageTestSupport.begin("latinSeparatorTokensCoverUrlLeadingSlashAndDashLocators");
        var e = ParagraphShapingStageCoverageTestSupport.engine();
        for (t in ["//example.com/a", "12(3):45\u201367", "12(3):45\u201467"]) {
            var i = ParagraphShapingStageCoverageTestSupport.input(t, 500);
            for (m in [500.0, 8.0]) {
                var p = ParagraphShapingStageCoverageTestSupport.paragraph(e, i, t, m, FontRole.LatinText);
                TracedAssertions.assertNotNullRendered(p != null, TestTraceRender.cap(p == null ? "null" : Std.string(p)));
            }
        }
    }

    @:test public static function latinWordCutsLoHiAndEmptyBranches():Void {
        var r = ParagraphShapingStageCoverageTestSupport.begin("latinWordCutsLoHiAndEmptyBranches");
        ParagraphShapingStageCoverageTestSupport.layout(ParagraphShapingStageCoverageTestSupport.engine(new ParagraphWordShaper(),
            new ParagraphCoverageHyphenator(1)), "abcdef ghijkl mnopqr empty", 1);
    }

    @:test public static function mapToClusterRangeWithZeroAndPositiveAdvance():Void {
        var r = ParagraphShapingStageCoverageTestSupport.begin("mapToClusterRangeWithZeroAndPositiveAdvance");
        var c = new Cluster(new TextRange(0, 4), "test", "k", 20.0, "test");
        for (g in [
            [new Glyph(1, new TextRange(0, 2), 0, 0), new Glyph(2, new TextRange(2, 4), 0, 0)],
            [
                new Glyph(1, new TextRange(0, 2), 8, 0),
                new Glyph(2, new TextRange(2, 4), 12, 8)
            ]
        ]) {
            var m = ParagraphShapingStage.mapToClusterRange(g, c);
            TracedAssertions.assertEqualsInt(2, m.length);
            TracedAssertions.assertEqualsFloat(g[0].advance <= 0 ? 10 : g[0].advance, m[0].advance);
            TracedAssertions.assertEqualsFloat(g[1].advance <= 0 ? 10 : g[1].advance, m[1].advance);
            if (g[0].advance <= 0)
                TracedAssertions.assertEqualsRendered(Std.string(new TextRange(0, 4)), Std.string(m[0].clusterRange));
        }
    }

    @:test public static function multiClusterShaperForWordCutsAndOpaqueHardCuts():Void {
        var r = ParagraphShapingStageCoverageTestSupport.begin("multiClusterShaperForWordCutsAndOpaqueHardCuts");
        ParagraphShapingStageCoverageTestSupport.layout(ParagraphShapingStageCoverageTestSupport.engine(new ParagraphMultiClusterShaper(),
            new ParagraphCoverageHyphenator(2)),
            "antidisestablishmentarianism some_opaque_token_with_separators/and/more", 20);
    }

    @:test public static function progressiveTechnicalSpanBreaksAndTiers():Void {
        var r = ParagraphShapingStageCoverageTestSupport.begin("progressiveTechnicalSpanBreaksAndTiers");
        var t = "Machine2Machine /v2.0_alpha=beta&gamma supercalifragilisticexpialidocious short";
        var e = ParagraphShapingStageCoverageTestSupport.engine(null, new ParagraphTierHyphenator());
        var i = ParagraphShapingStageCoverageTestSupport.input(t, 80, [
            new LineBreakSpan(new TextRange(0, t.length), LineBreakPolicy.ProgressiveTechnical),
            new LineBreakSpan(new TextRange(5, 10), LineBreakPolicy.ProgressiveTechnical)
        ]);
        var key = new TextRange(0, t.length);
        for (tier in [
            ProgressiveBreakTier.Structural,
            ProgressiveBreakTier.Syllable,
            ProgressiveBreakTier.Emergency
        ]) {
            var ti:Int = tier;
            var tiers = SortedSet.builder();
            tiers.put(ti);
            var m = SortedMap.builder();
            m.put(key, tiers.build());
            var ann = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(e, i, m.build());
            var prep = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(e, i, ann, m.build());
            TracedAssertions.assertNotNullRendered(prep != null, TestTraceRender.cap(prep == null ? "null" : "ParagraphLayoutPrep@identity"));
        }
        var annEmpty = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(e, i, SortedMap.builder().build());
        var multi = SortedSet.builder();
        multi.put((ProgressiveBreakTier.Structural : Int));
        multi.put((ProgressiveBreakTier.Syllable : Int));
        var mm = SortedMap.builder();
        mm.put(key, multi.build());
        var prepMulti = WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(e, i, annEmpty, mm.build());
        TracedAssertions.assertNotNullRendered(prepMulti != null, TestTraceRender.cap(prepMulti == null ? "null" : "ParagraphLayoutPrep@identity"));
    }

    @:test public static function progressiveTechnicalTierPriorityAndFalseBranches():Void {
        var r = ParagraphShapingStageCoverageTestSupport.begin("progressiveTechnicalTierPriorityAndFalseBranches");
        var t = "abcdef/ghijkl";
        {
            var p = ParagraphShapingStageCoverageTestSupport.paragraphRanges(ParagraphShapingStageCoverageTestSupport.engine(null,
                new ParagraphCoverageHyphenator(2)),
                ParagraphShapingStageCoverageTestSupport.input(t, 10), t, 10, [
                    new ResolvedClusterRange(new TextRange(0, 7), FontRole.LatinText, false, false),
                    new ResolvedClusterRange(new TextRange(2, 7), FontRole.LatinText, false, false)
                ], [new TextRange(0, 7), new TextRange(2, 7)]);
            TracedAssertions.assertNotNullRendered(p != null, TestTraceRender.cap(p == null ? "null" : Std.string(p)));
        }
    }

    @:test public static function progressiveTierLoopRevisitsOffsetsWithLowerPriorityTiers():Void {
        var r = ParagraphShapingStageCoverageTestSupport.begin("progressiveTierLoopRevisitsOffsetsWithLowerPriorityTiers");
        {
            var p = ParagraphShapingStageCoverageTestSupport.paragraphRanges(ParagraphShapingStageCoverageTestSupport.engine(null,
                new ParagraphCoverageHyphenator(2)),
                ParagraphShapingStageCoverageTestSupport.input("abcdef/", 4), "abcdef/", 4, [
                    new ResolvedClusterRange(new TextRange(0, 7), FontRole.LatinText, false, false),
                    new ResolvedClusterRange(new TextRange(2, 7), FontRole.LatinText, false, false)
                ], [new TextRange(0, 7), new TextRange(2, 7)]);
            TracedAssertions.assertNotNullRendered(p != null, TestTraceRender.cap(p == null ? "null" : Std.string(p)));
        }
    }
}
