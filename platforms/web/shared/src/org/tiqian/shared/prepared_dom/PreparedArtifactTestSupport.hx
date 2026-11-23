package org.tiqian.shared.prepared_dom;

/**
 * Typed plan and option builders for PreparedArtifactTest, generated from the
 * committed prepared-dom corpus fixture. Each wire plan is converted with the
 * same field mapping the browser glue performs (including the trim/filter fold
 * of render-text-span families and the JSON.stringify merge signatures), so the
 * expectations stay the corpus bytes rather than a second implementation.
 */
class PreparedArtifactTestSupport {

    public static function artifactJson(artifacts:Array<MarkupArtifact>):String {
        var out = "[";
        var i = 0;
        while (i < artifacts.length) {
            if (i > 0) out += ",";
            out += PreparedDomTestSupport.artifactToJson(artifacts[i]);
            i += 1;
        }
        return out + "]";
    }

    public static function planPlainMerge():PreparedPlan {
        return { height: 48,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "排", display: "排", drawX: 0, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 1, rangeEnd: 2, source: "版", display: "版", drawX: 16, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 2, rangeEnd: 3, source: "引", display: "引", drawX: 32, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 32, baseline: 24, indent: 0, visualWidth: 48, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 3 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsPlainMerge():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planTrailingLetterCarrier():PreparedPlan {
        return { height: 48,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 2, source: "排版", display: "排版", drawX: 0, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 32, baseline: 24, indent: 0, visualWidth: 16.4, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 2 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsTrailingLetterCarrier():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planSemanticsNested():PreparedPlan {
        return { height: 48,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "强", display: "强", drawX: 0, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 1, rangeEnd: 2, source: "大", display: "大", drawX: 16, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 2, rangeEnd: 3, source: "的", display: "的", drawX: 32, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 3, rangeEnd: 4, source: "排", display: "排", drawX: 48, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 4, rangeEnd: 5, source: "版", display: "版", drawX: 64, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 32, baseline: 24, indent: 0, visualWidth: 80, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 5 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsSemanticsNested():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [{ index: 0, start: 0, end: 5, tagName: "strong", sourceIndex: 0, attributes: [], signature: "{\"start\":0,\"end\":5,\"tagName\":\"strong\",\"attributes\":[]}" }, { index: 1, start: 1, end: 3, tagName: "em", sourceIndex: 0, attributes: [], signature: "{\"start\":1,\"end\":3,\"tagName\":\"em\",\"attributes\":[]}" }],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planSemanticAnchorAttributes():PreparedPlan {
        return { height: 48,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "入", display: "入", drawX: 0, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 1, rangeEnd: 2, source: "口", display: "口", drawX: 16, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 2, rangeEnd: 3, source: "在", display: "在", drawX: 32, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 32, baseline: 24, indent: 0, visualWidth: 48, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 3 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsSemanticAnchorAttributes():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [{ index: 0, start: 1, end: 2, tagName: "a", sourceIndex: 0, attributes: [{ name: "class", value: "x" }, { name: "href", value: "/entry" }, { name: "title", value: "入口" }], signature: "{\"start\":1,\"end\":2,\"tagName\":\"a\",\"attributes\":[[\"class\",\"x\"],[\"href\",\"/entry\"],[\"title\",\"入口\"]]}" }],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planRenderTextSpanProjection():PreparedPlan {
        return { height: 48,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "c", display: "c", drawX: 0, naturalWidth: 8, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 1, rangeEnd: 2, source: "o", display: "o", drawX: 8, naturalWidth: 8, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 2, rangeEnd: 3, source: "d", display: "d", drawX: 16, naturalWidth: 8, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 3, rangeEnd: 4, source: "e", display: "e", drawX: 24, naturalWidth: 8, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 4, rangeEnd: 5, source: "排", display: "排", drawX: 32, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 32, baseline: 24, indent: 0, visualWidth: 48, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 5 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsRenderTextSpanProjection():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [{ start: 0, end: 4, fontFamilies: ["Fira Code", "Mono"], signature: "[\"Fira Code\",\"Mono\"]" }],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planInlineBoxEdges():PreparedPlan {
        return { height: 48,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 2, source: "甲", display: "甲", drawX: 0, naturalWidth: 10, leadingLayoutAdvance: 3, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 2, rangeEnd: 4, source: "乙", display: "乙", drawX: 15, naturalWidth: 10, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 32, baseline: 24, indent: 0, visualWidth: 25, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 4 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsInlineBoxEdges():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [{ start: 0, end: 2, inlineStartPx: 3, inlineEndPx: 2 }],
            emphasisDotColor: null };
    }

    public static function planHyphenLocaleGap():PreparedPlan {
        return { height: 48,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 2, source: "示例", display: "示例", drawX: 0, naturalWidth: 32, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 32, baseline: 24, indent: 0, visualWidth: 36, hyphenAdvance: 8, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 2 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsHyphenLocaleGap():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planMandatoryBreak():PreparedPlan {
        return { height: 48,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "甲", display: "甲", drawX: 0, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 1, rangeEnd: 2, source: "乙", display: "乙", drawX: 16, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 32, baseline: 24, indent: 0, visualWidth: 32, hyphenAdvance: 0, endReason: "MandatoryBreak", rangeStart: 0, rangeEnd: 2 },
            { cells: [{ rangeStart: 2, rangeEnd: 3, source: "丙", display: "丙", drawX: 0, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 32, bottom: 64, baseline: 56, indent: 0, visualWidth: 16, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 2, rangeEnd: 3 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsMandatoryBreak():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planCrossingBoundary():PreparedPlan {
        return { height: 48,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "甲", display: "甲", drawX: 0, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 1, rangeEnd: 2, source: "乙", display: "乙", drawX: 16, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 32, baseline: 24, indent: 0, visualWidth: 32, hyphenAdvance: 0, endReason: "AutoWrap", rangeStart: 0, rangeEnd: 2 },
            { cells: [{ rangeStart: 2, rangeEnd: 3, source: "丙", display: "丙", drawX: 0, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 3, rangeEnd: 4, source: "丁", display: "丁", drawX: 16, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 32, bottom: 64, baseline: 56, indent: 0, visualWidth: 32, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 2, rangeEnd: 4 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsCrossingBoundary():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [{ index: 0, start: 0, end: 4, tagName: "em", sourceIndex: 0, attributes: [], signature: "{\"start\":0,\"end\":4,\"tagName\":\"em\",\"attributes\":[]}" }],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planInlineObjectPlaceholderKeepsFlow():PreparedPlan {
        return { height: 27,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "￼", display: "￼", drawX: 0, naturalWidth: 18, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: 18 },
                { rangeStart: 1, rangeEnd: 2, source: "字", display: "字", drawX: 18, naturalWidth: 18, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 27, baseline: 20, indent: 0, visualWidth: 36, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 2 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsInlineObjectPlaceholderKeepsFlow():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planPlanInlineEdgesPrecedence():PreparedPlan {
        return { height: 27,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "前", display: "前", drawX: 0, naturalWidth: 18, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 1, rangeEnd: 2, source: "后", display: "后", drawX: 22, naturalWidth: 18, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 27, baseline: 20, indent: 0, visualWidth: 40, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 2 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [{ offset: 1, inlineStart: null, inlineEnd: 4 }],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsPlanInlineEdgesPrecedence():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [{ start: 1, end: 1, inlineStartPx: 0, inlineEndPx: 10 }],
            emphasisDotColor: null };
    }

    public static function planRubyAnnotation():PreparedPlan {
        return { height: 27,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "京", display: "京", drawX: 0, naturalWidth: 18, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 27, baseline: 20, indent: 0, visualWidth: 18, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 1 }
        ],
        emphasisRanges: [],
        rubyDecisions: [{ fontSize: 10, ascent: Math.NaN, fontFamilies: ["Ruby Face"], text: "Běijīng", fontWeight: 500, centerX: 9, baselineY: 5, baseRangeEnd: 1 }],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsRubyAnnotation():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planBopomofoAnnotation():PreparedPlan {
        return { height: 27,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "只", display: "只", drawX: 0, naturalWidth: 18, leadingLayoutAdvance: 0, advance: 24, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 27, baseline: 20, indent: 0, visualWidth: 24, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 1 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [{ text: "ㄓˇ", fontWeight: 500, fontFamilies: ["Bopomofo Face"], placements: [{ text: "ㄓ", role: "Symbol", left: 0, top: 2, width: 6, height: 8 }, { text: "ˇ", role: "Tone", left: 6, top: 2, width: 4, height: 8 }], baseRangeEnd: 1 }],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsBopomofoAnnotation():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planInterlinearAndDotOverlays():PreparedPlan {
        return { height: 27,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "中", display: "中", drawX: 0, naturalWidth: 18, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 27, baseline: 20, indent: 0, visualWidth: 18, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 1 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: [{ left: 0, top: 20, right: 60, kind: ProperNoun }, { left: 60, top: 20, right: 120, kind: BookTitle }],
        emphasisDots: [{ clusterRangeStart: Math.NaN, anchorX: 10, anchorY: 25, dotDiameter: 5 }],
        fontSize: 20,
        overlayWidth: 120 };
    }

    public static function optionsInterlinearAndDotOverlays():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planEmphasisDotColor():PreparedPlan {
        return { height: 27,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "中", display: "中", drawX: 0, naturalWidth: 18, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 27, baseline: 20, indent: 0, visualWidth: 18, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 1 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: [{ clusterRangeStart: 0, anchorX: 10, anchorY: 25, dotDiameter: 5 }, { clusterRangeStart: 1, anchorX: 50, anchorY: 25, dotDiameter: 5 }],
        fontSize: 20,
        overlayWidth: 120 };
    }

    public static function optionsEmphasisDotColor():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: new FixedEmphasisDotColor() };
    }

    public static function planCjkEmphasisAttribute():PreparedPlan {
        return { height: 48,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "排", display: "排", drawX: 0, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 1, rangeEnd: 2, source: "版", display: "版", drawX: 16, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 32, baseline: 24, indent: 0, visualWidth: 32, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 2 }
        ],
        emphasisRanges: [{ start: 0, end: 2 }],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsCjkEmphasisAttribute():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [{ index: 0, start: 0, end: 2, tagName: "strong", sourceIndex: 0, attributes: [], signature: "{\"start\":0,\"end\":2,\"tagName\":\"strong\",\"attributes\":[]}" }],
            renderTextSpans: [],
            cjkStrongSemantics: [{ start: 0, end: 2, weight: 700 }],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planStyleDeltaThreeLines():PreparedPlan {
        return { height: 48,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "甲", display: "甲", drawX: 0, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 32, baseline: 24, indent: 0, visualWidth: 16, hyphenAdvance: 0, endReason: "AutoWrap", rangeStart: 0, rangeEnd: 1 },
            { cells: [{ rangeStart: 1, rangeEnd: 2, source: "乙", display: "乙", drawX: 0, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: { fontSize: 12, fontWeight: 700, italic: null }, styleSignature: "{\"fontSize\":12,\"fontWeight\":700}", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 32, bottom: 64, baseline: 56, indent: 0, visualWidth: 16, hyphenAdvance: 0, endReason: "AutoWrap", rangeStart: 1, rangeEnd: 2 },
            { cells: [{ rangeStart: 2, rangeEnd: 3, source: "丙", display: "丙", drawX: 0, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 64, bottom: 96, baseline: 88, indent: 0, visualWidth: 16, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 2, rangeEnd: 3 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsStyleDeltaThreeLines():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [{ index: 0, start: 0, end: 3, tagName: "em", sourceIndex: 0, attributes: [], signature: "{\"start\":0,\"end\":3,\"tagName\":\"em\",\"attributes\":[]}" }],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planInlineEdgesAndRenderTextSpan():PreparedPlan {
        return { height: 48,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "c", display: "c", drawX: 0, naturalWidth: 8, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 1, rangeEnd: 2, source: "o", display: "o", drawX: 8, naturalWidth: 8, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 2, rangeEnd: 3, source: "d", display: "d", drawX: 16, naturalWidth: 8, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 3, rangeEnd: 4, source: "e", display: "e", drawX: 24, naturalWidth: 8, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 4, rangeEnd: 5, source: "排", display: "排", drawX: 32, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 32, baseline: 24, indent: 0, visualWidth: 48, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 5 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [{ offset: 1, inlineStart: null, inlineEnd: 4 }],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsInlineEdgesAndRenderTextSpan():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [{ start: 0, end: 4, fontFamilies: ["Fira Code", "Mono"], signature: "[\"Fira Code\",\"Mono\"]" }],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planErrorLeadingLayoutAdvance():PreparedPlan {
        return { height: 48,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "甲", display: "甲", drawX: 0, naturalWidth: 16, leadingLayoutAdvance: 3, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null },
                { rangeStart: 1, rangeEnd: 2, source: "乙", display: "乙", drawX: 16, naturalWidth: 16, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 32, baseline: 24, indent: 0, visualWidth: 32, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 2 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsErrorLeadingLayoutAdvance():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [{ start: 0, end: 1, inlineStartPx: 5, inlineEndPx: 0 }],
            emphasisDotColor: null };
    }

    public static function planErrorConflictingRenderTextSpan():PreparedPlan {
        return { height: 48,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 2, source: "甲乙", display: "甲乙", drawX: 0, naturalWidth: 32, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 32, baseline: 24, indent: 0, visualWidth: 32, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 2 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsErrorConflictingRenderTextSpan():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [{ start: 0, end: 2, fontFamilies: ["A"], signature: "[\"A\"]" }, { start: 0, end: 2, fontFamilies: ["B"], signature: "[\"B\"]" }],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planErrorOpenTypeFeatures():PreparedPlan {
        return { height: 48,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "1", display: "1", drawX: 0, naturalWidth: 8, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: ["pwid"], style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 32, baseline: 24, indent: 0, visualWidth: 8, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 1 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: null,
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsErrorOpenTypeFeatures():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }

    public static function planErrorOverlayGeometry():PreparedPlan {
        return { height: 27,
        lines: [
            { cells: [{ rangeStart: 0, rangeEnd: 1, source: "中", display: "中", drawX: 0, naturalWidth: 18, leadingLayoutAdvance: 0, advance: null, shapingBoundary: false, openTypeFeatures: null, style: null, styleSignature: "null", punctuationSignature: "[null,null]", latin: false, dashStrategy: null, shapingLanguage: null, resolvedFace: null, glyphIds: null, shapingEvidence: null, punctuationInkFloor: null, punctuationBodyWidth: null, renderFontFamily: null, inlineObject: null }], top: 0, bottom: 27, baseline: 20, indent: 0, visualWidth: 18, hyphenAdvance: 0, endReason: "ParagraphEnd", rangeStart: 0, rangeEnd: 1 }
        ],
        emphasisRanges: [],
        rubyDecisions: [],
        bopomofoDecisions: [],
        inlineEdges: [],
        decorationSegments: [{ left: 0, top: 20, right: 60, kind: ProperNoun }],
        emphasisDots: null,
        fontSize: Math.NaN,
        overlayWidth: Math.NaN };
    }

    public static function optionsErrorOverlayGeometry():PreparedArtifactOptions {
        return { styleClassFor: null,
            liveSource: false,
            semantics: [],
            renderTextSpans: [],
            cjkStrongSemantics: [],
            inlineBoxes: [],
            emphasisDotColor: null };
    }
}
