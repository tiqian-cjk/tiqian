package org.tiqian.core;

import std.ReadOnlyArray;

// 行间注 (ruby, ADR 0032): small-size annotation [text] over a base SOURCE
// [baseRange] — 拼音 above the base (this slice). Unlike [DecorationSpan], ruby
// [text] is NOT part of the source (拼音 不进源；复制/搜索保真) — it lives only here.
// The 注文 font-family list is independent of the body font. 注音 needs a font with ㄅㄆㄇ glyphs, while 拼音 and glosses may use other families.
// The 注文 font is independent from the body font under ADR 0032, and an empty list uses the renderer default.
// Ruby modes are 拼音 above the base or 注音 on the right in vertical writing.
// The 注文 has its own BCP-47 language; 注音 defaults to `zh-TW`, while 拼音 inherits the body locale when the value is null.
// Callers do not need to repeat the language for 注音, and this does not change the locale or profile of 简体 横排 body text.
// 罗马拼音 places the 注文 above the base glyph and centers it horizontally under ADR 0032.
// 注音 places ㄅㄆㄇ on the right side under ADR 0033 and uses vertical and horizontal alignment.
// (着重号、示亡号 etc.) present, line spacing must not drop below 1/2 of the
// (CLREQ's 双面装 5/8 floor is print-only — show-through has no screen analogue —
// 行间注 geometry (ruby, ADR 0032): annotation [text] placed over the base
// centre (the注文 centres on it, CLREQ「横排注音注文整体水平向基字居中」);
// ruby size (≤ base). [width] is the measured 注文 width in its own font.
// [overhang] > 0 means the 注文 is wider than the base content and overhangs
// 注音 geometry (ADR 0033): the ㄅㄆㄇ symbols + 调号 placed in the right-side zone
// (absolute px) + role. Symbols use the 9×9 slot size; ordinary tone marks use the
// 5×5 slot size without glyph-ink-dependent rescaling.
// 注文 font (must carry ㄅㄆㄇ glyphs); empty = renderer's CJK default.
// ㄅㄆㄇ — fill the 9×9 box at the box font size (字身框).
// 平上去/入声调号 — share the 注音字号; the 5×5 slot positions ink but never changes size.
// 轻声 ˙ — its vert-alt is FULL-WIDTH (verified). Draw at the box-WIDTH font
@:dataClass
class RubySpan {
    public final baseRange:TextRange;
    public final text:String;
    public final fontFamilies:ReadOnlyArray<String>;
    public final kind:RubyKind;
    public final locale:Null<String>;

    public function new(baseRange:TextRange, text:String, ?fontFamilies:Array<String>, kind:RubyKind = RubyKind.Pinyin, ?locale:Null<String>) {
        this.baseRange = baseRange;
        this.text = text;
        this.fontFamilies = fontFamilies == null ? [] : fontFamilies;
        this.kind = kind;
        this.locale = locale == null ? (kind == RubyKind.Bopomofo ? "zh-TW" : null) : locale;
    }
}
