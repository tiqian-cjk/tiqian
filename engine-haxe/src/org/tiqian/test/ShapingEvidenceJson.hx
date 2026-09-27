package org.tiqian.test;

import org.tiqian.core.Rect;
import org.tiqian.core.TextRangeError;
import org.tiqian.core.TiqianIllegalArgumentException;
import org.tiqian.test.ShapingEvidence.MetricsEvidenceEntry;
import org.tiqian.test.ShapingEvidence.MetricsEvidenceKey;
import org.tiqian.test.ShapingEvidence.RecordedFontMetrics;
import org.tiqian.test.ShapingEvidence.RecordedGlyph;
import org.tiqian.test.ShapingEvidence.RecordedShapingDecision;
import org.tiqian.test.ShapingEvidence.RecordedShapingResult;
import org.tiqian.test.ShapingEvidence.ShapingEvidenceEntry;
import org.tiqian.test.ShapingEvidence.ShapingEvidenceKey;
import std.SortedMap;

/**
 * Typed JSON parser for ShapingEvidence (the Dynamic-returning haxe.Json is
 * outside the translatable subset). Mirrors the field order and nullability
 * of ShapingEvidenceJson.kt on the Kotlin side; the corpus is machine-generated
 * by kotlinx.serialization.
 */
enum JsonValue {
    JNull;
    JBool(v:Bool);
    JNum(v:Float);
    JStr(v:String);
    JArr(v:Array<JsonValue>);
    JObj(v:Array<JsonMember>);
}

@:dataClass
class JsonMember {
    public final name:String;
    public final value:JsonValue;

    public function new(name:String, value:JsonValue) {
        this.name = name;
        this.value = value;
    }
}

class JsonCursor {
    public var pos:Int;

    public function new(pos:Int) {
        this.pos = pos;
    }
}

class ShapingEvidenceJson {
    public static function parse(text:String):ShapingEvidence {
        final cur = new JsonCursor(0);
        skipWs(cur, text);
        final root = objRequired(parseValue(cur, text), "<root>");
        final metaObj = objRequired(field(root, "meta"), "meta");
        final meta = SortedMap.builder();
        for (i in 0...metaObj.length) {
            meta.put(metaObj[i].name, strRequired(metaObj[i].value, "meta." + metaObj[i].name));
        }
        final shapingArr = arrRequired(field(root, "shaping"), "shaping");
        final shaping:Array<ShapingEvidenceEntry> = [];
        for (i in 0...shapingArr.length) {
            final entry = objRequired(shapingArr[i], "shaping[" + i + "]");
            final key = parseShapingKey(objRequired(field(entry, "key"), "shaping[" + i + "].key"));
            final result = parseShapingResult(objRequired(field(entry, "result"), "shaping[" + i + "].result"));
            shaping.push(new ShapingEvidenceEntry(key, result));
        }
        final metricsArr = arrRequired(field(root, "metrics"), "metrics");
        final metrics:Array<MetricsEvidenceEntry> = [];
        for (i in 0...metricsArr.length) {
            final entry = objRequired(metricsArr[i], "metrics[" + i + "]");
            final key = parseMetricsKey(objRequired(field(entry, "key"), "metrics[" + i + "].key"));
            final result = parseFontMetrics(objRequired(field(entry, "result"), "metrics[" + i + "].result"));
            metrics.push(new MetricsEvidenceEntry(key, result));
        }
        return new ShapingEvidence(meta.build(), shaping, metrics);
    }

    // --- decoders (field order mirrors ShapingEvidenceJson.kt) ---

    private static function parseShapingKey(obj:Array<JsonMember>):ShapingEvidenceKey {
        return new ShapingEvidenceKey(strRequired(field(obj, "displayText"), "displayText"), strRequired(field(obj, "fontKey"), "fontKey"),
            strRequired(field(obj, "fontFamily"), "fontFamily"), strRequired(field(obj, "role"), "role"),
            strArrayRequired(field(obj, "styleFontFamilies"), "styleFontFamilies"), numRequired(field(obj, "fontSize"), "fontSize"),
            intRequired(field(obj, "fontWeight"), "fontWeight"), boolRequired(field(obj, "italic"), "italic"), strRequired(field(obj, "locale"), "locale"),
            strArrayRequired(field(obj, "openTypeFeatures"), "openTypeFeatures"));
    }

