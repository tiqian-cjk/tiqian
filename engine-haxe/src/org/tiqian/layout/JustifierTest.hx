package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.EastAsianSpacingEdges;
import org.tiqian.core.IntRange;
import org.tiqian.core.TextRange;
import org.tiqian.core.InlineObjectPreferredStretch;
import org.tiqian.core.InlineObjectPreferredStretchKind;
import std.SortedSet;
import std.SortedMap;
import org.tiqian.core.UnicodeEastAsianSpacing;
import org.tiqian.font.FontRole;
import org.tiqian.layout.PunctuationModel.GlueKind;
import org.tiqian.layout.Justifier.JustificationPlan;
import org.tiqian.layout.Justifier.JustificationOpportunity;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class JustifierTestSupport {
    public static var em:Float = 16.0;

    public static function cjk(at:Int):Cluster {
        return new Cluster(new TextRange(at, at + 1), "\u4E2D", "cjk", em);
    }

    public static function space(at:Int):Cluster {
        return new Cluster(new TextRange(at, at + 1), " ", "latin", 0.25 * em);
    }

    public static function latin(at:Int, w:Float):Cluster {
        return new Cluster(new TextRange(at, at + 2), "Hi", "latin", w);
    }

    public static function slashLatin(at:Int, w:Float):Cluster {
        return new Cluster(new TextRange(at, at + 3), "/Hi", "latin", w);
    }

    public static function punctuation(at:Int, ?text:String):Cluster {
        return new Cluster(new TextRange(at, at + 1), text == null ? "\uFF08" : text, "cjk", em);
    }

    public static function westernBracket(at:Int, text:String):Cluster {
        return new Cluster(new TextRange(at, at + 1), text, "latin", 0.5 * em);
    }

    public static function inlineObject(at:Int, text:String):Cluster {
        return new Cluster(new TextRange(at, at + text.length), text, "inline-object", 2.0 * em, "");
    }

    public static function spacingEdges(clusters:Array<Cluster>):Array<EastAsianSpacingEdges> {
        var a:Array<EastAsianSpacingEdges> = [];
        var i = 0;
        while (i < clusters.length) {
            a.push(UnicodeEastAsianSpacing.resolvedEdges(clusters[i].text, "zh-Hans"));
            i++;
        }
        return a;
    }

    public static function natural(c:Array<Cluster>):Float {
        var n = 0.0;
        var i = 0;
        while (i < c.length) {
            n += c[i].advance;
            i++;
        }
        return n;
    }

    public static function renderTargetIndexes(plan:JustificationPlan, kind:GlueKind):String {
        var s = "[";
        var first = true;
        var i = 0;
        while (i < plan.allocations.length) {
            var a = plan.allocations[i];
            if (a.kind == kind) {
                if (!first)
                    s += ", ";
                s += a.targetClusterIndex;
                first = false;
            }
            i++;
        }
        return s + "]";
    }

    public static function renderKinds(plan:JustificationPlan):String {
        var s = "[";
        var i = 0;
        while (i < plan.allocations.length) {
            if (i > 0)
                s += ", ";
            s += Std.string(plan.allocations[i].kind);
            i++;
        }
        return s + "]";
    }

    public static function renderDeltas(plan:JustificationPlan):String {
        var s = "[";
        var i = 0;
        while (i < plan.allocations.length) {
            if (i > 0)
                s += ", ";
            s += org.tiqian.test.trace.TestTraceRender.renderFloat(plan.allocations[i].delta);
            i++;
        }
        return s + "]";
    }

    public static function setInts(values:Array<Int>):SortedSet<Int> {
        var b = std.SortedSet.builder();
        var i = 0;
        while (i < values.length) {
            b.put(values[i]);
            i++;
        }
        return b.build();
    }

    public static function roles(n:Int, role:FontRole):Array<FontRole> {
        var a:Array<FontRole> = [];
        var i = 0;
        while (i < n) {
            a.push(role);
            i++;
        }
        return a;
    }
}

