package org.tiqian.protocol;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.FPHelper;
import org.tiqian.protocol.Plan;

/**
 * Packed plan encoding and decoding (Stage1-P3).
 *
 * The column-major layout mirrors PlanPackedWriter.kt (the Kotlin producer)
 * and plan_packed.rs (the Rust reader) one-to-one: u32 magic + version
 * header, a string pool with u32 deltas, per-column f64 geometry and u32
 * string refs, and NaN sentinels for absent scalars.
 *
 * P2's unified Reader/Writer (TableWriter / TableReader, stdlib/02:15-217)
 * provides the byte-level primitives: u8/u16/u32/f64 little-endian,
 * BytesBuffer for growing, Bytes.get for reading. This module reuses them
 * for the plan-specific column schema.
 */

private class PlanPackedWriter {
    final buf:BytesBuffer;

    public function new() { buf = new BytesBuffer(); }

    public function u8(v:Int):Void { buf.addByte(v & 0xFF); }
    public function u16(v:Int):Void {
        buf.addByte(v & 0xFF); buf.addByte((v >>> 8) & 0xFF);
    }
    public function u32(v:Int):Void {
        buf.addByte(v & 0xFF); buf.addByte((v >>> 8) & 0xFF);
        buf.addByte((v >>> 16) & 0xFF); buf.addByte((v >>> 24) & 0xFF);
    }
    public function f64(v:Float):Void {
        final bits = FPHelper.doubleToI64(v);
        u32(bits.low); u32(bits.high);
    }
    public function raw(bytes:Bytes):Void {
        for (i in 0...bytes.length) buf.addByte(bytes.get(i));
    }
    public function finish():Bytes { return buf.getBytes(); }
}

/** The symmetric read side: a cursor over Bytes with a failure flag,
    mirroring P2's TableReader (stdlib/02:217 bounds checking). */
private class PlanPackedReader {
    final bytes:Bytes;
    var pos:Int;
    public var failed:Bool;

    public function new(bytes:Bytes) {
        this.bytes = bytes;
        pos = 0;
        failed = false;
    }

    public function u8():Int {
        if (!need(1)) return 0;
        final v = bytes.get(pos);
        pos += 1;
        return v;
    }

    public function u32():Int {
        if (!need(4)) return 0;
        final v = (bytes.get(pos) | (bytes.get(pos + 1) << 8) | (bytes.get(pos + 2) << 16))
            + (bytes.get(pos + 3) * 0x1000000);
        pos += 4;
        return v;
    }

    public function f64():Float {
        final low = u32();
        final high = u32();
        if (failed) return 0.0;
        return FPHelper.i64ToDouble(low, high);
    }

    public function string(len:Int):String {
        if (!need(len)) return "";
        final s = bytes.getString(pos, len);
        pos += len;
        return s;
    }

    function need(length:Int):Bool {
        if (failed) return false;
        if (length < 0 || pos + length > bytes.length) {
            failed = true;
            return false;
        }
        return true;
    }
}

private class StringPool {
    public final ordered:Array<String> = [];

    public function new() {}

    public function intern(value:String):Int {
        for (i in 0...ordered.length) {
            if (ordered[i] == value) return i;
        }
        final idx = ordered.length;
        ordered.push(value);
        return idx;
    }

    public function indexOf(value:String):Int {
        for (i in 0...ordered.length) {
            if (ordered[i] == value) return i;
        }
        return -1;
    }
}

class PlanPacked {
    static inline var PLAN_MAGIC:Int = 0x54515050;
    static inline var PLAN_PROTOCOL_REVISION:Int = 2;
    static inline var PLAN_STRING_ABSENT:Int = 0xFFFFFFFF;

    /** Identity on Float; gives the Kotlin emitter an argument position so a
     * Haxe Int coerces to Float with an explicit .toFloat() (a plain
     * assignment emits no conversion and fails Kotlin typing). */
    static function f32(v:Float):Float return v;

