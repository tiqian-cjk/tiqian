package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.IntRange;
import org.tiqian.core.TextRange;
import org.tiqian.core.EastAsianSpacingEdges;
import org.tiqian.core.EastAsianSpacingValue;
import org.tiqian.core.InlineObjectPreferredStretch;
import org.tiqian.core.InlineObjectPreferredStretchKind;
import org.tiqian.font.FontRole;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedSet;
import std.SortedMap;
import org.tiqian.layout.Justifier.JustificationPlan;
import org.tiqian.layout.PunctuationModel.GlueKind;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;

class JustifierJfTestSupport {
    public static var em:Float = 16.0;

    public static function c(text:String, index:Int, ?advance:Null<Float>, ?fontKey:Null<String>):Cluster
        return new Cluster(new TextRange(index, index + text.length), text, fontKey == null ? "k" : fontKey, advance == null ? em : advance);

    public static function e(?leading:Null<EastAsianSpacingValue>, ?trailing:Null<EastAsianSpacingValue>, ?wide:Null<Bool>):EastAsianSpacingEdges
        return new EastAsianSpacingEdges(leading == null ? EastAsianSpacingValue.Other : leading, trailing == null ? EastAsianSpacingValue.Other : trailing,
            wide == null ? false : wide);

    public static function justify(c:Array<Cluster>, roles:Array<FontRole>, edges:Array<EastAsianSpacingEdges>, r:IntRange, maxWidth:Float,
            ?fontSize:Null<Float>, ?skip:Null<Bool>, ?skipReason:Null<String>, ?allow:Null<Bool>, ?base:Null<Float>, ?max:Null<Float>,
            ?ns:Null<SortedSet<Int>>, ?nsa:Null<SortedSet<Int>>, ?br:Null<SortedSet<Int>>, ?ph:Null<SortedSet<Int>>, ?v:Null<SortedMap<Int, Int>>,
            ?vs:Null<SortedSet<Int>>, ?uo:Null<SortedSet<Int>>, ?pref:Null<SortedMap<Int, InlineObjectPreferredStretch>>,
            ?te:Null<SortedMap<Int, ProgressiveBreakTier>>, ?emg:Null<SortedMap<Int, String>>, ?pem:Null<SortedMap<Int, String>>):JustificationPlan {
        var x = new Justifier();
        return x.justify(c, roles, edges, r, maxWidth, fontSize == null ? em : fontSize, skip == null ? false : skip, skipReason,
            allow == null ? true : allow, base == null ? 0.25 : base, max == null ? 0.5 : max, ns, nsa, br, ph, v, vs, uo, pref, te, emg, pem);
    }

    public static function set(xs:Array<Int>):SortedSet<Int> {
        var b = SortedSet.builder();
        var i0 = 0;
        while (i0 < xs.length) {
            b.put(xs[i0]);
            i0++;
        }
        return b.build();
    }

    public static function intMap(xs:Array<Int>, ys:Array<Int>):SortedMap<Int, Int> {
        var b = SortedMap.builder();
        var i = 0;
        while (i < xs.length) {
            b.put(xs[i], ys[i]);
            i++;
        }
        return b.build();
    }
}

class JustifierJfTest {
    static function sec(s:String):Void
        new TestTraceRecorder("JustifierJfTest").section(s);

