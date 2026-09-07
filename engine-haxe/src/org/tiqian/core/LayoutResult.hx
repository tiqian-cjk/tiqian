package org.tiqian.core;

import std.ReadOnlyArray;

@:dataClass
class LayoutResult {
    public final input:LayoutInput;
    public final size:Size;
    public final clusters:ReadOnlyArray<Cluster>;
    public final glyphRuns:ReadOnlyArray<GlyphRun>;
    public final lines:ReadOnlyArray<LineBox>;
    public final debug:LayoutDebugInfo;

    public function new(input:LayoutInput, size:Size, clusters:ReadOnlyArray<Cluster>, glyphRuns:ReadOnlyArray<GlyphRun>, lines:ReadOnlyArray<LineBox>,
            debug:LayoutDebugInfo) {
        this.input = input;
        this.size = size;
        this.clusters = clusters;
        this.glyphRuns = glyphRuns;
        this.lines = lines;
        this.debug = debug;
    }
}
