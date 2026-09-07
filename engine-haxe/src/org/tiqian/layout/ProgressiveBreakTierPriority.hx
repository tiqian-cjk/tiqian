package org.tiqian.layout;

import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;

/** Priority ordering for ProgressiveBreakTier; lower values win. */
class ProgressiveBreakTierPriority {
    public static function priority(tier:ProgressiveBreakTier):Int {
        return switch (tier) {
            case Whitespace: 0;
            case Structural: 1;
            case Syllable: 2;
            case WholeToken: 3;
            case Emergency: 4;
        }
    }

    /** Maps a stored priority value back to its tier. Any value outside 0-3 yields Emergency. */
    public static function fromPriority(value:Int):ProgressiveBreakTier {
        if (value == 0)
            return Whitespace;
        if (value == 1)
            return Structural;
        if (value == 2)
            return Syllable;
        if (value == 3)
            return WholeToken;
        return Emergency;
    }
}
