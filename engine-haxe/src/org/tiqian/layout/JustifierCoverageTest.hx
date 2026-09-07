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
import org.tiqian.layout.Justifier.JustificationAllocation;
import org.tiqian.layout.Justifier.CompressionPlan;
import org.tiqian.layout.Justifier.Justifier;
import org.tiqian.layout.LineOptimization.PushInAllocation;
import org.tiqian.layout.PunctuationModel.GlueKind;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;

typedef JustifierFixture = {c:Array<Cluster>, r:Array<FontRole>, e:Array<EastAsianSpacingEdges>};

class JustifierCoverageTestSupport {
    public static var em:Float = 16.0;

    public static function c(t:String, i:Int, ?a:Null<Float>, ?f:Null<String>):Cluster
        return new Cluster(new TextRange(i, i + t.length), t, f == null ? "k" : f, a == null ? em : a);

    public static function e(?l:Null<EastAsianSpacingValue>, ?tr:Null<EastAsianSpacingValue>, ?w:Null<Bool>):EastAsianSpacingEdges
        return new EastAsianSpacingEdges(l == null ? EastAsianSpacingValue.Other : l, tr == null ? EastAsianSpacingValue.Other : tr, w == null ? false : w);

    public static function set(xs:Array<Int>):SortedSet<Int> {
        var b = SortedSet.builder();
        var i = 0;
        while (i < xs.length) {
            b.put(xs[i]);
            i++;
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

    public static function tierMap(xs:Array<Int>, ys:Array<ProgressiveBreakTier>):SortedMap<Int, ProgressiveBreakTier> {
        var b = SortedMap.builder();
        var i = 0;
        while (i < xs.length) {
            b.put(xs[i], ys[i]);
            i++;
        }
        return b.build();
    }

    public static function strMap(xs:Array<Int>, ys:Array<String>):SortedMap<Int, String> {
        var b = SortedMap.builder();
        var i = 0;
        while (i < xs.length) {
            b.put(xs[i], ys[i]);
            i++;
        }
        return b.build();
    }

    public static function justify(c:Array<Cluster>, r:Array<FontRole>, e:Array<EastAsianSpacingEdges>, ir:IntRange, m:Float, ?fs:Null<Float>, ?sk:Null<Bool>,
            ?sr:Null<String>, ?al:Null<Bool>, ?ba:Null<Float>, ?mx:Null<Float>, ?ns:Null<SortedSet<Int>>, ?nsa:Null<SortedSet<Int>>, ?br:Null<SortedSet<Int>>,
            ?ph:Null<SortedSet<Int>>, ?v:Null<SortedMap<Int, Int>>, ?vs:Null<SortedSet<Int>>, ?uo:Null<SortedSet<Int>>,
            ?pr:Null<SortedMap<Int, InlineObjectPreferredStretch>>, ?te:Null<SortedMap<Int, ProgressiveBreakTier>>, ?emg:Null<SortedMap<Int, String>>,
            ?pem:Null<SortedMap<Int, String>>):JustificationPlan {
        var x = new Justifier();
        return x.justify(c, r, e, ir, m, fs == null ? em : fs, sk == null ? false : sk, sr, al == null ? true : al, ba == null ? 0.25 : ba,
            mx == null ? 0.5 : mx, ns, nsa, br, ph, v, vs, uo, pr, te, emg, pem);
    }

    public static function cjkCjk():JustifierFixture {
        return {
            c: [c("\u4E2D", 0), c("\u4E2D", 1)],
            r: [FontRole.CjkText, FontRole.CjkText],
            e: [
                e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
                e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true)
            ]
        };
    }

    public static function cjkLatin():JustifierFixture {
        return {
            c: [c("\u4E2D", 0), c("a", 1, em, "lat")],
            r: [FontRole.CjkText, FontRole.LatinText],
            e: [
                e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
                e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
            ]
        };
    }

    public static function latinSpaceLatin(?s:Null<Float>, ?a:Null<Float>, ?b:Null<Float>):JustifierFixture {
        return {
            c: [
                c("a", 0, a == null ? em : a, "lat"),
                c(" ", 1, s == null ? 4 : s, "lat"),
                c("b", 2, b == null ? em : b, "lat")
            ],
            r: [FontRole.LatinText, FontRole.LatinText, FontRole.LatinText],
            e: [
                e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
                e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
                e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
            ]
        };
    }
}

class JustifierCoverageTest {
    @:test public static function misalignedRoleAndSpacingListsAreRejected():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("misalignedRoleAndSpacingListsAreRejected");
        var f = JustifierCoverageTestSupport.cjkCjk();
        var roles3:Array<FontRole> = [f.r[0], f.r[1], FontRole.LatinText];
        var edges3:Array<EastAsianSpacingEdges> = [f.e[0], f.e[1], JustifierCoverageTestSupport.e()];
        TracedAssertions.assertFailsWith(null, function():Void {
            JustifierCoverageTestSupport.justify(f.c, roles3, f.e, new IntRange(0, 1), 64);
        });
        TracedAssertions.assertFailsWith(null, function():Void {
            JustifierCoverageTestSupport.justify(f.c, f.r, edges3, new IntRange(0, 1), 64);
        });
    }

