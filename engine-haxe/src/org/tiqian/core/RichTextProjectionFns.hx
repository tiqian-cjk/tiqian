package org.tiqian.core;

import std.ReadOnlyArray;
import org.tiqian.core.RichTextRole.Background;
import org.tiqian.core.RichTextRole.Link;
import org.tiqian.core.RichTextRole.InlineCode;
import org.tiqian.core.RichTextRole.TechnicalInline;

/**
 * Kotlin extension receivers for the render-only rich-text projections.
 *
 * These lived in RichTextLayoutProjection.kt in the handwritten engine and
 * were dropped by the port; frontends (compose, android/view) still import
 * them. They project span fields only and make no layout decision.
 */
@:keep
class RichTextProjectionFns {
    /** Shared rich-text projection for named technical line-breaking policies. */
    @:extension
    public static function layoutLineBreakSpans(spans:ReadOnlyArray<RichTextSpan>, text:String):Array<LineBreakSpan> {
        final out = new Array<LineBreakSpan>();
        var spanIndex = 0;
        while (spanIndex < spans.length) {
            final span = spans[spanIndex];
            var matches = false;
            final role = span.role;
            if (Std.isOfType(role, Link)) {
                final link:Link = cast(role, Link);
                matches = LinkAddressDisplay.displaysAddress(text.substring(span.range.start, span.range.end), link.target);
            } else if (Std.isOfType(role, InlineCode) || Std.isOfType(role, TechnicalInline)) {
                matches = true;
            }
            if (matches) {
                var duplicate = false;
                var existingIndex = 0;
                while (existingIndex < out.length) {
                    final existing = out[existingIndex];
                    if (existing.range.start == span.range.start && existing.range.end == span.range.end) {
                        duplicate = true;
                        break;
                    }
                    existingIndex += 1;
                }
                if (!duplicate) {
                    out.push(new LineBreakSpan(span.range, LineBreakPolicy.ProgressiveTechnical));
                }
            }
            spanIndex += 1;
        }
        // Insertion sort by range.start, then range.end.
        var index = 1;
        while (index < out.length) {
            final value = out[index];
            var cursor = index - 1;
            while (cursor >= 0 && (out[cursor].range.start > value.range.start
                || (out[cursor].range.start == value.range.start && out[cursor].range.end > value.range.end))) {
                out[cursor + 1] = out[cursor];
                cursor -= 1;
            }
            out[cursor + 1] = value;
            index += 1;
        }
        return out;
    }

    /** Inline-code and technical ranges preserve source while suppressing internal auto spacing. */
    @:extension
    public static function layoutAutoSpaceSuppressedRanges(spans:ReadOnlyArray<RichTextSpan>):Array<TextRange> {
        final out = new Array<TextRange>();
        var spanIndex = 0;
        while (spanIndex < spans.length) {
            final span = spans[spanIndex];
            final role = span.role;
            if (Std.isOfType(role, InlineCode) || Std.isOfType(role, TechnicalInline)) {
                var duplicate = false;
                var existingIndex = 0;
                while (existingIndex < out.length) {
                    final existing = out[existingIndex];
                    if (existing.start == span.range.start && existing.end == span.range.end) {
                        duplicate = true;
                        break;
                    }
                    existingIndex += 1;
                }
                if (!duplicate) {
                    out.push(span.range);
                }
            }
            spanIndex += 1;
        }
        var index = 1;
        while (index < out.length) {
            final value = out[index];
            var cursor = index - 1;
            while (cursor >= 0 && (out[cursor].start > value.start
                || (out[cursor].start == value.start && out[cursor].end > value.end))) {
                out[cursor + 1] = out[cursor];
                cursor -= 1;
            }
            out[cursor + 1] = value;
            index += 1;
        }
        return out;
    }

    /** Reserves renderer-owned horizontal padding in the engine's line-breaking geometry. */
    @:extension
    public static function layoutInlineBoxes(spans:ReadOnlyArray<RichTextSpan>):Array<InlineBoxSpan> {
        final out = new Array<InlineBoxSpan>();
        var spanIndex = 0;
        while (spanIndex < spans.length) {
            final span = spans[spanIndex];
            final horizontalPadding = span.paint.background.horizontalPadding;
            final role = span.role;
            if (horizontalPadding != 0.0 && (Std.isOfType(role, Background) || Std.isOfType(role, InlineCode))) {
                out.push(new InlineBoxSpan(span.range, horizontalPadding, horizontalPadding));
            }
            spanIndex += 1;
        }
        return out;
    }
}

