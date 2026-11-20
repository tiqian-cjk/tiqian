package org.tiqian.shared.prepared_dom;

import org.tiqian.test.trace.TracedAssertions;

/**
 * Pins Markup string primitives to the exact TS oracle outputs, so the
 * generated test lane proves byte-for-byte equivalence with
 * prepared-dom-markup.ts before the corpus gate runs.
 */
class MarkupTest {

    @:test
    public static function escapeTextMatchesTs():Void {
        TracedAssertions.assertEqualsString("a&amp;b&lt;c&gt;d", Markup.escapeText("a&b<c>d"), "escapeText mixed");
        TracedAssertions.assertEqualsString("&amp;&lt;&gt;", Markup.escapeText("&<>"), "escapeText all");
        TracedAssertions.assertEqualsString("plain", Markup.escapeText("plain"), "escapeText plain");
        TracedAssertions.assertEqualsString("", Markup.escapeText(""), "escapeText empty");
        TracedAssertions.assertEqualsString("&amp;&amp;&lt;&lt;&gt;&gt;", Markup.escapeText("&&<<>>"), "escapeText repeated");
        TracedAssertions.assertEqualsString("a" + String.fromCharCode(233) + "&amp;z", Markup.escapeText("a" + String.fromCharCode(233) + "&z"), "escapeText non-ascii");
    }

    @:test
    public static function escapeAttributeMatchesTs():Void {
        TracedAssertions.assertEqualsString("a&quot;b&amp;c&lt;d&gt;e", Markup.escapeAttribute("a\"b&c<d>e"), "escapeAttribute mixed");
        TracedAssertions.assertEqualsString("&quot;&amp;&lt;&gt;", Markup.escapeAttribute("\"&<>"), "escapeAttribute all");
        TracedAssertions.assertEqualsString("plain", Markup.escapeAttribute("plain"), "escapeAttribute plain");
    }

    @:test
    public static function cssStringMatchesTs():Void {
        TracedAssertions.assertEqualsString("\"a\\\"b\\\\c\"", Markup.cssString("a\"b\\c"), "cssString mixed");
        TracedAssertions.assertEqualsString("\"plain\"", Markup.cssString("plain"), "cssString plain");
        TracedAssertions.assertEqualsString("\"\"", Markup.cssString(""), "cssString empty");
        TracedAssertions.assertEqualsString("\"x\\\"y\"", Markup.cssString("x\"y"), "cssString quote");
    }

    @:test
    public static function pxMatchesTs():Void {
        TracedAssertions.assertEqualsString("0px", Markup.px(0), "px zero");
        TracedAssertions.assertEqualsString("0.5px", Markup.px(0.5), "px half");
        TracedAssertions.assertEqualsString("1.5px", Markup.px(1.5), "px one-half");
        TracedAssertions.assertEqualsString("-1.5px", Markup.px(-1.5), "px neg");
        TracedAssertions.assertEqualsString("12.34px", Markup.px(12.34), "px two-dec");
        TracedAssertions.assertEqualsString("12.34567px", Markup.px(12.34567), "px five-dec");
        TracedAssertions.assertEqualsString("12.34568px", Markup.px(12.345678), "px round-up");
        TracedAssertions.assertEqualsString("-12.34568px", Markup.px(-12.345678), "px neg-round-up");
        TracedAssertions.assertEqualsString("0px", Markup.px(0.0000005), "px under-epsilon");
        TracedAssertions.assertEqualsString("0px", Markup.px(0.000001), "px at-epsilon");
        TracedAssertions.assertEqualsString("0px", Markup.px(0.0000011), "px just-over-epsilon");
        TracedAssertions.assertEqualsString("100000px", Markup.px(100000), "px integer");
        TracedAssertions.assertEqualsString("3.14159px", Markup.px(3.14159265), "px pi");
        TracedAssertions.assertEqualsString("0.00001px", Markup.px(0.00001), "px small-five-dec");
        TracedAssertions.assertEqualsString("2.675px", Markup.px(2.675), "px repr");
        TracedAssertions.assertEqualsString("1.005px", Markup.px(1.005), "px repr-2");
        TracedAssertions.assertEqualsString("10.55556px", Markup.px(10.555555), "px half-up");
        TracedAssertions.assertEqualsString("12345.67891px", Markup.px(12345.67891), "px large");
        TracedAssertions.assertEqualsString("0.3px", Markup.px(0.30000000000000004), "px fp-sum");
        TracedAssertions.assertEqualsString("1.00001px", Markup.px(1.000005), "px boundary-up");
        TracedAssertions.assertEqualsString("1px", Markup.px(1.0000049), "px boundary-down");
        TracedAssertions.assertEqualsString("0.12346px", Markup.px(0.123456), "px sub-one-round");
        TracedAssertions.assertEqualsString("10px", Markup.px(9.999995), "px carry");
        TracedAssertions.assertEqualsString("1px", Markup.px(0.999999), "px carry-sub-one");
        TracedAssertions.assertEqualsString("42px", Markup.px(42), "px answer");
    }

    @:test
    public static function applyDynamicStylesMatchesTs():Void {
        // Empty styles -> no-op, no entry appended.
        final a1:Array<AttributeEntry> = [];
        Markup.applyDynamicStyles(a1, [], null);
        TracedAssertions.assertEqualsInt(0, a1.length, "empty styles no-op");

        // No resolver -> single style entry carrying the joined declaration.
        final a2:Array<AttributeEntry> = [];
        Markup.applyDynamicStyles(a2, ["color:red", "top:1px"], null);
        TracedAssertions.assertEqualsInt(1, a2.length, "style entry count");
        TracedAssertions.assertEqualsString("style", a2[0].name, "style entry name");
        TracedAssertions.assertEqualsString("color:red;top:1px", a2[0].value, "style entry value");

        // Single style -> declaration with no separator.
        final a6:Array<AttributeEntry> = [];
        Markup.applyDynamicStyles(a6, ["color:red"], null);
        TracedAssertions.assertEqualsString("color:red", a6[0].value, "single style declaration");

        // Resolver, no existing class -> append class entry.
        final a3:Array<AttributeEntry> = [];
        Markup.applyDynamicStyles(a3, ["a:b"], new PrefixedStyleClassResolver("gen-"));
        TracedAssertions.assertEqualsInt(1, a3.length, "class entry count");
        TracedAssertions.assertEqualsString("class", a3[0].name, "class entry name");
        TracedAssertions.assertEqualsString("gen-a:b", a3[0].value, "class entry value");

        // Resolver + existing non-empty class -> merge with space separator.
        final a4:Array<AttributeEntry> = [{ name: "class", value: "base" }];
        Markup.applyDynamicStyles(a4, ["x:y"], new FixedStyleClassResolver("gen"));
        TracedAssertions.assertEqualsInt(1, a4.length, "merge class count");
        TracedAssertions.assertEqualsString("class", a4[0].name, "merge class name");
        TracedAssertions.assertEqualsString("base gen", a4[0].value, "merge class value");

        // Resolver + existing empty class -> overwrite (empty is falsy in TS).
        final a5:Array<AttributeEntry> = [{ name: "class", value: "" }];
        Markup.applyDynamicStyles(a5, ["x:y"], new FixedStyleClassResolver("gen"));
        TracedAssertions.assertEqualsInt(1, a5.length, "overwrite class count");
        TracedAssertions.assertEqualsString("class", a5[0].name, "overwrite class name");
        TracedAssertions.assertEqualsString("gen", a5[0].value, "overwrite class value");
    }
}
