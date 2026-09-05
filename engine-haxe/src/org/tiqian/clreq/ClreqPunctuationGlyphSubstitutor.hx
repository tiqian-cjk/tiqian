package org.tiqian.clreq;

import std.StringBuf;

class ClreqPunctuationGlyphSubstitutor {
    private final policy:CjkPunctuationGlyphPolicy;

    public function new(?policy:Null<CjkPunctuationGlyphPolicy>) {
        this.policy = policy == null ? CjkPunctuationGlyphPolicy.PreferClreqRecommendedCodepoints : policy;
    }

    public function substitute(sourceText:String):CjkPunctuationGlyphSubstitution {
        final displayText:String = policy == CjkPunctuationGlyphPolicy.PreserveInput ? sourceText : toClreqRecommendedDisplayText(sourceText);

        final reason:String = displayText == sourceText ? "CjkPunctuationGlyphPolicy:" + policy + ":preserve" : "CjkPunctuationGlyphPolicy:"
            + policy
            + ":"
            + toCodePointLabels(sourceText)
            + "->"
            + toCodePointLabels(displayText);

        return new CjkPunctuationGlyphSubstitution(sourceText, displayText, reason);
    }

    private static function toClreqRecommendedDisplayText(text:String):String {
        // Every unit an ellipsis (U+2026): each becomes one midline ellipsis.
        final output = new StringBuf();
        var index:Int = 0;
        var allEllipsis:Bool = true;
        while (index < text.length) {
            if (text.charCodeAt(index) != 0x2026) {
                allEllipsis = false;
                break;
            }
            output.add(MIDLINE_ELLIPSIS);
            index += 1;
        }
        if (allEllipsis) {
            return output.toString();
        }
        if (text == TWO_EM_DASH_SOURCE) {
            return TWO_EM_DASH;
        }
        if (text == KATAKANA_MIDDLE_DOT || text == HYPHENATION_POINT || text == BULLET) {
            return MIDDLE_DOT;
        }
        return text;
    }

    private static function toCodePointLabels(text:String):String {
        final output = new StringBuf();
        var index:Int = 0;
        while (index < text.length) {
            if (index > 0) {
                output.add("+");
            }
            output.add("U+");
            output.add(hexLabel(text.charCodeAt(index)));
            index += 1;
        }
        return output.toString();
    }

    private static function hexLabel(unit:Int):String {
        // Four uppercase hex digits; every UTF-16 unit fits.
        return HEX_UPPER.substring((unit >>> 12) & 15, ((unit >>> 12) & 15) + 1)
            + HEX_UPPER.substring((unit >>> 8) & 15, ((unit >>> 8) & 15) + 1)
            + HEX_UPPER.substring((unit >>> 4) & 15, ((unit >>> 4) & 15) + 1)
            + HEX_UPPER.substring(unit & 15, (unit & 15) + 1);
    }

    private static final MIDLINE_ELLIPSIS:String = "⋯";
    private static final TWO_EM_DASH_SOURCE:String = "——";
    private static final TWO_EM_DASH:String = "⸺";
    private static final KATAKANA_MIDDLE_DOT:String = "・";
    private static final HYPHENATION_POINT:String = "‧";
    private static final BULLET:String = "•";
    private static final MIDDLE_DOT:String = "·";
    private static final HEX_UPPER:String = "0123456789ABCDEF";
}
