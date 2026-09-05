package org.tiqian.core;

/*
 * GENERATED from Unicode 17.0.0 emoji-data.txt by
 * tools/unicode-emoji/generate_emoji_presentation_data.py.
 * Source: https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-data.txt
 * SHA-256: 2cb2bb9455cda83e8481541ecf5b6dfda66a3bb89efa3fa7c5297eccf607b72b
 * Copyright © 2025 Unicode, Inc.
 * Terms of Use: https://www.unicode.org/terms_of_use.html
 */
@:build(DataTables.rangesField("engine-haxe/data/emoji-modifier-base-ranges.txt", "RANGES"))
class UnicodeEmojiModifierBaseData {
    public static function contains(codePoint:Int):Bool {
        var low:Int = 0;
        var high:Int = Std.int(RANGES.length / 2) - 1;
        while (low <= high) {
            final middle:Int = (low + high) >> 1;
            final base:Int = middle * 2;
            if (codePoint < RANGES[base]) {
                high = middle - 1;
            } else if (codePoint > RANGES[base + 1]) {
                low = middle + 1;
            } else {
                return true;
            }
        }
        return false;
    }
}
