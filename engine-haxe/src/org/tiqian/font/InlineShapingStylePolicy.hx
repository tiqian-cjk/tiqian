package org.tiqian.font;

class InlineShapingStylePolicy {
    public static final unsupportedInlineShapingProperties:std.ReadOnlyArray<String> = [
        "font-feature-settings",
        "font-variation-settings",
        "font-stretch",
        "font-kerning",
        "font-optical-sizing",
        "font-variant-ligatures",
        "font-variant-alternates",
        "font-variant-east-asian",
        "font-variant-caps",
        "font-variant-numeric",
        "font-variant-position",
        "font-language-override",
        "font-size-adjust",
        "word-spacing",
        "text-transform",
        "text-rendering"
    ];

    public static function firstDivergentProperty(elementValues:std.ReadOnlyArray<String>, paragraphValues:std.ReadOnlyArray<String>):Null<String> {
        var n = elementValues.length < paragraphValues.length ? elementValues.length : paragraphValues.length;
        if (n > unsupportedInlineShapingProperties.length)
            n = unsupportedInlineShapingProperties.length;
        var i = 0;
        while (i < n) {
            if (elementValues[i] != paragraphValues[i])
                return unsupportedInlineShapingProperties[i];
            i++;
        }
        return null;
    }
}
