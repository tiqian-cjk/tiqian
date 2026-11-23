package org.tiqian.shared.prepared_dom;

/**
 * Byte-exact string lowering for prepared-dom markup (web/TS-only, research
 * 5.4/5.5). Replaces the hand-written prepared-dom-markup.ts string
 * primitives. Every function reproduces the exact output of its TS twin, so
 * the corpus byte-comparison gate stays green.
 *
 * escapeText / escapeAttribute / cssString scan UTF-16 code units instead of
 * String.replace (boring exposes no replaceAll; StringTools.replace is
 * first-occurrence-only).
 *
 * px is the twin of JS `Number((x).toFixed(5))` then String(...): it rounds
 * the exact binary64 value to 5 fractional decimals with round-half-up and
 * strips trailing zeros. The rounding decomposes the binary64 through
 * haxe.io.FPHelper.doubleToI64 (full 53-bit significand + binary exponent)
 * and does exact integer round-half-up, because native JS toFixed(5) rounds
 * the exact value (ECMA-262 Number.prototype.toFixed step 10b), not the
 * shortest decimal — a FLOAT32 route would emit 12345.6787109375 for
 * 12345.67891.
 */
class Markup {

    /** Escapes & < > in UTF-16 code-unit order (JS replaceAll order: &, <, >). */
    public static function escapeText(value:String):String {
        var out = "";
        var i = 0;
        while (i < value.length) {
            final c = value.charCodeAt(i);
            if (c == 38)
                out += "&amp;";
            else if (c == 60)
                out += "&lt;";
            else if (c == 62)
                out += "&gt;";
            else
                out += String.fromCharCode(c);
            i += 1;
        }
        return out;
    }

    /** escapeText then escapes " as &quot;. */
    public static function escapeAttribute(value:String):String {
        final base = escapeText(value);
        var out = "";
        var i = 0;
        while (i < base.length) {
            final c = base.charCodeAt(i);
            if (c == 34)
                out += "&quot;";
            else
                out += String.fromCharCode(c);
            i += 1;
        }
        return out;
    }

    /** Quotes and escapes \\ and " (JS cssString: escape \\ first, then "). */
    public static function cssString(value:String):String {
        var out = "\"";
        var i = 0;
        while (i < value.length) {
            final c = value.charCodeAt(i);
            if (c == 92)
                out += "\\\\";
            else if (c == 34)
                out += "\\\"";
            else
                out += String.fromCharCode(c);
            i += 1;
        }
        out += "\"";
        return out;
    }

    /** Quantizes to 5 fractional decimals then renders the px unit string. */
    public static function px(value:Float):String {
        final normalized = Math.abs(value) < 0.000001 ? 0.0 : value;
        if (Math.isNaN(normalized))
            return "NaNpx";
        if (!Math.isFinite(normalized))
            return normalized < 0 ? "-Infinitypx" : "Infinitypx";
        if (normalized == 0.0)
            return "0px";
        final negative = normalized < 0;
        final a = negative ? -normalized : normalized;
        // Number.prototype.toFixed(5) returns String(x) for x >= 1e21.
        if (a >= 1e21)
            return (negative ? "-" : "") + Std.string(a) + "px";
        final n = roundToFiveDecimals(a);
        final formatted = formatFixed(n);
        if (formatted == "0")
            return "0px";
        return (negative ? "-" : "") + formatted + "px";
    }

    /**
     * The (a) half of prepared-dom-markup applyDynamicStyles: appends the
     * class/style entry for a style declaration to an ordered entry list.
     * styles empty -> no-op. With a resolver -> append/merge a class entry
     * (merge keeps the existing non-empty class and appends the generated
     * one, matching the TS truthiness check attributes.class ? ... : ...);
     * without -> append a style entry carrying the raw declaration. The
     * (b) glue re-serializes the entries in sorted order, so the final byte
     * output is identical to the hand-written TS twin.
     */
    public static function applyDynamicStyles(entries:Array<AttributeEntry>, styles:Array<String>, styleClassFor:Null<StyleClassResolver>):Void {
        if (styles.length == 0)
            return;
        final declaration = styles.join(";");
        if (styleClassFor != null) {
            final generatedClass = styleClassFor.resolve(declaration);
            var index = -1;
            var i = 0;
            while (i < entries.length) {
                if (entries[i].name == "class") {
                    index = i;
                    break;
                }
                i += 1;
            }
            if (index >= 0 && entries[index].value != "") {
                entries[index].value = entries[index].value + " " + generatedClass;
            } else if (index >= 0) {
                entries[index].value = generatedClass;
            } else {
                entries.push({ name: "class", value: generatedClass });
            }
        } else {
            entries.push({ name: "style", value: declaration });
        }
    }

