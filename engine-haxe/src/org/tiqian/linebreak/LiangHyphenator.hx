package org.tiqian.linebreak;

import runtime.SortedTable;

class LiangHyphenator implements Hyphenator {
    private final patterns:runtime.SortedTable.SortedMapTable<String, Array<Int>>;
    private final exceptions:runtime.SortedTable.SortedMapTable<String, Array<Int>>;
    private final leftMin:Int;
    private final rightMin:Int;

    public function new(patterns:runtime.SortedTable.SortedMapTable<String, Array<Int>>, ?exceptions:runtime.SortedTable.SortedMapTable<String, Array<Int>>,
            ?leftMin:Null<Int>, ?rightMin:Null<Int>) {
        this.patterns = patterns;
        this.exceptions = exceptions;
        this.leftMin = leftMin == null ? 2 : leftMin;
        this.rightMin = rightMin == null ? 3 : rightMin;
    }

    public function hyphenate(word:String):std.ReadOnlyArray<Int> {
        if (word.length < leftMin + rightMin)
            return [];
        final lower = word.toLowerCase();
        final explicit = exceptions.get(lower);
        if (explicit != null) {
            final out = [];
            var q = 0;
            while (q < explicit.length) {
                final v = explicit[q];
                if (v >= leftMin && v <= word.length - rightMin)
                    out.push(v);
                q++;
            }
            return out;
        }
        final work = "." + lower + ".";
        final levels = [for (_ in 0...work.length + 1) 0];
        var i = 0;
        while (i < work.length) {
            var key = "";
            var j = i + 1;
            while (j <= work.length) {
                key += work.charAt(j - 1);
                final pattern = patterns.get(key);
                if (pattern != null) {
                    var k = 0;
                    while (k < pattern.length) {
                        if (pattern[k] > levels[i + k])
                            levels[i + k] = pattern[k];
                        k++;
                    }
                }
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
