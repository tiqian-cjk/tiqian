package org.tiqian.protocol;

import org.tiqian.test.trace.TracedAssertions;

/**
 * Byte-consistency test for PlanJson.encode against the hand-written wire
 * shape (Stage1-P3). The expected strings are the exact JSON the Kotlin
 * producer emitted (PreparedParagraph.kt) and the Rust reader parsed
 * (plan.rs); the values below keep every optional field absent so the
 * plain-paragraph path (renderEvidence=false) stays byte-identical.
 */
class PlanJsonTest {
    @:test
    public static function plainPlanEncodesToTheWireShape():Void {
        final plan:Plan = {
            width: 300.0,
            height: 20.0,
            lines: [
                {
                    rangeStart: 0,
                    rangeEnd: 2,
                    top: 0.0,
                    bottom: 20.0,
                    baseline: 18.0,
                    indent: 0.0,
                    visualWidth: 24.0,
                    hyphenAdvance: 0.0,
                    endReason: ParagraphEnd,
                    cells: [
                        {
                            rangeStart: 0,
                            rangeEnd: 1,
                            source: "你",
                            display: "你",
                            drawX: 0.0,
                            naturalWidth: 12.0,
                            leadingLayoutAdvance: 12.0,
                            shapingBoundary: false,
                            openTypeFeatures: [],
                            renderFontFamily: null,
                            dashStrategy: null,
                            shapingLanguage: null,
                            resolvedFace: null,
                            glyphIds: null,
                            shapingEvidence: null,
                            punctuationInkFloor: null,
                            punctuationBodyWidth: null,
                            latin: false,
                            advance: null,
                            inlineObject: null,
                            styleDelta: null,
                        },
                        {
                            rangeStart: 1,
                            rangeEnd: 2,
                            source: "好",
                            display: "好",
                            drawX: 12.0,
                            naturalWidth: 12.0,
                            leadingLayoutAdvance: 12.0,
                            shapingBoundary: false,
                            openTypeFeatures: [],
                            renderFontFamily: null,
                            dashStrategy: null,
                            shapingLanguage: null,
                            resolvedFace: null,
                            glyphIds: null,
                            shapingEvidence: null,
                            punctuationInkFloor: null,
                            punctuationBodyWidth: null,
                            latin: false,
                            advance: null,
                            inlineObject: null,
                            styleDelta: null,
                        },
                    ],
                },
            ],
            emphasisRanges: [],
            inlineEdges: [],
            rubyDecisions: [],
            bopomofoDecisions: [],
            fontSize: null,
            overlayWidth: null,
            decorationSegments: [],
            emphasisDots: [],
            spacingCarrierAdvances: [],
        };
        final json = PlanJson.encode(plan);
        final expected = "{\"schema\":1,\"layoutRevision\":\"tiqian-layout-v2\",\"width\":300,\"height\":20,\"lines\":[{\"rangeStart\":0,\"rangeEnd\":2,\"top\":0,\"bottom\":20,\"baseline\":18,\"indent\":0,\"visualWidth\":24,\"hyphenAdvance\":0,\"endReason\":\"ParagraphEnd\",\"cells\":[{\"rangeStart\":0,\"rangeEnd\":1,\"source\":\"你\",\"display\":\"你\",\"drawX\":0,\"naturalWidth\":12,\"leadingLayoutAdvance\":12},{\"rangeStart\":1,\"rangeEnd\":2,\"source\":\"好\",\"display\":\"好\",\"drawX\":12,\"naturalWidth\":12,\"leadingLayoutAdvance\":12}]}]}";
        TracedAssertions.assertEqualsString(expected, json, "plain plan wire JSON");
    }

    @:test
    public static function shapingBoundaryAndFeaturesEmitOnlyWhenSet():Void {
        final plan:Plan = {
            width: 100.0,
            height: 20.0,
            lines: [
                {
                    rangeStart: 0,
                    rangeEnd: 2,
                    top: 0.0,
                    bottom: 20.0,
                    baseline: 18.0,
                    indent: 0.0,
                    visualWidth: 12.0,
                    hyphenAdvance: 0.0,
                    endReason: AutoWrap,
                    cells: [
                        {
                            rangeStart: 0,
                            rangeEnd: 2,
                            source: "A",
                            display: "A",
                            drawX: 0.0,
                            naturalWidth: 12.0,
                            leadingLayoutAdvance: 12.0,
                            shapingBoundary: true,
                            openTypeFeatures: ["kern", "liga"],
                            renderFontFamily: null,
                            dashStrategy: null,
                            shapingLanguage: null,
                            resolvedFace: null,
                            glyphIds: null,
                            shapingEvidence: null,
                            punctuationInkFloor: null,
                            punctuationBodyWidth: null,
                            latin: false,
                            advance: null,
                            inlineObject: null,
                            styleDelta: null,
                        },
                    ],
                },
            ],
            emphasisRanges: [],
            inlineEdges: [],
            rubyDecisions: [],
            bopomofoDecisions: [],
            fontSize: null,
            overlayWidth: null,
            decorationSegments: [],
            emphasisDots: [],
            spacingCarrierAdvances: [{rangeStart: 0, rangeEnd: 2, advance: 3.75}],
        };
        final json = PlanJson.encode(plan);
        TracedAssertions.assertTrue(json.indexOf("\"shapingBoundary\":true") >= 0, json);
        TracedAssertions.assertTrue(json.indexOf("\"openTypeFeatures\":[\"kern\",\"liga\"]") >= 0, json);
        TracedAssertions.assertTrue(json.indexOf("\"spacingCarrierAdvances\":[{\"rangeStart\":0,\"rangeEnd\":2,\"advance\":3.75}]") >= 0, json);
    }
}