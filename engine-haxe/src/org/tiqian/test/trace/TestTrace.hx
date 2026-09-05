package org.tiqian.test.trace;

class TestTrace {
    public static final updateMode:Bool = true;
    public static var recorder:Null<TestTraceRecorder> = null;

    public static function currentRecorder():Null<TestTraceRecorder> {
        return recorder;
    }
}
