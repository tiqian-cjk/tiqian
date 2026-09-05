package;

import js.Syntax;
import org.tiqian.core.RubyKind;
import org.tiqian.core.RubySpan;
import org.tiqian.core.TextRange;
import runtime.SortedTable;

/**
 * Binds the boring runtime sorted tables to the std.SortedSet and
 * std.SortedMap extern names for the stage A test runner. Every set and
 * map value is a resident SortedSetTable or SortedMapTable, so Std.string
 * prints the ruled text from the boring runtime and lookup semantics
 * match the generated targets. Keys in this runner are integers, strings,
 * TextRange, or RubySpan; compareKeys dispatches on the runtime key type.
 * The two structure-key arms mirror the per-type comparators boring
 * generates for real targets (compareTextRange and compareRubySpan in
 * out/kotlin-gen); when a dataClass key type changes its fields, update
 * the matching arm here in the same change.
 */
class SortedTablesOracle {
    public static function install():Void {
        Syntax.code("globalThis.std = globalThis.std || {}; globalThis.std.SortedSet = { builder: function() { return {0}.setBuilder({1}); } }; globalThis.std.SortedMap = { builder: function() { return {0}.mapBuilder({1}); } };",
            SortedTable, compareKeys);
    }

    static function compareKeys(left:Dynamic, right:Dynamic):Int {
        if (Std.isOfType(left, String)) {
            return SortedTable.compareStrings(left, right);
        }
        if (Std.isOfType(left, TextRange)) {
            return compareTextRangeKeys(left, right);
        }
        if (Std.isOfType(left, RubySpan)) {
            return compareRubySpanKeys(left, right);
        }
        return SortedTable.compareInts(Std.int(left), Std.int(right));
    }

    static function compareTextRangeKeys(left:TextRange, right:TextRange):Int {
        final byStart = SortedTable.compareInts(left.start, right.start);
        if (byStart != 0) {
            return byStart;
        }
        return SortedTable.compareInts(left.end, right.end);
    }

    static function compareRubySpanKeys(left:RubySpan, right:RubySpan):Int {
        final byRange = compareTextRangeKeys(left.baseRange, right.baseRange);
        if (byRange != 0) {
            return byRange;
        }
        final byText = SortedTable.compareStrings(left.text, right.text);
        if (byText != 0) {
            return byText;
        }
        var index = 0;
        while (index < left.fontFamilies.length && index < right.fontFamilies.length) {
            final byFamily = SortedTable.compareStrings(left.fontFamilies[index], right.fontFamilies[index]);
            if (byFamily != 0) {
                return byFamily;
            }
            index += 1;
        }
        final byFamilyCount = left.fontFamilies.length - right.fontFamilies.length;
        if (byFamilyCount != 0) {
            return byFamilyCount;
        }
        final byKind = rubyKindOrder(left.kind) - rubyKindOrder(right.kind);
        if (byKind != 0) {
            return byKind;
        }
        if (left.locale == null && right.locale != null) {
            return -1;
        }
        if (left.locale != null && right.locale == null) {
            return 1;
        }
        if (left.locale != null && right.locale != null) {
            return SortedTable.compareStrings(left.locale, right.locale);
        }
        return 0;
    }

    static function rubyKindOrder(kind:RubyKind):Int {
        return switch (kind) {
            case Pinyin: 0;
            case Bopomofo: 1;
        };
    }
}
