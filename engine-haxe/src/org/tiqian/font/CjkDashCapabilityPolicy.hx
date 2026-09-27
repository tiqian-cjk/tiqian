package org.tiqian.font;

class CjkDashCapabilityPolicy {
    public static inline final NoConformingCjkDashGlyph:String = "NoConformingCjkDashGlyph";
    public static inline final ConformingCjkDashRequiresExactFontSession:String = "ConformingCjkDashRequiresExactFontSession";

    public static function issueNameFor(status:Null<String>):String
        return status == "conforming" ? ConformingCjkDashRequiresExactFontSession : NoConformingCjkDashGlyph;

    public static function issueDetailFor(status:Null<String>, detail:Null<String>):String
        return status == null ? "CjkDashFontShapingNotPrepared" : (detail == null
            || StringTools.trim(detail) == "" ? "status=" + status : "status=" + status + "; " + detail);
}
