package org.tiqian.layout;

import org.tiqian.core.IntRange;
import org.tiqian.core.LineEndReason;
import org.tiqian.core.TextRange;
import org.tiqian.core.TextRangeError;
import org.tiqian.core.TiqianIllegalArgumentException;
import org.tiqian.linebreak.BreakKind;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import std.SortedSet;

@:dataClass
class BreakCandidate {
    public final index:Int;
    public final kind:BreakKind;
    public final naturalWidth:Float;
    public final compressedWidth:Float;
    public final expandedWidth:Float;
    public final forbiddenReason:Null<String>;
    public final repairOptions:Array<RepairOption>;

    public function new(index:Int, kind:BreakKind, naturalWidth:Float, compressedWidth:Float, expandedWidth:Float, ?forbiddenReason:Null<String>,
            ?repairOptions:Null<Array<RepairOption>>) {
        this.index = index;
        this.kind = kind;
        this.naturalWidth = naturalWidth;
        this.compressedWidth = compressedWidth;
        this.expandedWidth = expandedWidth;
        this.forbiddenReason = forbiddenReason;
        this.repairOptions = repairOptions == null ? [] : repairOptions;
    }
}

/**
 * Kotlin models this as a sealed interface with five data classes; the port
 * carries it as an enum with payloads. Haxe enum constructors take no
 * defaults, so the Kotlin interface reads (penalty, reason) are pattern
 * bindings read through switches in RepairOptions.
 */
enum RepairOption {
    /**
     * CLREQ 推入 semantics — compress in-line glue to make the offender
     * fit on the previous line. The shrink is distributed across every
     * cluster in the merged line whose punctuation atoms still have
     * compressible trailing glue (after spacing-compression and edge-trim
     * have run). Listed in cluster order.
     */
    PushIn(penalty:Int, reason:String, offenderClusterIndex:Int, allocations:Array<PushInAllocation>, totalShrink:Float, totalAvailableCapacity:Float);

    Hang(penalty:Int, reason:String, offenderClusterIndex:Int);
    CarryPrevious(penalty:Int, reason:String, offenderClusterIndex:Int, carriedClusterIndex:Int);

    /**
     * CLREQ 行尾禁则: a forbidden-at-line-end mark (开引号/开括号; GB·严格
     * 追加分隔号) at the line's end is moved to the NEXT line's start. The
     * break retreats past it — only the current line shortens, so no
     * overflow cascade. movedClusterIndex is the mark moved down.
     */
    CarryNext(penalty:Int, reason:String, movedClusterIndex:Int);

    LeaveRagged(penalty:Int, reason:String, offenderClusterIndex:Int);
}

/**
 * Member logic the Kotlin RepairOption interface held as abstract members.
 * Printed forms come from Std.string under the stage-one forms ruling.
 */
class RepairOptions {
    public static function penalty(o:RepairOption):Int
        return switch (o) {
            case PushIn(p, _, _, _, _, _): p;
            case Hang(p, _, _): p;
            case CarryPrevious(p, _, _, _): p;
            case CarryNext(p, _, _): p;
            case LeaveRagged(p, _, _): p;
        };

    public static function reason(o:RepairOption):String
        return switch (o) {
            case PushIn(_, r, _, _, _, _): r;
            case Hang(_, r, _): r;
            case CarryPrevious(_, r, _, _): r;
            case CarryNext(_, r, _): r;
            case LeaveRagged(_, r, _): r;
        };

    public static function hangOffender(o:RepairOption):Null<Int>
        return switch (o) {
            case Hang(_, _, offender): offender;
            case PushIn(_, _, _, _, _, _): null;
            case CarryPrevious(_, _, _, _): null;
            case CarryNext(_, _, _): null;
            case LeaveRagged(_, _, _): null;
        };

    public static function pushInReasonOf(o:RepairOption):Null<String>
        return switch (o) {
            case PushIn(_, reason, _, _, _, _): reason;
            case Hang(_, _, _): null;
            case CarryPrevious(_, _, _, _): null;
            case CarryNext(_, _, _): null;
            case LeaveRagged(_, _, _): null;
        };

    public static function pushInAllocations(o:RepairOption):Null<Array<PushInAllocation>>
        return switch (o) {
            case PushIn(_, _, _, allocations, _, _): allocations;
            case Hang(_, _, _): null;
            case CarryPrevious(_, _, _, _): null;
            case CarryNext(_, _, _): null;
            case LeaveRagged(_, _, _): null;
        };
}

@:dataClass
class PushInAllocation {
    public final clusterIndex:Int;
    public final shrink:Float;
    public final availableCapacity:Float;

    /** Which resource the shrink consumes (ADR 0020). */
    public final channel:ShrinkChannel;

    public function new(clusterIndex:Int, shrink:Float, availableCapacity:Float, ?channel:Null<ShrinkChannel>) {
        this.clusterIndex = clusterIndex;
        this.shrink = shrink;
        this.availableCapacity = availableCapacity;
        this.channel = channel == null ? ShrinkChannel.TrailingGlue : channel;
    }
}

@:dataClass
class LineCandidate {
    public final clusterRange:IntRange;
    public final sourceRange:TextRange;
    public final naturalWidth:Float;
    public final adjustedWidth:Float;
    public final endReason:LineEndReason;
    public final repair:Null<RepairOption>;
    public final repairCandidates:Array<RepairCandidate>;

