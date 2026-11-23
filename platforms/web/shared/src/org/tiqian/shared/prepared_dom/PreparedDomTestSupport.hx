package org.tiqian.shared.prepared_dom;

class PreparedDomTestSupport {
    public static function input(
        source:String, display:String, drawX:Float, naturalWidth:Float,
        shapingBoundary:Bool, openTypeFeatures:Null<Array<String>>, renderFontFamilies:Array<String>,
        trailingGap:Float, spacing:PreparedSpacingResult, styleDelta:Null<StyleDelta>,
        italicEffect:Bool, dashStrategy:Null<String>, shapingLanguage:Null<String>,
        resolvedFace:Null<String>, glyphIds:Null<String>, shapingEvidence:Null<String>,
        punctuationInkFloor:Null<Float>, punctuationBodyWidth:Null<Float>,
        evidenceRenderFontFamily:Null<String>):PreparedRunRenderInput {
        return {
            source: source,
            display: display,
            drawX: drawX,
            naturalWidth: naturalWidth,
            shapingBoundary: shapingBoundary,
            openTypeFeatures: openTypeFeatures,
            renderFontFamilies: renderFontFamilies,
            trailingGap: trailingGap,
            spacing: spacing,
            styleDelta: styleDelta,
            italicEffect: italicEffect,
            dashStrategy: dashStrategy,
            shapingLanguage: shapingLanguage,
            resolvedFace: resolvedFace,
            glyphIds: glyphIds,
            shapingEvidence: shapingEvidence,
            punctuationInkFloor: punctuationInkFloor,
            punctuationBodyWidth: punctuationBodyWidth,
            evidenceRenderFontFamily: evidenceRenderFontFamily
        };
    }

    /**
     * Byte-fidelity serializer mirroring JSON.stringify for the typed
     * MarkupArtifact shape. boring's reflaxe TypeScript target has no
     * haxe.Json, so the stringify escaping is
     * mirrored by hand: '"' -> \", '\' -> \\, \b \t \n \f \r short forms,
     * control chars < U+0020 -> \u00XX; U+0020..U+FFFF (incl. CJK and NBSP
     * U+00A0) stay raw.
     */
    public static function artifactToJson(artifact:MarkupArtifact):String {
        return switch (artifact) {
            case Text(text):
                "[\"#\"," + jsonString(text) + "]";
            case Element(tag, entries, children):
                serializeElement(tag, entries, children);
        };
    }

    private static function serializeElement(tag:String, entries:Array<AttributeEntry>, children:Array<MarkupArtifact>):String {
        var out = "[" + jsonString(tag) + ",[";
        var i = 0;
        while (i < entries.length) {
            if (i > 0) out += ",";
            out += "[" + jsonString(entries[i].name) + "," + jsonString(entries[i].value) + "]";
            i += 1;
        }
        out += "],[";
        var j = 0;
        while (j < children.length) {
            if (j > 0) out += ",";
            out += artifactToJson(children[j]);
            j += 1;
        }
        return out + "]]";
    }

    private static function jsonString(value:String):String {
        var out = "\"";
        var i = 0;
        while (i < value.length) {
            final c = value.charCodeAt(i);
            if (c == 34) out += "\\\"";
            else if (c == 92) out += "\\\\";
            else if (c == 8) out += "\\b";
            else if (c == 9) out += "\\t";
            else if (c == 10) out += "\\n";
            else if (c == 12) out += "\\f";
            else if (c == 13) out += "\\r";
            else if (c < 32) out += "\\u" + hex4(c);
            else out += String.fromCharCode(c);
            i += 1;
        }
        return out + "\"";
    }

    private static function hex4(value:Int):String {
        final digits = "0123456789abcdef";
        return digits.substr((value >> 12) & 15, 1)
            + digits.substr((value >> 8) & 15, 1)
            + digits.substr((value >> 4) & 15, 1)
            + digits.substr(value & 15, 1);
    }
}
