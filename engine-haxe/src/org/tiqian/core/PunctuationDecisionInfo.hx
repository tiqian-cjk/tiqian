package org.tiqian.core;

@:dataClass
class PunctuationDecisionInfo {
    public final range:TextRange;
    // Kotlin Char field; the port holds the single UTF-16 unit as a String.
    public final char:String;
    public final punctuationClass:String;
    public final advance:Float;
    public final bodyWidth:Float;
    public final leadingGlueNatural:Float;
    public final trailingGlueNatural:Float;
    public final anchor:String;
    public final inkBounds:Null<Rect>;
    public final geometrySource:String;
    // Kotlin declares policyBodyFloor: Float = bodyWidth. Parameter-reading
    // signature defaults are boring gap 4; until that lowering lands the
    // parameter stays mandatory and becomes ?Null<Float> with a coalescing
    // assignment afterwards.
    public final policyBodyFloor:Float;
    public final inkWidth:Null<Float>;
    public final inkCenter:Null<Float>;
    public final inkContainmentBodyFloor:Null<Float>;
    public final inkContainmentApplied:Bool;
    public final inkBoundsFallback:Null<String>;
    public final haltAdvance:Null<Float>;
    public final haltValidation:Null<String>;
    public final advanceExpansion:Float;
    public final glyphInlineShift:Float;
    public final glyphPlacementReason:Null<String>;
    public final leadingGlueInitiallyConsumed:Float;
    public final trailingGlueInitiallyConsumed:Float;

    public function new(range:TextRange, char:String, punctuationClass:String, advance:Float, bodyWidth:Float, leadingGlueNatural:Float,
            trailingGlueNatural:Float, anchor:String, ?inkBounds:Null<Rect>, ?geometrySource:Null<String>, policyBodyFloor:Float, ?inkWidth:Null<Float>,
            ?inkCenter:Null<Float>, ?inkContainmentBodyFloor:Null<Float>, ?inkContainmentApplied:Null<Bool>, ?inkBoundsFallback:Null<String>,
            ?haltAdvance:Null<Float>, ?haltValidation:Null<String>, ?advanceExpansion:Null<Float>, ?glyphInlineShift:Null<Float>,
            ?glyphPlacementReason:Null<String>, ?leadingGlueInitiallyConsumed:Null<Float>, ?trailingGlueInitiallyConsumed:Null<Float>) {
        this.range = range;
        this.char = char;
        this.punctuationClass = punctuationClass;
        this.advance = advance;
        this.bodyWidth = bodyWidth;
        this.leadingGlueNatural = leadingGlueNatural;
        this.trailingGlueNatural = trailingGlueNatural;
        this.anchor = anchor;
        this.inkBounds = inkBounds == null ? null : inkBounds;
        this.geometrySource = geometrySource == null ? "PolicyDerived" : geometrySource;
        this.policyBodyFloor = policyBodyFloor;
        this.inkWidth = inkWidth == null ? null : inkWidth;
        this.inkCenter = inkCenter == null ? null : inkCenter;
        this.inkContainmentBodyFloor = inkContainmentBodyFloor == null ? null : inkContainmentBodyFloor;
        this.inkContainmentApplied = inkContainmentApplied == null ? false : inkContainmentApplied;
        this.inkBoundsFallback = inkBoundsFallback == null ? null : inkBoundsFallback;
        this.haltAdvance = haltAdvance == null ? null : haltAdvance;
        this.haltValidation = haltValidation == null ? null : haltValidation;
        this.advanceExpansion = advanceExpansion == null ? 0.0 : advanceExpansion;
        this.glyphInlineShift = glyphInlineShift == null ? 0.0 : glyphInlineShift;
        this.glyphPlacementReason = glyphPlacementReason == null ? null : glyphPlacementReason;
        this.leadingGlueInitiallyConsumed = leadingGlueInitiallyConsumed == null ? 0.0 : leadingGlueInitiallyConsumed;
        this.trailingGlueInitiallyConsumed = trailingGlueInitiallyConsumed == null ? 0.0 : trailingGlueInitiallyConsumed;
    }
}
