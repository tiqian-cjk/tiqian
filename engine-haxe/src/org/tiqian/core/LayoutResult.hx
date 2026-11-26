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

    /** The decision records presentation code reads; see `LayoutPresentationDecisions`. */
    public final presentation:LayoutPresentationDecisions;

    public function new(input:LayoutInput, size:Size, clusters:ReadOnlyArray<Cluster>, glyphRuns:ReadOnlyArray<GlyphRun>, lines:ReadOnlyArray<LineBox>,
            ?debug:Null<LayoutDebugInfo>, ?presentation:Null<LayoutPresentationDecisions>) {
        this.input = input;
        this.size = size;
        this.clusters = clusters;
        this.glyphRuns = glyphRuns;
        this.lines = lines;
        this.debug = debug == null ? LayoutDebugInfo.Default : debug;
        this.presentation = presentation == null ? LayoutPresentationDecisions.Default : presentation;
    }
}
