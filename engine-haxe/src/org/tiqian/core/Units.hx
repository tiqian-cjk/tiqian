package org.tiqian.core;

/** Unit value used for a count of CJK 字身框 cells. */
// The `ic` unit counts CJK 字身框 cells declared by the font under ADR 0034.
// CSS Values L4 defines `ic` as the advance of an ideographic 字身框, measured by probing U+6C34.
// The glyph defines the value; the engine uses the font-declared 字身框 from BASE `ideo/idtp`, so the unit source is fixed.
// `ic` is a count; resolving it to px uses the contextual 字身框.
// A paragraph anchor uses the paragraph base font size, and an inline anchor uses the gap owner's font size, as required by ADR 0030.
// Horizontal full-width CJK uses one 字身框 as 1em, so the 字身框 width equals the 字号.
// For an `Ic(n)` value, `toPx(fontSize)` multiplies n by 字号; the numeric value matches the former em convention while the type gives it a unit.
// The `fontSize` value itself does not use `ic`; it defines a 字身框.
// The px result uses [emPx], the 字身框 spacing for the current context; horizontal full-width CJK uses the 字号.
// Author-facing literals are `2f.ic` and `0.25f.ic`.
// Author-facing literals are `40.ic` and `2.ic`.

/** Haxe spelling of the Kotlin Float.ic extension. */
class FloatIc {
    public static function ic(value:Float):Ic {
        return new Ic(value);
    }
}

/** Haxe spelling of the Kotlin Int.ic extension. */
class IntIc {
    public static function ic(value:Int):Ic {
        return new Ic(value);
    }
}
