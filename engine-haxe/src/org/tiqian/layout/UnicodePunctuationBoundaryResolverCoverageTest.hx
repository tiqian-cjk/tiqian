package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.ContextualKinsokuDecisionInfo;
import org.tiqian.core.EastAsianSpacingEdges;
import org.tiqian.core.EastAsianSpacingValue;
import org.tiqian.core.InlineAttachment;
import org.tiqian.core.IntRange;
import org.tiqian.core.TextRange;
import org.tiqian.font.FontRole;
import org.tiqian.layout.QuotePairAnalyzer.QuotePair;
import org.tiqian.layout.QuotePairAnalyzer.QuoteType;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedSet;

class UnicodePunctuationBoundaryResolverCoverageSupport {
    public static function start(n:String):Void
        new TestTraceRecorder("UnicodePunctuationBoundaryResolverCoverageTest").section(n);

    public static function cjkClusters(t:String):Array<Cluster> {
        var a:Array<Cluster> = [];
        var i = 0;
        while (i < t.length) {
            final s = t.substring(i, i + 1);
            a.push(new Cluster(new TextRange(i, i + 1), s, "cjk", 16.0));
            i++;
        }
        return a;
    }

    public static function latinClusters(t:String):Array<Cluster> {
        var a:Array<Cluster> = [];
        var i = 0;
        while (i < t.length) {
            final s = t.substring(i, i + 1);
            a.push(new Cluster(new TextRange(i, i + 1), s, "latin", 8.0));
            i++;
        }
        return a;
    }

    public static function cjkRoles(t:String):Array<FontRole> {
        var a:Array<FontRole> = [];
        var i = 0;
        while (i < t.length) {
            a.push(FontRole.CjkText);
            i++;
        }
        return a;
    }

    public static function latinRoles(t:String):Array<FontRole> {
        var a:Array<FontRole> = [];
        var i = 0;
        while (i < t.length) {
            a.push(FontRole.LatinText);
            i++;
        }
        return a;
    }

    public static function surrogate(codes:Array<Int>):String {
        var s = "";
        var i = 0;
        while (i < codes.length) {
            s += String.fromCharCode(codes[i]);
            i++;
        }
        return s;
    }

    public static function mapText(m:std.SortedMap<Int, Int>):String {
        var s = "{";
        var i = 0;
        while (i < m.size()) {
            if (i > 0)
                s += ", ";
            s += m.keyAt(i) + "=" + m.get(m.keyAt(i));
            i++;
        }
        return s + "}";
    }
}

class UnicodePunctuationBoundaryResolverCoverageTest {
    @:test public static function resolveAttachedInlineVirtualBoundariesWithMultiplePrevious():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineVirtualBoundariesWithMultiplePrevious");
        final attachments:Array<InlineAttachment> = [
            InlineAttachment.None,
            InlineAttachment.Previous,
            InlineAttachment.Previous,
            InlineAttachment.None
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveAttachedInlineVirtualBoundaries(attachments);
        TracedAssertions.assertEquals(1, r.length);
        TracedAssertions.assertEquals(0, r[0].previousClusterIndex);
        TracedAssertions.assertEqualsIntRange(new IntRange(1, 2), r[0].attachedClusterRange);
        TracedAssertions.assertEquals(3, r[0].nextClusterIndex);
    }