    public static function attachedInlineVirtualSinoWesternBoundaryOutOfBounds():Void {
        sec("attachedInlineVirtualSinoWesternBoundaryOutOfBounds");
        var c = [
            JustifierJfTestSupport.c("\u4E2D", 0),
            JustifierJfTestSupport.c("\u6587", 1),
            JustifierJfTestSupport.c("a", 2)
        ];
        var r = [FontRole.CjkText, FontRole.CjkText, FontRole.LatinText];
        var e = [
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var v = JustifierJfTestSupport.intMap([-1, 2, 5], [-2, 1, 4]);
        TracedAssertions.assertTrue(JustifierJfTestSupport.justify(c, r, e, new IntRange(0, 2), 60, JustifierJfTestSupport.em, false, null, true, .25, .5,
            null, null, null, null, v, JustifierJfTestSupport.set([-1, 2, 5]))
            .allocations.length > 0);
    }

    public static function attachedInlineVirtualSinoWesternZeroHeadroomInAllocate():Void {
        sec("attachedInlineVirtualSinoWesternZeroHeadroomInAllocate");
        var c = [
            JustifierJfTestSupport.c("\u4E2D", 0),
            JustifierJfTestSupport.c("\u6587", 1),
            JustifierJfTestSupport.c("a", 2)
        ];
        var r = [FontRole.CjkText, FontRole.CjkText, FontRole.LatinText];
        var e = [
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var p = JustifierJfTestSupport.justify(c, r, e, new IntRange(0, 2), 60, 16, false, null, true, .5, .5, null, null, null, null,
            JustifierJfTestSupport.intMap([1], [0]), JustifierJfTestSupport.set([1]));
        var hasCjkLatin = false;
        var hasInter = false;
        var i = 0;
        while (i < p.allocations.length) {
            if (p.allocations[i].kind == GlueKind.CjkLatinSpace)
                hasCjkLatin = true;
            if (p.allocations[i].kind == GlueKind.CjkInterChar)
                hasInter = true;
            i++;
        }
        TracedAssertions.assertTrue(!hasCjkLatin);
        TracedAssertions.assertTrue(hasInter);
    }

    public static function cjkLatinMixedZeroAndPositiveCapacityAllocation():Void {
        sec("cjkLatinMixedZeroAndPositiveCapacityAllocation");
        var c = [
            JustifierJfTestSupport.c("\u4E2D", 0),
            JustifierJfTestSupport.c(" ", 1, 2),
            JustifierJfTestSupport.c("a", 2),
            JustifierJfTestSupport.c("b", 3)
        ];
        var r = [FontRole.CjkText, FontRole.LatinText, FontRole.LatinText, FontRole.LatinText];
        var e = [
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierJfTestSupport.e(),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var p = JustifierJfTestSupport.justify(c, r, e, new IntRange(0, 3), 54, 16, false, null, true, .5, .5, null, null, null, null,
            JustifierJfTestSupport.intMap([2], [0]), JustifierJfTestSupport.set([2]));
        var la = [];
        var i = 0;
        while (i < p.allocations.length) {
            if (p.allocations[i].kind == GlueKind.CjkLatinSpace)
                la.push(p.allocations[i]);
            i++;
        }
        TracedAssertions.assertEquals(1, la.length);
        TracedAssertions.assertEquals(1, la[0].targetClusterIndex);
        TracedAssertions.assertEqualsFloat(4, la[0].delta);
        var q = JustifierJfTestSupport.justify(c, r, e, new IntRange(0, 3), 60, 16, false, null, true, .5, .5, null, null, null, null,
            JustifierJfTestSupport.intMap([2], [0]), JustifierJfTestSupport.set([2]));
        var lz = [];
        var j = 0;
        while (j < q.allocations.length) {
            if (q.allocations[j].kind == GlueKind.CjkLatinSpace)
                lz.push(q.allocations[j]);
            j++;
        }
        TracedAssertions.assertEquals(1, lz.length);
        TracedAssertions.assertEquals(1, lz[0].targetClusterIndex);
        TracedAssertions.assertEqualsFloat(6, lz[0].delta);
    }

    public static function closedSpaceGapInTypedSinoWesternAndUniformSpace():Void {
        sec("closedSpaceGapInTypedSinoWesternAndUniformSpace");
        var c = [
            JustifierJfTestSupport.c("\u4E2D", 0),
            JustifierJfTestSupport.c(" ", 1, 4),
            JustifierJfTestSupport.c("a", 2)
        ];
        var r = [FontRole.CjkText, FontRole.LatinText, FontRole.LatinText];
        var e = [
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierJfTestSupport.e(),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var p = JustifierJfTestSupport.justify(c, r, e, new IntRange(0, 2), 60, 16, false, null, true, .25, .5, JustifierJfTestSupport.set([2]));
        TracedAssertions.assertTrue(p.allocations.length == 0 || p.allocations[0].targetClusterIndex != 1);
    }

    public static function closedSpaceGapInUniformSpaceWhenWordSpace():Void {
        sec("closedSpaceGapInUniformSpaceWhenWordSpace");
        var c = [
            JustifierJfTestSupport.c("a", 0),
            JustifierJfTestSupport.c(" ", 1, 4),
            JustifierJfTestSupport.c("b", 2)
        ];
        var r = [FontRole.LatinText, FontRole.LatinText, FontRole.LatinText];
        var e = [
            JustifierJfTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            JustifierJfTestSupport.e(),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var p = JustifierJfTestSupport.justify(c, r, e, new IntRange(0, 2), 60, 16, false, null, true, .25, .5, JustifierJfTestSupport.set([0]));
        TracedAssertions.assertTrue(p.allocations.length == 0 || p.allocations[0].targetClusterIndex != 1);
    }

    public static function compressSubnormalUnderflowShrinkZero():Void {
        sec("compressSubnormalUnderflowShrinkZero");
        var p = new Justifier().compress(1e-300, [new ShrinkOpportunity(0, 1, 1e300, ShrinkChannel.TrailingGlue)]);
        TracedAssertions.assertEquals(0, p.allocations.length);
        TracedAssertions.assertEqualsFloat(1e-300, p.surplusBefore);
    }

    public static function compressionWithZeroSurplusAndZeroCapacity():Void {
        sec("compressionWithZeroSurplusAndZeroCapacity");
        var j = new Justifier();
        var a = j.compress(0, []);
        TracedAssertions.assertEqualsFloat(0, a.surplusBefore);
        TracedAssertions.assertEqualsFloat(0, a.unfilledSurplus);
        TracedAssertions.assertTrue(a.allocations.length == 0);
        var b = j.compress(10, [new ShrinkOpportunity(0, 1, 0, ShrinkChannel.TrailingGlue)]);
        TracedAssertions.assertEqualsFloat(10, b.surplusBefore);
        TracedAssertions.assertEqualsFloat(10, b.unfilledSurplus);
        TracedAssertions.assertTrue(b.allocations.length == 0);
    }

    public static function emptyLineClusterRangeSkipsUniformSpaceLoop():Void {
        sec("emptyLineClusterRangeSkipsUniformSpaceLoop");
        var c = [JustifierJfTestSupport.c("\u4E2D", 0), JustifierJfTestSupport.c("\u6587", 1)];
        var r = [FontRole.CjkText, FontRole.CjkText];
        var e = [
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true)
        ];
        var p = JustifierJfTestSupport.justify(c, r, e, new IntRange(1, 0), 50);
        TracedAssertions.assertEquals(0, p.allocations.length);
        TracedAssertions.assertEqualsFloat(50, p.unfilledDeficit);
    }

    public static function preferredInlineObjectBoundaryOutOfBounds():Void {
        sec("preferredInlineObjectBoundaryOutOfBounds");
        var c = [
            JustifierJfTestSupport.c("\u4E2D", 0),
            JustifierJfTestSupport.c("\u6587", 1),
            JustifierJfTestSupport.c("\u5B57", 2)
        ];
        var r = [FontRole.CjkText, FontRole.CjkText, FontRole.CjkText];
        var e = [
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true)
        ];
        var b = SortedMap.builder();
        var ks = [-1, 2, 5];
        var i2 = 0;
        while (i2 < ks.length) {
            b.put(ks[i2], new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.Relation, 0, 4));
            i2++;
        }
        var p = JustifierJfTestSupport.justify(c, r, e, new IntRange(0, 2), 60, 16, false, null, true, .25, .5, null, null, null, null, null, null, null,
            b.build());
        var none = true;
        var i3 = 0;
        while (i3 < p.allocations.length) {
            if (p.allocations[i3].kind == GlueKind.InlineObjectRelation)
                none = false;
            i3++;
        }
        TracedAssertions.assertTrue(none);
        TracedAssertions.assertTrue(p.allocations.length > 0);
    }

    public static function singleClusterRangeProducesNoOpportunities():Void {
        sec("singleClusterRangeProducesNoOpportunities");
        var p = JustifierJfTestSupport.justify([JustifierJfTestSupport.c("\u4E2D", 0)], [FontRole.CjkText], [
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true)
        ], new IntRange(0, 0), 30);
        TracedAssertions.assertEquals(0, p.allocations.length);
    }

    public static function typedSpaceAndWordSpacePredicateEdgeConditions():Void {
        sec("typedSpaceAndWordSpacePredicateEdgeConditions");
        var c = [
            JustifierJfTestSupport.c("", 0),
            JustifierJfTestSupport.c(" ", 1, 4),
            JustifierJfTestSupport.c(" ", 2, 4),
            JustifierJfTestSupport.c("abc", 3),
            JustifierJfTestSupport.c("xyz", 4),
            JustifierJfTestSupport.c("\u5B57", 5)
        ];
        var r = [
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.CjkText
        ];
        var e = [
            JustifierJfTestSupport.e(),
            JustifierJfTestSupport.e(),
            JustifierJfTestSupport.e(),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true)
        ];
        TracedAssertions.assertTrue(JustifierJfTestSupport.justify(c, r, e, new IntRange(0, 5), 150).allocations.length > 0);
    }