class JustifierTest {
    @:test public static function westernDominantLineDoesNotStretchAroundCjkPunctuation():Void {
        new TestTraceRecorder("JustifierTest").section("westernDominantLineDoesNotStretchAroundCjkPunctuation");
        final clusters:Array<Cluster> = [
            JustifierTestSupport.latin(0, 3.0 * JustifierTestSupport.em),
            JustifierTestSupport.punctuation(2),
            JustifierTestSupport.latin(3, 3.0 * JustifierTestSupport.em),
            JustifierTestSupport.punctuation(5, "\uFF09"),
            JustifierTestSupport.punctuation(6, "\u3001"),
            JustifierTestSupport.latin(7, 3.0 * JustifierTestSupport.em),
        ];
        final roles:Array<FontRole> = [
            FontRole.LatinText,
            FontRole.CjkPunctuation,
            FontRole.LatinText,
            FontRole.CjkPunctuation,
            FontRole.CjkPunctuation,
            FontRole.LatinText,
        ];
        var natural = 0.0;
        var ni = 0;
        while (ni < clusters.length) {
            natural += clusters[ni].advance;
            ni++;
        }
        final plan = new Justifier().justify(clusters, roles, JustifierTestSupport.spacingEdges(clusters), new IntRange(0, clusters.length - 1),
            natural + 2.0 * JustifierTestSupport.em, JustifierTestSupport.em, false, null, true, 0.25 * JustifierTestSupport.em, 0.5 * JustifierTestSupport.em);
        var noneCjkInterChar = true;
        var ai = 0;
        while (ai < plan.allocations.length) {
            if (plan.allocations[ai].kind == GlueKind.CjkInterChar) {
                noneCjkInterChar = false;
                break;
            }
            ai++;
        }
        TracedAssertions.assertTrue(noneCjkInterChar);
        TracedAssertions.assertEqualsFloatTolerance(2.0 * JustifierTestSupport.em, plan.unfilledDeficit, 0.001);
        TracedAssertions.assertEqualsString("WesternDominantLineNaturalSpacing", plan.fallbackReason);
    }

    @:test public static function explicitInlineObjectBoundariesShareUniformStretchOnFormulaOnlyLine():Void {
        new TestTraceRecorder("JustifierTest").section("explicitInlineObjectBoundariesShareUniformStretchOnFormulaOnlyLine");
        var S = JustifierTestSupport;
        var c = [S.inlineObject(0, "a+"), S.inlineObject(2, "b="), S.inlineObject(4, "c")];
        var b = SortedSet.builder();
        b.put(0);
        b.put(1);
        var p = new Justifier().justify(c, [FontRole.Unknown, FontRole.Unknown, FontRole.Unknown], S.spacingEdges(c), new IntRange(0, 2), S.natural(c) + S.em,
            S.em, false, null, true, .25, .5, null, null, null, null, null, null, b.build());
        TracedAssertions.assertEqualsFloatTolerance(0, p.unfilledDeficit, .001);
        TracedAssertions.assertEqualsRendered("[0, 1]", S.renderTargetIndexes(p, GlueKind.InlineObjectBoundary));
        TracedAssertions.assertTrue(p.allocations.length == 2);
        TracedAssertions.assertEqualsFloatTolerance(8, p.allocations[0].delta, .001);
        TracedAssertions.assertEqualsFloatTolerance(8, p.allocations[1].delta, .001);
    }

