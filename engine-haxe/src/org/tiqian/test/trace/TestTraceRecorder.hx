package org.tiqian.test.trace;

class TestTraceRecorder {
    private final className:String;
    private var sectionName:Null<String>;

    public function new(className:String) {
        this.className = className;
        sectionName = null;
        TestTrace.recorder = this;
    }

    public function section(name:String):Void {
        sectionName = name;
        TestTraceStore.open(className, name);
    }

    public function record(line:String):Void {
        final currentSection = sectionName;
        if (currentSection == null) {
            return;
        }
        TestTraceStore.append(className, currentSection, line);
    }

    public function flush():Void {
        if (!TestTracePlatform.updateMode || sectionName == null) {
            return;
        }
        TestTracePlatform.writeGolden(className, TestTraceStore.classText(className));
    }

    public static function flushClass(className:String):Void {
        if (!TestTracePlatform.updateMode) {
            return;
        }
        TestTracePlatform.writeGolden(className, TestTraceStore.classText(className));
    }
}