    /**
     * Encodes one Plan into its column-major packed bytes. Every string
     * (source, display, font families, feature tags, evidence refs, …) goes
     * through a global pool; absent scalar fields ride NaN (f64) or
     * PLAN_STRING_ABSENT (u32). The column order mirrors
     * PlanPackedWriter.kt:170-355 exactly.
     */
    public static function encode(plan:Plan):Bytes {
        final pool = new StringPool();
        final writer = new PlanPackedWriter();

        // Gather cell writes (column vectors), flat feature pool, families.
        final cellRangeStart:Array<Int> = [];
        final cellRangeEnd:Array<Int> = [];
        final cellSourceRef:Array<Int> = [];
        final cellDisplayRef:Array<Int> = [];
        final cellDrawX:Array<Float> = [];
        final cellNaturalWidth:Array<Float> = [];
        final cellLeadingAdvance:Array<Float> = [];
        final cellShapingBoundary:Array<Int> = [];
        final cellLatin:Array<Int> = [];
        final cellRenderFamilyRef:Array<Int> = [];
        final cellDashRef:Array<Int> = [];
        final cellLanguageRef:Array<Int> = [];
        final cellResolvedFaceRef:Array<Int> = [];
        final cellGlyphIdsRef:Array<Int> = [];
        final cellEvidenceRef:Array<Int> = [];
        final cellInkFloor:Array<Float> = [];
        final cellBodyWidth:Array<Float> = [];
        final cellAdvance:Array<Float> = [];
        final cellInlineObject:Array<Float> = [];
        final cellStyleFontSize:Array<Float> = [];
        final cellStyleFontWeight:Array<Float> = [];
        final cellStyleItalic:Array<Int> = [];
        final cellFeatureOffset:Array<Int> = [];
        final cellFeatureCount:Array<Int> = [];
        final featurePool:Array<Int> = [];

        var cellCount = 0;
        for (line in plan.lines) {
            cellCount += line.cells.length;
        }

        for (line in plan.lines) {
            for (cell in line.cells) {
                cellRangeStart.push(cell.rangeStart);
                cellRangeEnd.push(cell.rangeEnd);
                cellSourceRef.push(pool.intern(cell.source));
                cellDisplayRef.push(pool.intern(cell.display));
                cellDrawX.push(cell.drawX);
                cellNaturalWidth.push(cell.naturalWidth);
                cellLeadingAdvance.push(cell.leadingLayoutAdvance);
                cellShapingBoundary.push(cell.shapingBoundary ? 1 : 0);
                cellLatin.push(cell.latin ? 1 : 0);
                cellRenderFamilyRef.push(cell.renderFontFamily != null ? pool.intern(cell.renderFontFamily) : PLAN_STRING_ABSENT);
                cellDashRef.push(cell.dashStrategy != null ? pool.intern(cell.dashStrategy) : PLAN_STRING_ABSENT);
                cellLanguageRef.push(cell.shapingLanguage != null ? pool.intern(cell.shapingLanguage) : PLAN_STRING_ABSENT);
                cellResolvedFaceRef.push(cell.resolvedFace != null ? pool.intern(cell.resolvedFace) : PLAN_STRING_ABSENT);
                cellGlyphIdsRef.push(cell.glyphIds != null ? pool.intern(cell.glyphIds) : PLAN_STRING_ABSENT);
                cellEvidenceRef.push(cell.shapingEvidence != null ? pool.intern(cell.shapingEvidence) : PLAN_STRING_ABSENT);
                final ink = cell.punctuationInkFloor;
                cellInkFloor.push(ink != null ? ink : Math.NaN);
                final bw = cell.punctuationBodyWidth;
                cellBodyWidth.push(bw != null ? bw : Math.NaN);
                final adv = cell.advance;
                cellAdvance.push(adv != null ? adv : Math.NaN);
                final inl = cell.inlineObject;
                cellInlineObject.push(inl != null ? inl : Math.NaN);
                final style = cell.styleDelta;
                var styleFontSize = Math.NaN;
                var styleFontWeight = Math.NaN;
                var styleItalic = 2;
                if (style != null) {
                    final fs = style.fontSize;
                    if (fs != null) styleFontSize = (fs : Float);
                    final fw = style.fontWeight;
                    if (fw != null) styleFontWeight = f32(fw);
                    final it = style.italic;
                    if (it != null) styleItalic = it ? 1 : 0;
                }
                cellStyleFontSize.push(styleFontSize);
                cellStyleFontWeight.push(styleFontWeight);
                cellStyleItalic.push(styleItalic);
                final feats = cell.openTypeFeatures;
                for (f in feats) pool.intern(f);
                cellFeatureOffset.push(featurePool.length);
                cellFeatureCount.push(feats.length);
                for (f in feats) featurePool.push(pool.indexOf(f));
            }
        }

        // Ruby: pool families and texts, collect columns.
        final rubyBaseStart:Array<Int> = [];
        final rubyBaseEnd:Array<Int> = [];
        final rubyTextRef:Array<Int> = [];
        final rubyCenterX:Array<Float> = [];
        final rubyBaselineY:Array<Float> = [];
        final rubyFontSize:Array<Float> = [];
        final rubyFontWeight:Array<Int> = [];
        final rubyFamilyOffset:Array<Int> = [];
        final rubyFamilyCount:Array<Int> = [];
        final rubyAscent:Array<Float> = [];
        final rubyFamilyPool:Array<Int> = [];
        for (ruby in plan.rubyDecisions) {
            for (fam in ruby.fontFamilies) pool.intern(fam);
            pool.intern(ruby.text);
        }
        for (ruby in plan.rubyDecisions) {
            rubyBaseStart.push(ruby.baseRangeStart);
            rubyBaseEnd.push(ruby.baseRangeEnd);
            rubyTextRef.push(pool.indexOf(ruby.text));
            rubyCenterX.push(ruby.centerX);
            rubyBaselineY.push(ruby.baselineY);
            rubyFontSize.push(ruby.fontSize);
            rubyFontWeight.push(ruby.fontWeight);
            rubyFamilyOffset.push(rubyFamilyPool.length);
            rubyFamilyCount.push(ruby.fontFamilies.length);
            final ascent = ruby.ascent;
            rubyAscent.push(ascent != null ? ascent : Math.NaN);
            for (fam in ruby.fontFamilies) rubyFamilyPool.push(pool.indexOf(fam));
        }

        // Bopomofo: pool families, texts, roles, placements.
        final bopomofoBaseStart:Array<Int> = [];
        final bopomofoBaseEnd:Array<Int> = [];
        final bopomofoTextRef:Array<Int> = [];
        final bopomofoFontWeight:Array<Int> = [];
        final bopomofoFamilyOffset:Array<Int> = [];
        final bopomofoFamilyCount:Array<Int> = [];
        final bopomofoPlaceOffset:Array<Int> = [];
        final bopomofoPlaceCount:Array<Int> = [];
        final bopomofoFamilyPool:Array<Int> = [];
        final bopomofoPlaceTextRef:Array<Int> = [];
        final bopomofoPlaceRoleRef:Array<Int> = [];
        final bopomofoPlaceLeft:Array<Float> = [];
        final bopomofoPlaceTop:Array<Float> = [];
        final bopomofoPlaceWidth:Array<Float> = [];
        final bopomofoPlaceHeight:Array<Float> = [];
        for (bopomofo in plan.bopomofoDecisions) {
            for (fam in bopomofo.fontFamilies) pool.intern(fam);
            pool.intern(bopomofo.text);
            for (pl in bopomofo.placements) {
                pool.intern(pl.text);
                pool.intern(pl.role);
            }
        }
        for (bopomofo in plan.bopomofoDecisions) {
            bopomofoBaseStart.push(bopomofo.baseRangeStart);
            bopomofoBaseEnd.push(bopomofo.baseRangeEnd);
            bopomofoTextRef.push(pool.indexOf(bopomofo.text));
            bopomofoFontWeight.push(bopomofo.fontWeight);
            bopomofoFamilyOffset.push(bopomofoFamilyPool.length);
            bopomofoFamilyCount.push(bopomofo.fontFamilies.length);
            bopomofoPlaceOffset.push(bopomofoPlaceTextRef.length);
            bopomofoPlaceCount.push(bopomofo.placements.length);
            for (fam in bopomofo.fontFamilies) bopomofoFamilyPool.push(pool.indexOf(fam));
            for (pl in bopomofo.placements) {
                bopomofoPlaceTextRef.push(pool.indexOf(pl.text));
                bopomofoPlaceRoleRef.push(pool.indexOf(pl.role));
                bopomofoPlaceLeft.push(pl.left);
                bopomofoPlaceTop.push(pl.top);
                bopomofoPlaceWidth.push(pl.width);
                bopomofoPlaceHeight.push(pl.height);
            }
        }

        // Decoration segments: pool kind strings.
        final decorationKindRef:Array<Int> = [];
        final decorationLeft:Array<Float> = [];
        final decorationTop:Array<Float> = [];
        final decorationRight:Array<Float> = [];
        for (seg in plan.decorationSegments) pool.intern(seg.kind);
        for (seg in plan.decorationSegments) {
            decorationKindRef.push(pool.indexOf(seg.kind));
            decorationLeft.push(seg.left);
            decorationTop.push(seg.top);
            decorationRight.push(seg.right);
        }

        // Compute totals.
        final emphasisRangeCount = plan.emphasisRanges.length;
        final inlineEdgeCount = plan.inlineEdges.length;
        final rubyCount = plan.rubyDecisions.length;
        final bopomofoCount = plan.bopomofoDecisions.length;
        final bopomofoPlacementTotal = bopomofoPlaceTextRef.length;
        final decorationSegmentCount = plan.decorationSegments.length;
        final emphasisDotCount = plan.emphasisDots.length;
        final stringCount = pool.ordered.length;
        final featureTotal = featurePool.length;
        final rubyFamilyTotal = rubyFamilyPool.length;
        final bopomofoFamilyTotal = bopomofoFamilyPool.length;

        // === WRITE HEADER ===
        writer.u32(PLAN_MAGIC);
        writer.u32(PLAN_PROTOCOL_REVISION);
        writer.f64(plan.width);
        writer.f64(plan.height);
        final fontSize = plan.fontSize;
        writer.f64(fontSize != null ? (fontSize : Float) : Math.NaN);
        final overlayWidth = plan.overlayWidth;
        writer.f64(overlayWidth != null ? (overlayWidth : Float) : Math.NaN);
        writer.u32(plan.lines.length);
        writer.u32(cellCount);
        writer.u32(emphasisRangeCount);
        writer.u32(inlineEdgeCount);
        writer.u32(rubyCount);
        writer.u32(bopomofoCount);
        writer.u32(bopomofoPlacementTotal);
        writer.u32(decorationSegmentCount);
        writer.u32(emphasisDotCount);
        writer.u32(stringCount);
        writer.u32(featureTotal);
        writer.u32(rubyFamilyTotal);
        writer.u32(bopomofoFamilyTotal);

        // === STRING POOL ===
        for (s in pool.ordered) {
            final encoded = Bytes.ofString(s);
            writer.u32(encoded.length);
        }
        for (s in pool.ordered) {
            writer.raw(Bytes.ofString(s));
        }

        // === LINE COLUMNS ===
        for (line in plan.lines) writer.u32(line.rangeStart);
        for (line in plan.lines) writer.u32(line.rangeEnd);
        for (line in plan.lines) writer.f64(line.top);
        for (line in plan.lines) writer.f64(line.bottom);
        for (line in plan.lines) writer.f64(line.baseline);
        for (line in plan.lines) writer.f64(line.indent);
        for (line in plan.lines) writer.f64(line.visualWidth);
        for (line in plan.lines) writer.f64(line.hyphenAdvance);
        for (line in plan.lines) {
            writer.u8(endReasonCode(line.endReason));
        }
        for (line in plan.lines) writer.u32(line.cells.length);

        // === CELL COLUMNS (column-major) ===
        for (v in cellRangeStart) writer.u32(v);
        for (v in cellRangeEnd) writer.u32(v);
        for (v in cellSourceRef) writer.u32(v);
        for (v in cellDisplayRef) writer.u32(v);
        for (v in cellDrawX) writer.f64(v);
        for (v in cellNaturalWidth) writer.f64(v);
        for (v in cellLeadingAdvance) writer.f64(v);
        for (v in cellShapingBoundary) writer.u8(v);
        for (v in cellLatin) writer.u8(v);
        for (v in cellRenderFamilyRef) writer.u32(v);
        for (v in cellDashRef) writer.u32(v);
        for (v in cellLanguageRef) writer.u32(v);
        for (v in cellResolvedFaceRef) writer.u32(v);
        for (v in cellGlyphIdsRef) writer.u32(v);
        for (v in cellEvidenceRef) writer.u32(v);
        for (v in cellInkFloor) writer.f64(v);
        for (v in cellBodyWidth) writer.f64(v);
        for (v in cellAdvance) writer.f64(v);
        for (v in cellInlineObject) writer.f64(v);
        for (v in cellStyleFontSize) writer.f64(v);
        for (v in cellStyleFontWeight) writer.f64(v);
        for (v in cellStyleItalic) writer.u8(v);
        for (v in cellFeatureOffset) writer.u32(v);
        for (v in cellFeatureCount) writer.u32(v);

        // === FEATURE POOL ===
        for (v in featurePool) writer.u32(v);

        // === EMPHASIS RANGES ===
        for (range in plan.emphasisRanges) writer.f64(range.start);
        for (range in plan.emphasisRanges) writer.f64(range.end);

        // === INLINE EDGES ===
        for (edge in plan.inlineEdges) writer.f64(edge.offset);
        for (edge in plan.inlineEdges) { final s = edge.inlineStart; writer.f64(s != null ? s : Math.NaN); }
        for (edge in plan.inlineEdges) { final e = edge.inlineEnd; writer.f64(e != null ? e : Math.NaN); }

        // === RUBY ===
        for (v in rubyBaseStart) writer.u32(v);
        for (v in rubyBaseEnd) writer.u32(v);
        for (v in rubyTextRef) writer.u32(v);
        for (v in rubyCenterX) writer.f64(v);
        for (v in rubyBaselineY) writer.f64(v);
        for (v in rubyFontSize) writer.f64(v);
        for (v in rubyFontWeight) writer.u32(v);
        for (v in rubyFamilyOffset) writer.u32(v);
        for (v in rubyFamilyCount) writer.u32(v);
        for (v in rubyAscent) writer.f64(v);
        for (v in rubyFamilyPool) writer.u32(v);

        // === BOPOMOFO ===
        for (v in bopomofoBaseStart) writer.u32(v);
        for (v in bopomofoBaseEnd) writer.u32(v);
        for (v in bopomofoTextRef) writer.u32(v);
        for (v in bopomofoFontWeight) writer.u32(v);
        for (v in bopomofoFamilyOffset) writer.u32(v);
        for (v in bopomofoFamilyCount) writer.u32(v);
        for (v in bopomofoPlaceOffset) writer.u32(v);
        for (v in bopomofoPlaceCount) writer.u32(v);
        for (v in bopomofoFamilyPool) writer.u32(v);
        for (v in bopomofoPlaceTextRef) writer.u32(v);
        for (v in bopomofoPlaceRoleRef) writer.u32(v);
        for (v in bopomofoPlaceLeft) writer.f64(v);
        for (v in bopomofoPlaceTop) writer.f64(v);
        for (v in bopomofoPlaceWidth) writer.f64(v);
        for (v in bopomofoPlaceHeight) writer.f64(v);

        // === DECORATION SEGMENTS ===
        for (v in decorationKindRef) writer.u32(v);
        for (v in decorationLeft) writer.f64(v);
        for (v in decorationTop) writer.f64(v);
        for (v in decorationRight) writer.f64(v);

        // === EMPHASIS DOTS ===
        for (dot in plan.emphasisDots) {
            final cs = dot.clusterRangeStart;
            writer.f64(cs != null ? (cs : Float) : Math.NaN);
        }
        for (dot in plan.emphasisDots) writer.f64(dot.anchorX);
        for (dot in plan.emphasisDots) writer.f64(dot.anchorY);
        for (dot in plan.emphasisDots) writer.f64(dot.dotDiameter);

        // === SPACING CARRIER ADVANCES ===
        writer.u32(plan.spacingCarrierAdvances.length);
        for (carrier in plan.spacingCarrierAdvances) writer.u32(carrier.rangeStart);
        for (carrier in plan.spacingCarrierAdvances) writer.u32(carrier.rangeEnd);
        for (carrier in plan.spacingCarrierAdvances) writer.f64(carrier.advance);

        return writer.finish();
    }

