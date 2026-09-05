package org.tiqian.clreq;

/**
 * Member logic of the Kotlin KinsokuMode sealed interface: resolving a mode
 * against a measure and rendering the data-class toString of each variant.
 * The Kotlin lowering renders enum switches as when-expressions, so every
 * arm is a value; the multi-step MeasureAdaptive arms live in helpers.
 */
class KinsokuModes {
    public static function resolve(mode:KinsokuMode, measureEm:Float):ResolvedKinsoku {
        return switch (mode) {
            case KinsokuMode.Fixed(level, hanging):
                resolveFixed(level, hanging);
            case KinsokuMode.MeasureAdaptive(hangBelowEm, gbAboveEm, strictAboveEm):
                resolveMeasureAdaptive(measureEm, hangBelowEm, gbAboveEm, strictAboveEm);
        };
    }

    public static function render(mode:KinsokuMode):String {
        return switch (mode) {
            case KinsokuMode.Fixed(level, hanging):
                "Fixed(level=" + level + ", hanging=" + hanging + ")";
            case KinsokuMode.MeasureAdaptive(hangBelowEm, gbAboveEm, strictAboveEm):
                "MeasureAdaptive(hangBelowEm="
                + hangBelowEm
                + ", gbAboveEm="
                + gbAboveEm
                + ", strictAboveEm="
                + strictAboveEm
                + ")";
        };
    }

    public static function sameMode(a:KinsokuMode, b:KinsokuMode):Bool {
        return switch (a) {
            case KinsokuMode.Fixed(level, hanging):
                sameFixed(level, hanging, b);
            case KinsokuMode.MeasureAdaptive(hangBelowEm, gbAboveEm, strictAboveEm):
                sameMeasureAdaptive(hangBelowEm, gbAboveEm, strictAboveEm, b);
        };
    }

    private static function resolveFixed(level:KinsokuLevel, hanging:HangingPunctuationStyle):ResolvedKinsoku {
        return new ResolvedKinsoku(level, hanging, "Fixed:" + level + (hanging != HangingPunctuationStyle.Disabled ? "+Hang" : ""));
    }

    private static function resolveMeasureAdaptive(measureEm:Float, hangBelowEm:Float, gbAboveEm:Float, strictAboveEm:Float):ResolvedKinsoku {
        final level:KinsokuLevel = measureEm > strictAboveEm ? KinsokuLevel.Strict : (measureEm > gbAboveEm ? KinsokuLevel.GbStyle : KinsokuLevel.Basic);
        final hanging:HangingPunctuationStyle = measureEm < hangBelowEm ? HangingPunctuationStyle.PauseStops : HangingPunctuationStyle.Disabled;
        final tag = "MeasureAdaptiveKinsoku:"
            + Std.int(measureEm)
            + "字→"
            + level
            + (hanging != HangingPunctuationStyle.Disabled ? "+Hang" : "");
        return new ResolvedKinsoku(level, hanging, tag);
    }

    private static function sameFixed(level:KinsokuLevel, hanging:HangingPunctuationStyle, b:KinsokuMode):Bool {
        return switch (b) {
            case KinsokuMode.Fixed(otherLevel, otherHanging): level == otherLevel && hanging == otherHanging;
            case KinsokuMode.MeasureAdaptive(_, _, _):
                false;
        };
    }

    private static function sameMeasureAdaptive(hangBelowEm:Float, gbAboveEm:Float, strictAboveEm:Float, b:KinsokuMode):Bool {
        return switch (b) {
            case KinsokuMode.MeasureAdaptive(otherHangBelow, otherGbAbove, otherStrictAbove): hangBelowEm == otherHangBelow && gbAboveEm == otherGbAbove && strictAboveEm == otherStrictAbove;
            case KinsokuMode.Fixed(_, _):
                false;
        };
    }
}
