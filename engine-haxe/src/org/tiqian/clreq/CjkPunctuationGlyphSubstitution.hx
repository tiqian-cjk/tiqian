package org.tiqian.clreq;

@:dataClass
class CjkPunctuationGlyphSubstitution {
    public final sourceText:String;
    public final displayText:String;
    public final reason:String;

    public function new(sourceText:String, displayText:String, reason:String) {
        this.sourceText = sourceText;
        this.displayText = displayText;
        this.reason = reason;
    }
}
