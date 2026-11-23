package org.tiqian.shared.prepared_dom;

/** Numeric OpenType overrides replayed together with contextual punctuation. */
class NumericFeatures {
    private static final TAGS:Array<String> = [
        "lnum", "onum", "pnum", "tnum", "frac", "afrc", "ordn", "zero"
    ];
    private static final VARIANTS:Array<String> = [
        "lining-nums", "oldstyle-nums", "proportional-nums", "tabular-nums",
        "diagonal-fractions", "stacked-fractions", "ordinal", "slashed-zero"
    ];
    private static final GROUPS:Array<Int> = [1, 1, 2, 2, 4, 4, 8, 16];

    /** Decode numeric prefixes while rejecting mutually exclusive variants. */
    public static function contract(features:Array<String>):Null<NumericFeatureContract> {
        var groups = 0;
        var count = 0;
        final variants:Array<String> = [];

        // Numeric prefixes end at the first contextual punctuation feature.
        for (tag in features) {
            final index = TAGS.indexOf(tag);
            if (index < 0) break;
            final group = GROUPS[index];
            if ((groups & group) != 0) return null;
            groups |= group;
            variants.push(VARIANTS[index]);
            count++;
        }

        // An explicit CSS normal reset retains its native shaping evidence.
        if (count == 0 && features.length > 0 && features[0] == "lnum=0") {
            variants.push("normal");
            count++;
        }
        final roleFeatures = features.slice(count);
        final role = roleFeatures.join(",");
        if (role != "" && role != "fwid" && role != "pwid,palt") return null;

        // Preserve punctuation-only signatures without adding a numeric override.
        return {
            fontVariantNumeric: variants.length > 0 ? variants.join(" ") : null,
            roleFeatures: roleFeatures
        };
    }

    /** Reproduce the CSS declarations used by native prepared DOM rendering. */
    public static function styles(features:Null<Array<String>>):Array<String> {
        if (features == null) return [];
        final parsed = contract(features);
        if (parsed == null || parsed.fontVariantNumeric == null) return [];
        final numeric:String = parsed.fontVariantNumeric;
        final role = parsed.roleFeatures.join(",");
        final eastAsian = role == "fwid" ? "full-width" : role != "" ? "proportional-width" : "normal";

        // Contextual punctuation settings coexist with the numeric override.
        final settings = role == "fwid" ? ', "fwid" 1' : role != "" ? ', "pwid" 1' : "";
        final proportional = role == "pwid,palt" ? "1" : "0";
        return [
            "font-variant-numeric:" + numeric + "!important",
            "font-variant-east-asian:" + eastAsian + "!important",
            'font-feature-settings:"halt" 0, "chws" 0, "palt" ' + proportional + settings + "!important"
        ];
    }
}
