package org.tiqian.layout;

import org.tiqian.core.IntRange;
import org.tiqian.core.TextRange;
import org.tiqian.linebreak.BreakKind;
import org.tiqian.layout.LineOptimization.BreakCandidate;
import org.tiqian.layout.LineOptimization.LineCandidate;
import org.tiqian.layout.LineOptimization.LineSolution;
import org.tiqian.layout.LineOptimization.RepairCandidate;
import org.tiqian.layout.LineOptimization.RepairOption;
import org.tiqian.layout.LineOptimization.RepairOptions;
import org.tiqian.layout.LineOptimization.LineOptimizationStrategy;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedSet;

/**
 * Coverage for LineOptimization: the BreakCandidate default-parameter
 * constructors, the LineCandidate hanging-suffix invariants, the hanging
 * index / in-measure views, the repair variants (CarryNext included), and
 * the strategy enum entries.
 */
class LineOptimizationCoverageTest {
    @:test public static function breakCandidateDefaultsAreUsable():Void {
        LineOptimizationCoverageSupport.start("breakCandidateDefaultsAreUsable");
        final candidate = new BreakCandidate(3, BreakKind.Allowed, 16.0, 14.0, 18.0);
        TracedAssertions.assertNullRendered(candidate.forbiddenReason == null, "-");
        TracedAssertions.assertTrue(candidate.repairOptions.length == 0);
    }

    @:test public static function breakCandidateCarriesExplicitForbiddenReasonAndRepairs():Void {
        LineOptimizationCoverageSupport.start("breakCandidateCarriesExplicitForbiddenReasonAndRepairs");
        final repair = RepairOption.LeaveRagged(30, "ForbiddenAtLineStart:，:leave-ragged", 3);
        final candidate = new BreakCandidate(2, BreakKind.Problematic, 32.0, 28.0, 36.0, "kinsoku", [repair]);
        TracedAssertions.assertEqualsString("kinsoku", candidate.forbiddenReason);
        TracedAssertions.assertEqualsRepairOptionArray([repair], candidate.repairOptions);
    }

    @:test public static function lineCandidateRejectsHangingThatIsNotATrailingSuffix():Void {
        LineOptimizationCoverageSupport.start("lineCandidateRejectsHangingThatIsNotATrailingSuffix");
        TracedAssertions.assertFailsWith(null, function() LineOptimizationCoverageSupport.line(LineOptimizationCoverageSupport.set([0, 1])));
        // In range but not reaching the last cluster: same invariant.
        TracedAssertions.assertFailsWith(null, function() LineOptimizationCoverageSupport.line(LineOptimizationCoverageSupport.set([2, 3])));
        // Outside the line entirely: the first conjunct rejects it.
        TracedAssertions.assertFailsWith(null, function() LineOptimizationCoverageSupport.line(LineOptimizationCoverageSupport.set([7])));
    }

    @:test public static function lineCandidateRejectsDiscontiguousHanging():Void {
        LineOptimizationCoverageSupport.start("lineCandidateRejectsDiscontiguousHanging");
        TracedAssertions.assertFailsWith(null, function() LineOptimizationCoverageSupport.line(LineOptimizationCoverageSupport.set([2, 4])));
    }

    @:test public static function lineCandidateAcceptsAContiguousTrailingHangingSuffix():Void {
        LineOptimizationCoverageSupport.start("lineCandidateAcceptsAContiguousTrailingHangingSuffix");
        final line = LineOptimizationCoverageSupport.line(LineOptimizationCoverageSupport.set([3, 4]));
        TracedAssertions.assertEqualsIntSet(LineOptimizationCoverageSupport.set([3, 4]), line.hangingClusterIndices);
    }

    @:test public static function hangingClusterIndexPrefersTheHangOffenderOverTheSuffixEnd():Void {
        LineOptimizationCoverageSupport.start("hangingClusterIndexPrefersTheHangOffenderOverTheSuffixEnd");
        final withRepair = LineOptimizationCoverageSupport.line(LineOptimizationCoverageSupport.set([3, 4]),
            RepairOption.Hang(5, "ForbiddenAtLineStart:，:hang", 3));
        TracedAssertions.assertEqualsNullableInt(3, withRepair.hangingClusterIndex);

        final withoutRepair = LineOptimizationCoverageSupport.line(LineOptimizationCoverageSupport.set([3, 4]));
        TracedAssertions.assertEqualsNullableInt(4, withoutRepair.hangingClusterIndex);
    }