    /**
     * `LineEndHangingPunctuation`: the contiguous trailing suffix excluded
     * from the measure. It contains the hung mark(s), plus any zero-width
     * mandatory-break control structurally attached after them. The ordinary
     * profile path still hangs at most one mark; an impossible-width contextual
     * point-mark run may extend the same hang so none of its styled/shaped
     * clusters is left at line start.
     */
    public final hangingClusterIndices:SortedSet<Int>;

    public function new(clusterRange:IntRange, sourceRange:TextRange, naturalWidth:Float, adjustedWidth:Float, ?endReason:Null<LineEndReason>,
            ?repair:Null<RepairOption>, ?repairCandidates:Null<Array<RepairCandidate>>, ?hangingClusterIndices:Null<SortedSet<Int>>) {
        this.clusterRange = clusterRange;
        this.sourceRange = sourceRange;
        this.naturalWidth = naturalWidth;
        this.adjustedWidth = adjustedWidth;
        this.endReason = endReason == null ? LineEndReason.AutoWrap : endReason;
        this.repair = repair;
        this.repairCandidates = repairCandidates == null ? [] : repairCandidates;
        this.hangingClusterIndices = hangingClusterIndices == null ? LineCandidate.emptyHanging() : hangingClusterIndices;
        if (this.hangingClusterIndices.size() > 0) {
            final firstHanging = this.hangingClusterIndices.at(0);
            final lastHanging = this.hangingClusterIndices.at(this.hangingClusterIndices.size() - 1);
            if (!(clusterRange.start <= firstHanging && firstHanging <= clusterRange.end && lastHanging == clusterRange.end))
                throw new TiqianIllegalArgumentException(Message("Hanging clusters must be a trailing line suffix: line="
                    + LineCandidates.renderRange(clusterRange) + " hanging=" + Std.string(this.hangingClusterIndices)));
            if (this.hangingClusterIndices.size() != clusterRange.end - firstHanging + 1)
                throw new TiqianIllegalArgumentException(Message("Hanging clusters must be contiguous: line=" + LineCandidates.renderRange(clusterRange)
                    + " hanging=" + Std.string(this.hangingClusterIndices)));
        }
    }

    /**
     * Compatibility/convenience view of the last actual hanging mark. A
     * mandatory-break control may follow it inside hangingClusterIndices,
     * so prefer the selected Hang offender over the suffix's final index.
     */
    public var hangingClusterIndex(get, never):Null<Int>;

    public function get_hangingClusterIndex():Null<Int> {
        final fromRepair = repair == null ? null : RepairOptions.hangOffender(repair);
        final last = hangingClusterIndices.size() == 0 ? null : hangingClusterIndices.at(hangingClusterIndices.size() - 1);
        return fromRepair != null ? fromRepair : last;
    }

    /** Clusters that remain inside the measure and participate in fill scoring/justification. */
    public var inMeasureClusterRange(get, never):IntRange;

    public function get_inMeasureClusterRange():IntRange {
        final firstHanging = hangingClusterIndices.size() == 0 ? null : hangingClusterIndices.at(0);
        return firstHanging == null ? clusterRange : new IntRange(clusterRange.start, firstHanging - 1);
    }

    static function emptyHanging():SortedSet<Int> {
        final b = SortedSet.builder();
        return b.build();
    }
}

/** Text helper for LineCandidate's requirement messages (Kotlin renders IntRange as 0..4). */
class LineCandidates {
    public static function renderRange(r:IntRange):String
        return r.start + ".." + r.end;
}

@:dataClass
class RepairCandidate {
    public final kind:String;
    public final reasonCode:String;
    public final offenderClusterIndex:Int;
    public final penalty:Int;
    public final accepted:Bool;
    public final rejectionReason:Null<String>;
    public final targetClusterIndex:Null<Int>;
    public final carriedClusterIndex:Null<Int>;
    public final shrink:Float;
    public final requiredShrink:Float;
    public final availableCapacity:Float;

    public function new(kind:String, reasonCode:String, offenderClusterIndex:Int, penalty:Int, accepted:Bool, ?rejectionReason:Null<String>,
            ?targetClusterIndex:Null<Int>, ?carriedClusterIndex:Null<Int>, ?shrink:Null<Float>, ?requiredShrink:Null<Float>, ?availableCapacity:Null<Float>) {
        this.kind = kind;
        this.reasonCode = reasonCode;
        this.offenderClusterIndex = offenderClusterIndex;
        this.penalty = penalty;
        this.accepted = accepted;
        this.rejectionReason = rejectionReason;
        this.targetClusterIndex = targetClusterIndex;
        this.carriedClusterIndex = carriedClusterIndex;
        this.shrink = shrink == null ? 0 : shrink;
        this.requiredShrink = requiredShrink == null ? 0 : requiredShrink;
        this.availableCapacity = availableCapacity == null ? 0 : availableCapacity;
    }
}

@:dataClass
class LineSolution {
    public final lines:Array<LineCandidate>;
    public final totalBadness:Float;

    public function new(?lines:Null<Array<LineCandidate>>, ?totalBadness:Null<Float>) {
        this.lines = lines == null ? [] : lines;
        this.totalBadness = totalBadness == null ? 0 : totalBadness;
    }
}

enum LineOptimizationStrategy {
    Greedy;
    Lookahead;
    ParagraphDynamicProgramming;
}
