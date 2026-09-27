package org.tiqian.font;

@:dataClass class FontMetricsRequest {
    public final fontKey:String;
    public final fontSize:Float;
    public final role:FontRole;
    public final locale:String;
    public final fontFamilies:std.ReadOnlyArray<String>;
    public final fontWeight:Int;
    public final italic:Bool;
    public final faceSelectionText:String;

    public function new(fontKey:String, fontSize:Float, role:FontRole, locale:String, ?fontFamilies:Null<Array<String>>, ?fontWeight:Null<Int>,
            ?italic:Null<Bool>, ?faceSelectionText:Null<String>) {
        this.fontKey = fontKey;
        this.fontSize = fontSize;
        this.role = role;
        this.locale = locale;
        this.fontFamilies = fontFamilies == null ? [] : fontFamilies;
        this.fontWeight = fontWeight == null ? 400 : fontWeight;
        this.italic = italic == null ? false : italic;
        this.faceSelectionText = faceSelectionText == null ? "" : faceSelectionText;
    }
}

interface FontMetricsResolver {
    function resolve(request:FontMetricsRequest):RawFontMetrics;
}

class StubFontMetricsResolver implements FontMetricsResolver {
    public function new() {}

    public function resolve(r:FontMetricsRequest):RawFontMetrics {
        var result:RawFontMetrics;
        switch (r.role) {
            case CjkText | CjkPunctuation:
                result = new RawFontMetrics(r.fontSize * 1.16, r.fontSize * 0.288, 0, RawTables, r.fontSize * 0.88, r.fontSize * 0.12);
            case LatinText:
                result = new RawFontMetrics(r.fontSize * 0.8, r.fontSize * 0.2);
            case Symbol | Emoji | Unknown:
                result = new RawFontMetrics(r.fontSize * 0.9, r.fontSize * 0.25);
        }
        return result;
    }
}

@:dataClass class FontMetricsNormalizationInput {
    public final request:FontMetricsRequest;
    public final rawMetrics:RawFontMetrics;

    public function new(request:FontMetricsRequest, rawMetrics:RawFontMetrics) {
        this.request = request;
        this.rawMetrics = rawMetrics;
    }
}

interface FontMetricsNormalizer {
    function normalize(input:FontMetricsNormalizationInput):LayoutFontMetrics;
}

class ScriptAwareFontMetricsNormalizer implements FontMetricsNormalizer {
    public function new() {}

    public function normalize(i:FontMetricsNormalizationInput):LayoutFontMetrics {
        var result:LayoutFontMetrics;
        switch (i.request.role) {
            case CjkText | CjkPunctuation:
                result = normalizeCjk(i);
            case LatinText:
                result = normalizeRaw(i, "roman-raw");
            case Symbol | Emoji | Unknown:
                result = normalizeRaw(i, "fallback-raw");
        }
        return result;
    }

    private function normalizeCjk(i:FontMetricsNormalizationInput):LayoutFontMetrics {
        final m = i.rawMetrics;
        final t = m.typoAscent != null && m.typoDescent != null;
        return new LayoutFontMetrics(m.typoAscent != null ? m.typoAscent : m.ascent, m.typoDescent != null ? m.typoDescent : m.descent, 0,
            t ? IdeographicBox : Raw, Ideographic, IdeographicLow, IdeographicEmBox, m.source,
            "ScriptAwareFontMetricsNormalizer:"
            + i.request.role
            + ":"
            + (t ? "font-typo-box" : "hhea-fallback-no-os2"));
    }

    private function normalizeRaw(i:FontMetricsNormalizationInput, why:String):LayoutFontMetrics {
        final m = i.rawMetrics;
        return new LayoutFontMetrics(m.ascent, m.descent, 0, Raw, Alphabetic, Roman, RawFontBox, m.source,
            "ScriptAwareFontMetricsNormalizer:"
            + i.request.role
            + ":"
            + why);
    }
}
