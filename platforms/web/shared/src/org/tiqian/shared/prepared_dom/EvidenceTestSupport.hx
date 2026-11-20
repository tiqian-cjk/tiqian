package org.tiqian.shared.prepared_dom;

/**
 * Input builders and resolver stand-ins for EvidenceTest. The boring
 * ts-test-runner rejects non-test members on an @:test class, so the shared
 * constructions live here (same split as PreparedDomTestSupport).
 */
class EvidenceTestSupport {

    public static function bopomofoZone():BopomofoZone {
        return {
            text: "ㄅㄚ",
            fontWeight: 700,
            fontFamilies: ["Bopomofo Font"],
            placements: [
                { text: "ㄅ", role: "Symbol", left: 10, top: 20, width: 9, height: 9 },
                { text: "ˇ", role: "Tone", left: 12.5, top: 31.25, width: 9, height: 9 },
                { text: "ㄚ", role: "Neutral", left: 10, top: 42.5, width: 9, height: 9 }
            ]
        };
    }

    public static function overlayPlan():EvidenceOverlayPlan {
        return {
            decorationSegments: [
                { left: 1, top: 18.5, right: 40, kind: ProperNoun },
                { left: 50, top: 18.5, right: 120.25, kind: BookTitle }
            ],
            emphasisDots: [
                { clusterRangeStart: 3, anchorX: 12.5, anchorY: 21, dotDiameter: 3 },
                { clusterRangeStart: 7, anchorX: 30, anchorY: 21, dotDiameter: 2.5 }
            ],
            fontSize: 16,
            overlayWidth: 200,
            height: 20
        };
    }

    public static function plainDotPlan():EvidenceOverlayPlan {
        return {
            decorationSegments: null,
            emphasisDots: [{ clusterRangeStart: 1, anchorX: 4, anchorY: 9, dotDiameter: 3 }],
            fontSize: 16,
            overlayWidth: 100,
            height: 20
        };
    }

    public static function emptyPlan():EvidenceOverlayPlan {
        return { decorationSegments: null, emphasisDots: null, fontSize: 16, overlayWidth: 100, height: 20 };
    }

    public static function invalidGeometryPlan():EvidenceOverlayPlan {
        return {
            decorationSegments: [{ left: 0, top: 0, right: 1, kind: ProperNoun }],
            emphasisDots: null,
            fontSize: 16,
            overlayWidth: 100,
            height: Math.NaN
        };
    }
}
