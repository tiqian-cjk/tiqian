package org.tiqian.test.trace;

import std.StringBuf;

private class TraceSectionState {
    public final name:String;
    public final lines:StringBuf;

    public function new(name:String) {
        this.name = name;
        lines = new StringBuf();
    }
}

private class TraceClassState {
    public final className:String;
    public final sections:Array<TraceSectionState>;

    public function new(className:String) {
        this.className = className;
        sections = [];
    }
}

class TestTraceStore {
    private static final classes:Array<TraceClassState> = [];

    public static function open(className:String, sectionName:String):Void {
        var classState = findClass(className);
        if (classState == null) {
            classState = new TraceClassState(className);
            classes.push(classState);
        }
        final section = findSection(classState, sectionName);
        if (section == null) {
            classState.sections.push(new TraceSectionState(sectionName));
        }
    }

    public static function append(className:String, sectionName:String, line:String):Void {
        final classState = findClass(className);
        if (classState == null) {
            return;
        }
        final section = findSection(classState, sectionName);
        if (section == null) {
            return;
        }
        section.lines.add(line);
        section.lines.add("\n");
    }

    public static function classText(className:String):String {
        final classState = findClass(className);
        if (classState == null) {
            return "class: " + className + "\n";
        }

        final output = new StringBuf();
        output.add("class: ");
        output.add(className);
        output.add("\n");

        final order = new Array<Int>();
        var index = 0;
        while (index < classState.sections.length) {
            var insertion = order.length;
            while (insertion > 0 && classState.sections[order[insertion - 1]].name > classState.sections[index].name) {
                insertion -= 1;
            }
            order.insert(insertion, index);
            index += 1;
        }

        index = 0;
        while (index < order.length) {
            final section = classState.sections[order[index]];
            output.add("test: ");
            output.add(section.name);
            output.add("\n");
            final sectionText = section.lines.toString();
            if (sectionText.length > 0) {
                output.add(sectionText);
            }
            index += 1;
        }
        return output.toString();
    }

    private static function findClass(className:String):Null<TraceClassState> {
        var index = 0;
        while (index < classes.length) {
            if (classes[index].className == className) {
                return classes[index];
            }
            index += 1;
        }
        return null;
    }

    private static function findSection(classState:TraceClassState, sectionName:String):Null<TraceSectionState> {
        var index = 0;
        while (index < classState.sections.length) {
            if (classState.sections[index].name == sectionName) {
                return classState.sections[index];
            }
            index += 1;
        }
        return null;
    }
}