    public static function virtualNonSinoWesternBoundaryWhenAllowSinoWesternGapStretchIsFalse():Void {
        sec("virtualNonSinoWesternBoundaryWhenAllowSinoWesternGapStretchIsFalse");
        var c = [
            JustifierJfTestSupport.c("\u4E2D", 0),
            JustifierJfTestSupport.c("[", 1),
            JustifierJfTestSupport.c("1", 2),
            JustifierJfTestSupport.c("]", 3),
            JustifierJfTestSupport.c("\u6587", 4)
        ];
        var r = [
            FontRole.CjkText,
            FontRole.CjkText,
            FontRole.CjkText,
            FontRole.CjkText,
            FontRole.CjkText
        ];
        var e = [
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierJfTestSupport.e(),
            JustifierJfTestSupport.e(),
            JustifierJfTestSupport.e(),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true)
        ];
        var p = JustifierJfTestSupport.justify(c, r, e, new IntRange(0, 4), 100, 16, false, null, false, .25, .5, null, null, null, null,
            JustifierJfTestSupport.intMap([3], [0]));
        var ok = false;
        var i4 = 0;
        while (i4 < p.allocations.length) {
            if (p.allocations[i4].targetClusterIndex == 3 && p.allocations[i4].reason == "AttachedInlineVirtualInterChar")
                ok = true;
            i4++;
        }
        TracedAssertions.assertTrue(ok);
    }

    public static function virtualSinoWesternGapWhenAllowSinoWesternGapStretchIsFalse():Void {
        sec("virtualSinoWesternGapWhenAllowSinoWesternGapStretchIsFalse");
        var c = [
            JustifierJfTestSupport.c("\u4E2D", 0),
            JustifierJfTestSupport.c("[", 1),
            JustifierJfTestSupport.c("1", 2),
            JustifierJfTestSupport.c("]", 3),
            JustifierJfTestSupport.c("a", 4)
        ];
        var r = [
            FontRole.CjkText,
            FontRole.CjkText,
            FontRole.CjkText,
            FontRole.CjkText,
            FontRole.LatinText
        ];
        var e = [
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierJfTestSupport.e(),
            JustifierJfTestSupport.e(),
            JustifierJfTestSupport.e(),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var p = JustifierJfTestSupport.justify(c, r, e, new IntRange(0, 4), 100, 16, false, null, false, .25, .5, null, null, null, null,
            JustifierJfTestSupport.intMap([3], [0]), JustifierJfTestSupport.set([3]));
        var ok = true;
        var i5 = 0;
        while (i5 < p.allocations.length) {
            if (p.allocations[i5].targetClusterIndex == 3)
                ok = false;
            i5++;
        }
        TracedAssertions.assertTrue(ok);
    }

    public static function zeroCjkLatinHeadroomProducesNoOpportunities():Void {
        sec("zeroCjkLatinHeadroomProducesNoOpportunities");
        var c = [JustifierJfTestSupport.c("\u4E2D", 0), JustifierJfTestSupport.c("a", 1)];
        var r = [FontRole.CjkText, FontRole.LatinText];
        var e = [
            JustifierJfTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierJfTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var p = JustifierJfTestSupport.justify(c, r, e, new IntRange(0, 1), 40, 16, false, null, true, .5, .5);
        var ok = true;
        var i6 = 0;
        while (i6 < p.allocations.length) {
            if (p.allocations[i6].kind != GlueKind.CjkInterChar)
                ok = false;
            i6++;
        }
        TracedAssertions.assertTrue(ok);
    }
}
