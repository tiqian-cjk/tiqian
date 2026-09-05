package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.TextRange;
import org.tiqian.layout.LineOptimization.RepairOption;
import org.tiqian.layout.LineOptimization.PushInAllocation;
import org.tiqian.test.trace.TracedAssertions;

class PushInLineWideCapacityTestSupport {
    public static function cluster(s:Int, e:Int, text:String, a:Float):Cluster
        return new Cluster(new TextRange(s, e), text, "test", a);

    public static function pushInString(o:RepairOption):String
        return switch (o) {
            case PushIn(penalty, reason, offender, allocations, shrink, capacity):
                "PushIn(penalty="
                + penalty
                + ", reason="
                + reason
                + ", offenderClusterIndex="
                + offender
                + ", allocations="
                + Std.string(allocations)
                + ", totalShrink="
                + shrink
                + ", totalAvailableCapacity="
                + capacity
                + ")";
            case Hang(_, _, _): Std.string(o);
            case CarryPrevious(_, _, _, _): Std.string(o);
            case CarryNext(_, _, _): Std.string(o);
            case LeaveRagged(_, _, _): Std.string(o);
        };

    public static function pushInAllocations(o:RepairOption):Array<PushInAllocation>
        return switch (o) {
            case PushIn(_, _, _, alloc, _, _): alloc;
            case Hang(_, _, _): [];
            case CarryPrevious(_, _, _, _): [];
            case CarryNext(_, _, _): [];
            case LeaveRagged(_, _, _): [];
        };

    public static function pushInOffenderClusterIndex(o:RepairOption):Int
        return switch (o) {
            case PushIn(_, _, offender, _, _, _): offender;
            case Hang(_, _, _): -1;
            case CarryPrevious(_, _, _, _): -1;
            case CarryNext(_, _, _): -1;
            case LeaveRagged(_, _, _): -1;
        };

    public static function pushInTotalShrink(o:RepairOption):Float
        return switch (o) {
            case PushIn(_, _, _, _, shrink, _): shrink;
            case Hang(_, _, _): 0;
            case CarryPrevious(_, _, _, _): 0;
            case CarryNext(_, _, _): 0;
            case LeaveRagged(_, _, _): 0;
        };

    public static function pushInTotalAvailableCapacity(o:RepairOption):Float
        return switch (o) {
            case PushIn(_, _, _, _, _, capacity): capacity;
            case Hang(_, _, _): 0;
            case CarryPrevious(_, _, _, _): 0;
            case CarryNext(_, _, _): 0;
            case LeaveRagged(_, _, _): 0;
        };

    public static function isPushIn(o:RepairOption):Bool
        return switch (o) {
            case PushIn(_, _, _, _, _, _): true;
            case Hang(_, _, _): false;
            case CarryPrevious(_, _, _, _): false;
            case CarryNext(_, _, _): false;
            case LeaveRagged(_, _, _): false;
        };

    public static function isCarryPrevious(o:RepairOption):Bool
        return switch (o) {
            case PushIn(_, _, _, _, _, _): false;
            case Hang(_, _, _): false;
            case CarryPrevious(_, _, _, _): true;
            case CarryNext(_, _, _): false;
            case LeaveRagged(_, _, _): false;
        };

    public static function isLeaveRagged(o:RepairOption):Bool
        return switch (o) {
            case PushIn(_, _, _, _, _, _): false;
            case Hang(_, _, _): false;
            case CarryPrevious(_, _, _, _): false;
            case CarryNext(_, _, _): false;
            case LeaveRagged(_, _, _): true;
        };
}
