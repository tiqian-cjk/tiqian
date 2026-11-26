package org.tiqian.shared.layout;

import org.tiqian.protocol.ParagraphRequest;
import org.tiqian.protocol.ParagraphRequestChecks;
import org.tiqian.protocol.TextSpanInput;
import org.tiqian.protocol.LineBreakSpanInput;
import org.tiqian.protocol.InlineBoxInput;
import org.tiqian.protocol.InlineObjectInput;
import org.tiqian.protocol.DecorationInput;

/**
    Request normalization shared by the web client and its workers: fills the
    defaults the protocol model requires (session id, emphasis gap, inline box
    spacing) and validates the result with the protocol checks.
**/
class PreparedParagraphRequest {
    public static function normalize(request:ParagraphRequest):ParagraphRequest {
        final textSpans:Array<TextSpanInput> = [];
        for (span in request.textSpans) {
            textSpans.push({
                start: span.start,
                end: span.end,
                families: span.families,
                fontSizePx: span.fontSizePx,
                fontWeight: span.fontWeight,
                italic: span.italic,
                baselineShift: span.baselineShift
            });
        }
        final lineBreakSpans:Array<LineBreakSpanInput> = [];
        for (span in request.lineBreakSpans) {
            lineBreakSpans.push({start: span.start, end: span.end, policy: span.policy});
        }
        final inlineBoxes:Array<InlineBoxInput> = [];
        for (box in request.inlineBoxes) {
            inlineBoxes.push({
                start: box.start,
                end: box.end,
                inlineStart: box.inlineStart,
                inlineEnd: box.inlineEnd,
                outerSpacing: box.outerSpacing == null ? "Narrow" : box.outerSpacing
            });
        }
        final inlineObjects:Array<InlineObjectInput> = [];
        for (object in request.inlineObjects) {
            inlineObjects.push({
                start: object.start,
                end: object.end,
                advance: object.advance,
                ascent: object.ascent,
                descent: object.descent
            });
        }
        final decorations:Array<DecorationInput> = [];
        for (decoration in request.decorations) {
            decorations.push({start: decoration.start, end: decoration.end, kind: decoration.kind});
        }
        return {
            fontSessionId: "",
            text: request.text,
            maxWidthPx: request.maxWidthPx,
            fontFamilies: request.fontFamilies,
            fontSizePx: request.fontSizePx,
            lineHeightPx: request.lineHeightPx,
            locale: request.locale,
            fontWeight: request.fontWeight,
            italic: request.italic,
            firstLineIndentIc: request.firstLineIndentIc,
            lineLengthGridEnabled: request.lineLengthGridEnabled,
            emphasisDotGapEm: request.emphasisDotGapEm == null ? null : request.emphasisDotGapEm,
            sourceBoundaries: request.sourceBoundaries,
            textSpans: textSpans,
            lineBreakSpans: lineBreakSpans,
            inlineBoxes: inlineBoxes,
            inlineObjects: inlineObjects,
            decorations: decorations
        };
    }

    /** Validates the normalized request; the protocol check throws its named error. **/
    public static function validate(request:ParagraphRequest):Void {
        ParagraphRequestChecks.validate(request);
    }
}
