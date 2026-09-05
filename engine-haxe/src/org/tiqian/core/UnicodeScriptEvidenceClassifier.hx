package org.tiqian.core;

class UnicodeScriptEvidenceClassifier {
    public static final DATA_REVISION:String = "17.0.0";
    public static final DATA_SOURCE:String = "https://www.unicode.org/Public/17.0.0/ucd/Scripts.txt";
    public static final DATA_SHA256:String = "9f5e50d3abaee7d6ce09480f325c706f485ae3240912527e651954d2d6b035bf";

    public static function classify(codePoint:Int):UnicodeScriptEvidence {
        if (codePoint < 0 || codePoint > 0x10FFFF) {
            throw new TiqianIllegalArgumentException(Message("Not a Unicode scalar value: " + codePoint));
        }
        if (codePoint >= 0xD800 && codePoint <= 0xDFFF) {
            throw new TiqianIllegalArgumentException(Message("Surrogate is not a Unicode scalar value: " + codePoint));
        }
        return UnicodeScriptEvidenceData.classify(codePoint);
    }
}
