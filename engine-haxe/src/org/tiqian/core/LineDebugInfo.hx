package org.tiqian.core;

@:dataClass class LineDebugInfo {
    public final repair:Null<String>;
    public final notes:Array<String>;

    /** The published no-argument default, used by LineBox's debug parameter. */
    public static final Default:LineDebugInfo = new LineDebugInfo(null);

    public function new(repair:Null<String>, ?notes:Array<String>) {
        this.repair = repair;
        this.notes = notes == null ? [] : notes;
    }
}