    private static function parseShapingResult(obj:Array<JsonMember>):RecordedShapingResult {
        final glyphValues = arrRequired(field(obj, "glyphs"), "glyphs");
        final glyphs:Array<RecordedGlyph> = [];
        for (i in 0...glyphValues.length) {
            final g = objRequired(glyphValues[i], "glyphs[" + i + "]");
            glyphs.push(new RecordedGlyph(intRequired(field(g, "id"), "id"), numRequired(field(g, "advance"), "advance"), numRequired(field(g, "x"), "x"),
                numRequired(field(g, "y"), "y"), rectOrNull(field(g, "bounds"), "bounds"), floatOrNull(field(g, "haltAdvance"), "haltAdvance"),
                floatOrNull(field(g, "haltPlacementX"), "haltPlacementX")));
        }
        final decisionValues = arrRequired(field(obj, "decisions"), "decisions");
        final decisions:Array<RecordedShapingDecision> = [];
        for (i in 0...decisionValues.length) {
            final d = objRequired(decisionValues[i], "decisions[" + i + "]");
            decisions.push(new RecordedShapingDecision(intRequired(field(d, "glyphCount"), "glyphCount"), numRequired(field(d, "advance"), "advance"),
                strRequired(field(d, "source"), "source"), strRequired(field(d, "reason"), "reason"),
                intRequired(field(d, "glyphsWithoutInkBounds"), "glyphsWithoutInkBounds"), intRequired(field(d, "missingGlyphs"), "missingGlyphs"),
                strOrNull(field(d, "resolvedFace"), "resolvedFace"), strOrNull(field(d, "script"), "script"), strOrNull(field(d, "language"), "language"),
                strOrNull(field(d, "strategy"), "strategy"), strOrNull(field(d, "featureEvidence"), "featureEvidence"),
                strOrNull(field(d, "capabilityIssue"), "capabilityIssue")));
        }
        return new RecordedShapingResult(numRequired(field(obj, "clusterAdvance"), "clusterAdvance"), numRequired(field(obj, "runAdvance"), "runAdvance"),
            strArrayRequired(field(obj, "runFeatures"), "runFeatures"), glyphs, decisions);
    }

    private static function parseMetricsKey(obj:Array<JsonMember>):MetricsEvidenceKey {
        return new MetricsEvidenceKey(strRequired(field(obj, "fontKey"), "fontKey"), numRequired(field(obj, "fontSize"), "fontSize"),
            strRequired(field(obj, "role"), "role"), strRequired(field(obj, "locale"), "locale"),
            strArrayRequired(field(obj, "fontFamilies"), "fontFamilies"), intRequired(field(obj, "fontWeight"), "fontWeight"),
            boolRequired(field(obj, "italic"), "italic"), strRequired(field(obj, "faceSelectionText"), "faceSelectionText"));
    }

    private static function parseFontMetrics(obj:Array<JsonMember>):RecordedFontMetrics {
        return new RecordedFontMetrics(numRequired(field(obj, "ascent"), "ascent"), numRequired(field(obj, "descent"), "descent"),
            numRequired(field(obj, "leading"), "leading"), strRequired(field(obj, "source"), "source"), floatOrNull(field(obj, "typoAscent"), "typoAscent"),
            floatOrNull(field(obj, "typoDescent"), "typoDescent"));
    }

    // --- typed accessors (loud failures mirror Kotlin getValue semantics) ---

    private static function field(obj:Array<JsonMember>, name:String):JsonValue {
        var found:Null<JsonValue> = null;
        for (i in 0...obj.length) {
            if (obj[i].name == name) {
                found = obj[i].value;
                break;
            }
        }
        if (found == null) {
            throw new TiqianIllegalArgumentException(TextRangeError.Message("Missing JSON field: " + name));
        }
        return found;
    }

