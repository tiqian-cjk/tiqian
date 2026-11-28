package org.tiqian.protocol;

import org.tiqian.test.trace.TracedAssertions;

/**
 * Round-trip test for PlanPacked (Stage1-P3).  Encodes a Plan into packed
 * bytes and decodes back; the decoded Plan must carry the same structure
 * (lines, cells, evidence) as the original.  The comparison is structural
 * rather than byte-level because the packed format reorders strings through
 * the pool.
 */
class PlanPackedTest {
    @:test
    public static function roundTripPreservesPlanStructure():Void {
        final inlineEdges:Array<Plan.PlanInlineEdge> = [{
            offset: 10, inlineStart: 4.0, inlineEnd: null,
        }];
        final plan:Plan = {
            width: 300.0, height: 20.0,
            lines: [
                {
                    rangeStart: 0, rangeEnd: 2,
                    top: 0.0, bottom: 20.0, baseline: 18.0, indent: 0.0,
                    visualWidth: 24.0, hyphenAdvance: 0.0, endReason: ParagraphEnd,
                    cells: [
                        {
                            rangeStart: 0, rangeEnd: 1,
                            source: "你", display: "你",
                            drawX: 0.0, naturalWidth: 12.0, leadingLayoutAdvance: 12.0,
                            shapingBoundary: false, openTypeFeatures: [],
                            renderFontFamily: null, dashStrategy: null,
                            shapingLanguage: null, resolvedFace: null,
                            glyphIds: null, shapingEvidence: null,
                            punctuationInkFloor: null, punctuationBodyWidth: null,
                            latin: false, advance: null, inlineObject: null,
                            styleDelta: null,
                        },
                    ],
                },
            ],
            emphasisRanges: [{start: 0, end: 1}],
            inlineEdges: inlineEdges,
            rubyDecisions: [],
            bopomofoDecisions: [],
            fontSize: null, overlayWidth: null,
            decorationSegments: [],
            emphasisDots: [],
            spacingCarrierAdvances: [{rangeStart: 0, rangeEnd: 2, advance: 3.75}],
        };
        final bytes = PlanPacked.encode(plan);
        final decoded = PlanPacked.decode(bytes);
        // decoded != null is a structural assertion via cell count below
        TracedAssertions.assertEquals(plan.lines.length, decoded.lines.length, "line count");
        TracedAssertions.assertEquals(plan.lines[0].cells.length, decoded.lines[0].cells.length, "cell count");
        TracedAssertions.assertEqualsString(plan.lines[0].cells[0].source, decoded.lines[0].cells[0].source, "cell source");
        TracedAssertions.assertEqualsString(plan.lines[0].cells[0].display, decoded.lines[0].cells[0].display, "cell display");
        TracedAssertions.assertEquals(1, decoded.spacingCarrierAdvances.length, "carrier advance count");
        TracedAssertions.assertEquals(2, decoded.spacingCarrierAdvances[0].rangeEnd, "carrier advance range end");
        TracedAssertions.assertTrue(decoded.spacingCarrierAdvances[0].advance == 3.75, "carrier advance value");
        TracedAssertions.assertEquals(plan.emphasisRanges.length, decoded.emphasisRanges.length, "emphasis count");
        TracedAssertions.assertEquals(plan.inlineEdges.length, decoded.inlineEdges.length, "inline edge count");
        if (decoded.inlineEdges.length > 0) {
            TracedAssertions.assertEquals(plan.inlineEdges[0].offset, decoded.inlineEdges[0].offset, "inline offset");
        }
    }
}