    @:test public static function inMeasureClusterRangeExcludesTheHangingSuffix():Void {
        LineOptimizationCoverageSupport.start("inMeasureClusterRangeExcludesTheHangingSuffix");
        final hanging = LineOptimizationCoverageSupport.line(LineOptimizationCoverageSupport.set([3, 4]));
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), hanging.inMeasureClusterRange);

        final plain = LineOptimizationCoverageSupport.line(null);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 4), plain.inMeasureClusterRange);
    }

    @:test public static function carryNextRecordsTheMovedMark():Void {
        LineOptimizationCoverageSupport.start("carryNextRecordsTheMovedMark");
        final carryNext = RepairOption.CarryNext(15, "ForbiddenAtLineEnd:“:carry-next", 4);
        TracedAssertions.assertEquals(15, RepairOptions.penalty(carryNext));
        TracedAssertions.assertEquals(4, LineOptimizationCoverageSupport.movedIndex(carryNext));
        TracedAssertions.assertEqualsString("ForbiddenAtLineEnd:“:carry-next", RepairOptions.reason(carryNext));
    }

    @:test public static function repairCandidateDefaultsAreUsable():Void {
        LineOptimizationCoverageSupport.start("repairCandidateDefaultsAreUsable");
        final candidate = new RepairCandidate("PushIn", "ForbiddenAtLineStart", 4, 10, true);
        TracedAssertions.assertNullRendered(candidate.rejectionReason == null, "-");
        TracedAssertions.assertNullRendered(candidate.targetClusterIndex == null, "-");
        TracedAssertions.assertNullRendered(candidate.carriedClusterIndex == null, "-");
        TracedAssertions.assertEqualsFloat(0, candidate.shrink);
        TracedAssertions.assertEqualsFloat(0, candidate.requiredShrink);
        TracedAssertions.assertEqualsFloat(0, candidate.availableCapacity);
    }

    @:test public static function lineSolutionDefaultsToZeroBadness():Void {
        LineOptimizationCoverageSupport.start("lineSolutionDefaultsToZeroBadness");
        final solution = new LineSolution(null);
        TracedAssertions.assertEqualsFloat(0, solution.totalBadness);
    }

    @:test public static function optimizationStrategyEnumeratesAllThreeStrategies():Void {
        LineOptimizationCoverageSupport.start("optimizationStrategyEnumeratesAllThreeStrategies");
        TracedAssertions.assertEqualsRendered("[Greedy, Lookahead, ParagraphDynamicProgramming]", LineOptimizationCoverageSupport.renderStrategies());
    }
}

/** Shared fixtures and traced-assertion helpers for LineOptimizationCoverageTest; the Kotlin test-class lowering admits test functions only. */
class LineOptimizationCoverageSupport {
    public static function start(n:String):Void
        new TestTraceRecorder("LineOptimizationCoverageTest").section(n);

    public static function set(values:Array<Int>):SortedSet<Int> {
        final b = SortedSet.builder();
        var i = 0;
        while (i < values.length) {
            b.put(values[i]);
            i++;
        }
        return b.build();
    }

    public static function line(?hanging:Null<SortedSet<Int>>, ?repair:Null<RepairOption>):LineCandidate {
        return new LineCandidate(new IntRange(0, 4), new TextRange(0, 5), 80.0, 80.0, null, repair, null, hanging);
    }

    public static function movedIndex(o:RepairOption):Int
        return switch (o) {
            case CarryNext(_, _, moved): moved;
            case PushIn(_, _, _, _, _, _): -1;
            case Hang(_, _, _): -1;
            case CarryPrevious(_, _, _, _): -1;
            case LeaveRagged(_, _, _): -1;
        };

    /** Renders every declared strategy; the allEnums collection is only read at length and index positions (spec 28). */
    public static function renderStrategies():String {
        final values:Array<LineOptimizationStrategy> = Type.allEnums(LineOptimizationStrategy);
        final buf = new StringBuf();
        buf.add("[");
        var i = 0;
        while (i < values.length) {
            if (i > 0)
                buf.add(", ");
            buf.add(Type.enumConstructor(values[i]));
            i++;
        }
        buf.add("]");
        return buf.toString();
    }
}
