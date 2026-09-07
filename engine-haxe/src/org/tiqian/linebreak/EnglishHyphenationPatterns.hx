package org.tiqian.linebreak;

@:build(DataTables.codeUnitsField("engine-haxe/data/hyph-en-us.tex", "TEX_UNITS"))
class EnglishHyphenationPatterns {
    public static function raw():String {
        return load();
    }

    public static function load():String {
        final output = new std.StringBuf();
        var index = 0;
        while (index < TEX_UNITS.length) {
            output.add(String.fromCharCode(TEX_UNITS[index]));
            index++;
        }
        return output.toString();
    }
}
