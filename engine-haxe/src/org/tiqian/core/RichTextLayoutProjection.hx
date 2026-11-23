package org.tiqian.core;

import std.ReadOnlyArray;
import std.SortedSet;
using org.tiqian.core.LayoutQueryFns;
using org.tiqian.core.LayoutQueryFns.LayoutQueryRangeFns;
using org.tiqian.core.LayoutPaintBounds.LayoutPaintBoundsFns;
using org.tiqian.core.LayoutResultReplayIndex.LayoutResultReplayIndexFns;
using org.tiqian.core.RichTextProjectionFns;

/**
 * Projects render-only range edges into source cluster boundaries required by
 * geometry queries. Frontends must use this shared projection instead of
 * deriving their own boundary set: color, link and decoration ranges do not
 * change line layout, but their exact source edges must survive shaping so hit
 * testing and paint geometry do not slice a larger cluster proportionally.
 *
 * Returns the published boundary list (the handwritten engine's Set<Int>),
 * in ascending order; TiqianTextContent.sourceBoundaries consumes it as a list.
 */
class RichTextLayoutProjection {
    @:topLevel
    public static function sourceBoundariesForPresentation(textLength:Int, ?decorations:ReadOnlyArray<DecorationSpan>, ?colorSpans:ReadOnlyArray<ColorSpan>,
            ?richTextSpans:ReadOnlyArray<RichTextSpan>, ?textSpans:ReadOnlyArray<TextSpan>, ?rubySpans:ReadOnlyArray<RubySpan>):Array<Int> {
        final builder = SortedSet.builder();
        function addBoundary(offset:Int):Void {
            if (offset > 0 && offset < textLength)
                builder.put(offset);
        }
        function addRange(start:Int, end:Int):Void {
            addBoundary(start);
            addBoundary(end);
        }
        if (decorations != null) {
            var i = 0;
            while (i < decorations.length) {
                addRange(decorations[i].range.start, decorations[i].range.end);
                i += 1;
            }
        }
        if (colorSpans != null) {
            var i = 0;
            while (i < colorSpans.length) {
                addRange(colorSpans[i].start, colorSpans[i].end);
                i += 1;
            }
        }
        if (richTextSpans != null) {
            var i = 0;
            while (i < richTextSpans.length) {
                addRange(richTextSpans[i].range.start, richTextSpans[i].range.end);
                i += 1;
            }
        }
        if (textSpans != null) {
            var i = 0;
            while (i < textSpans.length) {
                addRange(textSpans[i].range.start, textSpans[i].range.end);
                i += 1;
            }
        }
        if (rubySpans != null) {
            var i = 0;
            while (i < rubySpans.length) {
                addRange(rubySpans[i].baseRange.start, rubySpans[i].baseRange.end);
                i += 1;
            }
        }
        final set = builder.build();
        final out = new Array<Int>();
        var index = 0;
        while (index < set.size()) {
            out.push(set.at(index));
            index += 1;
        }
        return out;
    }
}

