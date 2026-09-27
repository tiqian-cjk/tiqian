package org.tiqian.clreq;

@:dataClass
class PunctuationWidthPolicy {
    public final interior:InteriorPunctuationStyle;
    public final gbFixedSeparators:Bool;

    public function new(?interior:Null<InteriorPunctuationStyle>, ?gbFixedSeparators:Null<Bool>) {
        this.interior = interior == null ? InteriorPunctuationStyle.FullWidth : interior;
        this.gbFixedSeparators = gbFixedSeparators == null ? false : gbFixedSeparators;
    }

    public static function samePolicy(a:PunctuationWidthPolicy, b:PunctuationWidthPolicy):Bool {
        return a.interior == b.interior && a.gbFixedSeparators == b.gbFixedSeparators;
    }
}
