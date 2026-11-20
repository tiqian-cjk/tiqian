package org.tiqian.core;

class IntRange {
    public final start:Int;
    public final end:Int;

    public function new(start:Int, end:Int) {
        this.start = start;
        this.end = end;
    }

    public var isEmpty(get, never):Bool;

    /** kotlin.ranges.IntRange exposes first/last; consumers read them directly. */
    public var first(get, never):Int;
    public var last(get, never):Int;

    public function get_first():Int {
        return start;
    }

    public function get_last():Int {
        return end;
    }

    public function get_isEmpty():Bool {
        return start > end;
    }

    /** kotlin.ranges.IntRange prints "start..end" through ClosedRange's explicit toString. */
    public function toString():String {
        return start + ".." + end;
    }
}
