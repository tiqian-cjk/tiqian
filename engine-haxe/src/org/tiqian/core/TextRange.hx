package org.tiqian.core;

@:dataClass
class TextRange {
    public final start:Int;
    public final end:Int;

    public function new(start:Int, end:Int) {
        if (start > end) {
            throw new TiqianIllegalArgumentException(StartGreaterThanEnd);
        }
        if (start < 0) {
            throw new TiqianIllegalArgumentException(NegativeStart);
        }
        this.start = start;
        this.end = end;
    }

    public var length(get, never):Int;

    public function get_length():Int {
        return end - start;
    }

    public var isEmpty(get, never):Bool;

    public function get_isEmpty():Bool {
        return length == 0;
    }
}
