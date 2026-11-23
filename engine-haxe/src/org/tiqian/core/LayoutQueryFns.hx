package org.tiqian.core;

import std.ReadOnlyArray;

/**
 * Kotlin extension receivers for the LayoutQueries statics.
 *
 * The handwritten engine published these as extension functions; Haxe has no
 * extension declarations, so the port kept them as static queries. These
 * wrappers restore the published receiver shape without duplicating any query
 * logic.
 */
@:keep
class LayoutQueryFns {
    @:extension
    public static function getTextForCopy(result:LayoutResult, range:TextRange):String
        return LayoutQueries.getTextForCopy(result, range);

    @:extension
    public static function glyphInkBounds(result:LayoutResult):Null<Rect>
        return LayoutQueries.glyphInkBounds(result);

    @:extension
    public static function getLineForOffset(result:LayoutResult, offset:Int):Int
        return LayoutQueries.getLineForOffset(result, offset);

    @:extension
    public static function getBoundingBox(result:LayoutResult, offset:Int):Rect
        return LayoutQueries.getBoundingBox(result, offset);

    @:extension
    public static function getBoundingBoxes(result:LayoutResult, range:TextRange):Array<Rect>
        return LayoutQueries.getBoundingBoxes(result, range);

    @:extension
    public static function positionedRichTextSegments(result:LayoutResult, spans:ReadOnlyArray<RichTextSpan>):Array<RichTextLineSegment>
        return LayoutQueries.positionedRichTextSegments(result, toArray(spans));

    @:extension
    public static function richTextBackgroundSegments(result:LayoutResult, occupiedSegments:ReadOnlyArray<RichTextLineSegment>):Array<RichTextLineSegment>
        return LayoutQueries.richTextBackgroundSegments(result, toArray(occupiedSegments));

    @:extension
    public static function richTextDecorationSegments(result:LayoutResult, occupiedSegments:ReadOnlyArray<RichTextLineSegment>):Array<RichTextLineSegment>
        return LayoutQueries.trimmedRichTextDecorationSegments(result, toArray(occupiedSegments));

    @:extension
    public static function richTextDecorationLineY(result:LayoutResult, segment:RichTextLineSegment, strokeWidth:Float):Float
        return LayoutQueries.richTextDecorationLineY(result, segment, strokeWidth);

    @:extension
    public static function getCursorRect(result:LayoutResult, offset:Int):Rect
        return LayoutQueries.getCursorRect(result, offset);

    @:extension
    public static function getOffsetForPosition(result:LayoutResult, x:Float, y:Float):Int
        return LayoutQueries.getOffsetForPosition(result, x, y);

    @:extension
    public static function getSelectionOffsetForPosition(result:LayoutResult, x:Float, y:Float):Int
        return LayoutQueries.getSelectionOffsetForPosition(result, x, y);

    @:extension
    public static function coerceSelectionOffset(result:LayoutResult, offset:Int, bias:SourceBoundaryBias):Int
        return LayoutQueries.coerceSelectionOffset(result, offset, bias);

    @:extension
    public static function getSelectionWordBoundary(result:LayoutResult, offset:Int):TextRange
        return LayoutQueries.getSelectionWordBoundary(result, offset);

    @:extension
    public static function getSelectionWordBoundaryForPosition(result:LayoutResult, x:Float, y:Float):Null<TextRange>
        return LayoutQueries.getSelectionWordBoundaryForPosition(result, x, y);

    @:extension
    public static function resolvedBackgroundCornerRadii(segment:RichTextLineSegment, ?inset:Null<Float>):RichTextCornerRadii
        return LayoutQueries.resolvedBackgroundCornerRadii(segment, inset == null ? 0.0 : inset);

    @:allow(org.tiqian.core.LayoutQueryFns)
    private static function toArray<T>(values:ReadOnlyArray<T>):Array<T> {
        final out = new Array<T>();
        var index = 0;
        while (index < values.length) {
            out.push(values[index]);
            index += 1;
        }
        return out;
    }
}

@:keep
class LayoutQueryRangeFns {
    /** Int-pair overload of getBoundingBoxes; Haxe has no overloading. */
    @:extension
    public static function getBoundingBoxes(result:LayoutResult, start:Int, end:Int):Array<Rect>
        return LayoutQueries.getBoundingBoxesInt(result, start, end);
}

