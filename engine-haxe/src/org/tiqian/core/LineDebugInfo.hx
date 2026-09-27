package org.tiqian.core;

@:dataClass class LineDebugInfo {
    public final repair:Null<String>;
    public final notes:Array<String>;

    public function new(repair:Null<String>, ?notes:Array<String>) {
        this.repair = repair;
        this.notes = notes == null ? [] : notes;
    }
}
