package org.tiqian.test.trace;

import std.StringBuf;

class TraceRecorder {
    private final buffer:StringBuf;

    public function new() {
        buffer = new StringBuf();
    }

    public function event(name:String, fields:Array<Null<TraceField>>):Void {
        buffer.add(name);
        var index = 0;
        while (index < fields.length) {
            final field = fields[index];
            if (field != null) {
                buffer.add(" ");
                buffer.add(field.key);
                buffer.add("=");
                buffer.add(field.value);
            }
            index += 1;
        }
        buffer.add("\n");
    }

    public function raw(value:String):Void {
        buffer.add(value);
        buffer.add("\n");
    }

    public function text():String {
        return buffer.toString();
    }
}
