package org.tiqian.linebreak;

/**
 * Frank Liang's algorithm over a `PackedHyphenationTable`. The break offsets equal those of
 * `LiangHyphenator` over the same patterns and exceptions parsed by
 * `ParseTexHyphenationPatterns.parse` (`EnglishHyphenationTest.packedTableMatchesTheParsedTex`
 * checks this for the bundled en-US table). The pattern walk stops extending a slice once no
 * pattern starts with its letters, which skips lookups that cannot match.
 */
class PackedLiangHyphenator implements Hyphenator {
    final table:PackedHyphenationTable;
    final leftMin:Int;
    final rightMin:Int;

    public function new(table:PackedHyphenationTable, ?leftMin:Null<Int>, ?rightMin:Null<Int>) {
        this.table = table;
        this.leftMin = leftMin == null ? 2 : leftMin;
        this.rightMin = rightMin == null ? 3 : rightMin;
    }

    public function hyphenate(word:String):std.ReadOnlyArray<Int> {
        if (word.length < leftMin + rightMin)
            return [];
        final lower = word.toLowerCase();
        final lowerUnits = new Array<Int>();
        for (i in 0...lower.length) {
            final unit:Null<Int> = lower.charCodeAt(i);
            lowerUnits.push(unit == null ? 0 : unit);
        }
        final explicit = table.exceptionOffsets(lowerUnits);
        if (explicit != null) {
            final out = [];
            for (qIdx in 0...explicit.length) {
                final v = explicit[qIdx];
                if (v >= leftMin && v <= word.length - rightMin)
                    out.push(v);
            }
            return out;
        }
        final work = new Array<Int>();
        work.push(".".code);
        for (i in 0...lowerUnits.length)
            work.push(lowerUnits[i]);
        work.push(".".code);
        final levels = new Array<Int>();
        for (_ in 0...work.length + 1)
            levels.push(0);
        var i = 0;
        while (i < work.length) {
            var j = i + 1;
            while (j <= work.length) {
                if (table.raisePatternLevels(work, i, j, levels, i) == PackedHyphenationTable.NoPatternWithPrefix)
                    break;
                j++;
            }
            i++;
        }
        final result = [];
        var m = 0;
        while (m < word.length - 1) {
            final offset = m + 1;
            if (offset >= leftMin && offset <= word.length - rightMin && levels[m + 2] % 2 == 1)
                result.push(offset);
            m++;
        }
        return result;
    }
}
