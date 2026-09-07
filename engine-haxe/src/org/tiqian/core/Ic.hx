package org.tiqian.core;

/** Unit value used for a count of CJK 字身框 cells. */
@:valueType
abstract Ic(Float) from Float {
    public inline function new(count:Float)
        this = count;

    public inline function count():Float
        return this;

    public function toPx(emPx:Float):Float
        return this * emPx;

    @:op(A + B)
    public static inline function plus(a:Ic, b:Ic):Ic
        return new Ic(a.count() + b.count());

    @:op(-A)
    public static inline function unaryMinus(a:Ic):Ic
        return new Ic(-a.count());

    public static var Zero:Ic = new Ic(0.0);

    public function toString():String
        return "Ic(count=" + Std.string(count()) + ")";
}