    private static function strRequired(v:JsonValue, name:String):String {
        var value:Null<String> = null;
        switch (v) {
            case JStr(s):
                value = s;
            case JNull:
                value = null;
            case JBool(_):
                value = null;
            case JNum(_):
                value = null;
            case JArr(_):
                value = null;
            case JObj(_):
                value = null;
        }
        if (value == null) {
            throw new TiqianIllegalArgumentException(TextRangeError.Message("Field " + name + ": expected string"));
        }
        return value;
    }

    private static function numRequired(v:JsonValue, name:String):Float {
        var matched = false;
        var value = 0.0;
        switch (v) {
            case JNum(n):
                value = n;
                matched = true;
            case JNull:
                matched = false;
            case JBool(_):
                matched = false;
            case JStr(_):
                matched = false;
            case JArr(_):
                matched = false;
            case JObj(_):
                matched = false;
        }
        if (!matched) {
            throw new TiqianIllegalArgumentException(TextRangeError.Message("Field " + name + ": expected number"));
        }
        return value;
    }

    private static function intRequired(v:JsonValue, name:String):Int {
        return Std.int(numRequired(v, name));
    }

    private static function boolRequired(v:JsonValue, name:String):Bool {
        var matched = false;
        var value = false;
        switch (v) {
            case JBool(b):
                value = b;
                matched = true;
            case JNull:
                matched = false;
            case JNum(_):
                matched = false;
            case JStr(_):
                matched = false;
            case JArr(_):
                matched = false;
            case JObj(_):
                matched = false;
        }
        if (!matched) {
            throw new TiqianIllegalArgumentException(TextRangeError.Message("Field " + name + ": expected bool"));
        }
        return value;
    }

    private static function strArrayRequired(v:JsonValue, name:String):Array<String> {
        final values = arrRequired(v, name);
        final out:Array<String> = [];
        for (i in 0...values.length) {
            out.push(strRequired(values[i], name + "[" + i + "]"));
        }
        return out;
    }

    private static function strOrNull(v:JsonValue, name:String):Null<String> {
        var nullKind = false;
        var value:Null<String> = null;
        switch (v) {
            case JNull:
                nullKind = true;
            case JStr(s):
                value = s;
            case JBool(_):
                value = null;
            case JNum(_):
                value = null;
            case JArr(_):
                value = null;
            case JObj(_):
                value = null;
        }
        if (!nullKind && value == null) {
            throw new TiqianIllegalArgumentException(TextRangeError.Message("Field " + name + ": expected string or null"));
        }
        return value;
    }

    private static function floatOrNull(v:JsonValue, name:String):Null<Float> {
        var nullKind = false;
        var value:Null<Float> = null;
        switch (v) {
            case JNull:
                nullKind = true;
            case JNum(n):
                value = n;
            case JBool(_):
                value = null;
            case JStr(_):
                value = null;
            case JArr(_):
                value = null;
            case JObj(_):
                value = null;
        }
        if (!nullKind && value == null) {
            throw new TiqianIllegalArgumentException(TextRangeError.Message("Field " + name + ": expected number or null"));
        }
        return value;
    }

    private static function rectOrNull(v:JsonValue, name:String):Null<Rect> {
        final values = arrOrNull(v, name);
        if (values == null) {
            return null;
        }
        if (values.length != 4) {
            throw new TiqianIllegalArgumentException(TextRangeError.Message("Field " + name + ": expected 4 bounds values, got " + values.length));
        }
        return new Rect(numRequired(values[0], name + "[0]"), numRequired(values[1], name + "[1]"), numRequired(values[2], name + "[2]"),
            numRequired(values[3], name + "[3]"));
    }