    @:test public static function formulaBoundariesStretchPunctuationThenRelationsThenBinaryOperators():Void {
        new TestTraceRecorder("JustifierTest").section("formulaBoundariesStretchPunctuationThenRelationsThenBinaryOperators");
        var S = JustifierTestSupport;
        var c = [
            S.inlineObject(0, "a"),
            S.inlineObject(1, ","),
            S.inlineObject(2, "b"),
            S.inlineObject(3, "="),
            S.inlineObject(4, "c"),
            S.inlineObject(5, "+"),
            S.inlineObject(6, "d")
        ];
        var b = SortedMap.builder();
        b.put(1, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.PunctuationTrailing, 1, 8));
        b.put(2, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.Relation, 2, 8));
        b.put(3, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.Relation, 2, 8));
        b.put(4, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.BinaryOperator, 3, 8));
        b.put(5, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.BinaryOperator, 3, 8));
        var p = new Justifier().justify(c, S.roles(7, FontRole.Unknown), S.spacingEdges(c), new IntRange(0, 6), S.natural(c) + 24, S.em, false, null, true,
            .25, .5, null, null, null, null, null, null, null, b.build());
        TracedAssertions.assertEqualsRendered("[InlineObjectPunctuationTrailing, InlineObjectRelation, InlineObjectRelation, InlineObjectBinaryOperator, InlineObjectBinaryOperator]",
            S.renderKinds(p));
        TracedAssertions.assertEqualsRendered("[7, 6, 6, 2.500000, 2.500000]", S.renderDeltas(p));
        var i = 0;
        while (i < 3) {
            TracedAssertions.assertEqualsFloatTolerance(8, p.allocations[i].delta + ((i == 0) ? 1 : 2), .001);
            i++;
        }
        TracedAssertions.assertEqualsFloatTolerance(p.allocations[1].delta, p.allocations[2].delta, .001,
            "both relation sides must stretch by exactly the same amount");
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
        var q = new Justifier().justify(c, S.roles(7, FontRole.Unknown), S.spacingEdges(c), new IntRange(0, 6), S.natural(c) + 34, S.em, false, null, true,
            .25, .5, null, null, null, null, null, null, S.setInts([1, 2, 3, 4, 5]), b.build());
        var sum = 0.0;
        i = 0;
        while (i < 5) {
            sum += q.allocations[i].delta;
            i++;
        }
        TracedAssertions.assertEqualsFloat(29, sum);
        var u:Array<Int> = [];
        i = 0;
        while (i < q.allocations.length) {
            if (q.allocations[i].kind == GlueKind.InlineObjectBoundary)
                u.push(q.allocations[i].targetClusterIndex);
            i++;
        }
        TracedAssertions.assertEqualsIntSetUnordered([1, 2, 3, 4, 5], u);
        i = 0;
        while (i < u.length) {
            TracedAssertions.assertEqualsFloatTolerance(1, q.allocations[5 + i].delta, .001);
            i++;
        }
        var widths = [1, 2, 2, 3, 3];
        i = 0;
        while (i < 5) {
            var total = 0.0;
            var j = 0;
            while (j < q.allocations.length) {
                if (q.allocations[j].targetClusterIndex == p.allocations[i].targetClusterIndex)
                    total += q.allocations[j].delta;
                j++;
            }
            TracedAssertions.assertEqualsFloatTolerance(9, widths[i] + total, .001);
            i++;
        }
        TracedAssertions.assertEqualsFloat(0, q.unfilledDeficit);
    }

    @:test public static function mixedCjkLineStillStretchesPunctuationWesternBoundary():Void {
        new TestTraceRecorder("JustifierTest").section("mixedCjkLineStillStretchesPunctuationWesternBoundary");
        var S = JustifierTestSupport;
        var c = [S.latin(0, 2 * S.em), S.punctuation(2), S.cjk(3)];
        var p = new Justifier().justify(c, [FontRole.LatinText, FontRole.CjkPunctuation, FontRole.CjkText], S.spacingEdges(c), new IntRange(0, 2),
            S.natural(c) + .5 * S.em, S.em, false, null, true, .25, .5);
        var has = false;
        var i = 0;
        while (i < p.allocations.length) {
            if (p.allocations[i].kind == GlueKind.CjkInterChar && p.allocations[i].targetClusterIndex == 0)
                has = true;
            i++;
        }
        TracedAssertions.assertTrue(has, "mixed CJK lines retain punctuation-western tier-3 tracking");
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
        TracedAssertions.assertEqualsRendered("-", p.fallbackReason == null ? "-" : p.fallbackReason);
    }

    @:test public static function typedSinoWesternSpaceStretchesInTierTwo():Void {
        new TestTraceRecorder("JustifierTest").section("typedSinoWesternSpaceStretchesInTierTwo");
        var S = JustifierTestSupport;
        var c = [S.cjk(0), S.space(1), S.latin(2, 2 * S.em)];
        var p = new Justifier().justify(c, [FontRole.CjkText, FontRole.LatinText, FontRole.LatinText], S.spacingEdges(c), new IntRange(0, 2),
            S.natural(c) + .2 * S.em, S.em, false, null, true, .25, .5);
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
        var a = p.allocations[0];
        TracedAssertions.assertEquals(1, a.targetClusterIndex);
        TracedAssertions.assertEqualsRendered("CjkLatinSpace", Std.string(a.kind));
        TracedAssertions.assertEqualsFloatTolerance(.2 * S.em, a.delta, .001);
    }

    @:test public static function typedSinoWesternSpaceIsCappedAtHalfEm():Void {
        new TestTraceRecorder("JustifierTest").section("typedSinoWesternSpaceIsCappedAtHalfEm");
        var S = JustifierTestSupport;
        var c = [S.cjk(0), S.space(1), S.latin(2, 2 * S.em), S.cjk(3), S.cjk(4)];
        var p = new Justifier().justify(c, [
            FontRole.CjkText,
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.CjkText,
            FontRole.CjkText
        ], S.spacingEdges(c), new IntRange(0, 4),
            S.natural(c) + 2 * S.em, S.em, false, null, true, .25, .5);
        var sinoIdx:Array<Int> = [];
        var si = 0;
        while (si < p.allocations.length) {
            if (p.allocations[si].kind == GlueKind.CjkLatinSpace)
                sinoIdx.push(p.allocations[si].targetClusterIndex);
            si++;
        }
        TracedAssertions.assertEqualsIntSetUnordered([1, 2], sinoIdx);
        si = 0;
        while (si < p.allocations.length) {
            if (p.allocations[si].kind == GlueKind.CjkLatinSpace)
                TracedAssertions.assertEqualsFloatTolerance(.25 * S.em, p.allocations[si].delta, .001);
            si++;
        }
        var uniformCount = 0;
        var ui = 0;
        while (ui < p.allocations.length) {
            if (p.allocations[ui].kind == GlueKind.CjkInterChar)
                uniformCount++;
            ui++;
        }
        TracedAssertions.assertEquals(3, uniformCount);
        var uniformIdx:Array<Int> = [];
        ui = 0;
        while (ui < p.allocations.length) {
            if (p.allocations[ui].kind == GlueKind.CjkInterChar)
                uniformIdx.push(p.allocations[ui].targetClusterIndex);
            ui++;
        }
        TracedAssertions.assertEqualsIntSetUnordered([1, 2, 3], uniformIdx);
        ui = 0;
        while (ui < p.allocations.length) {
            if (p.allocations[ui].kind == GlueKind.CjkInterChar)
                TracedAssertions.assertEqualsFloatTolerance(.5 * S.em, p.allocations[ui].delta, .001);
            ui++;
        }
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
    }

    @:test public static function finalUniformSpacingIncludesWordAndSinoWesternGapsOnceEach():Void {
        new TestTraceRecorder("JustifierTest").section("finalUniformSpacingIncludesWordAndSinoWesternGapsOnceEach");
        var S = JustifierTestSupport;
        var c = [
            S.cjk(0),
            S.latin(1, 2 * S.em),
            S.space(3),
            S.latin(4, 2 * S.em),
            S.cjk(6),
            S.cjk(7)
        ];
        var p = new Justifier().justify(c, [
            FontRole.CjkText,
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.CjkText,
            FontRole.CjkText
        ], S.spacingEdges(c), new IntRange(0, 5),
            S.natural(c) + 2.25 * S.em, S.em, false, null, true, .25, .5);
        var a:Array<Int> = [];
        var i = 0;
        while (i < p.allocations.length) {
            if (p.allocations[i].kind == GlueKind.WordSpace)
                a.push(p.allocations[i].targetClusterIndex);
            i++;
        }
        TracedAssertions.assertEqualsRendered("[2]", S.renderTargetIndexes(p, GlueKind.WordSpace));
        TracedAssertions.assertEqualsFloatTolerance(.25 * S.em, p.allocations[0].delta, .001);
        var s:Array<Int> = [];
        i = 0;
        while (i < p.allocations.length) {
            if (p.allocations[i].kind == GlueKind.CjkLatinSpace)
                s.push(p.allocations[i].targetClusterIndex);
            i++;
        }
        TracedAssertions.assertEqualsIntSetUnordered([0, 3], s);
        i = 0;
        while (i < s.length) {
            TracedAssertions.assertEqualsFloatTolerance(.25 * S.em, p.allocations[1 + i].delta, .001);
            i++;
        }
        var u:Array<Int> = [];
        i = 0;
        while (i < p.allocations.length) {
            if (p.allocations[i].kind == GlueKind.CjkInterChar)
                u.push(p.allocations[i].targetClusterIndex);
            i++;
        }
        TracedAssertions.assertEqualsRendered("[0, 3, 4, 2]", S.renderTargetIndexes(p, GlueKind.CjkInterChar));
        i = 0;
        while (i < u.length) {
            TracedAssertions.assertEqualsFloatTolerance(.375 * S.em, p.allocations[3 + i].delta, .001);
            i++;
        }
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
    }

    @:test public static function westernBracketsTouchingCjkShareTierThreeStretch():Void {
        new TestTraceRecorder("JustifierTest").section("westernBracketsTouchingCjkShareTierThreeStretch");
        var S = JustifierTestSupport;
        var c = [S.cjk(0), S.westernBracket(1, "("), S.cjk(2), S.westernBracket(3, ")"), S.cjk(4)];
        var b = SortedSet.builder();
        var i = 0;
        while (i < 4) {
            b.put(i);
            i++;
        }
        var p = new Justifier().justify(c, [
            FontRole.CjkText,
            FontRole.LatinText,
            FontRole.CjkText,
            FontRole.LatinText,
            FontRole.CjkText
        ], S.spacingEdges(c), new IntRange(0, 4),
            S.natural(c) + S.em, S.em, false, null, true, .25, .5, null, null, b.build());
        var a:Array<Int> = [];
        i = 0;
        while (i < p.allocations.length) {
            if (p.allocations[i].kind == GlueKind.CjkInterChar)
                a.push(p.allocations[i].targetClusterIndex);
            i++;
        }
        TracedAssertions.assertEqualsIntSetUnordered([0, 1, 2, 3], a);
        i = 0;
        while (i < a.length) {
            TracedAssertions.assertEqualsString("WesternBracketCjkInterChar", p.allocations[i].reason);
            TracedAssertions.assertEqualsFloatTolerance(.25 * S.em, p.allocations[i].delta, .001);
            i++;
        }
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
    }

    @:test public static function attachedReferenceUsesTheVirtualProseBoundaryForStretching():Void {
        new TestTraceRecorder("JustifierTest").section("attachedReferenceUsesTheVirtualProseBoundaryForStretching");
        var S = JustifierTestSupport;
        var c = [
            S.cjk(0),
            S.westernBracket(1, "["),
            S.latin(2, S.em),
            S.westernBracket(4, "]"),
            S.cjk(5)
        ];
        var b = SortedMap.builder();
        b.put(3, 0);
        var p = new Justifier().justify(c, [
            FontRole.CjkText,
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.CjkText
        ], S.spacingEdges(c),
            new IntRange(0, 4), S.natural(c) + S.em, S.em, false, null, true, .25, .5, null, null, null, null, b.build());
        TracedAssertions.assertEquals(3, p.allocations[0].targetClusterIndex);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualInterChar", p.allocations[0].reason);
        TracedAssertions.assertEqualsFloatTolerance(S.em, p.allocations[0].delta, .001);
        var q = new Justifier().justify(c, [
            FontRole.CjkText,
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.CjkText
        ],
            S.spacingEdges(c), new IntRange(0, 3), S.natural(c) - c[4].advance + S.em, S.em, false, null, true, .25, .5, null, null, null, null, b.build());
        TracedAssertions.assertTrue(q.allocations.length == 0);
    }

    @:test public static function inseparableNumberSymbolBoundaryNeverStretches():Void {
        new TestTraceRecorder("JustifierTest").section("inseparableNumberSymbolBoundaryNeverStretches");
        var S = JustifierTestSupport;
        var c = [S.cjk(0), S.latin(1, 2 * S.em), S.punctuation(3, "%"), S.cjk(4), S.cjk(5)];
        var b = SortedSet.builder();
        b.put(1);
        var p = new Justifier().justify(c, [
            FontRole.CjkText,
            FontRole.LatinText,
            FontRole.CjkPunctuation,
            FontRole.CjkText,
            FontRole.CjkText
        ], S.spacingEdges(c), new IntRange(0, 4),
            S.natural(c) + S.em, S.em, false, null, true, .25, .5, null, b.build());
        TracedAssertions.assertTrue(p.allocations.length > 0);
        var ok = true;
        var i = 0;
        while (i < p.allocations.length) {
            if (p.allocations[i].targetClusterIndex == 1
                && (p.allocations[i].kind == GlueKind.CjkLatinSpace || p.allocations[i].kind == GlueKind.CjkInterChar))
                ok = false;
            i++;
        }
        TracedAssertions.assertTrue(ok, "50|% must stay closed: " + Std.string(p.allocations));
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
    }

    @:test public static function fixedSinoWesternGapDoesNotJoinFinalUniformSpacing():Void {
        new TestTraceRecorder("JustifierTest").section("fixedSinoWesternGapDoesNotJoinFinalUniformSpacing");
        var S = JustifierTestSupport;
        var c = [S.cjk(0), S.latin(1, 2 * S.em), S.cjk(3), S.cjk(4)];
        var p = new Justifier().justify(c, [FontRole.CjkText, FontRole.LatinText, FontRole.CjkText, FontRole.CjkText], S.spacingEdges(c), new IntRange(0, 3),
            S.natural(c) + S.em, S.em, false, null, false, .25, .5);
        TracedAssertions.assertEquals(1, p.allocations.length);
        TracedAssertions.assertEqualsRendered("CjkInterChar", Std.string(p.allocations[0].kind));
        TracedAssertions.assertEquals(2, p.allocations[0].targetClusterIndex);
        TracedAssertions.assertEqualsFloatTolerance(S.em, p.allocations[0].delta, .001);
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
    }

    @:test public static function virtualSinoWesternStretchRequiresAlphaNumericBoundaryChar():Void {
        new TestTraceRecorder("JustifierTest").section("virtualSinoWesternStretchRequiresAlphaNumericBoundaryChar");
        var S = JustifierTestSupport;
        var c = [S.cjk(0), S.slashLatin(1, 2 * S.em), S.cjk(4)];
        var p = new Justifier().justify(c, [FontRole.CjkText, FontRole.LatinText, FontRole.CjkText], S.spacingEdges(c), new IntRange(0, 2),
            S.natural(c) + .2 * S.em, S.em, false, null, true, .25, .5);
        TracedAssertions.assertEqualsRendered("[1]", S.renderTargetIndexes(p, GlueKind.CjkLatinSpace));
    }

    @:test public static function typedSpaceBeforeSlashLedLatinRunIsNotSinoWesternGap():Void {
        new TestTraceRecorder("JustifierTest").section("typedSpaceBeforeSlashLedLatinRunIsNotSinoWesternGap");
        var S = JustifierTestSupport;
        var c = [S.cjk(0), S.space(1), S.slashLatin(2, 2 * S.em)];
        var p = new Justifier().justify(c, [FontRole.CjkText, FontRole.LatinText, FontRole.LatinText], S.spacingEdges(c), new IntRange(0, 2),
            S.natural(c) + .2 * S.em, S.em, false, null, true, .25, .5);
        var ok = true;
        var i = 0;
        while (i < p.allocations.length) {
            if (p.allocations[i].kind == GlueKind.CjkLatinSpace)
                ok = false;
            i++;
        }
        TracedAssertions.assertTrue(ok);
    }

    @:test public static function sinoWesternStretchRespectsThirdEmCapWhenStyleSetsIt():Void {
        new TestTraceRecorder("JustifierTest").section("sinoWesternStretchRespectsThirdEmCapWhenStyleSetsIt");
        var S = JustifierTestSupport;
        var c = [S.cjk(0), S.space(1), S.latin(2, 2 * S.em)];
        var p = new Justifier().justify(c, [FontRole.CjkText, FontRole.LatinText, FontRole.LatinText], S.spacingEdges(c), new IntRange(0, 2),
            S.natural(c) + S.em, S.em, false, null, true, .25, 1.0 / 3.0);
        TracedAssertions.assertEqualsFloatTolerance((1.0 / 3.0 - .25) * S.em, p.allocations[0].delta, .001);
    }
}
