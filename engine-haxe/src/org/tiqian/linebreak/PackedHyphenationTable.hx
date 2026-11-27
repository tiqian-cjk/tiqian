package org.tiqian.linebreak;

/**
 * A Liang hyphenation table in packed form, read without parsing TeX text
 * (`HyphenationTablePacking`).
 *
 * The pattern sequence holds every pattern token (letters with the inter-letter level digits,
 * such as `.ach4`) as UTF-16 code units, ordered by the token's letters in code-unit order; the
 * exception sequence holds every exception token lowercased, letters with `-` at the break
 * points, in the same order by letters. A line feed (code unit 10) separates adjacent tokens in
 * each sequence; the constructor scans both sequences once and keeps the start offset of every
 * token. `data` serves the sequences by index: the `HyphenationTables`
 * build macro produces them from a TeX pattern file at compile time and
 * `EnglishHyphenationTableData` reads those static fields in place; a host that ships another
 * language's patterns supplies them through `ArrayHyphenationTableData` and plugs the table in
 * through `PackedLiangHyphenator`.
 */
class PackedHyphenationTable {
    final data:HyphenationTableData;
    /** The start offset of every pattern token, then the unit count plus one (one past the end). */
    final patternStarts:Array<Int>;
    /** The start offset of every exception token, then the unit count plus one. */
    final exceptionStarts:Array<Int>;

    public function new(data:HyphenationTableData) {
        this.data = data;
        final patternUnitCount = data.patternUnitCount();
        final patterns = new Array<Int>();
        if (patternUnitCount > 0) {
            patterns.push(0);
            for (offset in 0...patternUnitCount) {
                if (data.patternUnit(offset) == TokenSeparator)
                    patterns.push(offset + 1);
            }
            patterns.push(patternUnitCount + 1);
        }
        this.patternStarts = patterns;
        final exceptionUnitCount = data.exceptionUnitCount();
        final exceptions = new Array<Int>();
        if (exceptionUnitCount > 0) {
            exceptions.push(0);
            for (offset in 0...exceptionUnitCount) {
                if (data.exceptionUnit(offset) == TokenSeparator)
                    exceptions.push(offset + 1);
            }
            exceptions.push(exceptionUnitCount + 1);
        }
        this.exceptionStarts = exceptions;
    }

    public function patternCount():Int
        return patternStarts.length == 0 ? 0 : patternStarts.length - 1;

    public function exceptionCount():Int
        return exceptionStarts.length == 0 ? 0 : exceptionStarts.length - 1;

    /**
     * Applies the pattern whose letters are `word[start, end)`: level `k` of the pattern raises
     * `levels[at + k]` when it is larger. Returns `MatchedPattern` when the pattern exists,
     * `PrefixOnly` when no pattern has exactly these letters but a longer one starts with them,
     * and `NoPatternWithPrefix` when no pattern starts with them, so a caller extending the
     * slice to the right can stop.
     */
    public function raisePatternLevels(word:Array<Int>, start:Int, end:Int, levels:Array<Int>, at:Int):Int {
        final index = lowerBound(word, start, end, true);
        if (index >= patternCount())
            return NoPatternWithPrefix;
        final tokenStart = patternStarts[index];
        final tokenEnd = patternStarts[index + 1] - 1;
        final relation = keyRelation(tokenStart, tokenEnd, word, start, end, true);
        if (relation == KeyEqualsSlice) {
            var position = 0;
            var p = tokenStart;
            while (p < tokenEnd) {
                final unit = data.patternUnit(p);
                if (isDigit(unit)) {
                    final level = unit - 48;
                    if (level > levels[at + position])
                        levels[at + position] = level;
                } else
                    position++;
                p++;
            }
            return MatchedPattern;
        }
        return relation == KeyExtendsSlice ? PrefixOnly : NoPatternWithPrefix;
    }