    private static function arrOrNull(v:JsonValue, name:String):Null<Array<JsonValue>> {
        var nullKind = false;
        var value:Null<Array<JsonValue>> = null;
        switch (v) {
            case JNull:
                nullKind = true;
            case JArr(a):
                value = a;
            case JBool(_):
                value = null;
            case JNum(_):
                value = null;
            case JStr(_):
                value = null;
            case JObj(_):
                value = null;
        }
        if (!nullKind && value == null) {
            throw new TiqianIllegalArgumentException(TextRangeError.Message("Field " + name + ": expected array or null"));
        }
        return value;
    }

    private static function arrRequired(v:JsonValue, name:String):Array<JsonValue> {
        var value:Null<Array<JsonValue>> = null;
        switch (v) {
            case JArr(a):
                value = a;
            case JNull:
                value = null;
            case JBool(_):
                value = null;
            case JNum(_):
                value = null;
            case JStr(_):
                value = null;
            case JObj(_):
                value = null;
        }
        if (value == null) {
            throw new TiqianIllegalArgumentException(TextRangeError.Message("Field " + name + ": expected array"));
        }
        return value;
    }

    private static function objRequired(v:JsonValue, name:String):Array<JsonMember> {
        var value:Null<Array<JsonMember>> = null;
        switch (v) {
            case JObj(o):
                value = o;
            case JNull:
                value = null;
            case JBool(_):
                value = null;
            case JNum(_):
                value = null;
            case JStr(_):
                value = null;
            case JArr(_):
                value = null;
        }
        if (value == null) {
            throw new TiqianIllegalArgumentException(TextRangeError.Message("Field " + name + ": expected object"));
        }
        return value;
    }

    // --- recursive-descent parser (no Dynamic; corpus is kotlinx output) ---

    private static function skipWs(cur:JsonCursor, text:String):Void {
        var scanning = true;
        while (scanning) {
            if (cur.pos >= text.length) {
                scanning = false;
                break;
            }
            final c = text.charCodeAt(cur.pos);
            if (c == 32 || c == 9 || c == 10 || c == 13) {
                cur.pos++;
            } else {
                scanning = false;
            }
        }
    }

    private static function parseValue(cur:JsonCursor, text:String):JsonValue {
        skipWs(cur, text);
        final c = text.charCodeAt(cur.pos);
        if (c == "{".code) {
            return JObj(parseObject(cur, text));
        }
        if (c == "[".code) {
            return JArr(parseArray(cur, text));
        }
        if (c == '"'.code) {
            return JStr(parseString(cur, text));
        }
        if (text.substr(cur.pos, 4) == "true") {
            cur.pos += 4;
            return JBool(true);
        }
        if (text.substr(cur.pos, 5) == "false") {
            cur.pos += 5;
            return JBool(false);
        }
        if (text.substr(cur.pos, 4) == "null") {
            cur.pos += 4;
            return JNull;
        }
        return JNum(parseNumber(cur, text));
    }

    private static function parseObject(cur:JsonCursor, text:String):Array<JsonMember> {
        final members:Array<JsonMember> = [];
        cur.pos++; // consume '{'
        skipWs(cur, text);
        var closed = false;
        if (text.charCodeAt(cur.pos) == "}".code) {
            cur.pos++;
            closed = true;
        }
        while (!closed) {
            skipWs(cur, text);
            if (text.charCodeAt(cur.pos) != '"'.code) {
                throw new TiqianIllegalArgumentException(TextRangeError.Message("Malformed JSON: expected member name at offset " + cur.pos));
            }
            final name = parseString(cur, text);
            skipWs(cur, text);
            if (text.charCodeAt(cur.pos) != ":".code) {
                throw new TiqianIllegalArgumentException(TextRangeError.Message("Malformed JSON: expected ':' at offset " + cur.pos));
            }
            cur.pos++;
            skipWs(cur, text);
            members.push(new JsonMember(name, parseValue(cur, text)));
            skipWs(cur, text);
            final c = text.charCodeAt(cur.pos);
            if (c == ",".code) {
                cur.pos++;
            } else if (c == "}".code) {
                cur.pos++;
                closed = true;
            } else {
                throw new TiqianIllegalArgumentException(TextRangeError.Message("Malformed JSON: expected ',' or '}' at offset " + cur.pos));
            }
        }
        return members;
    }

