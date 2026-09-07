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
        var ti = 0;
        while (ti < tokens(block(noComments, "\\patterns")).length) {
            final token = tokens(block(noComments, "\\patterns"))[ti];
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
        var ei = 0;
        while (ei < tokens(block(noComments, "\\hyphenation")).length) {
            final token = tokens(block(noComments, "\\hyphenation"))[ei];
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
