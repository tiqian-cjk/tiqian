package org.tiqian.core;

@:dataClass
class MetricDecisionInfo {
    public final range:TextRange;
    public final sourceText:String;
    public final role:String;
    public final fontKey:String;
    public final rawAscent:Float;
    public final rawDescent:Float;
    public final rawLeading:Float;
    public final rawSource:String;
    public final layoutAscent:Float;
    public final layoutDescent:Float;
    public final baselineClass:String;
    public final metricBox:String;
    public final layoutSource:String;
    public final reason:String;

    public function new(range:TextRange, sourceText:String, role:String, fontKey:String, rawAscent:Float, rawDescent:Float, rawLeading:Float,
            rawSource:String, layoutAscent:Float, layoutDescent:Float, baselineClass:String, metricBox:String, layoutSource:String, reason:String) {
        this.range = range;
        this.sourceText = sourceText;
        this.role = role;
        this.fontKey = fontKey;
        this.rawAscent = rawAscent;
        this.rawDescent = rawDescent;
        this.rawLeading = rawLeading;
        this.rawSource = rawSource;
        this.layoutAscent = layoutAscent;
        this.layoutDescent = layoutDescent;
        this.baselineClass = baselineClass;
        this.metricBox = metricBox;
        this.layoutSource = layoutSource;
        this.reason = reason;
    }
}