    @:test public static function skipKeepsTheDeficitAndRecordsTheReason():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("skipKeepsTheDeficitAndRecordsTheReason");
        var f = JustifierCoverageTestSupport.cjkCjk();
        var p = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 1), 64, JustifierCoverageTestSupport.em, true, "RaggedRight");
        TracedAssertions.assertEqualsFloat(32, p.deficitBefore);
        TracedAssertions.assertEqualsFloat(32, p.unfilledDeficit);
        TracedAssertions.assertTrue(p.allocations.length == 0);
        TracedAssertions.assertEqualsString("RaggedRight", p.fallbackReason);
    }

    @:test public static function zeroDeficitReturnsAnEmptyPlanWithoutReason():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("zeroDeficitReturnsAnEmptyPlanWithoutReason");
        var f = JustifierCoverageTestSupport.cjkCjk();
        var p = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 1), 32);
        TracedAssertions.assertEqualsFloat(0, p.deficitBefore);
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
        TracedAssertions.assertTrue(p.allocations.length == 0);
        TracedAssertions.assertNullRendered(p.fallbackReason == null, "-");
    }

    @:test public static function technicalWhitespaceStretchFillsAndStopsTheTierChain():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("technicalWhitespaceStretchFillsAndStopsTheTierChain");
        var f = JustifierCoverageTestSupport.latinSpaceLatin(2);
        var j = new Justifier(null, 0.25);
        var p = j.justify(f.c, f.r, f.e, new IntRange(0, 2), 38, 16, false, null, true, 0.25, 0.5, null, null, null, null, null, null, null, null,
            JustifierCoverageTestSupport.tierMap([1], [ProgressiveBreakTier.Whitespace]), null, null);
        var a = p.allocations[0];
        TracedAssertions.assertEquals(1, a.targetClusterIndex);
        TracedAssertions.assertEqualsRendered("ProgressiveTechnical", Std.string(a.kind));
        TracedAssertions.assertEqualsString("ProgressiveTechnicalWhitespaceStretch", a.reason);
        TracedAssertions.assertEqualsFloat(4, a.delta);
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
    }

    @:test public static function technicalWhitespaceRequiresTheWhitespaceTierAndASourceSpace():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("technicalWhitespaceRequiresTheWhitespaceTierAndASourceSpace");
        var f = JustifierCoverageTestSupport.latinSpaceLatin(4);
        var wrongTier = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 2), 40, null, null, null, null, null, null, null, null, null,
            null, null, null, null, null, JustifierCoverageTestSupport.tierMap([1], [ProgressiveBreakTier.Structural]));
        TracedAssertions.assertEqualsRendered("WordSpace", Std.string(wrongTier.allocations[0].kind));
        var wrongCluster = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 2), 40, null, null, null, null, null, null, null, null, null,
            null, null, null, null, null, JustifierCoverageTestSupport.tierMap([0], [ProgressiveBreakTier.Whitespace]));
        TracedAssertions.assertEqualsRendered("WordSpace", Std.string(wrongCluster.allocations[0].kind));
    }

    @:test public static function zeroTechnicalStretchCapacityProducesNoOpportunity():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("zeroTechnicalStretchCapacityProducesNoOpportunity");
        var f = JustifierCoverageTestSupport.latinSpaceLatin(4);
        var j = new Justifier(null, 0);
        var p = j.justify(f.c, f.r, f.e, new IntRange(0, 2), 40, 16, false, null, true, 0.25, 0.5, null, null, null, null, null, null, null, null,
            JustifierCoverageTestSupport.tierMap([1], [ProgressiveBreakTier.Whitespace]), null, null);
        TracedAssertions.assertEqualsRendered("WordSpace", Std.string(p.allocations[0].kind));
    }

    @:test public static function wordSpaceStretchesWithinItsCap():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("wordSpaceStretchesWithinItsCap");
        var f = JustifierCoverageTestSupport.latinSpaceLatin(4);
        var p = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 2), 38);
        var a = p.allocations[0];
        TracedAssertions.assertEqualsRendered("WordSpace", Std.string(a.kind));
        TracedAssertions.assertEquals(1, a.targetClusterIndex);
        TracedAssertions.assertEqualsFloat(2, a.delta);
        TracedAssertions.assertEqualsString("WordSpace", a.reason);
    }

    @:test public static function wordSpaceAtTheCapOrCollapsedIsSkipped():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("wordSpaceAtTheCapOrCollapsedIsSkipped");
        var atCap = JustifierCoverageTestSupport.latinSpaceLatin(8);
        var atCapPlan = JustifierCoverageTestSupport.justify(atCap.c, atCap.r, atCap.e, new IntRange(0, 2), 48);
        TracedAssertions.assertTrue(atCapPlan.allocations.length == 0);
        TracedAssertions.assertEqualsString("WesternDominantLineNaturalSpacing", atCapPlan.fallbackReason);
        var collapsed = JustifierCoverageTestSupport.latinSpaceLatin(0);
        var collapsedPlan = JustifierCoverageTestSupport.justify(collapsed.c, collapsed.r, collapsed.e, new IntRange(0, 2), 40);
        TracedAssertions.assertTrue(collapsedPlan.allocations.length == 0);
    }

    @:test public static function spaceGapProtectionCoversAllFourDisjuncts():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("spaceGapProtectionCoversAllFourDisjuncts");
        var base = JustifierCoverageTestSupport.latinSpaceLatin(4);
        var c:Array<Cluster> = [
            base.c[0],
            base.c[1],
            base.c[2],
            JustifierCoverageTestSupport.c("\u4E2D", 3),
            JustifierCoverageTestSupport.c("x", 4, JustifierCoverageTestSupport.em, "lat")
        ];
        var r:Array<FontRole> = [base.r[0], base.r[1], base.r[2], FontRole.CjkText, FontRole.LatinText];
        var e:Array<EastAsianSpacingEdges> = [
            base.e[0],
            base.e[1],
            base.e[2],
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var v1 = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 4), 72, null, null, null, null, null, null, null,
            JustifierCoverageTestSupport.set([0]));
        var h1 = true;
        var i = 0;
        while (i < v1.allocations.length) {
            if (v1.allocations[i].kind == GlueKind.WordSpace)
                h1 = false;
            i++;
        }
        TracedAssertions.assertTrue(h1, "expected no word-space allocation for [0]/[]");
        TracedAssertions.assertEqualsFloat(0, v1.unfilledDeficit);
        var v2 = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 4), 72, null, null, null, null, null, null, null,
            JustifierCoverageTestSupport.set([1]));
        var h2 = true;
        var i2 = 0;
        while (i2 < v2.allocations.length) {
            if (v2.allocations[i2].kind == GlueKind.WordSpace)
                h2 = false;
            i2++;
        }
        TracedAssertions.assertTrue(h2, "expected no word-space allocation for [1]/[]");
        TracedAssertions.assertEqualsFloat(0, v2.unfilledDeficit);
        var v3 = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 4), 72, null, null, null, null, null, null,
            JustifierCoverageTestSupport.set([0]));
        var h3 = true;
        var i3 = 0;
        while (i3 < v3.allocations.length) {
            if (v3.allocations[i3].kind == GlueKind.WordSpace)
                h3 = false;
            i3++;
        }
        TracedAssertions.assertTrue(h3, "expected no word-space allocation for []/[0]");
        TracedAssertions.assertEqualsFloat(0, v3.unfilledDeficit);
        var v4 = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 4), 72, null, null, null, null, null, null,
            JustifierCoverageTestSupport.set([2]));
        var h4 = true;
        var i4 = 0;
        while (i4 < v4.allocations.length) {
            if (v4.allocations[i4].kind == GlueKind.WordSpace)
                h4 = false;
            i4++;
        }
        TracedAssertions.assertTrue(h4, "expected no word-space allocation for []/[2]");
        TracedAssertions.assertEqualsFloat(0, v4.unfilledDeficit);
    }

    @:test public static function virtualSinoWesternGapSkipsProtectedAndTypedEdges():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("virtualSinoWesternGapSkipsProtectedAndTypedEdges");
        var tlc = [
            JustifierCoverageTestSupport.c("\u4E2D", 0),
            JustifierCoverageTestSupport.c(" ", 1, 4),
            JustifierCoverageTestSupport.c("a", 2, JustifierCoverageTestSupport.em, "lat")
        ];
        var tlr = [FontRole.CjkText, FontRole.LatinText, FontRole.LatinText];
        var tle = [
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Wide),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var typedLeft = JustifierCoverageTestSupport.justify(tlc, tlr, tle, new IntRange(0, 2), 40);
        TracedAssertions.assertEqualsRendered("CjkLatinSpace", Std.string(typedLeft.allocations[0].kind));
        TracedAssertions.assertEquals(1, typedLeft.allocations[0].targetClusterIndex);
        var trc = [
            JustifierCoverageTestSupport.c("\u4E2D", 0),
            JustifierCoverageTestSupport.c(" a", 1, JustifierCoverageTestSupport.em, "lat"),
            JustifierCoverageTestSupport.c("b", 2, JustifierCoverageTestSupport.em, "lat")
        ];
        var tre = [
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Other),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var typedRight = JustifierCoverageTestSupport.justify(trc, tlr, tre, new IntRange(0, 2), 52);
        var ok1 = true;
        var i1 = 0;
        while (i1 < typedRight.allocations.length) {
            if (typedRight.allocations[i1].kind == GlueKind.CjkLatinSpace)
                ok1 = false;
            i1++;
        }
        TracedAssertions.assertTrue(ok1);
        var f = JustifierCoverageTestSupport.cjkLatin();
        var physical = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 1), 36, null, null, null, null, null, null, null, null, null,
            JustifierCoverageTestSupport.set([0]));
        var ok2 = true;
        var i2 = 0;
        while (i2 < physical.allocations.length) {
            if (physical.allocations[i2].kind == GlueKind.CjkLatinSpace)
                ok2 = false;
            i2++;
        }
        TracedAssertions.assertTrue(ok2);
        var closed = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 1), 36, null, null, null, null, null, null, null,
            JustifierCoverageTestSupport.set([0]));
        var ok3 = true;
        var i3 = 0;
        while (i3 < closed.allocations.length) {
            if (closed.allocations[i3].kind == GlueKind.CjkLatinSpace)
                ok3 = false;
            i3++;
        }
        TracedAssertions.assertTrue(ok3);
        TracedAssertions.assertTrue(closed.unfilledDeficit > 0);
    }

    @:test public static function attachedInlineVirtualAutoSpaceJoinsTierTwo():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("attachedInlineVirtualAutoSpaceJoinsTierTwo");
        var c = [
            JustifierCoverageTestSupport.c("\u4E2D", 0),
            JustifierCoverageTestSupport.c("", 1, 0, "obj"),
            JustifierCoverageTestSupport.c("a", 2, JustifierCoverageTestSupport.em, "lat"),
            JustifierCoverageTestSupport.c("b", 3, JustifierCoverageTestSupport.em, "lat")
        ];
        var r = [FontRole.CjkText, FontRole.Unknown, FontRole.LatinText, FontRole.LatinText];
        var e = [
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierCoverageTestSupport.e(),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var happy = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 3), 52, null, null, null, null, null, null, null, null, null, null,
            JustifierCoverageTestSupport.intMap([2], [0]), JustifierCoverageTestSupport.set([2]));
        var a = happy.allocations[0];
        TracedAssertions.assertEqualsRendered("CjkLatinSpace", Std.string(a.kind));
        TracedAssertions.assertEqualsString("AttachedInlineVirtualAutoSpace", a.reason);
        TracedAssertions.assertEquals(2, a.targetClusterIndex);
        TracedAssertions.assertEqualsFloat(4, a.delta);
        var noPrevious = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 3), 52, null, null, null, null, null, null, null, null, null, null,
            null, JustifierCoverageTestSupport.set([2]));
        var ok1 = true;
        var i1 = 0;
        while (i1 < noPrevious.allocations.length) {
            if (noPrevious.allocations[i1].reason == "AttachedInlineVirtualAutoSpace")
                ok1 = false;
            i1++;
        }
        TracedAssertions.assertTrue(ok1);
        var targetOutOfRange = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 2), 36, null, null, null, null, null, null, null, null, null,
            null, JustifierCoverageTestSupport.intMap([3], [0]), JustifierCoverageTestSupport.set([3]));
        var ok2 = true;
        var i2 = 0;
        while (i2 < targetOutOfRange.allocations.length) {
            if (targetOutOfRange.allocations[i2].reason == "AttachedInlineVirtualAutoSpace")
                ok2 = false;
            i2++;
        }
        TracedAssertions.assertTrue(ok2);
        var nextOutOfRange = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 2), 36, null, null, null, null, null, null, null, null, null, null,
            JustifierCoverageTestSupport.intMap([2], [0]), JustifierCoverageTestSupport.set([2]));
        var ok3 = true;
        var i3 = 0;
        while (i3 < nextOutOfRange.allocations.length) {
            if (nextOutOfRange.allocations[i3].reason == "AttachedInlineVirtualAutoSpace")
                ok3 = false;
            i3++;
        }
        TracedAssertions.assertTrue(ok3);
        var p0 = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 3), 52, null, null, null, null, null, null,
            JustifierCoverageTestSupport.set([0]), null, null, null, JustifierCoverageTestSupport.intMap([2], [0]), JustifierCoverageTestSupport.set([2]));
        var ok4 = true;
        var i4 = 0;
        while (i4 < p0.allocations.length) {
            if (p0.allocations[i4].reason == "AttachedInlineVirtualAutoSpace")
                ok4 = false;
            i4++;
        }
        TracedAssertions.assertTrue(ok4, "expected skip for protected [0]");
        var p3 = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 3), 52, null, null, null, null, null, null,
            JustifierCoverageTestSupport.set([3]), null, null, null, JustifierCoverageTestSupport.intMap([2], [0]), JustifierCoverageTestSupport.set([2]));
        var ok5 = true;
        var i5 = 0;
        while (i5 < p3.allocations.length) {
            if (p3.allocations[i5].reason == "AttachedInlineVirtualAutoSpace")
                ok5 = false;
            i5++;
        }
        TracedAssertions.assertTrue(ok5, "expected skip for protected [3]");
    }

    @:test public static function attachedInlineVirtualInterCharHonoursNoStretchProtection():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("attachedInlineVirtualInterCharHonoursNoStretchProtection");
        var c = [
            JustifierCoverageTestSupport.c("a", 0, JustifierCoverageTestSupport.em, "lat"),
            JustifierCoverageTestSupport.c("", 1, 0, "obj"),
            JustifierCoverageTestSupport.c("b", 2, JustifierCoverageTestSupport.em, "lat"),
            JustifierCoverageTestSupport.c("\u4E2D", 3)
        ];
        var r = [FontRole.LatinText, FontRole.Unknown, FontRole.LatinText, FontRole.CjkText];
        var e = [
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            JustifierCoverageTestSupport.e(),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Wide, true)
        ];
        var happy = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 3), 60, null, null, null, null, null, null, null, null, null, null,
            JustifierCoverageTestSupport.intMap([1], [0]));
        TracedAssertions.assertEqualsString("AttachedInlineVirtualInterChar", happy.allocations[0].reason);
        TracedAssertions.assertEqualsFloat(0, happy.unfilledDeficit);
        var v1 = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 3), 60, null, null, null, null, null, null,
            JustifierCoverageTestSupport.set([0]), null, null, null, JustifierCoverageTestSupport.intMap([1], [0]));
        var ok1 = true;
        var i1 = 0;
        while (i1 < v1.allocations.length) {
            if (v1.allocations[i1].reason == "AttachedInlineVirtualInterChar")
                ok1 = false;
            i1++;
        }
        TracedAssertions.assertTrue(ok1, "expected skip for [0]/[]");
        TracedAssertions.assertTrue(v1.unfilledDeficit > 0);
        var v2 = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 3), 60, null, null, null, null, null, null,
            JustifierCoverageTestSupport.set([2]), null, null, null, JustifierCoverageTestSupport.intMap([1], [0]));
        var ok2 = true;
        var i2 = 0;
        while (i2 < v2.allocations.length) {
            if (v2.allocations[i2].reason == "AttachedInlineVirtualInterChar")
                ok2 = false;
            i2++;
        }
        TracedAssertions.assertTrue(ok2, "expected skip for [2]/[]");
        TracedAssertions.assertTrue(v2.unfilledDeficit > 0);
        var v3 = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 3), 60, null, null, null, null, null, null, null,
            JustifierCoverageTestSupport.set([0]), null, null, JustifierCoverageTestSupport.intMap([1], [0]));
        var ok3 = true;
        var i3 = 0;
        while (i3 < v3.allocations.length) {
            if (v3.allocations[i3].reason == "AttachedInlineVirtualInterChar")
                ok3 = false;
            i3++;
        }
        TracedAssertions.assertTrue(ok3, "expected skip for []/[0]");
        TracedAssertions.assertTrue(v3.unfilledDeficit > 0);
        var promoted = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 3), 60, null, null, null, null, null, null, null, null, null, null,
            JustifierCoverageTestSupport.intMap([1], [0]), null, JustifierCoverageTestSupport.set([1]));
        var found = null;
        var i4 = 0;
        while (i4 < promoted.allocations.length) {
            if (promoted.allocations[i4].targetClusterIndex == 1)
                found = promoted.allocations[i4];
            i4++;
        }
        TracedAssertions.assertEqualsRendered("InlineObjectBoundary", Std.string(found.kind));
    }

    @:test public static function attachedInlineVirtualSinoWesternNeedsStretchEnabled():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("attachedInlineVirtualSinoWesternNeedsStretchEnabled");
        var c = [
            JustifierCoverageTestSupport.c("a", 0, JustifierCoverageTestSupport.em, "lat"),
            JustifierCoverageTestSupport.c("", 1, 0, "obj"),
            JustifierCoverageTestSupport.c("b", 2, JustifierCoverageTestSupport.em, "lat"),
            JustifierCoverageTestSupport.c("\u4E2D", 3)
        ];
        var r = [FontRole.LatinText, FontRole.Unknown, FontRole.LatinText, FontRole.CjkText];
        var e = [
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            JustifierCoverageTestSupport.e(),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Wide, true)
        ];
        var p = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 3), 60, null, null, null, false, null, null, null, null, null, null,
            JustifierCoverageTestSupport.intMap([1], [0]), JustifierCoverageTestSupport.set([1]));
        var ok = true;
        var i = 0;
        while (i < p.allocations.length) {
            if (p.allocations[i].reason == "AttachedInlineVirtualInterChar")
                ok = false;
            i++;
        }
        TracedAssertions.assertTrue(ok);
        TracedAssertions.assertTrue(p.unfilledDeficit > 0);
    }

    @:test public static function cjkLineWithNoOpportunitiesReportsUnfilledWithoutFallback():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("cjkLineWithNoOpportunitiesReportsUnfilledWithoutFallback");
        var c = [JustifierCoverageTestSupport.c("\u4E2D", 0)];
        var r = [FontRole.CjkText];
        var e = [
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true)
        ];
        var p = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 0), 20);
        TracedAssertions.assertTrue(p.allocations.length == 0);
        TracedAssertions.assertEqualsFloat(4, p.unfilledDeficit);
        TracedAssertions.assertNullRendered(p.fallbackReason == null, "-");
    }

    @:test public static function compressDistributesTierByTier():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("compressDistributesTierByTier");
        var j = new Justifier();
        var t1 = new ShrinkOpportunity(0, 1, 4, ShrinkChannel.TrailingGlue);
        var t2 = new ShrinkOpportunity(1, 2, 16, ShrinkChannel.LeadingGlue);
        var p = j.compress(12, [t2, t1]);
        TracedAssertions.assertEqualsFloat(0, p.unfilledSurplus);
        TracedAssertions.assertEqualsPushInAllocationArray([
            new PushInAllocation(0, 4, 4, ShrinkChannel.TrailingGlue),
            new PushInAllocation(1, 8, 16, ShrinkChannel.LeadingGlue)
        ], p.allocations);
    }

    @:test public static function compressEarlyExitsAndFiltersDegenerateInputs():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("compressEarlyExitsAndFiltersDegenerateInputs");
        var j = new Justifier();
        TracedAssertions.assertEqualsRendered(Std.string(new CompressionPlan([], 0, 0)), Std.string(j.compress(0, [])));
        var zero = new ShrinkOpportunity(0, 1, 0, ShrinkChannel.TrailingGlue);
        var unfilled = j.compress(8, [zero]);
        TracedAssertions.assertTrue(unfilled.allocations.length == 0);
        TracedAssertions.assertEqualsFloat(8, unfilled.unfilledSurplus);
        var big = new ShrinkOpportunity(0, 1, 16, ShrinkChannel.TrailingGlue);
        var other = new ShrinkOpportunity(1, 2, 16, ShrinkChannel.TrailingGlue);
        var capped = j.compress(8, [big, other]);
        TracedAssertions.assertEqualsPushInAllocationArray([new PushInAllocation(0, 8, 16, ShrinkChannel.TrailingGlue)], capped.allocations);
        TracedAssertions.assertEqualsFloat(0, capped.unfilledSurplus);
    }

    @:test public static function emergencyTrackingFillsTheResidualForAuthorizedBoundaries():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("emergencyTrackingFillsTheResidualForAuthorizedBoundaries");
        var c = [
            JustifierCoverageTestSupport.c("a", 0, JustifierCoverageTestSupport.em, "lat"),
            JustifierCoverageTestSupport.c("b", 1, JustifierCoverageTestSupport.em, "lat")
        ];
        var r = [FontRole.LatinText, FontRole.LatinText];
        var e = [
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var p = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 1), 36, null, null, null, null, null, null, null, null, null, null, null, null,
            null, null, null, JustifierCoverageTestSupport.strMap([0], ["token"]));
        var a = p.allocations[0];
        TracedAssertions.assertEqualsRendered("EmergencyGraphemeTracking", Std.string(a.kind));
        TracedAssertions.assertEqualsString("EmergencyGraphemeTracking:token", a.reason);
        TracedAssertions.assertEqualsFloat(4, a.delta);
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
        var preferred = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 1), 36, null, null, null, null, null, null, null, null, null, null,
            null, null, null, null, null, JustifierCoverageTestSupport.strMap([0], ["token"]), JustifierCoverageTestSupport.strMap([0], ["code"]));
        var pa = preferred.allocations[0];
        TracedAssertions.assertEqualsString("TerminalTechnicalEmergencyTracking:code", pa.reason);
        TracedAssertions.assertEqualsRendered("EmergencyGraphemeTracking", Std.string(pa.kind));
    }

    @:test public static function emptyClusterRangeDefersEveryTierLoop():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("emptyClusterRangeDefersEveryTierLoop");
        var f = JustifierCoverageTestSupport.cjkLatin();
        var p = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(1, 0), 16);
        TracedAssertions.assertTrue(p.allocations.length == 0);
        TracedAssertions.assertEqualsFloat(16, p.unfilledDeficit);
        TracedAssertions.assertEqualsString("WesternDominantLineNaturalSpacing", p.fallbackReason);
    }

    @:test public static function paragraphEdgeSpaceLinesCoverTheBoundaryGuards():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("paragraphEdgeSpaceLinesCoverTheBoundaryGuards");
        var leading = [
            JustifierCoverageTestSupport.c(" ", 0, 4),
            JustifierCoverageTestSupport.c("\u4E2D", 1),
            JustifierCoverageTestSupport.c("x", 2, JustifierCoverageTestSupport.em, "lat")
        ];
        var lr = [FontRole.LatinText, FontRole.CjkText, FontRole.LatinText];
        var le = [
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var lp = JustifierCoverageTestSupport.justify(leading, lr, le, new IntRange(0, 2), 40);
        var wc1 = 0;
        var i1 = 0;
        while (i1 < lp.allocations.length) {
            if (lp.allocations[i1].kind == GlueKind.WordSpace)
                wc1++;
            i1++;
        }
        TracedAssertions.assertEquals(0, wc1);
        var lg = null;
        var i2 = 0;
        while (i2 < lp.allocations.length) {
            if (lp.allocations[i2].kind == GlueKind.CjkLatinSpace)
                lg = lp.allocations[i2];
            i2++;
        }
        TracedAssertions.assertEquals(1, lg.targetClusterIndex);
        TracedAssertions.assertEqualsFloat(0, lp.unfilledDeficit);
        var trailing = [
            JustifierCoverageTestSupport.c("\u4E2D", 0),
            JustifierCoverageTestSupport.c("x", 1, JustifierCoverageTestSupport.em, "lat"),
            JustifierCoverageTestSupport.c(" ", 2, 4)
        ];
        var tp = JustifierCoverageTestSupport.justify(trailing, lr, le, new IntRange(0, 2), 40);
        var wc2 = 0;
        var i3 = 0;
        while (i3 < tp.allocations.length) {
            if (tp.allocations[i3].kind == GlueKind.WordSpace)
                wc2++;
            i3++;
        }
        TracedAssertions.assertEquals(0, wc2);
        var tg = null;
        var i4 = 0;
        while (i4 < tp.allocations.length) {
            if (tp.allocations[i4].kind == GlueKind.CjkLatinSpace)
                tg = tp.allocations[i4];
            i4++;
        }
        TracedAssertions.assertEquals(0, tg.targetClusterIndex);
        TracedAssertions.assertEqualsFloat(0, tp.unfilledDeficit);
    }

    @:test public static function preferredInlineObjectKindsChainUntilFilled():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("preferredInlineObjectKindsChainUntilFilled");
        var c = [
            JustifierCoverageTestSupport.c("\u4E2D", 0),
            JustifierCoverageTestSupport.c("", 1, 0, "obj"),
            JustifierCoverageTestSupport.c("\u4E2D", 2)
        ];
        var r = [FontRole.CjkText, FontRole.Unknown, FontRole.CjkText];
        var e = [
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierCoverageTestSupport.e(),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true)
        ];
        var pb = SortedMap.builder();
        pb.put(1, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.PunctuationTrailing, 4, 6));
        pb.put(0, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.Relation, 4, 6));
        var p = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 2), 36, null, null, null, null, null, null, null, null, null, null, null, null,
            null, pb.build());
        TracedAssertions.assertEquals(2, p.allocations.length);
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
        var all = true;
        var i = 0;
        while (i < p.allocations.length) {
            if (p.allocations[i].kind != GlueKind.InlineObjectPunctuationTrailing
                && p.allocations[i].kind != GlueKind.InlineObjectRelation)
                all = false;
            i++;
        }
        TracedAssertions.assertTrue(all);
    }

    @:test public static function preferredInlineObjectStretchRunsBySemanticKind():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("preferredInlineObjectStretchRunsBySemanticKind");
        var c = [
            JustifierCoverageTestSupport.c("\u4E2D", 0),
            JustifierCoverageTestSupport.c("", 1, 0, "obj"),
            JustifierCoverageTestSupport.c("\u4E2D", 2)
        ];
        var r = [FontRole.CjkText, FontRole.Unknown, FontRole.CjkText];
        var e = [
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierCoverageTestSupport.e(),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true)
        ];
        var kinds = [
            InlineObjectPreferredStretchKind.PunctuationTrailing,
            InlineObjectPreferredStretchKind.Relation,
            InlineObjectPreferredStretchKind.BinaryOperator
        ];
        var reasons = [
            "InlineObjectPunctuationTrailing",
            "InlineObjectRelation",
            "InlineObjectBinaryOperator"
        ];
        var glues = [
            "InlineObjectPunctuationTrailing",
            "InlineObjectRelation",
            "InlineObjectBinaryOperator"
        ];
        var i = 0;
        while (i < 3) {
            var pb = SortedMap.builder();
            pb.put(1, new InlineObjectPreferredStretch(kinds[i], 4, 8));
            var p = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 2), 36, null, null, null, null, null, null, null, null, null, null, null,
                null, null, pb.build());
            var a = p.allocations[0];
            TracedAssertions.assertEqualsRendered(glues[i], Std.string(a.kind));
            TracedAssertions.assertEqualsString(reasons[i], a.reason);
            TracedAssertions.assertEqualsFloat(4, a.delta);
            TracedAssertions.assertEquals(2, a.priority);
            i++;
        }
        var pb2 = SortedMap.builder();
        pb2.put(1, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.Relation, 4, 8));
        var atEnd = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 1), 20, null, null, null, null, null, null, null, null, null, null, null,
            null, null, pb2.build());
        TracedAssertions.assertTrue(atEnd.allocations.length == 0);
        TracedAssertions.assertEqualsFloat(4, atEnd.unfilledDeficit);
        var pb3 = SortedMap.builder();
        pb3.put(1, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.Relation, 4, 8));
        var closed = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 2), 36, null, null, null, null, null, null, null,
            JustifierCoverageTestSupport.set([1]), null, null, null, null, null, pb3.build());
        TracedAssertions.assertEqualsFloat(4, closed.unfilledDeficit);
        var ok = true;
        var i5 = 0;
        while (i5 < closed.allocations.length) {
            if (closed.allocations[i5].kind == GlueKind.InlineObjectRelation)
                ok = false;
            i5++;
        }
        TracedAssertions.assertTrue(ok);
    }

    @:test public static function sinoWesternStretchDisabledSkipsTierTwoAndItsVirtualTracking():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("sinoWesternStretchDisabledSkipsTierTwoAndItsVirtualTracking");
        var f = JustifierCoverageTestSupport.cjkLatin();
        var p = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 1), 36, null, null, null, false);
        TracedAssertions.assertTrue(p.allocations.length == 0);
        TracedAssertions.assertEqualsFloat(4, p.unfilledDeficit);
    }

    @:test public static function typedSinoWesternSpaceNeedsBothEdgesToPair():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("typedSinoWesternSpaceNeedsBothEdgesToPair");
        var c = [
            JustifierCoverageTestSupport.c("\u4E2D", 0),
            JustifierCoverageTestSupport.c(" ", 1, 4),
            JustifierCoverageTestSupport.c("\u4E2D", 2)
        ];
        var r = [FontRole.CjkText, FontRole.LatinText, FontRole.CjkText];
        var e = [
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true)
        ];
        var p = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 2), 40);
        var ok = true;
        var i = 0;
        while (i < p.allocations.length) {
            if (p.allocations[i].kind == GlueKind.WordSpace || p.allocations[i].kind == GlueKind.CjkLatinSpace)
                ok = false;
            i++;
        }
        TracedAssertions.assertTrue(ok);
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
    }

    @:test public static function typedSinoWesternSpaceStretchesFromItsBase():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("typedSinoWesternSpaceStretchesFromItsBase");
        var c = [
            JustifierCoverageTestSupport.c("\u4E2D", 0),
            JustifierCoverageTestSupport.c(" ", 1, 2),
            JustifierCoverageTestSupport.c("b", 2, JustifierCoverageTestSupport.em, "lat")
        ];
        var r = [FontRole.CjkText, FontRole.LatinText, FontRole.LatinText];
        var e = [
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var p = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 2), 38);
        var a = p.allocations[0];
        TracedAssertions.assertEqualsRendered("CjkLatinSpace", Std.string(a.kind));
        TracedAssertions.assertEquals(1, a.targetClusterIndex);
        TracedAssertions.assertEqualsFloat(4, a.delta);
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
        var atCap = [
            JustifierCoverageTestSupport.c("\u4E2D", 0),
            JustifierCoverageTestSupport.c(" ", 1, 8),
            JustifierCoverageTestSupport.c("b", 2, JustifierCoverageTestSupport.em, "lat")
        ];
        var ap = JustifierCoverageTestSupport.justify(atCap, r, e, new IntRange(0, 2), 44);
        var n1 = 0;
        var i1 = 0;
        while (i1 < ap.allocations.length) {
            if (ap.allocations[i1].kind == GlueKind.CjkLatinSpace)
                n1++;
            i1++;
        }
        TracedAssertions.assertEquals(0, n1);
        var n2 = 0;
        var i2 = 0;
        while (i2 < ap.allocations.length) {
            if (ap.allocations[i2].kind == GlueKind.CjkInterChar)
                n2++;
            i2++;
        }
        TracedAssertions.assertEquals(2, n2);
        TracedAssertions.assertEqualsFloat(0, ap.unfilledDeficit);
        var collapsed = [
            JustifierCoverageTestSupport.c("\u4E2D", 0),
            JustifierCoverageTestSupport.c(" ", 1, 0),
            JustifierCoverageTestSupport.c("b", 2, JustifierCoverageTestSupport.em, "lat")
        ];
        var cp = JustifierCoverageTestSupport.justify(collapsed, r, e, new IntRange(0, 2), 36, null, null, null, null, 0.25, 0.25);
        var ok = true;
        var i3 = 0;
        while (i3 < cp.allocations.length) {
            if (cp.allocations[i3].targetClusterIndex == 1 && cp.allocations[i3].delta > 0)
                ok = false;
            i3++;
        }
        TracedAssertions.assertTrue(ok);
    }

    @:test public static function uniformObjectBoundaryOpensTheGateAndFills():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("uniformObjectBoundaryOpensTheGateAndFills");
        var f = JustifierCoverageTestSupport.latinSpaceLatin(8);
        var p = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 2), 64, null, null, null, null, null, null, null, null, null, null, null,
            null, JustifierCoverageTestSupport.set([0]));
        TracedAssertions.assertNullRendered(p.fallbackReason == null, "-");
        var has = false;
        var i = 0;
        while (i < p.allocations.length) {
            if (p.allocations[i].kind == GlueKind.InlineObjectBoundary)
                has = true;
            i++;
        }
        TracedAssertions.assertTrue(has);
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
    }

    @:test public static function uniformTextBoundariesExcludeProtectedClasses():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("uniformTextBoundariesExcludeProtectedClasses");
        var f = JustifierCoverageTestSupport.cjkLatin();
        var plain = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 1), 36, null, null, null, null, null, 0.25);
        TracedAssertions.assertEqualsRendered("CjkInterChar", Std.string(plain.allocations[0].kind));
        var bracket = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 1), 36, null, null, null, null, null, 0.25, null, null,
            JustifierCoverageTestSupport.set([0]));
        TracedAssertions.assertEqualsString("WesternBracketCjkInterChar", bracket.allocations[0].reason);
        var physical = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 1), 36, null, null, null, null, null, 0.25, null, null, null,
            JustifierCoverageTestSupport.set([0]));
        TracedAssertions.assertEqualsFloat(4, physical.unfilledDeficit);
        var virtualOwned = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 1), 36, null, null, null, null, null, 0.25, null, null, null,
            null, JustifierCoverageTestSupport.intMap([0], [-1]));
        TracedAssertions.assertEqualsString("AttachedInlineVirtualInterChar", virtualOwned.allocations[0].reason);
        var uniformObject = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 1), 36, null, null, null, null, null, 0.25, null, null, null,
            null, null, null, JustifierCoverageTestSupport.set([0]));
        TracedAssertions.assertEqualsRendered("InlineObjectBoundary", Std.string(uniformObject.allocations[0].kind));
        var bracketPhysical = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 1), 36, null, null, null, null, null, 0.25, null, null,
            JustifierCoverageTestSupport.set([0]), JustifierCoverageTestSupport.set([0]));
        TracedAssertions.assertEqualsFloat(4, bracketPhysical.unfilledDeficit);
        var bracketObject = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 1), 36, null, null, null, null, null, 0.25, null, null,
            JustifierCoverageTestSupport.set([0]), null, null, null, JustifierCoverageTestSupport.set([0]));
        TracedAssertions.assertEqualsRendered("InlineObjectBoundary", Std.string(bracketObject.allocations[0].kind));
    }

    @:test public static function westernDominantLineStaysRagged():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("westernDominantLineStaysRagged");
        var f = JustifierCoverageTestSupport.latinSpaceLatin(8);
        var p = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 2), 64);
        TracedAssertions.assertEqualsString("WesternDominantLineNaturalSpacing", p.fallbackReason);
        TracedAssertions.assertTrue(p.unfilledDeficit > 0);
        var closedObject = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 2), 64, null, null, null, null, null, null, null,
            JustifierCoverageTestSupport.set([0]), null, null, null, null, JustifierCoverageTestSupport.set([0]));
        TracedAssertions.assertEqualsString("WesternDominantLineNaturalSpacing", closedObject.fallbackReason);
    }

    @:test public static function mixedCapacitySinoWesternOppsSkipZeroCapacityInOverflow():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("mixedCapacitySinoWesternOppsSkipZeroCapacityInOverflow");
        var c = [
            JustifierCoverageTestSupport.c("\u4E2D", 0),
            JustifierCoverageTestSupport.c(" ", 1, 2),
            JustifierCoverageTestSupport.c("a", 2, JustifierCoverageTestSupport.em, "lat")
        ];
        var r = [FontRole.CjkText, FontRole.LatinText, FontRole.LatinText];
        var e = [
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide, true),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            JustifierCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var p = JustifierCoverageTestSupport.justify(c, r, e, new IntRange(0, 2), 40, null, null, null, null, null, 0.25);
        var tier2 = [];
        var i = 0;
        while (i < p.allocations.length) {
            if (p.allocations[i].kind == GlueKind.CjkLatinSpace)
                tier2.push(p.allocations[i]);
            i++;
        }
        var idxs = [];
        var i2 = 0;
        while (i2 < tier2.length) {
            idxs.push(tier2[i2].targetClusterIndex);
            i2++;
        }
        TracedAssertions.assertEqualsIntArray([1], idxs);
        TracedAssertions.assertEqualsFloat(2, tier2[0].delta);
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
    }

    @:test public static function zeroCapacitySinoWesternTierDefersEverythingDownward():Void {
        new TestTraceRecorder("JustifierCoverageTest").section("zeroCapacitySinoWesternTierDefersEverythingDownward");
        var f = JustifierCoverageTestSupport.cjkLatin();
        var p = JustifierCoverageTestSupport.justify(f.c, f.r, f.e, new IntRange(0, 1), 36, null, null, null, null, null, 0.25);
        TracedAssertions.assertEqualsFloat(0, p.unfilledDeficit);
        var a = p.allocations[0];
        TracedAssertions.assertEqualsRendered("CjkInterChar", Std.string(a.kind));
        TracedAssertions.assertEqualsFloat(4, a.delta);
    }
}
