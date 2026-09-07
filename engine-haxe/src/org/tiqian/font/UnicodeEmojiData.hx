package org.tiqian.font;

@:build(DataTables.rangesField("engine-haxe/data/emoji-ranges.txt", "RANGES"))
class UnicodeEmojiData {
    public static function contains(codePoint:Int):Bool {
        var l = 0;
        var h = Std.int(RANGES.length / 2) - 1;
        while (l <= h) {
            var m = (l + h) >> 1;
            var b = m * 2;
            if (codePoint < RANGES[b])
                h = m - 1;
            else if (codePoint > RANGES[b + 1])
                l = m + 1;
            else
                return true;
        }
        return false;
    }
}
