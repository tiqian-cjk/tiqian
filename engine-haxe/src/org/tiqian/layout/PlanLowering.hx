package org.tiqian.layout;

import std.SortedMap;
import org.tiqian.core.*;
import org.tiqian.font.FontRole;
import org.tiqian.protocol.*;
import std.ReadOnlyArray;

/**
 * Lowers a LayoutResult into a protocol Plan (Stage1-P3). The evidence
 * computation mirrors PreparedParagraphFns.toPreparedParagraphJson exactly;
 * the caller then serialises the Plan through PlanJson.encode or
 * PlanPacked.encode.
 */
class PlanLowering {
    /** Identity on Float; gives the Kotlin emitter an argument position so a
     * Haxe Int coerces to Float with an explicit .toFloat() (a plain
     * assignment emits no conversion and fails Kotlin typing). */
    static function f32(v:Float):Float return v;
    static function rangeKey(r:TextRange):String
        return Std.string(r.start) + ":" + Std.string(r.end);

    static function styleAt(result:LayoutResult, offset:Int):TextStyle {
        final spanSrc = result.input.content.spans;
        for (si in 0...spanSrc.length) {
            final span = spanSrc[si];
            if (offset >= span.range.start && offset < span.range.end)
                return span.style;
        }
        return result.input.textStyle;
    }

