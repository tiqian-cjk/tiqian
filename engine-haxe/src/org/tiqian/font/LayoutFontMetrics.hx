package org.tiqian.font;

@:dataClass class LayoutFontMetrics {
    public final ascent:Float;
    public final descent:Float;
    public final baselineOffset:Float;
    public final policy:FontMetricsPolicy;
    public final baselinePolicy:BaselinePolicy;
    public final baselineClass:BaselineClass;
    public final metricBox:MetricBox;
    public final source:FontMetricSource;
    public final reason:String;

    public function new(ascent:Float, descent:Float, baselineOffset:Float, policy:FontMetricsPolicy, baselinePolicy:BaselinePolicy,
            ?baselineClass:Null<BaselineClass>, ?metricBox:Null<MetricBox>, ?source:Null<FontMetricSource>, ?reason:Null<String>) {
        this.ascent = ascent;
        this.descent = descent;
        this.baselineOffset = baselineOffset;
        this.policy = policy;
        this.baselinePolicy = baselinePolicy;
        this.baselineClass = baselineClass == null ? BaselineClass.Roman : baselineClass;
        this.metricBox = metricBox == null ? MetricBox.RawFontBox : metricBox;
        this.source = source == null ? FontMetricSource.RawTables : source;
        this.reason = reason == null ? "" : reason;
    }
}