    private static function parseArray(cur:JsonCursor, text:String):Array<JsonValue> {
        final values:Array<JsonValue> = [];
        cur.pos++; // consume '['
        skipWs(cur, text);
        var closed = false;
        if (text.charCodeAt(cur.pos) == "]".code) {
            cur.pos++;
            closed = true;
        }
        while (!closed) {
            skipWs(cur, text);
            values.push(parseValue(cur, text));
            skipWs(cur, text);
            final c = text.charCodeAt(cur.pos);
            if (c == ",".code) {
                cur.pos++;
            } else if (c == "]".code) {
                cur.pos++;
                closed = true;
            } else {
                throw new TiqianIllegalArgumentException(TextRangeError.Message("Malformed JSON: expected ',' or ']' at offset " + cur.pos));
            }
        }
        return values;
    }

    private static function parseString(cur:JsonCursor, text:String):String {
        cur.pos++; // consume '"'
        final buf = new StringBuf();
        var done = false;
        while (!done) {
            final c = text.charCodeAt(cur.pos);
            if (c == '"'.code) {
                cur.pos++;
                done = true;
            } else if (c == "\\".code) {
                cur.pos++;
                final e = text.charCodeAt(cur.pos);
                if (e == '"'.code) {
                    buf.addChar(34);
                    cur.pos++;
                } else if (e == "\\".code) {
                    buf.addChar(92);
                    cur.pos++;
                } else if (e == "/".code) {
                    buf.addChar(47);
                    cur.pos++;
                } else if (e == "b".code) {
                    buf.addChar(8);
                    cur.pos++;
                } else if (e == "f".code) {
                    buf.addChar(12);
                    cur.pos++;
                } else if (e == "n".code) {
                    buf.addChar(10);
                    cur.pos++;
                } else if (e == "r".code) {
                    buf.addChar(13);
                    cur.pos++;
                } else if (e == "t".code) {
                    buf.addChar(9);
                    cur.pos++;
                } else if (e == "u".code) {
                    buf.addChar(parseHex4(text, cur.pos + 1));
                    cur.pos += 5;
                } else {
                    throw new TiqianIllegalArgumentException(TextRangeError.Message("Malformed JSON: unsupported escape at offset " + cur.pos));
                }
            } else {
                buf.addChar(c);
                cur.pos++;
            }
        }
        return buf.toString();
    }

    private static function parseHex4(text:String, start:Int):Int {
        var value = 0;
        for (i in 0...4) {
            final c = text.charCodeAt(start + i);
            var digit = 0;
            if (c >= "0".code && c <= "9".code) {
                digit = c - "0".code;
            } else if (c >= "a".code && c <= "f".code) {
                digit = c - "a".code + 10;
            } else if (c >= "A".code && c <= "F".code) {
                digit = c - "A".code + 10;
            } else {
                throw new TiqianIllegalArgumentException(TextRangeError.Message("Malformed JSON: bad \\u escape at offset " + start));
            }
            value = value * 16 + digit;
        }
        return value;
    }

    private static function parseNumber(cur:JsonCursor, text:String):Float {
        final start = cur.pos;
        var scanning = true;
        while (scanning) {
            if (cur.pos >= text.length) {
                scanning = false;
                break;
            }
            final c = text.charCodeAt(cur.pos);
            if ((c >= "0".code && c <= "9".code) || c == "-".code || c == "+".code || c == ".".code || c == "e".code || c == "E".code) {
                cur.pos++;
            } else {
                scanning = false;
            }
        }
        if (cur.pos == start) {
            throw new TiqianIllegalArgumentException(TextRangeError.Message("Malformed JSON: expected value at offset " + start));
        }
        return Std.parseFloat(text.substring(start, cur.pos));
    }
}
