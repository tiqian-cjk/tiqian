package org.tiqian.core;

@:dataClass
class ShapingDecisionInfo {
    public final range:TextRange;
    public final sourceText:String;
    public final displayText:String;
    public final fontKey:String;
    public final glyphCount:Int;
    public final advance:Float;
    public final source:String;
    public final reason:String;
    public final glyphsWithoutInkBounds:Int;
    public final missingGlyphs:Int;
    public final resolvedFace:Null<String>;
    public final script:Null<String>;
    public final language:Null<String>;
    public final strategy:Null<String>;
    public final featureEvidence:Null<String>;
    public final capabilityIssue:Null<String>;

    public function new(range:TextRange, sourceText:String, displayText:String, fontKey:String, glyphCount:Int, advance:Float, source:String, reason:String,
            ?glyphsWithoutInkBounds:Null<Int>, ?missingGlyphs:Null<Int>, ?resolvedFace:Null<String>, ?script:Null<String>, ?language:Null<String>,
            ?strategy:Null<String>, ?featureEvidence:Null<String>, ?capabilityIssue:Null<String>) {
        this.range = range;
        this.sourceText = sourceText;
        this.displayText = displayText;
        this.fontKey = fontKey;
        this.glyphCount = glyphCount;
        this.advance = advance;
        this.source = source;
        this.reason = reason;
        this.glyphsWithoutInkBounds = glyphsWithoutInkBounds == null ? 0 : glyphsWithoutInkBounds;
        this.missingGlyphs = missingGlyphs == null ? 0 : missingGlyphs;
        this.resolvedFace = resolvedFace == null ? null : resolvedFace;
        this.script = script == null ? null : script;
        this.language = language == null ? null : language;
        this.strategy = strategy == null ? null : strategy;
        this.featureEvidence = featureEvidence == null ? null : featureEvidence;
        this.capabilityIssue = capabilityIssue == null ? null : capabilityIssue;
    }
}
