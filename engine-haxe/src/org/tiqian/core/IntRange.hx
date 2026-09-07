package org.tiqian.core;

class IntRange {
    public final start:Int;
    public final end:Int;

    public function new(start:Int, end:Int) {
        this.start = start;
        this.end = end;
    }

    public var isEmpty(get, never):Bool;

    public function get_isEmpty():Bool {
        return start > end;
    }

    /** kotlin.ranges.IntRange prints "start..end" through ClosedRange's explicit toString. */
    public function toString():String {
        return start + ".." + end;
    }
}
