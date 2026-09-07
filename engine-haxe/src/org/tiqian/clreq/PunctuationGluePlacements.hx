package org.tiqian.clreq;

/**
 * Companion logic of the Kotlin PunctuationGluePlacement enum: the
 * region-to-placement mapping and the per-class glue side. The Mainland
 * branch lists every PunctuationClass variant where Kotlin grouped the
 * symmetric classes under a final else arm. The Kotlin lowering renders
 * enum switches as when-expressions, so every arm is a value.
 */
class PunctuationGluePlacements {
    public static function forRegion(region:ClreqRegion):PunctuationGluePlacement {
        return switch (region) {
            case ClreqRegion.Mainland:
                PunctuationGluePlacement.MainlandSimplified;
            case ClreqRegion.Taiwan:
                PunctuationGluePlacement.Traditional;
            case ClreqRegion.HongKong:
                PunctuationGluePlacement.Traditional;
            case ClreqRegion.Custom:
                PunctuationGluePlacement.MainlandSimplified;
        };
    }

    public static function glueSideFor(placement:PunctuationGluePlacement, punctuationClass:PunctuationClass):GlueSide {
        return switch (placement) {
            case PunctuationGluePlacement.MainlandSimplified:
                mainlandGlueSide(punctuationClass);
            case PunctuationGluePlacement.Traditional:
                GlueSide.BothSides;
        };
    }

    private static function mainlandGlueSide(punctuationClass:PunctuationClass):GlueSide {
        return switch (punctuationClass) {
            case PunctuationClass.Opening:
                GlueSide.LeadingOnly;
            case PunctuationClass.Closing:
                GlueSide.TrailingOnly;
            case PunctuationClass.PauseOrStop:
                GlueSide.TrailingOnly;
            case PunctuationClass.MiddleDot:
                GlueSide.BothSides;
            case PunctuationClass.Interpunct:
                GlueSide.BothSides;
            case PunctuationClass.Connector:
                GlueSide.BothSides;
            case PunctuationClass.Solidus:
                GlueSide.BothSides;
            case PunctuationClass.Ellipsis:
                GlueSide.BothSides;
            case PunctuationClass.Dash:
                GlueSide.BothSides;
            case PunctuationClass.Other:
                GlueSide.BothSides;
        };
    }
}