    /** Find-or-update an attribute by name (the TS attributes[name]=value record collapse). */
    public static function setAttribute(entries:Array<AttributeEntry>, name:String, value:String):Void {
        var i = 0;
        while (i < entries.length) {
            if (entries[i].name == name) {
                entries[i].value = value;
                return;
            }
            i += 1;
        }
        entries.push({ name: name, value: value });
    }

    /** New sorted copy of entries, code-unit ascending by name only (TS sort). */
    public static function sortedAttributeEntries(entries:Array<AttributeEntry>):Array<AttributeEntry> {
        final copy:Array<AttributeEntry> = [];
        var i = 0;
        while (i < entries.length) {
            copy.push(entries[i]);
            i += 1;
        }
        // Insertion sort, code-unit ascending by name (stable, matches JS sort).
        var j = 1;
        while (j < copy.length) {
            final key = copy[j];
            var k = j - 1;
            while (k >= 0 && compareEntryNames(copy[k], key) > 0) {
                copy[k + 1] = copy[k];
                k -= 1;
            }
            copy[k + 1] = key;
            j += 1;
        }
        return copy;
    }

    /** Serialize sorted entries into the ` name="escaped"` attribute string. */
    public static function serializeAttributeEntries(entries:Array<AttributeEntry>):String {
        var out = "";
        var i = 0;
        while (i < entries.length) {
            if (i > 0)
                out += " ";
            final e = entries[i];
            if (e.value == "")
                out += e.name;
            else
                out += e.name + "=\"" + escapeAttribute(e.value) + "\"";
            i += 1;
        }
        return out;
    }

    /** Joins cssString-quoted font families with a comma (the TS twin of families.map(cssString).join(",")). */
    public static function cssFamilyList(families:Array<String>):String {
        var out = "";
        var i = 0;
        while (i < families.length) {
            if (i > 0)
                out += ",";
            out += cssString(families[i]);
            i += 1;
        }
        return out;
    }

    /** Bare text leaf (prepared-dom-markup.ts renderedText). */
    public static function renderedText(value:String):MarkupNode {
        return new RenderedMarkupNode(escapeText(value), Text(value));
    }

    /** Element with optional text body (prepared-dom-markup.ts renderedElement). */
    public static function renderedElement(tag:String, entries:Array<AttributeEntry>, text:Null<String>, voidElement:Bool):MarkupNode {
        final sorted = sortedAttributeEntries(entries);
        final attrs = serializeAttributeEntries(sorted);
        final open = "<" + tag + (attrs.length > 0 ? " " + attrs : "") + ">";
        if (voidElement) {
            return new RenderedMarkupNode(open, Element(tag, sorted, []));
        }
        final body = text == null ? "" : escapeText(text);
        final html = open + body + "</" + tag + ">";
        final children:Array<MarkupArtifact> = [];
        if (text != null) {
            children.push(Text(text));
        }
        return new RenderedMarkupNode(html, Element(tag, sorted, children));
    }

    /** Container whose children are appended later (prepared-dom-markup.ts renderedContainer). */
    public static function renderedContainer(tag:String, entries:Array<AttributeEntry>):RenderedMarkupContainer {
        final sorted = sortedAttributeEntries(entries);
        return new RenderedMarkupContainer(tag, sorted);
    }

    private static function compareEntryNames(a:AttributeEntry, b:AttributeEntry):Int {
        if (a.name < b.name)
            return -1;
        if (a.name > b.name)
            return 1;
        return 0;
    }

    // --- exact binary64 -> 5-decimal round-half-up ---

