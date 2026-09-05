package org.tiqian.font;

@:dataClass class FontRoleContext {
    public final locale:String;
    public final regionHint:Null<String>;

    public function new(?locale:Null<String>, ?regionHint:Null<String>) {
        this.locale = locale == null ? "zh-Hans" : locale;
        this.regionHint = regionHint;
    }
}

interface FontRoleClassifier {
    function classify(text:String, range:org.tiqian.core.TextRange, ?context:Null<FontRoleContext>):FontRole;
}