    @:test public static function resolveAttachedInlineVirtualBoundariesWithNoPrevious():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineVirtualBoundariesWithNoPrevious");
        final attachments:Array<InlineAttachment> = [InlineAttachment.None, InlineAttachment.None];
        final r = UnicodePunctuationBoundaryResolver.resolveAttachedInlineVirtualBoundaries(attachments);
        TracedAssertions.assertEquals(0, r.length);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithOpenPunctuation():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithOpenPunctuation");
        final text = "\uFF08\u4E2D\u6587\uFF09";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        var found = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineEnd") {
                found = true;
                break;
            }
            i++;
        }
        TracedAssertions.assertTrue(found);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithPairedQuotes():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithPairedQuotes");
        final text = "\u4E2D\u6587\u201C\u4F60\u597D\u201D\u4E2D\u6587";
        final pairs:Array<QuotePair> = [new QuotePair(2, 5, QuoteType.Double)];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), pairs);
        var a = false;
        var b = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].reason == "Uax14WesternPunctuationBoundary:PairedOpeningQuote")
                a = true;
            if (r.decisions[i].reason == "Uax14WesternPunctuationBoundary:PairedClosingQuote")
                b = true;
            i++;
        }
        TracedAssertions.assertTrue(a);
        TracedAssertions.assertTrue(b);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithUnmatchedClosingPunctuation():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithUnmatchedClosingPunctuation");
        final text = "\u4E2D\u3002";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithCjkClosingAtLineStart():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithCjkClosingAtLineStart");
        final text = "\u3002\uFF0C";
        final pairs:Array<QuotePair> = [new QuotePair(0, 1, QuoteType.Single)];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), pairs);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineEnd")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithExclamationMark():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithExclamationMark");
        final text = "\u4E2D!\u4E2D";
        final clusters:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "\u4E2D", "cjk", 16.0),
            new Cluster(new TextRange(1, 2), "!", "latin", 16.0),
            new Cluster(new TextRange(2, 3), "\u4E2D", "cjk", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, clusters,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineStart")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithInitialQuoteForbidLineEnd():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithInitialQuoteForbidLineEnd");
        final text = "\u4E2D\u201C\u4E2D";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineEnd")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithUnresolvedQuote():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithUnresolvedQuote");
        final text = "\u4E2D\u2019\u4E2D";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineStart")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithMultipleClusters():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithMultipleClusters");
        final text = "\u4E2D\u6587\uFF0C\u4E2D\u6587";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineStart")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithEmptyClusters():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithEmptyClusters");
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries("", [], [], []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithAllCjkText():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithAllCjkText");
        final text = "\u4E2D\u6587\u6587\u6587";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        TracedAssertions.assertEquals(0, r.decisions.length);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithWesternClosingForbidLineStart():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithWesternClosingForbidLineStart");
        final text = "\u4E2D)\u4E2D";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "\u4E2D", "cjk", 16.0),
            new Cluster(new TextRange(1, 2), ")", "latin", 16.0),
            new Cluster(new TextRange(2, 3), "\u4E2D", "cjk", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithCjkClosingForbidLineStart():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithCjkClosingForbidLineStart");
        final text = "\u4E2D\u3002\u4E2D";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithOpenPunctuationForbidLineEnd():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithOpenPunctuationForbidLineEnd");
        final text = "\uFF08\u4E2D\u6587";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineEnd")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithPunctuationAndSpace():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithPunctuationAndSpace");
        final text = "\u4E2D \u3002";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "\u4E2D", "cjk", 16.0),
            new Cluster(new TextRange(1, 2), " ", "latin", 16.0),
            new Cluster(new TextRange(2, 3), "\u3002", "cjk", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineStart")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundary():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundary");
        final text = "\n\uFF08\u4E2D\u6587";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        var hit:ContextualKinsokuDecisionInfo = null;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].sourceText == "\uFF08" && r.decisions[i].forbiddenPosition == "LineStart") {
                hit = r.decisions[i];
                break;
            }
            i++;
        }
        TracedAssertions.assertEqualsRendered("-", hit == null ? "-" : Std.string(hit));
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithClosePunctuationClass():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithClosePunctuationClass");
        final text = "\u4E2D\u3002";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithInfixNumericSeparator():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithInfixNumericSeparator");
        final text = "1\uFF0C2";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "1", "latin", 8.0),
            new Cluster(new TextRange(1, 2), "\uFF0C", "cjk", 16.0),
            new Cluster(new TextRange(2, 3), "2", "latin", 8.0)
        ];
        final roles:Array<FontRole> = [FontRole.LatinText, FontRole.CjkPunctuation, FontRole.LatinText];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, roles, []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithDecimalMarkAfterSpace():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithDecimalMarkAfterSpace");
        final text = "1 \uFF0C2";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "1", "latin", 8.0),
            new Cluster(new TextRange(1, 2), " ", "latin", 8.0),
            new Cluster(new TextRange(2, 3), "\uFF0C", "cjk", 16.0),
            new Cluster(new TextRange(3, 4), "2", "latin", 8.0)
        ];
        final roles:Array<FontRole> = [
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.CjkPunctuation,
            FontRole.LatinText
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, roles, []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithRuleForLineStartInfix():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithRuleForLineStartInfix");
        final text = "1,2";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        var hit:ContextualKinsokuDecisionInfo = null;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].sourceText == ",") {
                hit = r.decisions[i];
                break;
            }
            i++;
        }
        TracedAssertions.assertNotNullRendered(hit != null, hit == null ? "null" : Std.string(hit));
        TracedAssertions.assertEqualsString("Uax14WesternPunctuationBoundary:LB15d", hit == null ? "" : hit.reason);
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesWithCjkBothCjk():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesWithCjkBothCjk");
        final text = "\u4E2D\u6587";
        final e:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Narrow, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Wide, false)
        ];
        final a:Array<InlineAttachment> = [InlineAttachment.None, InlineAttachment.None];
        final r = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), e,
            SortedSet.builder().build(), a);
        TracedAssertions.assertEquals(0, r.virtualBoundaryAfterClusters.size());
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesWithWesternBracket():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesWithWesternBracket");
        final text = "(\u4E2D";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "(", "latin", 8.0),
            new Cluster(new TextRange(1, 2), "\u4E2D", "cjk", 16.0)
        ];
        final roles:Array<FontRole> = [FontRole.LatinText, FontRole.CjkText];
        final e:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false)
        ];
        final a:Array<InlineAttachment> = [InlineAttachment.None, InlineAttachment.None];
        final r = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text, c, roles, e, SortedSet.builder().build(), a);
        TracedAssertions.assertEquals(0, r.virtualBoundaryAfterClusters.size());
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesWithCjkBodyWesternBracket():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesWithCjkBodyWesternBracket");
        final text = "\u4E2D)";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "\u4E2D", "cjk", 16.0),
            new Cluster(new TextRange(1, 2), ")", "latin", 8.0)
        ];
        final roles:Array<FontRole> = [FontRole.CjkText, FontRole.LatinText];
        final e:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false)
        ];
        final a:Array<InlineAttachment> = [InlineAttachment.None, InlineAttachment.None];
        final r = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text, c, roles, e, SortedSet.builder().build(), a);
        TracedAssertions.assertEquals(0, r.ordinaryWesternBoundaryAfterClusters.size());
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesRequiresMatchingClusterRoleEdgeSizes():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesRequiresMatchingClusterRoleEdgeSizes");
        final c:Array<Cluster> = [new Cluster(new TextRange(0, 1), "a", "latin", 8.0)];
        final e:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false)
        ];
        final a:Array<InlineAttachment> = [InlineAttachment.None];
        TracedAssertions.assertFailsWith(null,
            () -> UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries("ab", c, [FontRole.LatinText, FontRole.LatinText], e,
                SortedSet.builder().build(), a));
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesRequiresMatchingAttachmentSize():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesRequiresMatchingAttachmentSize");
        final text = "ab";
        final c = UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text);
        final e:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false)
        ];
        TracedAssertions.assertFailsWith(null,
            () -> UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text, c,
                UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), e, SortedSet.builder().build(), [InlineAttachment.None]));
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesPunctuationWesternNarrowTrailing():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesPunctuationWesternNarrowTrailing");
        final text = "a,\u3002";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "a", "latin", 8.0),
            new Cluster(new TextRange(1, 2), ",", "latin", 8.0),
            new Cluster(new TextRange(2, 3), "\u3002", "cjk", 16.0)
        ];
        final roles:Array<FontRole> = [FontRole.LatinText, FontRole.CjkPunctuation, FontRole.CjkPunctuation];
        final e:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Narrow, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false)
        ];
        final a:Array<InlineAttachment> = [InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None];
        final r = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text, c, roles, e, SortedSet.builder().build(), a);
        TracedAssertions.assertTrue(r.virtualBoundaryAfterClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesPreviousContentClusterReturnsNull():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesPreviousContentClusterReturnsNull");
        final text = "  !";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), " ", "test", 8.0),
            new Cluster(new TextRange(1, 2), " ", "test", 8.0),
            new Cluster(new TextRange(2, 3), "!", "test", 8.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.size() == 0);
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesPunctuationWesternTrailingNotNarrow():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesPunctuationWesternTrailingNotNarrow");
        final text = "a,\u4E2D";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "a", "latin", 8.0),
            new Cluster(new TextRange(1, 2), ",", "latin", 8.0),
            new Cluster(new TextRange(2, 3), "\u4E2D", "cjk", 16.0)
        ];
        final roles:Array<FontRole> = [FontRole.CjkPunctuation, FontRole.CjkPunctuation, FontRole.CjkText];
        final e:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false)
        ];
        final a:Array<InlineAttachment> = [InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None];
        final r = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text, c, roles, e, SortedSet.builder().build(), a);
        TracedAssertions.assertTrue(r.virtualBoundaryAfterClusters.size() > 0);
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesPunctuationWesternTrailingNarrowNotCjkPunct():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesPunctuationWesternTrailingNarrowNotCjkPunct");
        final text = "a,\u4E2D";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "a", "latin", 8.0),
            new Cluster(new TextRange(1, 2), ",", "latin", 8.0),
            new Cluster(new TextRange(2, 3), "\u4E2D", "cjk", 16.0)
        ];
        final roles:Array<FontRole> = [FontRole.LatinText, FontRole.CjkPunctuation, FontRole.CjkText];
        final e:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Narrow, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false)
        ];
        final a:Array<InlineAttachment> = [InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None];
        final r = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text, c, roles, e, SortedSet.builder().build(), a);
        TracedAssertions.assertTrue(r.virtualBoundaryAfterClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithInfixNumericSeparatorNotDecimalMark():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithInfixNumericSeparatorNotDecimalMark");
        final text = "1\uFF0C";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "1", "latin", 8.0),
            new Cluster(new TextRange(1, 2), "\uFF0C", "cjk", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, [FontRole.LatinText, FontRole.LatinText], []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithDecimalMarkAfterNonSpace():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithDecimalMarkAfterNonSpace");
        final text = "1,\uFF0C2";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "1", "latin", 8.0),
            new Cluster(new TextRange(1, 2), ",", "latin", 8.0),
            new Cluster(new TextRange(2, 3), "\uFF0C", "cjk", 16.0),
            new Cluster(new TextRange(3, 4), "2", "latin", 8.0)
        ];
        final roles:Array<FontRole> = [
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.CjkPunctuation,
            FontRole.LatinText
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, roles, []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithQuoteDirectionFinal():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithQuoteDirectionFinal");
        final text = "\u4E2D\u201D\u4E2D";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineStart")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithQuoteDirectionInitial():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithQuoteDirectionInitial");
        final text = "\u4E2D\u201C\u4E2D";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineEnd")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithQuoteDirectionUnresolved():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithQuoteDirectionUnresolved");
        final text = "\u4E2D\u00AB\u4E2D";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineEnd")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithWordApostrophe2019():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithWordApostrophe2019");
        final text = "it\u2019s";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithLatinWordCodePoint():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithLatinWordCodePoint");
        final text = "caf\u00E9";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertEquals(0, r.decisions.length);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithFirstSignificantCodePoint():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithFirstSignificantCodePoint");
        final text = "  \u201C";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineEnd")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithLastSignificantCodePoint():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithLastSignificantCodePoint");
        final text = "a\u201D  ";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineStart")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithHasAuthoredBreak():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithHasAuthoredBreak");
        final text = "\n\u201C";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithNextContentCluster():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithNextContentCluster");
        final text = "a\u201D\u4E2D";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertTrue(r.unbreakableRanges.length > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithPreviousContentClusterHasContent():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithPreviousContentClusterHasContent");
        final text = "\u4E2D\u201D";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        TracedAssertions.assertTrue(r.unbreakableRanges.length > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithClosePunctuation():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithClosePunctuation");
        final text = "\u4E2D\uFF09";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithExclamationClass():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithExclamationClass");
        final text = "\u4E2D\uFF01";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithCloseParenthesisClass():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithCloseParenthesisClass");
        final text = "\u4E2D\uFF09";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].reason.indexOf("LB13") >= 0)
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithInfixNumericSeparatorRule():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithInfixNumericSeparatorRule");
        final text = "1,2";
        final c = UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text);
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        var hit:ContextualKinsokuDecisionInfo = null;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].sourceText == ",") {
                hit = r.decisions[i];
                break;
            }
            i++;
        }
        TracedAssertions.assertNotNullRendered(hit != null, hit == null ? "null" : Std.string(hit));
        TracedAssertions.assertTrue(hit != null && hit.reason.indexOf("LB15d") >= 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithRuleForLineStartElse():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithRuleForLineStartElse");
        final text = "\u4E2D\u3001";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesWithSinoWesternPair():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesWithSinoWesternPair");
        final text = "\u4E2D\uFF0C\u4E2D";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "\u4E2D", "cjk", 16.0),
            new Cluster(new TextRange(1, 2), "\uFF0C", "cjk", 16.0),
            new Cluster(new TextRange(2, 3), "\u4E2D", "cjk", 16.0)
        ];
        final roles:Array<FontRole> = [FontRole.CjkText, FontRole.CjkPunctuation, FontRole.CjkText];
        final e:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Narrow, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Wide, false)
        ];
        final a:Array<InlineAttachment> = [InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None];
        final r = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text, c, roles, e, SortedSet.builder().build(), a);
        TracedAssertions.assertTrue(r.virtualSinoWesternBoundaryAfterClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithCodePointBeforeSupplementary():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithCodePointBeforeSupplementary");
        final text = "\u4E2D\u201D";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        TracedAssertions.assertTrue(r.decisions.length > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithEmptyRange():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithEmptyRange");
        final text = "\u4E2D";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 0), "", "cjk", 0.0),
            new Cluster(new TextRange(0, 1), "\u4E2D", "cjk", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, [FontRole.CjkText, FontRole.CjkText], []);
        TracedAssertions.assertEquals(0, r.decisions.length);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithFirstCodePointLength():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithFirstCodePointLength");
        final text = "\u4E2D";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.cjkClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.cjkRoles(text), []);
        TracedAssertions.assertEquals(0, r.decisions.length);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithIsWhitespaceCodePoint():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithIsWhitespaceCodePoint");
        final text = " \u201C";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineEnd")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundaryMandatory():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundaryMandatory");
        final text = "\r\u201C";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundaryZWSP():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundaryZWSP");
        final text = "\u200B\u201C";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithDecimalMarkFollowingInsideDigit():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithDecimalMarkFollowingInsideDigit");
        final text = " 1\uFF0C23";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), " ", "latin", 8.0),
            new Cluster(new TextRange(1, 2), "1", "latin", 8.0),
            new Cluster(new TextRange(2, 3), "\uFF0C", "cjk", 16.0),
            new Cluster(new TextRange(3, 5), "23", "latin", 8.0)
        ];
        final roles:Array<FontRole> = [
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.CjkPunctuation,
            FontRole.LatinText
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, roles, []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithDecimalMarkFollowingOutsideDigit():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithDecimalMarkFollowingOutsideDigit");
        final text = " a\uFF0C2";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), " ", "latin", 8.0),
            new Cluster(new TextRange(1, 2), "a", "latin", 8.0),
            new Cluster(new TextRange(2, 3), "\uFF0C", "cjk", 16.0),
            new Cluster(new TextRange(3, 4), "2", "latin", 8.0)
        ];
        final roles:Array<FontRole> = [FontRole.LatinText, FontRole.LatinText, FontRole.LatinText, FontRole.LatinText];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, roles, []);
        TracedAssertions.assertTrue(r.decisions.length > 0 || r.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithPreviousContentClusterHasAuthoredBreak():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithPreviousContentClusterHasAuthoredBreak");
        final text = "\n\uFF08";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.size() == 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithNextContentClusterHasAuthoredBreak():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithNextContentClusterHasAuthoredBreak");
        final text = "\u201D\n";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertTrue(r.unbreakableRanges.length == 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithIsWhitespaceCodePointNonBmp():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithIsWhitespaceCodePointNonBmp");
        final text = UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]);
        final c:Array<Cluster> = [new Cluster(new TextRange(0, 2), text, "latin", 8.0)];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, [FontRole.LatinText], []);
        TracedAssertions.assertEquals(0, r.decisions.length);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithHasAuthoredBreakBoth():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithHasAuthoredBreakBoth");
        final text = "\n\u201C\n";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertTrue(r.decisions.length > 0);
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesWithBothCjkPunctuation():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesWithBothCjkPunctuation");
        final text = "\u3001\u3002\u4E2D";
        final clusters:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "\u3001", "cjk", 16.0),
            new Cluster(new TextRange(1, 2), "\u3002", "cjk", 16.0),
            new Cluster(new TextRange(2, 3), "\u4E2D", "cjk", 16.0)
        ];
        final roles:Array<FontRole> = [FontRole.CjkPunctuation, FontRole.CjkPunctuation, FontRole.CjkText];
        final edges:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false)
        ];
        final result = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text, clusters, roles, edges, SortedSet.builder().build(),
            [InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None]);
        TracedAssertions.assertTrue(result.virtualBoundaryAfterClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundaryWhitespace():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundaryWhitespace");
        final text = " \u201C";
        final result = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertEquals(0, result.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundaryWhitespaceThenNonWhitespace():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithFollowsAuthoredBoundaryWhitespaceThenNonWhitespace");
        final text = " \u0041\u201C";
        final result = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertTrue(result.decisions.length > 0 || result.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithPreviousContentClusterEmpty():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithPreviousContentClusterEmpty");
        final text = "\u201C";
        final clusters:Array<Cluster> = [new Cluster(new TextRange(0, 1), "\u201C", "latin", 16.0)];
        final result = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, clusters, [FontRole.LatinText], []);
        TracedAssertions.assertTrue(result.decisions.length > 0
            || result.forbiddenLineStartClusters.size() > 0
            || result.unbreakableRanges.length > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithNextContentClusterEmpty():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithNextContentClusterEmpty");
        final text = "a\u201Db";
        final result = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertTrue(result.forbiddenLineStartClusters.size() > 0 || result.unbreakableRanges.length > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithCodePointAtOrNullSurrogate():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithCodePointAtOrNullSurrogate");
        final text = "\u201C" + UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]);
        final clusters:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "\u201C", "latin", 16.0),
            new Cluster(new TextRange(1, 3), UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]), "emoji", 16.0)
        ];
        final result = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, clusters, [FontRole.LatinText, FontRole.Emoji], []);
        TracedAssertions.assertTrue(result.decisions.length > 0 || result.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithHasAuthoredBreakMandatoryOnly():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithHasAuthoredBreakMandatoryOnly");
        final text = "\r\u201C";
        final result = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertEquals(0, result.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithCodePointBeforeSurrogatePair():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithCodePointBeforeSurrogatePair");
        final text = UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]) + "\u201D";
        final clusters:Array<Cluster> = [
            new Cluster(new TextRange(0, 2), UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]), "emoji", 16.0),
            new Cluster(new TextRange(2, 3), "\u201D", "latin", 16.0)
        ];
        final result = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, clusters, [FontRole.Emoji, FontRole.LatinText], []);
        TracedAssertions.assertTrue(result.decisions.length > 0 || result.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesWithCodePointAtOrNullSupplementary():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesWithCodePointAtOrNullSupplementary");
        final text = UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]) + "\u201C";
        final clusters:Array<Cluster> = [
            new Cluster(new TextRange(0, 2), UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]), "emoji", 16.0),
            new Cluster(new TextRange(2, 3), "\u201C", "latin", 16.0)
        ];
        final result = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, clusters, [FontRole.Emoji, FontRole.LatinText], []);
        TracedAssertions.assertTrue(result.decisions.length > 0 || result.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveAttachedInlineVirtualBoundariesAtStart():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineVirtualBoundariesAtStart");
        final result = UnicodePunctuationBoundaryResolver.resolveAttachedInlineVirtualBoundaries([InlineAttachment.Previous, InlineAttachment.None]);
        TracedAssertions.assertEquals(0, result.length);
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesRequiresMatchingEdgesSize():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesRequiresMatchingEdgesSize");
        final clusters:Array<Cluster> = [new Cluster(new TextRange(0, 1), "a", "latin", 8.0)];
        final edges:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false)
        ];
        TracedAssertions.assertFailsWith(null,
            () -> UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries("a", clusters, [FontRole.LatinText], edges,
                SortedSet.builder().build(), [InlineAttachment.None]));
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesPunctuationWesternLeadingNotNarrow():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesPunctuationWesternLeadingNotNarrow");
        final text = ",\u4E2Da";
        final clusters:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), ",", "cjk", 16.0),
            new Cluster(new TextRange(1, 2), "\u4E2D", "cjk", 16.0),
            new Cluster(new TextRange(2, 3), "a", "latin", 8.0)
        ];
        final edges:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false)
        ];
        final result = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text, clusters,
            [FontRole.CjkPunctuation, FontRole.CjkText, FontRole.LatinText], edges, SortedSet.builder().build(),
            [InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None]);
        TracedAssertions.assertEquals(0, result.virtualBoundaryAfterClusters.size());
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesAllConditionsFalse():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesAllConditionsFalse");
        final text = "a*b";
        final clusters:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "a", "latin", 8.0),
            new Cluster(new TextRange(1, 2), "*", "latin", 8.0),
            new Cluster(new TextRange(2, 3), "b", "latin", 8.0)
        ];
        final edges:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false)
        ];
        final result = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text, clusters,
            [FontRole.LatinText, FontRole.LatinText, FontRole.LatinText], edges, SortedSet.builder().build(),
            [InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None]);
        TracedAssertions.assertEquals(0, result.virtualBoundaryAfterClusters.size());
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesNarrowNarrowPair():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesNarrowNarrowPair");
        final text = "a*b";
        final clusters:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "a", "latin", 8.0),
            new Cluster(new TextRange(1, 2), "*", "latin", 8.0),
            new Cluster(new TextRange(2, 3), "b", "latin", 8.0)
        ];
        final edges:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Narrow, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Wide, false)
        ];
        final result = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text, clusters,
            [FontRole.LatinText, FontRole.LatinText, FontRole.LatinText], edges, SortedSet.builder().build(),
            [InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None]);
        TracedAssertions.assertEquals(0, result.virtualBoundaryAfterClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesInfixNumericSeparatorWithSpaceAndNoSpace():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesInfixNumericSeparatorWithSpaceAndNoSpace");
        var t = " .5";
        var r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t),
            UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
        t = " 1.5";
        r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t),
            UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.has(2));
        var found = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].reason == "Uax14WesternPunctuationBoundary:LB15d")
                found = true;
            i++;
        }
        TracedAssertions.assertTrue(found);
        t = ".5";
        r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t),
            UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesDecimalMarkFollowingVariations():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesDecimalMarkFollowingVariations");
        var t = ".";
        var c:Array<Cluster> = [
            new Cluster(new TextRange(0, 0), "", "latin", 0.0),
            new Cluster(new TextRange(0, 1), ".", "latin", 8.0)
        ];
        var r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, c, [FontRole.LatinText, FontRole.LatinText], []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
        t = "a .#";
        r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t),
            UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.has(2));
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].reason == "Uax14WesternPunctuationBoundary:LB15d")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
        t = "a .a";
        r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t),
            UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.has(2));
        f = false;
        i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].reason == "Uax14WesternPunctuationBoundary:LB15d")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
        t = " .5";
        c = [
            new Cluster(new TextRange(0, 1), " ", "latin", 8.0),
            new Cluster(new TextRange(1, 3), ".5", "latin", 16.0)
        ];
        r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, c, [FontRole.LatinText, FontRole.LatinText], []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesApostropheAndLatinWordBranches():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesApostropheAndLatinWordBranches");
        var t = "a\u2019 ";
        var r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t),
            UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineStart")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
        t = " \u2019a";
        r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t),
            UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        f = false;
        i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineEnd")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
        t = "\u00C0\u2019\u024F";
        r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t),
            UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
        t = "\u00BF\u2019\u4E2D";
        r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t),
            [FontRole.LatinText, FontRole.LatinText, FontRole.CjkText], []);
        f = false;
        i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineStart")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesSurrogateScanningVariations():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesSurrogateScanningVariations");
        final strings:Array<String> = [
            "a",
            UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]),
            "\u4E2D",
            "hello"
        ];
        var si = 0;
        while (si < strings.length) {
            final s = strings[si];
            final t = " " + s + ")";
            final c:Array<Cluster> = [
                new Cluster(new TextRange(0, 1), " ", "latin", 8.0),
                new Cluster(new TextRange(1, 1 + s.length), s, "latin", 16.0),
                new Cluster(new TextRange(1 + s.length, 2 + s.length), ")", "latin", 8.0)
            ];
            final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, c,
                [FontRole.LatinText, FontRole.LatinText, FontRole.LatinText], []);
            TracedAssertions.assertTrue(r.forbiddenLineStartClusters.size() > 0
                || r.decisions.length > 0
                || r.forbiddenLineEndClusters.size() > 0
                || r.unbreakableRanges.length == 0
                || r.unbreakableRanges.length > 0);
            si++;
        }
        final strings2:Array<String> = [
            "a\u2019",
            UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]) + "\u2019",
            "\u4E2D\u2019"
        ];
        si = 0;
        while (si < strings2.length) {
            final s = strings2[si];
            final t = " " + s + " ";
            final c:Array<Cluster> = [
                new Cluster(new TextRange(0, 1), " ", "latin", 8.0),
                new Cluster(new TextRange(1, 1 + s.length), s, "latin", 16.0),
                new Cluster(new TextRange(1 + s.length, 2 + s.length), " ", "latin", 8.0)
            ];
            final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, c,
                [FontRole.LatinText, FontRole.LatinText, FontRole.LatinText], []);
            TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
            si++;
        }
        var t = " " + UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]) + ".5";
        var c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), " ", "latin", 8.0),
            new Cluster(new TextRange(1, 3), UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]), "emoji", 16.0),
            new Cluster(new TextRange(3, 5), ".5", "latin", 16.0)
        ];
        var r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, c, [FontRole.LatinText, FontRole.Emoji, FontRole.LatinText], []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.has(2));
        t = "(\u200Ba";
        c = UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t);
        r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, c, UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        TracedAssertions.assertTrue(r.forbiddenLineEndClusters.has(0));
        t = "(\na";
        c = UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t);
        r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, c, UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        TracedAssertions.assertTrue(r.forbiddenLineEndClusters.has(0));
    }

    @:test public static function resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceIndexZero():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceIndexZero");
        final t = ".5";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceNonWhitespacePrev():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceNonWhitespacePrev");
        final t = "1\uFF0C2";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceEmptyPrev():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceEmptyPrev");
        final t = "a\uFF0C5";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesFollowsAuthoredBoundaryNonWhitespace():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesFollowsAuthoredBoundaryNonWhitespace");
        final t = "a\u201C";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineEnd")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesPreviousContentClusterReturnsContent():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesPreviousContentClusterReturnsContent");
        final t = "a \u201D";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        TracedAssertions.assertTrue(r.unbreakableRanges.length > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesPreviousContentClusterEmptyOnly():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesPreviousContentClusterEmptyOnly");
        final t = "\u201C";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 0), "", "latin", 0.0),
            new Cluster(new TextRange(0, 1), "\u201C", "latin", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, c, [FontRole.LatinText, FontRole.LatinText], []);
        TracedAssertions.assertTrue(r.forbiddenLineEndClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesNextContentClusterReturnsContent():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesNextContentClusterReturnsContent");
        final t = ")\u201D\u4E2D";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), ")", "latin", 8.0),
            new Cluster(new TextRange(1, 2), "\u201D", "latin", 8.0),
            new Cluster(new TextRange(2, 3), "\u4E2D", "cjk", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, c, [FontRole.LatinText, FontRole.LatinText, FontRole.CjkText], []);
        TracedAssertions.assertTrue(r.unbreakableRanges.length > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesHasAuthoredBreakWithCodePoint():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesHasAuthoredBreakWithCodePoint");
        final t = "a\n\u201C";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.size() == 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesHasAuthoredBreakNullCodePoint():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesHasAuthoredBreakNullCodePoint");
        final t = "\u201C";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        TracedAssertions.assertTrue(r.forbiddenLineEndClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesFirstCodePointLengthBmp():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesFirstCodePointLengthBmp");
        final t = "a\u201C";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(t), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(t), []);
        TracedAssertions.assertTrue(r.decisions.length > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesFirstCodePointLengthSurrogate():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesFirstCodePointLengthSurrogate");
        final t = UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]) + "\u201C";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 2), UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]), "emoji", 16.0),
            new Cluster(new TextRange(2, 3), "\u201C", "latin", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, c, [FontRole.Emoji, FontRole.LatinText], []);
        TracedAssertions.assertTrue(r.decisions.length > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesCodePointAtOrNullSurrogatePair():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesCodePointAtOrNullSurrogatePair");
        final t = UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]) + "\u201C";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 2), UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]), "emoji", 16.0),
            new Cluster(new TextRange(2, 3), "\u201C", "latin", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(t, c, [FontRole.Emoji, FontRole.LatinText], []);
        TracedAssertions.assertTrue(r.decisions.length > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesCodePointBeforeSurrogatePair():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesCodePointBeforeSurrogatePair");
        final text = UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]);
        final c:Array<Cluster> = [new Cluster(new TextRange(0, 2), text, "emoji", 16.0)];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, [FontRole.Emoji], []);
        TracedAssertions.assertEquals(0, r.decisions.length);
    }

    @:test public static function resolveUnicodePunctuationBoundariesCodePointBeforeLowSurrogate():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesCodePointBeforeLowSurrogate");
        final text = "a" + UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]);
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "a", "latin", 8.0),
            new Cluster(new TextRange(1, 3), UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]), "emoji", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, [FontRole.LatinText, FontRole.Emoji], []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesQuoteDirection2019SurrogateLeft():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesQuoteDirection2019SurrogateLeft");
        final text = UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]) + "\u2019";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 2), UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]), "emoji", 16.0),
            new Cluster(new TextRange(2, 3), "\u2019", "latin", 8.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, [FontRole.Emoji, FontRole.LatinText], []);
        TracedAssertions.assertTrue(r.decisions.length > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesPreviousContentClusterMultipleEmpty():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesPreviousContentClusterMultipleEmpty");
        final text = "a \u201D";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 0), "", "latin", 0.0),
            new Cluster(new TextRange(1, 2), " ", "latin", 8.0),
            new Cluster(new TextRange(2, 3), "\u201D", "latin", 8.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c,
            [FontRole.LatinText, FontRole.LatinText, FontRole.LatinText], []);
        TracedAssertions.assertTrue(r.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesFollowsAuthoredBoundaryZWSPInMiddle():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesFollowsAuthoredBoundaryZWSPInMiddle");
        final text = " \u200B\u201C";
        final c = UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text);
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesLastSignificantCodePointSurrogateEnding():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesLastSignificantCodePointSurrogateEnding");
        final text = UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]) + "\u201D";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 2), UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]), "emoji", 16.0),
            new Cluster(new TextRange(2, 3), "\u201D", "latin", 8.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, [FontRole.Emoji, FontRole.LatinText], []);
        TracedAssertions.assertTrue(r.forbiddenLineEndClusters.size() > 0 || r.unbreakableRanges.length > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceFollowingInside():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceFollowingInside");
        final text = "a .5";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "a", "latin", 8.0),
            new Cluster(new TextRange(1, 2), " ", "latin", 8.0),
            new Cluster(new TextRange(2, 4), ".5", "latin", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c,
            [FontRole.LatinText, FontRole.LatinText, FontRole.CjkPunctuation], []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundaryFullWidthCommaAfterSpaceStaysForbidden():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundaryFullWidthCommaAfterSpaceStaysForbidden");
        final text = "a \uFF0C5";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "a", "latin", 8.0),
            new Cluster(new TextRange(1, 2), " ", "latin", 8.0),
            new Cluster(new TextRange(2, 4), "\uFF0C5", "latin", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c,
            [FontRole.LatinText, FontRole.LatinText, FontRole.LatinText], []);
        TracedAssertions.assertEquals(1, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceFollowingOutside():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesIsDecimalMarkAfterSpaceFollowingOutside");
        final text = "a .5";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "a", "latin", 8.0),
            new Cluster(new TextRange(1, 2), " ", "latin", 8.0),
            new Cluster(new TextRange(2, 3), ".", "latin", 8.0),
            new Cluster(new TextRange(3, 4), "5", "latin", 8.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, [
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.CjkPunctuation,
            FontRole.LatinText
        ], []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesQuoteDirection2019BmpLeft():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesQuoteDirection2019BmpLeft");
        final text = "\u0041\u2019";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertTrue(r.decisions.length > 0 || r.forbiddenLineStartClusters.size() > 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesQuoteDirection2019RightWordOnly():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesQuoteDirection2019RightWordOnly");
        final text = " \u2019a";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineEnd")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesQuoteDirection2019LeftWordOnly():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesQuoteDirection2019LeftWordOnly");
        final text = "a\u2019 ";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineStart")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesQuoteDirection2019NeitherWord():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesQuoteDirection2019NeitherWord");
        final text = "!\u2019!";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        var f = false;
        var i = 0;
        while (i < r.decisions.length) {
            if (r.decisions[i].forbiddenPosition == "LineStart")
                f = true;
            i++;
        }
        TracedAssertions.assertTrue(f);
    }

    @:test public static function resolveUnicodePunctuationBoundariesCodePointBeforeLowSurrogateSingle():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesCodePointBeforeLowSurrogateSingle");
        final text = UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]);
        final c:Array<Cluster> = [new Cluster(new TextRange(0, 2), text, "emoji", 16.0)];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, [FontRole.Emoji], []);
        TracedAssertions.assertEquals(0, r.decisions.length);
    }

    @:test public static function resolveUnicodePunctuationBoundariesCodePointAtOrNullSupplementary():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesCodePointAtOrNullSupplementary");
        final text = UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]);
        final c:Array<Cluster> = [new Cluster(new TextRange(0, 2), text, "emoji", 16.0)];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, [FontRole.Emoji], []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesHasAuthoredBreakEmptyString():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesHasAuthoredBreakEmptyString");
        final text = "\u201C";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertTrue(r.forbiddenLineEndClusters.size() > 0);
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesVirtualFromCjkPunctuationLeft():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesVirtualFromCjkPunctuationLeft");
        final text = "\uFF0Cx\u6C49";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "\uFF0C", "cjk", 16.0),
            new Cluster(new TextRange(1, 2), "x", "latin", 8.0),
            new Cluster(new TextRange(2, 3), "\u6C49", "cjk", 16.0)
        ];
        final e:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Wide, false)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text, c,
            [FontRole.CjkPunctuation, FontRole.LatinText, FontRole.CjkText], e, SortedSet.builder().build(),
            [InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None]);
        TracedAssertions.assertEqualsRendered("{1=0}", UnicodePunctuationBoundaryResolverCoverageSupport.mapText(r.virtualBoundaryAfterClusters));
    }

    @:test public static function resolveUnicodePunctuationBoundariesDecimalMarkAtClusterZeroForbidden():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesDecimalMarkAtClusterZeroForbidden");
        final text = "a.5";
        final c:Array<Cluster> = [new Cluster(new TextRange(1, 3), ".5", "latin", 16.0)];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, [FontRole.LatinText], []);
        TracedAssertions.assertEquals(1, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesDecimalMarkAfterLetterClusterForbidden():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesDecimalMarkAfterLetterClusterForbidden");
        final text = "a.5";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "a", "latin", 8.0),
            new Cluster(new TextRange(1, 3), ".5", "latin", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, [FontRole.LatinText, FontRole.LatinText], []);
        TracedAssertions.assertEquals(1, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesDecimalMarkFollowedByLetterForbidden():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesDecimalMarkFollowedByLetterForbidden");
        final text = "a .x";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertEquals(1, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesDecimalMarkAloneAfterSpaceForbidden():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesDecimalMarkAloneAfterSpaceForbidden");
        final text = "a .";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertEquals(1, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesAstralTailKeepsPairAsLastSignificant():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesAstralTailKeepsPairAsLastSignificant");
        final text = "a ." + UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]);
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "a", "latin", 8.0),
            new Cluster(new TextRange(1, 2), " ", "latin", 8.0),
            new Cluster(new TextRange(2, 5), "." + UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]), "latin", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c,
            [FontRole.LatinText, FontRole.LatinText, FontRole.LatinText], []);
        TracedAssertions.assertEquals(1, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesAuthoredBreakInsidePreviousClusterDropsUnbreakable():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesAuthoredBreakInsidePreviousClusterDropsUnbreakable");
        final text = "a\nb\uFF0C";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 3), "a\nb", "latin", 24.0),
            new Cluster(new TextRange(3, 4), "\uFF0C", "latin", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, [FontRole.LatinText, FontRole.LatinText], []);
        TracedAssertions.assertEquals(1, r.forbiddenLineStartClusters.size());
        TracedAssertions.assertTrue(r.unbreakableRanges.length == 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesApostropheAtTextStartNoLeftContext():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesApostropheAtTextStartNoLeftContext");
        final text = "\u2019s";
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text,
            UnicodePunctuationBoundaryResolverCoverageSupport.latinClusters(text), UnicodePunctuationBoundaryResolverCoverageSupport.latinRoles(text), []);
        TracedAssertions.assertEquals(0, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesApostropheRightNeighbourUnpairedHighSurrogate():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesApostropheRightNeighbourUnpairedHighSurrogate");
        final text = UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0x2019, 0xD800, 0x4E2D]);
        final c:Array<Cluster> = [new Cluster(new TextRange(0, 3), text, "latin", 24.0)];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, [FontRole.LatinText], []);
        TracedAssertions.assertEquals(0, r.decisions.length);
    }

    @:test public static function resolveUnicodePunctuationBoundariesApostropheLeftNeighbourSupplementaryPair():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesApostropheLeftNeighbourSupplementaryPair");
        final text = UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]) + "\u2019";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 2), UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]), "emoji", 16.0),
            new Cluster(new TextRange(2, 3), "\u2019", "latin", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, [FontRole.Emoji, FontRole.LatinText], []);
        TracedAssertions.assertTrue(r.decisions.length > 0);
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesPunctuationWesternLeadingNarrowOnly():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesPunctuationWesternLeadingNarrowOnly");
        final text = "\uFF0Cxa";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "\uFF0C", "cjk", 16.0),
            new Cluster(new TextRange(1, 2), "x", "latin", 8.0),
            new Cluster(new TextRange(2, 3), "a", "latin", 8.0)
        ];
        final e:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Other, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Other, false)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text, c,
            [FontRole.CjkPunctuation, FontRole.LatinText, FontRole.LatinText], e, SortedSet.builder().build(),
            [InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None]);
        TracedAssertions.assertEqualsRendered("{1=0}", UnicodePunctuationBoundaryResolverCoverageSupport.mapText(r.virtualBoundaryAfterClusters));
        TracedAssertions.assertTrue(r.virtualSinoWesternBoundaryAfterClusters.size() == 0);
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesPunctuationWesternTrailingNarrowOnly():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesPunctuationWesternTrailingNarrowOnly");
        final text = "xa\uFF0C";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "x", "latin", 8.0),
            new Cluster(new TextRange(1, 2), "a", "latin", 8.0),
            new Cluster(new TextRange(2, 3), "\uFF0C", "cjk", 16.0)
        ];
        final e:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Other, EastAsianSpacingValue.Narrow, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other, false)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text, c,
            [FontRole.LatinText, FontRole.LatinText, FontRole.CjkPunctuation], e, SortedSet.builder().build(),
            [InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None]);
        TracedAssertions.assertEqualsRendered("{1=0}", UnicodePunctuationBoundaryResolverCoverageSupport.mapText(r.virtualBoundaryAfterClusters));
        TracedAssertions.assertTrue(r.virtualSinoWesternBoundaryAfterClusters.size() == 0);
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesSinoWesternOnly():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesSinoWesternOnly");
        final text = "\u6C49xa";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "\u6C49", "cjk", 16.0),
            new Cluster(new TextRange(1, 2), "x", "latin", 8.0),
            new Cluster(new TextRange(2, 3), "a", "latin", 8.0)
        ];
        final e:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Other, false)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text, c,
            [FontRole.CjkText, FontRole.LatinText, FontRole.LatinText], e, SortedSet.builder().build(),
            [InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None]);
        TracedAssertions.assertEqualsRendered("{1=0}", UnicodePunctuationBoundaryResolverCoverageSupport.mapText(r.virtualBoundaryAfterClusters));
        final expected = SortedSet.builder();
        expected.put(1);
        TracedAssertions.assertEqualsIntSet(expected.build(), r.virtualSinoWesternBoundaryAfterClusters);
    }

    @:test public static function resolveAttachedInlineInterCharBoundariesWesternBracketOnly():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveAttachedInlineInterCharBoundariesWesternBracketOnly");
        final text = "(x\u6C49";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "(", "latin", 8.0),
            new Cluster(new TextRange(1, 2), "x", "latin", 8.0),
            new Cluster(new TextRange(2, 3), "\u6C49", "cjk", 16.0)
        ];
        final e:Array<EastAsianSpacingEdges> = [
            new EastAsianSpacingEdges(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other, false),
            new EastAsianSpacingEdges(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other, false)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(text, c,
            [FontRole.LatinText, FontRole.LatinText, FontRole.CjkText], e, SortedSet.builder().build(),
            [InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None]);
        TracedAssertions.assertEqualsRendered("{1=0}", UnicodePunctuationBoundaryResolverCoverageSupport.mapText(r.virtualBoundaryAfterClusters));
        TracedAssertions.assertTrue(r.virtualSinoWesternBoundaryAfterClusters.size() == 0);
    }

    @:test public static function resolveUnicodePunctuationBoundariesDecimalMarkAfterEmptyClusterForbidden():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesDecimalMarkAfterEmptyClusterForbidden");
        final text = "a.5";
        final c:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "a", "latin", 8.0),
            new Cluster(new TextRange(1, 1), "", "latin", 0.0),
            new Cluster(new TextRange(1, 3), ".5", "latin", 16.0)
        ];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c,
            [FontRole.LatinText, FontRole.LatinText, FontRole.LatinText], []);
        TracedAssertions.assertEquals(1, r.forbiddenLineStartClusters.size());
    }

    @:test public static function resolveUnicodePunctuationBoundariesApostropheRightNeighbourSupplementaryPair():Void {
        UnicodePunctuationBoundaryResolverCoverageSupport.start("resolveUnicodePunctuationBoundariesApostropheRightNeighbourSupplementaryPair");
        final text = "\u2019" + UnicodePunctuationBoundaryResolverCoverageSupport.surrogate([0xD83D, 0xDE00]);
        final c:Array<Cluster> = [new Cluster(new TextRange(0, 3), text, "latin", 32.0)];
        final r = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(text, c, [FontRole.LatinText], []);
        TracedAssertions.assertEquals(0, r.decisions.length);
    }
}
