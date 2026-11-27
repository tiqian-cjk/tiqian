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
        // Per-cluster-range accumulators indexed by ClusterRangeSlots. A later write to the same
        // range replaces an earlier one, as SortedMapBuilder.build keeps the last put of a key.
        // A glyph or decision range that is no cluster's range is skipped: the cell loop below
        // reads only cluster ranges. (PlanClusterRangeSlots)
        final slots = new ClusterRangeSlots(result.clusters);
        final slotCount = slots.count();
        final naturalBySlot = new Array<Float>();
        final hasGlyphBySlot = new Array<Bool>();
        final featuresBySlot = new Array<Array<String>>();
        final fontRunBySlot = new Array<Int>();
        final fontGlyphBySlot = new Array<Int>();
        final glyphIdsBySlot = new Array<Array<String>>();
        final zeroBySlot = new Array<Bool>();
        final shapingBySlot = new Array<Int>();
        final punctBySlot = new Array<Int>();
        final inlineAdvanceBySlot = new Array<Float>();
        final hasInlineAdvanceBySlot = new Array<Bool>();
        for (_ in 0...slotCount) {
            naturalBySlot.push(0.0);
            hasGlyphBySlot.push(false);
            featuresBySlot.push([]);
            fontRunBySlot.push(-1);
            fontGlyphBySlot.push(-1);
            glyphIdsBySlot.push([]);
            zeroBySlot.push(false);
            shapingBySlot.push(-1);
            punctBySlot.push(-1);
            inlineAdvanceBySlot.push(0.0);
            hasInlineAdvanceBySlot.push(false);
        }
        for (ri in 0...result.glyphRuns.length) {
            final run = result.glyphRuns[ri];
            for (gi in 0...run.glyphs.length) {
                final glyph = run.glyphs[gi];
                final slot = slots.slotOf(glyph.clusterRange);
                if (slot < 0)
                    continue;
                naturalBySlot[slot] = naturalBySlot[slot] + glyph.advance;
                hasGlyphBySlot[slot] = true;
                if (run.openTypeFeatures.length > 0) {
                    // Push through the element: a local alias of an inner array is a copy on Rust.
                    for (fi in 0...run.openTypeFeatures.length) {
                        final f = run.openTypeFeatures[fi];
                        if (featuresBySlot[slot].indexOf(f) < 0) featuresBySlot[slot].push(f);
                    }
                }
                if (glyph.renderFontKey != null) {
                    fontRunBySlot[slot] = ri;
                    fontGlyphBySlot[slot] = gi;
                }
                glyphIdsBySlot[slot].push(Std.string(glyph.id));
            }
        }
        final zeroSrc = result.presentation.zeroWidthBreakDecisions;
        for (zi in 0...zeroSrc.length) {
            final slot = slots.slotOf(zeroSrc[zi].range);
            if (slot >= 0) zeroBySlot[slot] = true;
        }
        final shapingSrc = result.presentation.shapingDecisions;
        for (zi in 0...shapingSrc.length) {
            final slot = slots.slotOf(shapingSrc[zi].range);
            if (slot >= 0) shapingBySlot[slot] = zi;
        }
        final punctSrc = result.presentation.punctuationDecisions;
        for (zi in 0...punctSrc.length) {
            final slot = slots.slotOf(punctSrc[zi].range);
            if (slot >= 0) punctBySlot[slot] = zi;
        }
        final inlineObjSrc = result.input.inlineObjects;
        for (zi in 0...inlineObjSrc.length) {
            final slot = slots.slotOf(inlineObjSrc[zi].range);
            if (slot >= 0) {
                inlineAdvanceBySlot[slot] = inlineObjSrc[zi].advance;
                hasInlineAdvanceBySlot[slot] = true;
            }
        }
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
        final edgeStart = edgeStartB.build();
        final edgeEnd = edgeEndB.build();

        final lines:Array<Plan.PlanLine> = [];
        final positionedByLine = LayoutQueries.positionedClustersByLine(result);
        for (li in 0...result.lines.length) {
            final line = result.lines[li];
            final cells:Array<Plan.PlanCell> = [];
            for (p in positionedByLine[li]) {
                final c = result.clusters[p.clusterIndex];
                final slot = slots.slotOf(c.range);
                if (!(c.displayText.length > 0 || zeroBySlot[slot] || (renderEvidence && hasInlineAdvanceBySlot[slot])))
                    continue;
                final natW:Float = hasGlyphBySlot[slot] ? naturalBySlot[slot] : c.advance;
                var inlineObj:Null<Float> = null; var advOverride:Null<Float> = null;
                var renderFam:Null<String> = null; var dash:Null<String> = null;
                var lang:Null<String> = null; var face:Null<String> = null;
                var gIds:Null<String> = null; var ev:Null<String> = null;
                var inkFloor:Null<Float> = null; var bodyW:Null<Float> = null;
                var latin = false; var styleDelta:Null<PlanStyleDelta> = null;
                if (renderEvidence) {
                    if (hasInlineAdvanceBySlot[slot]) {
                        final inlineAdvance:Float = inlineAdvanceBySlot[slot];
                        inlineObj = inlineAdvance;
                    }
                    final glyphW:Float = hasInlineAdvanceBySlot[slot] ? inlineAdvanceBySlot[slot] : natW;
                    advOverride = (c.advance != glyphW) ? c.advance : null;
                    final fontRun = fontRunBySlot[slot];
                    if (fontRun >= 0)
                        renderFam = result.glyphRuns[fontRun].glyphs[fontGlyphBySlot[slot]].renderFontKey;
                    final shapingIndex = shapingBySlot[slot];
                    if (shapingIndex >= 0) {
                        final sd = shapingSrc[shapingIndex];
                        dash = sd.strategy;
                        lang = sd.language;
                        face = sd.resolvedFace;
                        ev = sd.reason;
                    }
                    final ids = glyphIdsBySlot[slot];
                    if (ids.length > 0) {
                        final joined:String = ids.join(",");
                        gIds = joined;
                    }
                    final punctIndex = punctBySlot[slot];
                    final pd = punctIndex >= 0 ? punctSrc[punctIndex] : null;
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
                final feats = featuresBySlot[slot];
                cells.push({
                    rangeStart: c.range.start, rangeEnd: c.range.end,
                    source: c.text, display: c.displayText,
                    drawX: p.drawX, naturalWidth: natW, leadingLayoutAdvance: c.leadingLayoutAdvance,
                    shapingBoundary: c.range.end - c.range.start > 1,
                    openTypeFeatures: feats,
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
/**
 * Numbers the distinct cluster ranges of one layout result (`PlanClusterRangeSlots`): the ranges are
 * ordered by start, then end, duplicates share one slot, and `slotOf` finds the slot of a range by
 * binary search, or -1 when no cluster has exactly that range.
 */
class ClusterRangeSlots {
    final starts:Array<Int>;
    final ends:Array<Int>;

    public function new(clusters:ReadOnlyArray<Cluster>) {
        final order = new Array<Int>();
        for (i in 0...clusters.length)
            order.push(i);
        // Clusters arrive in text order, so the insertion sort below normally moves nothing.
        var i = 1;
        while (i < order.length) {
            final moving = order[i];
            var j = i - 1;
            while (j >= 0 && compare(clusters[order[j]].range, clusters[moving].range) > 0) {
                order[j + 1] = order[j];
                j--;
            }
            order[j + 1] = moving;
            i++;
        }
        final distinctStarts = new Array<Int>();
        final distinctEnds = new Array<Int>();
        for (k in 0...order.length) {
            final range = clusters[order[k]].range;
            final last = distinctStarts.length - 1;
            if (last < 0 || distinctStarts[last] != range.start || distinctEnds[last] != range.end) {
                distinctStarts.push(range.start);
                distinctEnds.push(range.end);
            }
        }
        this.starts = distinctStarts;
        this.ends = distinctEnds;
    }

    public function count():Int
        return starts.length;

    public function slotOf(range:TextRange):Int {
        var low = 0;
        var high = starts.length;
        while (low < high) {
            final mid = (low + high) >> 1;
            final s = starts[mid];
            final e = ends[mid];
            if (s < range.start || (s == range.start && e < range.end))
                low = mid + 1;
            else
                high = mid;
        }
        return low < starts.length && starts[low] == range.start && ends[low] == range.end ? low : -1;
    }

    static function compare(a:TextRange, b:TextRange):Int
        return a.start != b.start ? a.start - b.start : a.end - b.end;
}