    /** N = round(a * 1e5) as a decimal string, round-half-up on the exact value. */
    private static function roundToFiveDecimals(a:Float):String {
        final d = haxe.io.FPHelper.doubleToI64(a);
        final exp11 = (d.high >>> 20) & 0x7FF;
        final mantHigh = d.high & 0xFFFFF;
        final low31 = d.low & 0x7FFFFFFF;
        final lowHigh = d.low >>> 31;
        // frac = mantHigh * 2^32 + lowHigh * 2^31 + low31 (the low 52 bits).
        var frac = timesSmall("4294967296", mantHigh);
        if (lowHigh != 0)
            frac = addDecimal(frac, "2147483648");
        frac = addDecimal(frac, Std.string(low31));
        final significand = exp11 == 0 ? frac : addDecimal("4503599627370496", frac);
        final e = exp11 == 0 ? -1074 : exp11 - 1075;
        final t = e + 5;
        if (t >= 0)
            return multiplyDecimal(timesSmall(significand, 3125), twoPower(t));
        final m = -t;
        final x = multiplyDecimal(significand, fivePower(m + 5));
        final half = "5" + zeros(m - 1);
        return truncateLast(addDecimal(x, half), m);
    }

    /** Renders N / 1e5 as fixed notation then strips trailing zeros. */
    private static function formatFixed(n:String):String {
        final len = n.length;
        if (len <= 5)
            return stripFractionZeros("0." + zeros(5 - len) + n);
        final intPart = n.substr(0, len - 5);
        final fracPart = n.substr(len - 5);
        return stripFractionZeros(intPart + "." + fracPart);
    }

    // --- decimal-string big arithmetic (never routes through Float) ---

    private static function timesSmall(digits:String, factor:Int):String {
        final out = new StringBuf();
        var carry = 0;
        var i = digits.length - 1;
        while (i >= 0) {
            final product = (digits.charCodeAt(i) - 48) * factor + carry;
            out.addChar(48 + product % 10);
            carry = Std.int(product / 10);
            i -= 1;
        }
        while (carry > 0) {
            out.addChar(48 + carry % 10);
            carry = Std.int(carry / 10);
        }
        return reverse(out.toString());
    }

    private static function addDecimal(a:String, b:String):String {
        final out = new StringBuf();
        var i = a.length - 1;
        var j = b.length - 1;
        var carry = 0;
        while (i >= 0 || j >= 0 || carry > 0) {
            final sum = (i >= 0 ? a.charCodeAt(i) - 48 : 0) + (j >= 0 ? b.charCodeAt(j) - 48 : 0) + carry;
            out.addChar(48 + sum % 10);
            carry = Std.int(sum / 10);
            i -= 1;
            j -= 1;
        }
        return reverse(out.toString());
    }

    private static function multiplyDecimal(a:String, b:String):String {
        var result = "0";
        var shift = 0;
        var i = b.length - 1;
        while (i >= 0) {
            final digit = b.charCodeAt(i) - 48;
            if (digit != 0) {
                var part = timesSmall(a, digit);
                if (shift > 0)
                    part += zeros(shift);
                result = addDecimal(result, part);
            }
            shift += 1;
            i -= 1;
        }
        return result;
    }

    private static function fivePower(k:Int):String {
        var acc = "1";
        var i = 0;
        while (i < k) {
            acc = timesSmall(acc, 5);
            i += 1;
        }
        return acc;
    }

    private static function twoPower(k:Int):String {
        var acc = "1";
        var i = 0;
        while (i < k) {
            acc = timesSmall(acc, 2);
            i += 1;
        }
        return acc;
    }

    /** floor(digits / 10^m). */
    private static function truncateLast(digits:String, m:Int):String {
        if (digits.length <= m)
            return "0";
        return digits.substr(0, digits.length - m);
    }

    private static function reverse(s:String):String {
        var out = "";
        var i = s.length - 1;
        while (i >= 0) {
            out += s.charAt(i);
            i -= 1;
        }
        return out;
    }

    /** "12.34000" -> "12.34", "0.00000" -> "0", "100000.00000" -> "100000". */
    private static function stripFractionZeros(s:String):String {
        final dot = s.indexOf(".");
        if (dot < 0)
            return s;
        var end = s.length;
        while (end > dot + 1 && s.charCodeAt(end - 1) == 48)
            end -= 1;
        if (end == dot + 1)
            return s.substr(0, dot);
        return s.substr(0, end);
    }

    private static function zeros(n:Int):String {
        var s = "";
        var i = 0;
        while (i < n) {
            s += "0";
            i += 1;
        }
        return s;
    }
}