    public static function toPlan(result:LayoutResult, renderEvidence:Bool = false):Plan {
        final naturalB:SortedMapBuilder<String, Float> = SortedMap.builder();
        final featuresB = SortedMap.builder();
        final fontsB:SortedMapBuilder<String, String> = SortedMap.builder();
        final glyphIdsB = SortedMap.builder();
        for (ri in 0...result.glyphRuns.length) {
            final run = result.glyphRuns[ri];
            for (gi in 0...run.glyphs.length) {
                final glyph = run.glyphs[gi];
                final k = rangeKey(glyph.clusterRange);
                final priorNatural = naturalB.get(k);
                final priorN:Float = priorNatural == null ? 0.0 : priorNatural;
                naturalB.put(k, priorN + glyph.advance);
                if (run.openTypeFeatures.length > 0) {
                    var fs = featuresB.get(k);
                    if (fs == null) fs = [];
                    for (fi in 0...run.openTypeFeatures.length) {
                        final f = run.openTypeFeatures[fi];
                        if (fs.indexOf(f) < 0) fs.push(f);
                    }
                    featuresB.put(k, fs);
                }
                final rfk = glyph.renderFontKey;
                if (rfk != null) fontsB.put(k, rfk);
                var ids = glyphIdsB.get(k);
                if (ids == null) ids = [];
                ids.push(Std.string(glyph.id));
                glyphIdsB.put(k, ids);
            }
        }
        final zeroB = SortedMap.builder();
        final zeroSrc = result.presentation.zeroWidthBreakDecisions;
        for (zi in 0...zeroSrc.length) zeroB.put(rangeKey(zeroSrc[zi].range), true);
        final shapingB = SortedMap.builder();
        final shapingSrc = result.presentation.shapingDecisions;
        for (zi in 0...shapingSrc.length) shapingB.put(rangeKey(shapingSrc[zi].range), shapingSrc[zi]);
        final punctB = SortedMap.builder();
        final punctSrc = result.presentation.punctuationDecisions;
        for (zi in 0...punctSrc.length) punctB.put(rangeKey(punctSrc[zi].range), punctSrc[zi]);
        final inlineAdvanceB = SortedMap.builder();
        final inlineObjSrc = result.input.inlineObjects;
        for (zi in 0...inlineObjSrc.length) inlineAdvanceB.put(rangeKey(inlineObjSrc[zi].range), inlineObjSrc[zi].advance);
        final edgeStartB:SortedMapBuilder<String, Float> = SortedMap.builder();
        final edgeEndB:SortedMapBuilder<String, Float> = SortedMap.builder();
        final boxSrc = result.input.inlineBoxes;
        for (bi in 0...boxSrc.length) {
            final b = boxSrc[bi];
            if (b.inlineStart != 0) {
                final sk = Std.string(b.range.start);
                final priorStart = edgeStartB.get(sk);
                final pStart:Float = priorStart == null ? 0.0 : priorStart;
                edgeStartB.put(sk, pStart + b.inlineStart);
            }
            if (b.inlineEnd != 0) {
                final ek = Std.string(b.range.end);
                final priorEnd = edgeEndB.get(ek);
                final pEnd:Float = priorEnd == null ? 0.0 : priorEnd;
                edgeEndB.put(ek, pEnd + b.inlineEnd);
            }
        }
        final natural = naturalB.build();
        final features = featuresB.build();
        final fonts = fontsB.build();
        final glyphIds = glyphIdsB.build();
        final zero = zeroB.build();
        final shaping = shapingB.build();
        final punct = punctB.build();
        final inlineAdvance = inlineAdvanceB.build();
        final edgeStart = edgeStartB.build();
        final edgeEnd = edgeEndB.build();

        final lines:Array<Plan.PlanLine> = [];
        final positionedByLine = LayoutQueries.positionedClustersByLine(result);
        for (li in 0...result.lines.length) {
            final line = result.lines[li];
            final cells:Array<Plan.PlanCell> = [];
            for (p in positionedByLine[li]) {
                final c = result.clusters[p.clusterIndex];
                final ck = rangeKey(c.range);
                if (!(c.displayText.length > 0 || zero.has(ck) || (renderEvidence && inlineAdvance.has(ck))))
                    continue;
                final naturalEntry = natural.get(ck);
                final natW:Float = naturalEntry == null ? c.advance : naturalEntry;
                var inlineObj:Null<Float> = null; var advOverride:Null<Float> = null;
                var renderFam:Null<String> = null; var dash:Null<String> = null;
                var lang:Null<String> = null; var face:Null<String> = null;
                var gIds:Null<String> = null; var ev:Null<String> = null;
                var inkFloor:Null<Float> = null; var bodyW:Null<Float> = null;
                var latin = false; var styleDelta:Null<PlanStyleDelta> = null;
                if (renderEvidence) {
                    inlineObj = inlineAdvance.get(ck);
                    final glyphW:Float = inlineObj == null ? natW : inlineObj;
                    advOverride = (c.advance != glyphW) ? c.advance : null;
                    renderFam = fonts.get(ck);
                    final sd = shaping.get(ck);
                    dash = sd != null ? sd.strategy : null;
                    lang = sd != null ? sd.language : null;
                    face = sd != null ? sd.resolvedFace : null;
                    final glyphIdsEntry = glyphIds.get(ck);
                    gIds = glyphIdsEntry == null ? null : (glyphIdsEntry.length > 0 ? glyphIdsEntry.join(",") : null);
                    ev = sd != null ? sd.reason : null;
                    final pd = punct.get(ck);
                    if (pd != null && pd.inkContainmentApplied && pd.inkContainmentBodyFloor != null) {
                        inkFloor = pd.inkContainmentBodyFloor;
                        bodyW = pd.bodyWidth;
                    }
                    final fdSrc = result.presentation.fontDecisions;
                    for (fi in 0...fdSrc.length) {
                        final fd = fdSrc[fi];
                        if (c.range.start >= fd.range.start && c.range.end <= fd.range.end && fd.role == Type.enumConstructor(FontRole.LatinText))
                            latin = true;
                    }
                    final cs = styleAt(result, c.range.start);
                    styleDelta = if (cs != result.input.textStyle) {
                        fontSize: cs.fontSize != result.input.textStyle.fontSize ? cs.fontSize : null,
                        fontWeight: cs.fontWeight != result.input.textStyle.fontWeight ? cs.fontWeight : null,
                        italic: cs.italic != result.input.textStyle.italic ? cs.italic : null,
                    } else null;
                }
                final feats = features.get(ck);
                cells.push({
                    rangeStart: c.range.start, rangeEnd: c.range.end,
                    source: c.text, display: c.displayText,
                    drawX: p.drawX, naturalWidth: natW, leadingLayoutAdvance: c.leadingLayoutAdvance,
                    shapingBoundary: c.range.end - c.range.start > 1,
                    openTypeFeatures: feats != null ? feats : [],
                    renderFontFamily: renderFam, dashStrategy: dash,
                    shapingLanguage: lang, resolvedFace: face,
                    glyphIds: gIds, shapingEvidence: ev,
                    punctuationInkFloor: inkFloor, punctuationBodyWidth: bodyW,
                    latin: latin, advance: advOverride, inlineObject: inlineObj,
                    styleDelta: styleDelta,
                });
            }
            lines.push({
                rangeStart: line.range.start, rangeEnd: line.range.end,
                top: line.top, bottom: line.bottom, baseline: line.baseline,
                indent: line.indent, visualWidth: line.visualWidth,
                hyphenAdvance: line.hyphenAdvance, endReason: endReasonFrom(line.endReason),
                cells: cells,
            });
        }

        // Paragraph evidence
        var emphasisRanges:Array<Plan.PlanEmphasisRange> = [];
        var inlineEdges:Array<Plan.PlanInlineEdge> = [];
        var rubyDecisions:Array<Plan.PlanRuby> = [];
        var bopomofoDecisions:Array<Plan.PlanBopomofo> = [];
        var decorationSegments:Array<Plan.PlanDecorationSegment> = [];
        var emphasisDots:Array<Plan.PlanEmphasisDot> = [];
        var fontSize:Null<Float> = null;
        var overlayWidth:Null<Float> = null;
        if (renderEvidence) {
            fontSize = result.input.textStyle.fontSize;
            overlayWidth = result.size.width;
            final emphSrc = result.input.decorations;
            for (ei in 0...emphSrc.length) {
                final d = emphSrc[ei];
                if (d.kind == DecorationKind.Emphasis)
                    emphasisRanges.push({start: d.range.start, end: d.range.end});
            }
            var offsets:Array<Int> = [];
            for (oi in 0...edgeStart.size()) offsets.push(Std.parseInt(edgeStart.keyAt(oi)));
            for (ei in 0...edgeEnd.size()) {
                final ev = Std.parseInt(edgeEnd.keyAt(ei));
                if (offsets.indexOf(ev) < 0) offsets.push(ev);
            }
            var oi = 1;
            while (oi < offsets.length) {
                var ov = offsets[oi]; var oj = oi - 1;
                while (oj >= 0 && offsets[oj] > ov) {
                    offsets[oj + 1] = offsets[oj]; oj--;
                }
                offsets[oj + 1] = ov; oi++;
            }
            for (offset in offsets) {
                final sk = Std.string(offset);
                inlineEdges.push({
                    offset: offset,
                    inlineStart: edgeStart.get(sk),
                    inlineEnd: edgeEnd.get(sk),
                });
            }
            final rubySrc = result.presentation.rubyDecisions;
            for (ri in 0...rubySrc.length) {
                final r = rubySrc[ri];
                rubyDecisions.push({
                    baseRangeStart: r.baseRange.start, baseRangeEnd: r.baseRange.end,
                    text: r.text, centerX: r.centerX, baselineY: r.baselineY,
                    fontSize: r.fontSize, fontWeight: r.fontWeight,
                    fontFamilies: toArray(r.fontFamilies), ascent: r.ascent,
                });
            }
            final bopoSrc = result.presentation.bopomofoDecisions;
            for (bi in 0...bopoSrc.length) {
                final z = bopoSrc[bi];
                final placements:Array<Plan.PlanBopomofoPlacement> = [];
                for (pj in 0...z.placements.length) {
                    final pl = z.placements[pj];
                    placements.push({
                        text: pl.text, role: Type.enumConstructor(pl.role),
                        left: pl.left, top: pl.top, width: pl.width, height: pl.height,
                    });
                }
                bopomofoDecisions.push({
                    baseRangeStart: z.baseRange.start, baseRangeEnd: z.baseRange.end,
                    text: z.text, fontWeight: z.fontWeight,
                    fontFamilies: toArray(z.fontFamilies), placements: placements,
                });
            }
            final segSrc = result.presentation.decorationSegments;
            for (si in 0...segSrc.length) {
                final s = segSrc[si];
                if (s.kind == Type.enumConstructor(DecorationKind.ProperNoun) || s.kind == Type.enumConstructor(DecorationKind.BookTitle))
                    decorationSegments.push({kind: s.kind, left: s.left, top: s.top, right: s.right, sourceRangeStart: s.sourceRange.start, sourceRangeEnd: s.sourceRange.end});
            }
            final dotSrc = result.presentation.decorationDecisions;
            for (di in 0...dotSrc.length) {
                final d = dotSrc[di];
                if (d.applied && d.kind == Type.enumConstructor(DecorationKind.Emphasis) && d.dotDiameter > 0)
                    emphasisDots.push({clusterRangeStart: f32(d.clusterRange.start), anchorX: d.anchorX, anchorY: d.anchorY, dotDiameter: d.dotDiameter});
            }
        }
        return {
            width: result.input.constraints.maxWidth, height: result.size.height,
            lines: lines,
            emphasisRanges: emphasisRanges, inlineEdges: inlineEdges,
            rubyDecisions: rubyDecisions, bopomofoDecisions: bopomofoDecisions,
            fontSize: fontSize, overlayWidth: overlayWidth,
            decorationSegments: decorationSegments, emphasisDots: emphasisDots,
        };
    }

    static function endReasonFrom(reason:org.tiqian.core.LineEndReason):PlanEndReason {
        return switch (reason) {
            case AutoWrap: AutoWrap;
            case MandatoryBreak: MandatoryBreak;
            case ParagraphEnd: ParagraphEnd;
        };
    }

    static function toArray(src:ReadOnlyArray<String>):Array<String> {
        final out:Array<String> = [];
        for (i in 0...src.length) out.push(src[i]);
        return out;
    }
}