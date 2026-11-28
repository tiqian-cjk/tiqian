package org.tiqian.protocol;

/**
 * Plan data model — lines, cells, and evidence — single-sourced in Haxe
 * (Stage1-P3 research 5.3 "plan 数据模型（行、cell、evidence）与 JSON/
 * packed 序列化"). Every typedef corresponds one-to-one with the Rust reader
 * structs in plan.rs; field names follow the same camelCase the JSON carries
 * and the boring emitter converts to the target conventions
 * (features/03-structures-and-typedefs.md:180).
 *
 * Authority order:
 *   PreparedParagraph.kt:73-154   JSON producer append sequence
 *   plan.rs:23-190                Rust reader struct definitions
 *   plan_packed.rs                packed layout
 */

// ---- Paragraph-level evidence DTOs ----

/** One `emphasisRanges` entry: a `[start, end]` pair. */
typedef PlanEmphasisRange = {
    var start:Int;
    var end:Int;
}

/** One `inlineEdges` entry: `{offset, inlineStart?, inlineEnd?}`. */
typedef PlanInlineEdge = {
    var offset:Int;
    var inlineStart:Null<Float>;
    var inlineEnd:Null<Float>;
}

/** One `rubyDecisions` entry. */
typedef PlanRuby = {
    var baseRangeStart:Int;
    var baseRangeEnd:Int;
    var text:String;
    var centerX:Float;
    var baselineY:Float;
    var fontSize:Float;
    var fontWeight:Int;
    var fontFamilies:Array<String>;
    var ascent:Null<Float>;
}

/** One `bopomofoDecisions` entry. */
typedef PlanBopomofo = {
    var baseRangeStart:Int;
    var baseRangeEnd:Int;
    var text:String;
    var fontWeight:Int;
    var fontFamilies:Array<String>;
    var placements:Array<PlanBopomofoPlacement>;
}

/** One bopomofo glyph placement; role is the Kotlin enum name. */
typedef PlanBopomofoPlacement = {
    var text:String;
    var role:String;
    var left:Float;
    var top:Float;
    var width:Float;
    var height:Float;
}

/** One `decorationSegments` entry. */
typedef PlanDecorationSegment = {
    var kind:String;
    var left:Float;
    var top:Float;
    var right:Float;
    var sourceRangeStart:Int;
    var sourceRangeEnd:Int;
}

/** One `emphasisDots` entry. */
typedef PlanEmphasisDot = {
    var clusterRangeStart:Null<Float>;
    var anchorX:Float;
    var anchorY:Float;
    var dotDiameter:Float;
}

// ---- Line and cell DTOs ----

/** A single formatted line. */
typedef PlanLine = {
    var rangeStart:Int;
    var rangeEnd:Int;
    var top:Float;
    var bottom:Float;
    var baseline:Float;
    var indent:Float;
    var visualWidth:Float;
    var hyphenAdvance:Float;
    var endReason:PlanEndReason;
    var cells:Array<PlanCell>;
}

/** A single display cell within a line. Evidence fields are omitted (null /
    false / empty array) when absent; the encode function decides which ones
    to emit based on renderEvidence and their runtime values. */
typedef PlanCell = {
    var rangeStart:Int;
    var rangeEnd:Int;
    var source:String;
    var display:String;
    var drawX:Float;
    var naturalWidth:Float;
    var leadingLayoutAdvance:Float;
    /** True only on multi-code-unit clusters; absent means false. */
    var shapingBoundary:Bool;
    /** OpenType feature tags applied by shaping policy; absent means none. */
    var openTypeFeatures:Array<String>;
    // -- renderEvidence-only fields (all Option/null = absent) --
    var renderFontFamily:Null<String>;
    var dashStrategy:Null<String>;
    var shapingLanguage:Null<String>;
    var resolvedFace:Null<String>;
    var glyphIds:Null<String>;
    var shapingEvidence:Null<String>;
    var punctuationInkFloor:Null<Float>;
    var punctuationBodyWidth:Null<Float>;
    var latin:Bool;
    var advance:Null<Float>;
    var inlineObject:Null<Float>;
    var styleDelta:Null<PlanStyleDelta>;
}

/** Advance of the U+00A0 spacing carrier for cells inside [rangeStart, rangeEnd); present with or without render evidence. */
typedef PlanSpacingCarrierAdvance = {
    var rangeStart:Int;
    var rangeEnd:Int;
    var advance:Float;
}

// ---- Top-level plan DTO ----

/**
 * The complete plan for one paragraph. Schema and revision ride the JSON wire
 * as the first two keys (PreparedParagraph.kt:94-95); the encode function
 * writes them from PlanSchema, not from this struct. Every paragraph-level
 * evidence vector is empty when the evidence path is off.
 */
typedef Plan = {
    var width:Float;
    var height:Float;
    var lines:Array<PlanLine>;
    var emphasisRanges:Array<PlanEmphasisRange>;
    var inlineEdges:Array<PlanInlineEdge>;
    var rubyDecisions:Array<PlanRuby>;
    var bopomofoDecisions:Array<PlanBopomofo>;
    var fontSize:Null<Float>;
    var overlayWidth:Null<Float>;
    var decorationSegments:Array<PlanDecorationSegment>;
    var emphasisDots:Array<PlanEmphasisDot>;
    var spacingCarrierAdvances:Array<PlanSpacingCarrierAdvance>;
}