    /** The break offsets of the exception whose letters are the whole of `word`, or null. */
    public function exceptionOffsets(word:Array<Int>):Null<Array<Int>> {
        final index = lowerBound(word, 0, word.length, false);
        if (index >= exceptionCount())
            return null;
        final tokenStart = exceptionStarts[index];
        final tokenEnd = exceptionStarts[index + 1] - 1;
        if (keyRelation(tokenStart, tokenEnd, word, 0, word.length, false) != KeyEqualsSlice)
            return null;
        final offsets = new Array<Int>();
        var position = 0;
        var p = tokenStart;
        while (p < tokenEnd) {
            if (data.exceptionUnit(p) == "-".code)
                offsets.push(position);
            else
                position++;
            p++;
        }
        return offsets;
    }

    public static inline final MatchedPattern = 2;
    public static inline final PrefixOnly = 1;
    public static inline final NoPatternWithPrefix = 0;

    static inline final TokenSeparator = 10;
    static inline final KeyEqualsSlice = 0;
    static inline final KeyExtendsSlice = 1;
    static inline final KeyAfterSlice = 2;
    static inline final KeyBeforeSlice = 3;

    static function isDigit(unit:Int):Bool
        return unit >= 48 && unit <= 57;

    function unitAt(offset:Int, pattern:Bool):Int
        return pattern ? data.patternUnit(offset) : data.exceptionUnit(offset);

    function startAt(index:Int, pattern:Bool):Int
        return pattern ? patternStarts[index] : exceptionStarts[index];

    /** Whether `unit` is markup inside a token: a level digit of a pattern, `-` of an exception. */
    static function isMarkup(unit:Int, pattern:Bool):Bool
        return pattern ? isDigit(unit) : unit == "-".code;

    /**
     * Compares the letters of the token `units[from, to)` with `word[start, end)` in code-unit
     * order, skipping the token's markup.
     */
    function keyRelation(from:Int, to:Int, word:Array<Int>, start:Int, end:Int, pattern:Bool):Int {
        var p = from;
        var q = start;
        while (true) {
            while (p < to && isMarkup(unitAt(p, pattern), pattern))
                p++;
            if (p >= to)
                return q >= end ? KeyEqualsSlice : KeyBeforeSlice;
            if (q >= end)
                return KeyExtendsSlice;
            final a = unitAt(p, pattern);
            final b = word[q];
            if (a != b)
                return a < b ? KeyBeforeSlice : KeyAfterSlice;
            p++;
            q++;
        }
    }

    /** The index of the first token whose letters do not order before `word[start, end)`. */
    function lowerBound(word:Array<Int>, start:Int, end:Int, pattern:Bool):Int {
        var low = 0;
        var high = pattern ? patternCount() : exceptionCount();
        while (low < high) {
            final mid = (low + high) >> 1;
            if (keyRelation(startAt(mid, pattern), startAt(mid + 1, pattern) - 1, word, start, end, pattern) == KeyBeforeSlice)
                low = mid + 1;
            else
                high = mid;
        }
        return low;
    }
}

/**
 * The two token sequences of a packed hyphenation table, read by index: `patternUnit(offset)` for
 * `offset` in `0...patternUnitCount()` is a code unit of the pattern tokens, with a line feed
 * (code unit 10) between adjacent tokens; the exception accessors read the exception tokens the
 * same way.
 */
interface HyphenationTableData {
    public function patternUnitCount():Int;
    public function patternUnit(offset:Int):Int;
    public function exceptionUnitCount():Int;
    public function exceptionUnit(offset:Int):Int;
}

/** A packed hyphenation table a host supplies as arrays, for patterns the engine does not bundle. */
class ArrayHyphenationTableData implements HyphenationTableData {
    final patternUnits:Array<Int>;
    final exceptionUnits:Array<Int>;

    public function new(patternUnits:Array<Int>, exceptionUnits:Array<Int>) {
        this.patternUnits = patternUnits;
        this.exceptionUnits = exceptionUnits;
    }

    public function patternUnitCount():Int
        return patternUnits.length;

    public function patternUnit(offset:Int):Int
        return patternUnits[offset];

    public function exceptionUnitCount():Int
        return exceptionUnits.length;

    public function exceptionUnit(offset:Int):Int
        return exceptionUnits[offset];
}
