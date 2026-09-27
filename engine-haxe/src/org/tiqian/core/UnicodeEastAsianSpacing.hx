package org.tiqian.core;

class UnicodeEastAsianSpacing {
    public static final DATA_REVISION:String = "draft-2024-12-16";
    public static final DATA_SOURCE:String = "https://www.unicode.org/reports/tr59/east-asian-spacing.txt";
    public static final DATA_SHA256:String = "49fe340a964a6e8e0ebc30099709c665cc6138d444b5c36dc336604047f1010f";
    public static final LANGUAGE_REGISTRY_REVISION:String = "2026-06-14";
    public static final LANGUAGE_REGISTRY_SOURCE:String = "https://www.iana.org/assignments/language-subtag-registry/language-subtag-registry";

    public static function isChineseLanguageContext(locale:String):Bool {
        final language:String = languageSubtag(locale);
        if (language == "zh") {
            return true;
        }
        return language == "cdo" || language == "cjy" || language == "cmn" || language == "cnp" || language == "cpx" || language == "csp"
            || language == "czh" || language == "czo" || language == "gan" || language == "hak" || language == "hnm" || language == "hsn"
            || language == "luh" || language == "lzh" || language == "mnp" || language == "nan" || language == "sjc" || language == "wuu" || language == "yue";
    }

    public static function propertyOf(codePoint:Int):EastAsianSpacingValue {
        validateScalar(codePoint);
        return EastAsianSpacingData.lookup(codePoint);
    }

    public static function resolvedForGraphemeCluster(graphemeCluster:String, locale:String):EastAsianSpacingValue {
        if (graphemeCluster.length == 0) {
            return EastAsianSpacingValue.Other;
        }
        var index:Int = 0;
        while (index < graphemeCluster.length) {
            final codePoint:Int = SourceInteractionBoundaries.codePointAtCompat(graphemeCluster, index, graphemeCluster.length);
            if (isEnclosingMark(codePoint)) {
                return EastAsianSpacingValue.Other;
            }
            final advance:Int = codePoint > 0xFFFF ? 2 : 1;
            index += advance;
        }
        final property:EastAsianSpacingValue = propertyOf(SourceInteractionBoundaries.codePointAtCompat(graphemeCluster, 0, graphemeCluster.length));
        if (property == EastAsianSpacingValue.Conditional) {
            return isChineseLanguageContext(locale) ? EastAsianSpacingValue.Narrow : EastAsianSpacingValue.Other;
        }
        return property;
    }

    public static function resolvedEdges(text:String, locale:String):EastAsianSpacingEdges {
        if (text.length == 0) {
            return new EastAsianSpacingEdges(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other, false);
        }
        final boundaries:Array<Int> = SourceInteractionBoundaries.interactionBoundaries(text, new TextRange(0, text.length));
        var index:Int = 0;
        var leading:EastAsianSpacingValue = EastAsianSpacingValue.Other;
        var trailing:EastAsianSpacingValue = EastAsianSpacingValue.Other;
        var containsWide:Bool = false;
        while (index + 1 < boundaries.length) {
            final value:EastAsianSpacingValue = resolvedForGraphemeCluster(text.substring(boundaries[index], boundaries[index + 1]), locale);
            if (index == 0) {
                leading = value;
            }
            trailing = value;
            if (value == EastAsianSpacingValue.Wide) {
                containsWide = true;
            }
            index += 1;
        }
        return new EastAsianSpacingEdges(leading, trailing, containsWide);
    }

    private static function validateScalar(codePoint:Int):Void {
        if (codePoint < 0 || codePoint > 0x10FFFF) {
            throw new TiqianIllegalArgumentException(Message("Not a Unicode scalar value: " + codePoint));
        }
        if (codePoint >= 0xD800 && codePoint <= 0xDFFF) {
            throw new TiqianIllegalArgumentException(Message("Surrogate is not a Unicode scalar value: " + codePoint));
        }
    }

    private static function languageSubtag(locale:String):String {
        var end:Int = locale.indexOf("-");
        final underscore:Int = locale.indexOf("_");
        if (end < 0 || (underscore >= 0 && underscore < end)) {
            end = underscore;
        }
        if (end < 0) {
            end = locale.length;
        }
        return locale.substring(0, end).toLowerCase();
    }

    private static function isEnclosingMark(codePoint:Int):Bool {
        return codePoint == 0x0488
            || codePoint == 0x0489
            || codePoint == 0x1ABE
            || (codePoint >= 0x20DD && codePoint <= 0x20E0)
            || (codePoint >= 0xA670 && codePoint <= 0xA672)
            || (codePoint >= 0xA674 && codePoint <= 0xA67D);
    }
}
