package org.tiqian.linebreak;

import org.tiqian.linebreak.LazyHyphenator.HyphenatorSource;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class EnglishHyphenationTest {
    @:test public static function hyphenatesCommonWordsAtSyllablePoints():Void {
        new TestTraceRecorder("EnglishHyphenationTest").section("hyphenatesCommonWordsAtSyllablePoints");
        TracedAssertions.assertEqualsString("hy-phen-ation", EnglishHyphenationTestHelpers.hyphenated("hyphenation"));
        TracedAssertions.assertEqualsString("com-puter", EnglishHyphenationTestHelpers.hyphenated("computer"));
        TracedAssertions.assertTrue(EnglishHyphenationTestHelpers.hyphenated("international").indexOf("in-ter") == 0,
            EnglishHyphenationTestHelpers.hyphenated("international"));
    }

    @:test public static function respectsMarginsAndShortWords():Void {
        new TestTraceRecorder("EnglishHyphenationTest").section("respectsMarginsAndShortWords");
        TracedAssertions.assertEqualsIntArray([], EnglishHyphenation.enUs().hyphenate("the"));
        TracedAssertions.assertEqualsIntArray([], EnglishHyphenation.enUs().hyphenate("a"));
        TracedAssertions.assertTrue(EnglishHyphenationTestHelpers.withinMargins(EnglishHyphenation.enUs().hyphenate("supercalifragilistic"), 2, 3, 20),
            "offsets=[2, 5, 8, 13, 17]");
    }

    @:test public static function honoursTheExceptionList():Void {
        new TestTraceRecorder("EnglishHyphenationTest").section("honoursTheExceptionList");
        TracedAssertions.assertEqualsIntArray([], EnglishHyphenation.enUs().hyphenate("project"));
        TracedAssertions.assertEqualsIntArray([], EnglishHyphenation.enUs().hyphenate("present"));
    }

    @:test public static function packedTableMatchesTheParsedTex():Void {
        new TestTraceRecorder("EnglishHyphenationTest").section("packedTableMatchesTheParsedTex");
        final parsed = ParseTexHyphenationPatterns.parse(EnglishHyphenationTexSource.load());
        final table = EnglishHyphenationPatterns.table();
        TracedAssertions.assertEqualsInt(parsed.patterns.size(), table.patternCount());
        TracedAssertions.assertEqualsInt(parsed.exceptions.size(), table.exceptionCount());
        var mismatches = 0;
        for (i in 0...parsed.patterns.size()) {
            final key = EnglishHyphenationTestHelpers.units(parsed.patterns.keyAt(i));
            final expected = parsed.patterns.valueAt(i);
            final levels = new Array<Int>();
            for (_ in 0...key.length + 1)
                levels.push(0);
            final matched = table.raisePatternLevels(key, 0, key.length, levels, 0) == PackedHyphenationTable.MatchedPattern;
            if (!matched || !EnglishHyphenationTestHelpers.sameInts(expected, levels))
                mismatches++;
        }
        for (i in 0...parsed.exceptions.size()) {
            final offsets = table.exceptionOffsets(EnglishHyphenationTestHelpers.units(parsed.exceptions.keyAt(i)));
            if (offsets == null || !EnglishHyphenationTestHelpers.sameInts(parsed.exceptions.valueAt(i), offsets))
                mismatches++;
        }
        TracedAssertions.assertEqualsInt(0, mismatches);
        final reference = new LiangHyphenator(parsed.patterns, parsed.exceptions, 2, 3);
        final packed = EnglishHyphenation.enUs();
        final words = ["hyphenation", "computer", "international", "internationalization", "supercalifragilistic", "Associate",
            "PROJECT", "present", "table", "typography", "paragraph", "justification", "Unicode", "HarfBuzz", "punctuation",
            "philanthropic", "declination", "obligatory", "uncopyrightable", "a", "the", "xylophone", "rhythm", "encyclopaedia"];
        for (word in words)
            TracedAssertions.assertEqualsIntArray(reference.hyphenate(word), packed.hyphenate(word), word);
    }

    @:test public static function lazySlotBuildsOnTheFirstRequestOnly():Void {
        new TestTraceRecorder("EnglishHyphenationTest").section("lazySlotBuildsOnTheFirstRequestOnly");
        final source = new CountingHyphenatorSource();
        final slot = new LazyHyphenator(source);
        TracedAssertions.assertEqualsInt(0, source.created);
        final first = slot.hyphenate("hyphenation");
        TracedAssertions.assertEqualsInt(1, source.created);
        TracedAssertions.assertEqualsIntArray(EnglishHyphenation.enUs().hyphenate("hyphenation"), first);
        slot.hyphenate("computer");
        TracedAssertions.assertEqualsInt(1, source.created);
    }

    public static function flushTestTrace():Void {
        TestTraceRecorder.flushClass("EnglishHyphenationTest");
    }
}

class EnglishHyphenationTestHelpers {
    public static function hyphenated(word:String):String {
        final offsets = EnglishHyphenation.enUs().hyphenate(word);
        final b = new StringBuf();
        var i = 0;
        while (i < word.length) {
            var j = 0;
            var found = false;
            while (j < offsets.length) {
                if (offsets[j] == i)
                    found = true;
                j++;
            }
            if (found)
                b.add("-");
            b.add(word.charAt(i));
            i++;
        }
        return b.toString();
    }

    public static function units(text:String):Array<Int> {
        final out = new Array<Int>();
        for (i in 0...text.length) {
            final unit:Null<Int> = text.charCodeAt(i);
            out.push(unit == null ? 0 : unit);
        }
        return out;
    }

    public static function sameInts(a:std.ReadOnlyArray<Int>, b:std.ReadOnlyArray<Int>):Bool {
        if (a.length != b.length)
            return false;
        for (i in 0...a.length) {
            if (a[i] != b[i])
                return false;
        }
        return true;
    }

    public static function withinMargins(values:std.ReadOnlyArray<Int>, left:Int, right:Int, length:Int):Bool {
        var i = 0;
        while (i < values.length) {
            if (values[i] < left || values[i] > length - right)
                return false;
            i++;
        }
        return true;
    }
}

/** Counts how many hyphenators the slot under test asks for. */
class CountingHyphenatorSource implements HyphenatorSource {
    public var created:Int;

    public function new() {
        created = 0;
    }

    public function createHyphenator():Hyphenator {
        created++;
        return EnglishHyphenation.enUs();
    }
}

/** The bundled TeX text, for the test that checks the compile-time packed table against it. */
@:build(DataTables.codeUnitsField("engine-haxe/data/hyph-en-us.tex", "TEX_UNITS"))
class EnglishHyphenationTexSource {
    public static function load():String {
        final output = new StringBuf();
        var index = 0;
        while (index < TEX_UNITS.length) {
            output.add(String.fromCharCode(TEX_UNITS[index]));
            index++;
        }
        return output.toString();
    }
}
