package org.tiqian.core;

/**
 * End-anchored dash and dot fitting for line patterns. The handwritten engine
 * published these two functions from org.tiqian.core; the port had dropped
 * them, so they are restored here with the same geometry.
 */
class FittedLinePatternGeometry {
    /**
     * End-anchored dash fitting for a dotted line. The first and last dots meet
     * the span edges, while any remainder is shared by all intervening gaps.
     * keptLeft and keptRight only apply skip-ink clipping; they do not restart
     * the pattern.
     */
    @:topLevel
    public static function fittedDottedLineCenters(spanLeft:Float, spanRight:Float, keptLeft:Float, keptRight:Float, dotDiameter:Float,
            gapLength:Float):Array<Float> {
        if (!Math.isFinite(spanLeft) || !Math.isFinite(spanRight) || !Math.isFinite(keptLeft) || !Math.isFinite(keptRight))
            throw new TiqianIllegalArgumentException(Message("Failed requirement."));
        if (!Math.isFinite(dotDiameter) || dotDiameter <= 0.0)
            throw new TiqianIllegalArgumentException(Message("Failed requirement."));
        if (!Math.isFinite(gapLength) || gapLength < 0.0)
            throw new TiqianIllegalArgumentException(Message("Failed requirement."));
        if (spanRight <= spanLeft || keptRight <= keptLeft)
            return [];

        final dottedCenterEpsilon:Float = 0.001;
        final radius:Float = dotDiameter / 2.0;
        final spanWidth:Float = spanRight - spanLeft;
        final targetPitch:Float = dotDiameter + gapLength;
        var fittedCount:Int = Math.round((spanWidth + gapLength) / targetPitch);
        if (fittedCount < 1)
            fittedCount = 1;
        var nonOverlappingCount:Int = Std.int(Math.floor(spanWidth / dotDiameter));
        if (nonOverlappingCount < 1)
            nonOverlappingCount = 1;
        final count:Int = fittedCount < nonOverlappingCount ? fittedCount : nonOverlappingCount;

        if (count == 1) {
            final center:Float = (spanLeft + spanRight) / 2.0;
            final completeDotFits:Bool = center - radius >= keptLeft - dottedCenterEpsilon
                && center + radius <= keptRight + dottedCenterEpsilon;
            final shortSpanIsFullyKept:Bool = spanWidth < dotDiameter && keptLeft <= spanLeft + dottedCenterEpsilon
                && keptRight >= spanRight - dottedCenterEpsilon;
            return completeDotFits || shortSpanIsFullyKept ? [center] : [];
        }

        final firstCenter:Float = spanLeft + radius;
        final fittedPitch:Float = (spanWidth - dotDiameter) / (count - 1);
        final centers:Array<Float> = [];
        var index:Int = 0;
        while (index < count) {
            final center:Float = firstCenter + index * fittedPitch;
            if (center - radius >= keptLeft - dottedCenterEpsilon && center + radius <= keptRight + dottedCenterEpsilon)
                centers.push(center);
            index += 1;
        }
        return centers;
    }

    /**
     * End-anchored dash fitting expressed as flat visible [left, right] pairs.
     * Dash length stays fixed whenever at least two dashes fit. The remainder is
     * shared by the intervening gaps, so the first and last dashes meet the span
     * edges. A shorter span becomes one dash instead of disappearing or leaving
     * an unmatched end gap.
     */
    @:topLevel
    public static function fittedDashedLineSegments(spanLeft:Float, spanRight:Float, dashLength:Float, gapLength:Float):Array<Float> {
        if (!Math.isFinite(spanLeft) || !Math.isFinite(spanRight))
            throw new TiqianIllegalArgumentException(Message("Failed requirement."));
        if (!Math.isFinite(dashLength) || dashLength <= 0.0)
            throw new TiqianIllegalArgumentException(Message("Failed requirement."));
        if (!Math.isFinite(gapLength) || gapLength < 0.0)
            throw new TiqianIllegalArgumentException(Message("Failed requirement."));
        if (spanRight <= spanLeft)
            return [];

        final spanWidth:Float = spanRight - spanLeft;
        if (spanWidth < dashLength * 2.0)
            return [spanLeft, spanRight];

        var fittedCount:Int = Math.round((spanWidth + gapLength) / (dashLength + gapLength));
        if (fittedCount < 2)
            fittedCount = 2;
        var nonOverlappingCount:Int = Std.int(Math.floor(spanWidth / dashLength));
        if (nonOverlappingCount < 2)
            nonOverlappingCount = 2;
        final count:Int = fittedCount < nonOverlappingCount ? fittedCount : nonOverlappingCount;
        final fittedGap:Float = (spanWidth - count * dashLength) / (count - 1);

        final segments:Array<Float> = [];
        var coordinateIndex:Int = 0;
        while (coordinateIndex < count * 2) {
            final dashIndex:Int = Std.int(coordinateIndex / 2);
            final dashLeft:Float = spanLeft + dashIndex * (dashLength + fittedGap);
            segments.push(coordinateIndex % 2 == 0 ? dashLeft : dashLeft + dashLength);
            coordinateIndex += 1;
        }
        return segments;
    }
}