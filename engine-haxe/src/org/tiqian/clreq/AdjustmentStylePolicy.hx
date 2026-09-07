package org.tiqian.clreq;

@:dataClass
class AdjustmentStylePolicy {
    public final lineEndPunctuation:LineEndPunctuationStyle;
    public final allowInlineStopCompression:Bool;
    public final allowSinoWesternGapAdjustment:Bool;
    public final lineAdjustment:LineAdjustmentStrategy;

    public function new(?lineEndPunctuation:Null<LineEndPunctuationStyle>, ?allowInlineStopCompression:Null<Bool>, ?allowSinoWesternGapAdjustment:Null<Bool>,
            ?lineAdjustment:Null<LineAdjustmentStrategy>) {
        this.lineEndPunctuation = lineEndPunctuation == null ? LineEndPunctuationStyle.ForceHalfWidth : lineEndPunctuation;
        this.allowInlineStopCompression = allowInlineStopCompression == null ? true : allowInlineStopCompression;
        this.allowSinoWesternGapAdjustment = allowSinoWesternGapAdjustment == null ? true : allowSinoWesternGapAdjustment;
        this.lineAdjustment = lineAdjustment == null ? LineAdjustmentStrategy.PushInFirst : lineAdjustment;
    }

    public static function samePolicy(a:AdjustmentStylePolicy, b:AdjustmentStylePolicy):Bool {
        return a.lineEndPunctuation == b.lineEndPunctuation
            && a.allowInlineStopCompression == b.allowInlineStopCompression
            && a.allowSinoWesternGapAdjustment == b.allowSinoWesternGapAdjustment
            && a.lineAdjustment == b.lineAdjustment;
    }
}
