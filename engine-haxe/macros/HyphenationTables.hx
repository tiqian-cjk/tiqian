#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import sys.io.File;

/**
 * Compile-time packing of a TeX hyphenation pattern file (`HyphenationTablePacking`).
 *
 * `texPatternFields(path)` runs as a `@:build` macro. It parses the file with the rules of
 * `org.tiqian.linebreak.ParseTexHyphenationPatterns.parse` (a `%` starts a comment to the end of
 * its line; the `\patterns{...}` and `\hyphenation{...}` blocks hold whitespace-separated
 * tokens; a later token with the same letters replaces an earlier one) and adds two static
 * final `Array<Int>` fields that `org.tiqian.linebreak.PackedHyphenationTable` reads:
 *
 * - `PATTERN_UNITS`: every pattern token (letters with the inter-letter level digits, such as
 *   `.ach4`) as UTF-16 code units, ordered by the token's letters in code-unit order;
 * - `EXCEPTION_UNITS`: every exception token lowercased (letters with `-` at the break points),
 *   ordered by its letters in code-unit order.
 *
 * A line feed (code unit 10) separates adjacent tokens; a TeX token holds no whitespace, so the
 * separator never occurs inside a token. The fields carry no offset table: a table of increasing
 * offsets compresses poorly in the Web bundle, and the reader derives the offsets in one scan.
 *
 * The fields take the data-table emission of boring feature spec 20, so the runtime reads the
 * table without parsing TeX text. The macro rejects input whose packed form would read
 * differently from the runtime parse: a non-ASCII character (lowercasing could change the
 * length) and a pattern token with two adjacent level digits (the runtime parse keeps only the
 * second digit, the packed reader would apply both).
 */
class HyphenationTables {
    macro public static function texPatternFields(path:String):Array<Field> {
        final fields = Context.getBuildFields();
        final pos = Context.currentPos();
        if (!sys.FileSystem.exists(path))
            Context.fatalError('Hyphenation pattern file not found: $path', pos);
        final tex = File.getContent(path);
        for (i in 0...tex.length) {
            if (tex.charCodeAt(i) > 0x7F)
                Context.fatalError('$path: non-ASCII character at offset $i', pos);
        }
        final noComments = new StringBuf();
        for (line in tex.split("\n")) {
            final p = line.indexOf("%");
            noComments.add(p < 0 ? line : line.substring(0, p));
            noComments.add("\n");
        }
        final text = noComments.toString();

        final patternByKey = new Map<String, String>();
        for (token in tokens(block(text, "\\patterns"))) {
            final key = new StringBuf();
            var previousDigit = false;
            for (i in 0...token.length) {
                final code = token.charCodeAt(i);
                final digit = code >= "0".code && code <= "9".code;
                if (digit && previousDigit)
                    Context.fatalError('$path: pattern "$token" has adjacent level digits', pos);
                if (!digit)
                    key.add(token.charAt(i));
                previousDigit = digit;
            }
            patternByKey.set(key.toString(), token);
        }
        final exceptionByKey = new Map<String, String>();
        for (token in tokens(block(text, "\\hyphenation"))) {
            final lowered = token.toLowerCase();
            exceptionByKey.set(StringTools.replace(lowered, "-", ""), lowered);
        }

        pack(fields, "PATTERN", patternByKey, pos);
        pack(fields, "EXCEPTION", exceptionByKey, pos);
        return fields;
    }

    static function block(text:String, name:String):String {
        final start = text.indexOf(name);
        if (start < 0)
            return "";
        final open = text.indexOf("{", start);
        if (open < 0)
            return "";
        final close = text.indexOf("}", open + 1);
        if (close < 0)
            return "";
        return text.substring(open + 1, close);
    }

    static function tokens(text:String):Array<String> {
        final out = [];
        var token = "";
        for (i in 0...text.length) {
            final c = text.charAt(i);
            if (c == " " || c == "\t" || c == "\n" || c == "\r") {
                if (token.length > 0) {
                    out.push(token);
                    token = "";
                }
            } else
                token += c;
        }
        if (token.length > 0)
            out.push(token);
        return out;
    }

    static function compareUnits(a:String, b:String):Int {
        final n = a.length < b.length ? a.length : b.length;
        for (i in 0...n) {
            final d = a.charCodeAt(i) - b.charCodeAt(i);
            if (d != 0)
                return d;
        }
        return a.length - b.length;
    }

    static function pack(fields:Array<Field>, prefix:String, tokenByKey:Map<String, String>, pos:Position):Void {
        final keys = [for (k in tokenByKey.keys()) k];
        keys.sort(compareUnits);
        final units:Array<Expr> = [];
        for (k in keys) {
            if (units.length > 0)
                units.push({expr: EConst(CInt("10")), pos: pos});
            final token = tokenByKey.get(k);
            for (i in 0...token.length)
                units.push({expr: EConst(CInt(Std.string(token.charCodeAt(i)))), pos: pos});
        }
        fields.push({
            name: prefix + "_UNITS",
            doc: null,
            meta: [],
            access: [APublic, AStatic, AFinal],
            kind: FVar(macro :Array<Int>, {expr: EArrayDecl(units), pos: pos}),
            pos: pos
        });
    }
}
#end
