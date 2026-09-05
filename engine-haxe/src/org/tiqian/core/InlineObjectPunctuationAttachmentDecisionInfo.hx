package org.tiqian.core;

@:dataClass
class InlineObjectPunctuationAttachmentDecisionInfo {
    public final objectRange:TextRange;
    public final separatorRange:TextRange;
    public final punctuationRange:TextRange;
    public final punctuationText:String;
    public final protectedRange:TextRange;
    public final collapsedAdvance:Float;
    public final reason:String;

    public function new(objectRange:TextRange, separatorRange:TextRange, punctuationRange:TextRange, punctuationText:String, protectedRange:TextRange,
            collapsedAdvance:Float, ?reason:Null<String>) {
        this.objectRange = objectRange;
        this.separatorRange = separatorRange;
        this.punctuationRange = punctuationRange;
        this.punctuationText = punctuationText;
        this.protectedRange = protectedRange;
        this.collapsedAdvance = collapsedAdvance;
        this.reason = reason == null ? "InlineObjectPunctuationSeparatorSpaceCollapse" : reason;
    }
}
