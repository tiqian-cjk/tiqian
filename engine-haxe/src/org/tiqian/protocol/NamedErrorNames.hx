package org.tiqian.protocol;

/**
 * The single-source name accessors of the NamedError family. The published
 * issue name of a variant is the variant's own name (the two replaced lanes
 * publish the names as written: paragraph.rs:74-131,
 * ParagraphWireCodec.kt:279-297), so describe is the identity of the
 * variant names and the ordered list carries the declaration order.
 * Consumers read the name of a variant from these accessors; none of the
 * three lanes keeps its own copy of the strings.
 */
@:mainOnly
class NamedErrorNames {
    /** The variants in declaration order (NamedError.hx header rules the order). */
    public static function variants():Array<NamedError> {
        return [
            EmptyParagraph,
            InvalidMaximumMeasure,
            InvalidFontSize,
            InvalidLineHeight,
            InvalidFirstLineIndent,
            InvalidFontWeight,
            InvalidEmphasisDotGapEm,
            MissingExplicitFontFamilies,
            InvalidTextSpanRange,
            MissingTextSpanFontFamilies,
            InvalidTextSpanFontSize,
            InvalidTextSpanFontWeight,
            InvalidTextSpanBaselineShift,
            InvalidSourceBoundary,
            InvalidLineBreakSpanRange,
            InvalidInlineBoxRange,
            InvalidInlineBoxGeometry,
            InvalidInlineObjectRange,
            InvalidInlineObjectAdvance,
            InvalidInlineObjectVerticalGeometry,
            InvalidDecorationRange,
        ];
    }

    /** The published issue name of one variant. */
    public static function describe(error:NamedError):String {
        return switch (error) {
            case EmptyParagraph: "EmptyParagraph";
            case InvalidMaximumMeasure: "InvalidMaximumMeasure";
            case InvalidFontSize: "InvalidFontSize";
            case InvalidLineHeight: "InvalidLineHeight";
            case InvalidFirstLineIndent: "InvalidFirstLineIndent";
            case InvalidFontWeight: "InvalidFontWeight";
            case InvalidEmphasisDotGapEm: "InvalidEmphasisDotGapEm";
            case MissingExplicitFontFamilies: "MissingExplicitFontFamilies";
            case InvalidTextSpanRange: "InvalidTextSpanRange";
            case MissingTextSpanFontFamilies: "MissingTextSpanFontFamilies";
            case InvalidTextSpanFontSize: "InvalidTextSpanFontSize";
            case InvalidTextSpanFontWeight: "InvalidTextSpanFontWeight";
            case InvalidTextSpanBaselineShift: "InvalidTextSpanBaselineShift";
            case InvalidSourceBoundary: "InvalidSourceBoundary";
            case InvalidLineBreakSpanRange: "InvalidLineBreakSpanRange";
            case InvalidInlineBoxRange: "InvalidInlineBoxRange";
            case InvalidInlineBoxGeometry: "InvalidInlineBoxGeometry";
            case InvalidInlineObjectRange: "InvalidInlineObjectRange";
            case InvalidInlineObjectAdvance: "InvalidInlineObjectAdvance";
            case InvalidInlineObjectVerticalGeometry: "InvalidInlineObjectVerticalGeometry";
            case InvalidDecorationRange: "InvalidDecorationRange";
        };
    }
}