    static function endReasonCode(reason:PlanEndReason):Int {
        return switch (reason) {
            case AutoWrap: 0;
            case MandatoryBreak: 1;
            case ParagraphEnd: 2;
        };
    }

    /** Decodes packed bytes, mirroring plan_packed.rs column reader. */
    public static function decode(bytes:Bytes):Null<Plan> {
        final r = new PlanPackedReader(bytes);
        if (r.u32() != PLAN_MAGIC) return null;
        if (r.u32() != PLAN_PROTOCOL_REVISION) return null;
        final width = r.f64();
        final height = r.f64();
        final fontSz = r.f64();
        final overlayW = r.f64();
        final lc = r.u32();
        final cc = r.u32();
        final erc = r.u32();
        final iec = r.u32();
        final rc = r.u32();
        final bc = r.u32();
        final bpt = r.u32();
        final dsc = r.u32();
        final edc = r.u32();
        final sc = r.u32();
        final ft = r.u32();
        final rft = r.u32();
        final bft = r.u32();
        if (r.failed) return null;

        // String pool
        final deltas:Array<Int> = [];
        for (i in 0...sc) deltas.push(r.u32());
        final pool:Array<String> = [];
        for (d in deltas) pool.push(r.string(d));
        if (r.failed) return null;

        function sref(ref:Int):Null<String> {
            return ref != PLAN_STRING_ABSENT ? pool[ref] : null;
        }

        // Line columns
        final lrs:Array<Int> = []; for (i in 0...lc) lrs.push(r.u32());
        final lre:Array<Int> = []; for (i in 0...lc) lre.push(r.u32());
        final lt:Array<Float> = []; for (i in 0...lc) lt.push(r.f64());
        final lb:Array<Float> = []; for (i in 0...lc) lb.push(r.f64());
        final lbl:Array<Float> = []; for (i in 0...lc) lbl.push(r.f64());
        final lin:Array<Float> = []; for (i in 0...lc) lin.push(r.f64());
        final lvw:Array<Float> = []; for (i in 0...lc) lvw.push(r.f64());
        final lha:Array<Float> = []; for (i in 0...lc) lha.push(r.f64());
        final ler:Array<Int> = []; for (i in 0...lc) ler.push(r.u8());
        final lcc:Array<Int> = []; for (i in 0...lc) lcc.push(r.u32());
        if (r.failed) return null;

        // Cell columns
        final crs:Array<Int> = []; for (i in 0...cc) crs.push(r.u32());
        final cre:Array<Int> = []; for (i in 0...cc) cre.push(r.u32());
        final csr:Array<Int> = []; for (i in 0...cc) csr.push(r.u32());
        final cdr:Array<Int> = []; for (i in 0...cc) cdr.push(r.u32());
        final cdx:Array<Float> = []; for (i in 0...cc) cdx.push(r.f64());
        final cnw:Array<Float> = []; for (i in 0...cc) cnw.push(r.f64());
        final cla:Array<Float> = []; for (i in 0...cc) cla.push(r.f64());
        final csb:Array<Int> = []; for (i in 0...cc) csb.push(r.u8());
        final cla2:Array<Int> = []; for (i in 0...cc) cla2.push(r.u8());
        final crf:Array<Int> = []; for (i in 0...cc) crf.push(r.u32());
        final cd2:Array<Int> = []; for (i in 0...cc) cd2.push(r.u32());
        final cl2:Array<Int> = []; for (i in 0...cc) cl2.push(r.u32());
        final crf2:Array<Int> = []; for (i in 0...cc) crf2.push(r.u32());
        final cgi:Array<Int> = []; for (i in 0...cc) cgi.push(r.u32());
        final cev:Array<Int> = []; for (i in 0...cc) cev.push(r.u32());
        final cif:Array<Float> = []; for (i in 0...cc) cif.push(r.f64());
        final cbw:Array<Float> = []; for (i in 0...cc) cbw.push(r.f64());
        final cad:Array<Float> = []; for (i in 0...cc) cad.push(r.f64());
        final cio:Array<Float> = []; for (i in 0...cc) cio.push(r.f64());
        final csf:Array<Float> = []; for (i in 0...cc) csf.push(r.f64());
        final csw:Array<Float> = []; for (i in 0...cc) csw.push(r.f64());
        final csi:Array<Int> = []; for (i in 0...cc) csi.push(r.u8());
        final cfo:Array<Int> = []; for (i in 0...cc) cfo.push(r.u32());
        final cfc:Array<Int> = []; for (i in 0...cc) cfc.push(r.u32());
        if (r.failed) return null;

        // Feature pool
        final fp:Array<Int> = []; for (i in 0...ft) fp.push(r.u32());

        // Build cells and lines
        var cursor = 0;
        final lines:Array<Plan.PlanLine> = [];
        for (li in 0...lc) {
            final cellN = lcc[li];
            final cells:Array<Plan.PlanCell> = [];
            for (ci in 0...cellN) {
                final i = cursor;
                cursor += 1;
                final fo = cfo[i];
                final fn = cfc[i];
                final feats:Array<String> = [];
                for (k in 0...fn) feats.push(pool[fp[fo + k]]);
                final sf = csf[i]; final sw = csw[i]; final si = csi[i];
                final style:Null<PlanStyleDelta> = if (Math.isNaN(sf) && Math.isNaN(sw) && si == 2) null else {
                    fontSize: Math.isNaN(sf) ? null : sf,
                    fontWeight: Math.isNaN(sw) ? null : Std.int(sw),
                    italic: si == 2 ? null : (si != 0),
                };
                cells.push({
                    rangeStart: crs[i], rangeEnd: cre[i],
                    source: pool[csr[i]], display: pool[cdr[i]],
                    drawX: cdx[i], naturalWidth: cnw[i], leadingLayoutAdvance: cla[i],
                    shapingBoundary: csb[i] != 0, openTypeFeatures: feats,
                    renderFontFamily: sref(crf[i]), dashStrategy: sref(cd2[i]),
                    shapingLanguage: sref(cl2[i]), resolvedFace: sref(crf2[i]),
                    glyphIds: sref(cgi[i]), shapingEvidence: sref(cev[i]),
                    punctuationInkFloor: Math.isNaN(cif[i]) ? null : cif[i],
                    punctuationBodyWidth: Math.isNaN(cbw[i]) ? null : cbw[i],
                    latin: cla2[i] != 0,
                    advance: Math.isNaN(cad[i]) ? null : cad[i],
                    inlineObject: Math.isNaN(cio[i]) ? null : cio[i],
                    styleDelta: style,
                });
            }
            final er = ler[li];
            final endR:PlanEndReason = er == 1 ? MandatoryBreak : (er == 2 ? ParagraphEnd : AutoWrap);
            lines.push({
                rangeStart: lrs[li], rangeEnd: lre[li],
                top: lt[li], bottom: lb[li], baseline: lbl[li], indent: lin[li],
                visualWidth: lvw[li], hyphenAdvance: lha[li],
                endReason: endR, cells: cells,
            });
        }

        // Emphasis ranges
        final emphasis:Array<Plan.PlanEmphasisRange> = [];
        for (i in 0...erc) {
            final s = r.f64(); final e = r.f64();
            emphasis.push({start: Std.int(s), end: Std.int(e)});
        }
        // Inline edges
        final edges:Array<Plan.PlanInlineEdge> = [];
        for (i in 0...iec) {
            final off = r.f64(); final s = r.f64(); final e = r.f64();
            edges.push({offset: Std.int(off),
                inlineStart: Math.isNaN(s) ? null : s,
                inlineEnd: Math.isNaN(e) ? null : e});
        }
        // Ruby columns (column-major), then family pool
        final rbS:Array<Int> = []; for (i in 0...rc) rbS.push(r.u32());
        final rbE:Array<Int> = []; for (i in 0...rc) rbE.push(r.u32());
        final rbT:Array<Int> = []; for (i in 0...rc) rbT.push(r.u32());
        final rbCx:Array<Float> = []; for (i in 0...rc) rbCx.push(r.f64());
        final rbBy:Array<Float> = []; for (i in 0...rc) rbBy.push(r.f64());
        final rbFs:Array<Float> = []; for (i in 0...rc) rbFs.push(r.f64());
        final rbFw:Array<Int> = []; for (i in 0...rc) rbFw.push(r.u32());
        final rbFo:Array<Int> = []; for (i in 0...rc) rbFo.push(r.u32());
        final rbFc:Array<Int> = []; for (i in 0...rc) rbFc.push(r.u32());
        final rbAs:Array<Float> = []; for (i in 0...rc) rbAs.push(r.f64());
        final rubyFam:Array<Int> = []; for (i in 0...rft) rubyFam.push(r.u32());
        final rubys:Array<Plan.PlanRuby> = [];
        for (i in 0...rc) {
            final fams:Array<String> = [];
            for (k in 0...rbFc[i]) fams.push(pool[rubyFam[rbFo[i] + k]]);
            rubys.push({baseRangeStart: rbS[i], baseRangeEnd: rbE[i], text: pool[rbT[i]],
                centerX: rbCx[i], baselineY: rbBy[i], fontSize: rbFs[i], fontWeight: rbFw[i],
                fontFamilies: fams, ascent: Math.isNaN(rbAs[i]) ? null : rbAs[i]});
        }
        // Bopomofo columns (column-major), family pool, then placement columns
        final bbS:Array<Int> = []; for (i in 0...bc) bbS.push(r.u32());
        final bbE:Array<Int> = []; for (i in 0...bc) bbE.push(r.u32());
        final bbT:Array<Int> = []; for (i in 0...bc) bbT.push(r.u32());
        final bbFw:Array<Int> = []; for (i in 0...bc) bbFw.push(r.u32());
        final bbFo:Array<Int> = []; for (i in 0...bc) bbFo.push(r.u32());
        final bbFc:Array<Int> = []; for (i in 0...bc) bbFc.push(r.u32());
        final bbPo:Array<Int> = []; for (i in 0...bc) bbPo.push(r.u32());
        final bbPc:Array<Int> = []; for (i in 0...bc) bbPc.push(r.u32());
        final bopoFam:Array<Int> = []; for (i in 0...bft) bopoFam.push(r.u32());
        final bpT:Array<Int> = []; for (i in 0...bpt) bpT.push(r.u32());
        final bpR:Array<Int> = []; for (i in 0...bpt) bpR.push(r.u32());
        final bpL:Array<Float> = []; for (i in 0...bpt) bpL.push(r.f64());
        final bpT2:Array<Float> = []; for (i in 0...bpt) bpT2.push(r.f64());
        final bpW:Array<Float> = []; for (i in 0...bpt) bpW.push(r.f64());
        final bpH:Array<Float> = []; for (i in 0...bpt) bpH.push(r.f64());
        final bopos:Array<Plan.PlanBopomofo> = [];
        for (i in 0...bc) {
            final fams:Array<String> = [];
            for (k in 0...bbFc[i]) fams.push(pool[bopoFam[bbFo[i] + k]]);
            final placements:Array<Plan.PlanBopomofoPlacement> = [];
            for (k in 0...bbPc[i]) {
                final pidx = bbPo[i] + k;
                placements.push({text: pool[bpT[pidx]], role: pool[bpR[pidx]],
                    left: bpL[pidx], top: bpT2[pidx], width: bpW[pidx], height: bpH[pidx]});
            }
            bopos.push({baseRangeStart: bbS[i], baseRangeEnd: bbE[i], text: pool[bbT[i]],
                fontWeight: bbFw[i], fontFamilies: fams, placements: placements});
        }
        // Decoration
        final decos:Array<Plan.PlanDecorationSegment> = [];
        for (i in 0...dsc) {
            final kr = r.u32();
            decos.push({kind: pool[kr], left: r.f64(), top: r.f64(), right: r.f64(), sourceRangeStart: 0, sourceRangeEnd: 0});
        }
        // Emphasis dots
        final dots:Array<Plan.PlanEmphasisDot> = [];
        for (i in 0...edc) {
            final ds = r.f64();
            dots.push({clusterRangeStart: Math.isNaN(ds) ? null : ds,
                anchorX: r.f64(), anchorY: r.f64(), dotDiameter: r.f64()});
        }
        // Spacing carrier advances
        final sca = r.u32();
        final scS:Array<Int> = []; for (i in 0...sca) scS.push(r.u32());
        final scE:Array<Int> = []; for (i in 0...sca) scE.push(r.u32());
        final scA:Array<Float> = []; for (i in 0...sca) scA.push(r.f64());
        final carriers:Array<Plan.PlanSpacingCarrierAdvance> = [];
        for (i in 0...sca) carriers.push({rangeStart: scS[i], rangeEnd: scE[i], advance: scA[i]});
        if (r.failed) return null;

        return {
            width: width, height: height,
            lines: lines,
            emphasisRanges: emphasis, inlineEdges: edges,
            rubyDecisions: rubys, bopomofoDecisions: bopos,
            fontSize: Math.isNaN(fontSz) ? null : fontSz,
            overlayWidth: Math.isNaN(overlayW) ? null : overlayW,
            decorationSegments: decos, emphasisDots: dots,
            spacingCarrierAdvances: carriers,
        };
    }
}