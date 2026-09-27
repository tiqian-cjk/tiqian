package org.tiqian.core;

@:dataClass
class LineLengthGrid {
    public final enabled:Bool;
    public final bodyAlignment:Null<LastLineAlignment>;

    public function new(?enabled:Null<Bool>, ?bodyAlignment:Null<LastLineAlignment>) {
        this.enabled = enabled == null ? true : enabled;
        this.bodyAlignment = bodyAlignment == null ? null : bodyAlignment;
    }
}
