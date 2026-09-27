package org.tiqian.linebreak;

import runtime.SortedTable;

class ParseTexHyphenationPatterns {
    private static function block(text:String, name:String):String {
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

    private static function tokens(text:String):Array<String> {
        final out = [];
        var token = "";
        var i = 0;
        while (i < text.length) {
            final c = text.charAt(i);
            final sep = c == " " || c == "\t" || c == "\n" || c == "\r";
            if (sep) {
                if (token.length > 0) {
                    out.push(token);
                    token = "";
                }
            } else
                token += c;
            i++;
        }
        if (token.length > 0)
            out.push(token);
        return out;
    }

    public static function parse(tex:String):ParsedTexHyphenation {
        var noComments = "";
        final sourceLines = tex.split("\n");
        var li = 0;
        while (li < sourceLines.length) {
            final line = sourceLines[li];
            final p = line.indexOf("%");
            noComments += (p < 0 ? line : line.substring(0, p)) + "\n";
            li++;
        }
        final pb = SortedTable.mapBuilder(SortedTable.compareStrings);
        final eb = SortedTable.mapBuilder(SortedTable.compareStrings);
        // The token list is loop-invariant: block() scans the whole pattern
        // text and tokens() rebuilds every token, so recomputing it in both
        // the condition and the body made the parse quadratic in the number
        // of tokens. Hoisting it keeps the parsed result identical and turns
        // the parse back into a single pass. (HyphenationParseHoist)
        final patternTokens = tokens(block(noComments, "\\patterns"));
        var ti = 0;
        while (ti < patternTokens.length) {
            final token = patternTokens[ti];
            final key = new StringBuf();
            final levels = [0];
            var i = 0;
            while (i < token.length) {
                final code = token.charCodeAt(i);
                if (code >= "0".code && code <= "9".code)
                    levels[levels.length - 1] = code - 48;
                else {
                    key.add(token.charAt(i));
                    levels.push(0);
                }
                i++;
            }
            pb.put(key.toString(), levels);
            ti++;
        }
        // Same hoist as the patterns loop above. (HyphenationParseHoist)
        final hyphenationTokens = tokens(block(noComments, "\\hyphenation"));
        var ei = 0;
        while (ei < hyphenationTokens.length) {
            final token = hyphenationTokens[ei];
            final key = new StringBuf();
            final offsets = [];
            var pos = 0;
            var i = 0;
            while (i < token.length) {
                if (token.charAt(i) == "-")
                    offsets.push(pos);
                else {
                    key.add(token.charAt(i));
                    pos++;
                }
                i++;
            }
            eb.put(key.toString().toLowerCase(), offsets);
            ei++;
        }
        return new ParsedTexHyphenation(pb.build(), eb.build());
    }
}
