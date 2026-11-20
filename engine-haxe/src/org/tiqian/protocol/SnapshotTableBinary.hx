package org.tiqian.protocol;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.FPHelper;

/**
 * The snapshot-table binary form (TIQTBL03, ADR 0052 BundleLayering),
 * single-sourced in Haxe and generated for TypeScript and Rust. The byte
 * contract follows the existing implementations, which are the authority:
 * snapshot_table_binary.rs:9-35 for the region order and the 56-byte header
 * (magic plus twelve u32 counts), snapshot-table-binary.ts:8-13 for the
 * constants, table-binary-writer.ts:200-253 for the encoder region order.
 * Little-endian throughout; delta regions are u32 row byte lengths summed
 * from an implicit zero (snapshot-table-binary.ts:132-147).
 *
 * The unified Reader/Writer pair is symmetric (research doc 6.2): TableWriter
 * and TableReader mirror each other primitive for primitive, and the inverse
 * properties close inside SnapshotTableBinaryTest (write-read-read-write and
 * the golden hex vector). Exit languages carry zero hand-written read or
 * write code; they replay the same golden vector.
 *
 * Boundary ruling (Stage1-P2): the Haxe module owns the container only.
 * The four JSON text regions (face, typography, valueStyle, fontPreload) and
 * the revision tail ride as pre-serialized text; JSON production and parsing
 * stay in the platform shells.
 */
@:mainOnly
class SnapshotTableBinary {
    public static inline var MAGIC:String = "TIQTBL03";
    public static inline var HEADER_U32_COUNT:Int = 12;
    public static inline var METRIC_POOL_ROW_BYTES:Int = 40;
    public static inline var PROBE_STYLE_ROW_BYTES:Int = 25;
    public static inline var ABSENT_HIGH:Int = 0x7ff80000;
    public static inline var ABSENT_LOW:Int = 0;

    public static function encode(table:TableInput):Bytes {
        return encodeData(lower(table));
    }

    public static function encodeData(data:TableData):Bytes {
        final writer = new TableWriter();
        writer.raw(Bytes.ofString(MAGIC));
        writer.u32(data.replayStringCount);
        writer.u32(data.strings.length);
        writer.u32(data.metricRows.length);
        writer.u32(data.valuePool.length);
        writer.u32(data.probeTextRefs.length);
        writer.u32(data.advancePool.length);
        writer.u32(data.styleFontSize.length);
        writer.u32(data.featuresPool.length);
        writer.u32(data.faceTexts.length);
        writer.u32(data.typographyTexts.length);
        writer.u32(data.valueStyleTexts.length);
        writer.u32(data.fontPreloadTexts.length);
        writeTextRegion(writer, data.strings);
        var indexIdx:Int = 0;
        while (indexIdx < data.metricRows.length) {
            writer.u32(data.metricRows[indexIdx].familiesRef);
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < data.metricRows.length) {
            writer.f64(data.metricRows[indexIdx].weight);
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < data.metricRows.length) {
            writer.u8(data.metricRows[indexIdx].italic);
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < data.metricRows.length) {
            writer.u32(data.metricRows[indexIdx].roleRef);
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < data.metricRows.length) {
            writer.u32(data.metricRows[indexIdx].faceSelectionRef);
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < data.metricRows.length) {
            writer.u32(data.metricRows[indexIdx].valuePoolRef);
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < data.valuePool.length) {
            writeValueRow(writer, data.valuePool[indexIdx]);
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < data.probeTextRefs.length) {
            writer.u32(data.probeTextRefs[indexIdx]);
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < data.probeAdvanceRefs.length) {
            writer.u16(data.probeAdvanceRefs[indexIdx]);
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < data.probeStyleRefs.length) {
            writer.u16(data.probeStyleRefs[indexIdx]);
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < data.probeFeatureRefs.length) {
            writer.u16(data.probeFeatureRefs[indexIdx]);
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < data.advancePool.length) {
            writer.f64(data.advancePool[indexIdx]);
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < data.styleFontSize.length) {
            writer.f64(data.styleFontSize[indexIdx]);
            writer.f64(data.styleFontWeight[indexIdx]);
            writer.u8(data.styleItalic[indexIdx]);
            writer.u32(data.styleScriptRefs[indexIdx]);
            writer.u32(data.styleLanguageRefs[indexIdx]);
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < data.featuresPool.length) {
            writer.u32(featureRowBytes(data.featuresPool[indexIdx]).length);
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < data.featuresPool.length) {
            writer.raw(featureRowBytes(data.featuresPool[indexIdx]));
            indexIdx++;
        }
        writeTextRegion(writer, data.faceTexts);
        writeTextRegion(writer, data.typographyTexts);
        writeTextRegion(writer, data.valueStyleTexts);
        writeTextRegion(writer, data.fontPreloadTexts);
        writer.raw(Bytes.ofString(data.revisionText));
        return writer.finish();
    }
    /**
     * Decodes into the caller-provided stored form and returns "" on
     * success, or the named issue. The out-parameter form keeps the enum
     * payload out of the exit languages' derive/Debug surface.
     */
    public static function decodeInto(bytes:Bytes, data:TableData):String {
        final reader = new TableReader(bytes);
        if (!reader.matchMagic()) {
            return reader.issue;
        }
        data.replayStringCount = reader.u32();
        final stringCount = reader.u32();
        final metricCount = reader.u32();
        final valuePoolCount = reader.u32();
        final probeCount = reader.u32();
        final advancePoolCount = reader.u32();
        final stylePoolCount = reader.u32();
        final featuresPoolCount = reader.u32();
        final faceCount = reader.u32();
        final typographyCount = reader.u32();
        final valueStyleCount = reader.u32();
        final fontPreloadCount = reader.u32();
        data.strings = reader.textRegion(stringCount);
        // Column-major reads into locals first, then one assembled row per
        // metric: no in-place field mutation through array indexing (the
        // Rust target lowers indexed field assignment to a discarded clone).
        final famRefs = new Array<Int>();
        final weights = new Array<Float>();
        final italics = new Array<Int>();
        final roleRefs = new Array<Int>();
                final faceSelRefs = new Array<Int>();
        final poolRefs = new Array<Int>();
        var colIdx:Int = 0;
        while (colIdx < metricCount) {
            famRefs.push(reader.u32());
            colIdx++;
        }
        colIdx = 0;
        while (colIdx < metricCount) {
            weights.push(reader.f64());
            colIdx++;
        }
        colIdx = 0;
        while (colIdx < metricCount) {
            italics.push(reader.u8());
            colIdx++;
        }
        colIdx = 0;
        while (colIdx < metricCount) {
            roleRefs.push(reader.u32());
            colIdx++;
        }
        colIdx = 0;
        while (colIdx < metricCount) {
            faceSelRefs.push(reader.u32());
            colIdx++;
        }
        colIdx = 0;
        while (colIdx < metricCount) {
            poolRefs.push(reader.u32());
            colIdx++;
        }
        colIdx = 0;
        while (colIdx < metricCount) {
            data.metricRows.push(new MetricEntry(famRefs[colIdx], weights[colIdx], italics[colIdx],
                roleRefs[colIdx], faceSelRefs[colIdx], poolRefs[colIdx]));
            colIdx++;
        }
        var indexIdx:Int = 0;
        while (indexIdx < valuePoolCount) {
            data.valuePool.push(readValueRow(reader));
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < probeCount) {
            data.probeTextRefs.push(reader.u32());
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < probeCount) {
            data.probeAdvanceRefs.push(reader.u16());
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < probeCount) {
            data.probeStyleRefs.push(reader.u16());
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < probeCount) {
            data.probeFeatureRefs.push(reader.u16());
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < advancePoolCount) {
            data.advancePool.push(reader.f64());
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < stylePoolCount) {
            data.styleFontSize.push(reader.f64());
            data.styleFontWeight.push(reader.f64());
            data.styleItalic.push(reader.u8());
            data.styleScriptRefs.push(reader.u32());
            data.styleLanguageRefs.push(reader.u32());
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < featuresPoolCount) {
            reader.u32();
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < featuresPoolCount) {
            data.featuresPool.push(reader.featureRow());
            indexIdx++;
        }
        data.faceTexts = reader.textRegion(faceCount);
        data.typographyTexts = reader.textRegion(typographyCount);
        data.valueStyleTexts = reader.textRegion(valueStyleCount);
        data.fontPreloadTexts = reader.textRegion(fontPreloadCount);
        if (reader.failed) {
            return reader.issue;
        }
        data.revisionText = reader.restText();
        if (reader.failed) {
            return reader.issue;
        }
        return "";
    }

    public static function sortMetricRows(rows:Array<MetricEntry>):Array<MetricEntry> {
        var writeIdx:Int = 1;
        while (writeIdx < rows.length) {
            final record = rows[writeIdx];
            var readIdx:Int = writeIdx - 1;
            while (readIdx >= 0 && metricBefore(record, rows[readIdx])) {
                rows[readIdx + 1] = rows[readIdx];
                readIdx--;
            }
            rows[readIdx + 1] = record;
            writeIdx++;
        }
        return rows;
    }

    static function metricBefore(a:MetricEntry, b:MetricEntry):Bool {
        if (a.familiesRef != b.familiesRef) {
            return a.familiesRef < b.familiesRef;
        }
        if (a.weight < b.weight) {
            return true;
        }
        if (b.weight < a.weight) {
            return false;
        }
        if (a.italic != b.italic) {
            return a.italic < b.italic;
        }
        if (a.roleRef != b.roleRef) {
            return a.roleRef < b.roleRef;
        }
        return a.faceSelectionRef < b.faceSelectionRef;
    }

    static function lower(table:TableInput):TableData {
        final data = new TableData();
        data.replayStringCount = table.replayStrings.length;
        final interner = new StringInterner(table.replayStrings);
        var indexIdx:Int = 0;
        final metricEntries = new Array<MetricEntry>();
        while (indexIdx < table.metrics.length) {
            final row = table.metrics[indexIdx];
            final entry = new MetricEntry(interner.intern(row.serializedFamilies), row.fontWeight,
                row.italic ? 1 : 0, interner.intern(row.role), interner.intern(row.faceSelectionText), 0);
            entry.valuesEm = row.valuesEm;
            metricEntries.push(entry);
            indexIdx++;
        }
        sortMetricRows(metricEntries);
        final valuePool = new Array<ValueRow>();
        final pooled = new Array<MetricEntry>();
        indexIdx = 0;
        while (indexIdx < metricEntries.length) {
            final sorted = metricEntries[indexIdx];
            pooled.push(new MetricEntry(sorted.familiesRef, sorted.weight, sorted.italic,
                sorted.roleRef, sorted.faceSelectionRef, poolRefOf(valuePool, sorted.valuesEm)));
            indexIdx++;
        }
        data.metricRows = pooled;
        data.valuePool = valuePool;
        final advancePool = new Array<Float>();
        final stylePool = new Array<StyleRow>();
        final featuresPool = new Array<Array<Int>>();
        indexIdx = 0;
        while (indexIdx < table.probes.length) {
            final probe = table.probes[indexIdx];
            final textRef = interner.intern(probe.text);
            final scriptRef = interner.intern(probe.script);
            final languageRef = interner.intern(probe.language);
            final featureRefs = new Array<Int>();
            var featureIdx:Int = 0;
            while (featureIdx < probe.features.length) {
                featureRefs.push(interner.intern(probe.features[featureIdx]));
                featureIdx++;
            }
            data.probeTextRefs.push(textRef);
            data.probeAdvanceRefs.push(pooledFloat(advancePool, probe.advancePx));
            data.probeStyleRefs.push(pooledStyle(stylePool, probe, scriptRef, languageRef));
            data.probeFeatureRefs.push(pooledFeatures(featuresPool, featureRefs));
            indexIdx++;
        }
        data.advancePool = advancePool;
        data.featuresPool = featuresPool;
        data.styleFontSize = new Array<Float>();
        data.styleFontWeight = new Array<Float>();
        data.styleItalic = new Array<Int>();
        data.styleScriptRefs = new Array<Int>();
        data.styleLanguageRefs = new Array<Int>();
        var styleIdx:Int = 0;
        while (styleIdx < stylePool.length) {
            data.styleFontSize.push(stylePool[styleIdx].fontSizePx);
            data.styleFontWeight.push(stylePool[styleIdx].fontWeight);
            data.styleItalic.push(stylePool[styleIdx].italic);
            data.styleScriptRefs.push(stylePool[styleIdx].scriptRef);
            data.styleLanguageRefs.push(stylePool[styleIdx].languageRef);
            styleIdx++;
        }
        data.strings = interner.strings;
        data.faceTexts = copyTexts(table.faces);
        data.typographyTexts = copyTexts(table.typographies);
        data.valueStyleTexts = copyTexts(table.valueStyles);
        data.fontPreloadTexts = copyTexts(table.fontPreloads);
        data.revisionText = table.revisionsText;
        return data;
    }
    static function copyTexts(texts:Array<String>):Array<String> {
        final out = new Array<String>();
        var indexIdx:Int = 0;
        while (indexIdx < texts.length) {
            out.push(texts[indexIdx]);
            indexIdx++;
        }
        return out;
    }

    static function poolRefOf(pool:Array<ValueRow>, values:Array<Null<Float>>):Int {
        var indexIdx:Int = 0;
        while (indexIdx < pool.length) {
            if (sameValues(pool[indexIdx].values, values)) {
                return indexIdx;
            }
            indexIdx++;
        }
        pool.push(new ValueRow(values));
        return pool.length - 1;
    }

    static function sameValues(a:Array<Null<Float>>, b:Array<Null<Float>>):Bool {
        if (a.length != b.length) {
            return false;
        }
        var indexIdx:Int = 0;
        while (indexIdx < a.length) {
            final left = a[indexIdx];
            final right = b[indexIdx];
            if (left == null && right == null) {
                indexIdx++;
                continue;
            }
            if (left == null || right == null) {
                return false;
            }
            if (left != right) {
                return false;
            }
            indexIdx++;
        }
        return true;
    }

    static function f64BitsEqual(a:Float, b:Float):Bool {
        final ab = FPHelper.doubleToI64(a);
        final bb = FPHelper.doubleToI64(b);
        return ab.high == bb.high && ab.low == bb.low;
    }

    static function pooledFloat(pool:Array<Float>, value:Float):Int {
        var indexIdx:Int = 0;
        while (indexIdx < pool.length) {
            if (f64BitsEqual(pool[indexIdx], value)) {
                return indexIdx;
            }
            indexIdx++;
        }
        pool.push(value);
        return pool.length - 1;
    }

    static function pooledStyle(pool:Array<StyleRow>, probe:TableProbe, scriptRef:Int, languageRef:Int):Int {
        var indexIdx:Int = 0;
        while (indexIdx < pool.length) {
            final row = pool[indexIdx];
            if (f64BitsEqual(row.fontSizePx, probe.fontSizePx)
                && f64BitsEqual(row.fontWeight, probe.fontWeight)
                && row.italic == (probe.italic ? 1 : 0)
                && row.scriptRef == scriptRef
                && row.languageRef == languageRef) {
                return indexIdx;
            }
            indexIdx++;
        }
        pool.push(new StyleRow(probe.fontSizePx, probe.fontWeight, probe.italic ? 1 : 0, scriptRef, languageRef));
        return pool.length - 1;
    }

    static function pooledFeatures(pool:Array<Array<Int>>, refs:Array<Int>):Int {
        var indexIdx:Int = 0;
        while (indexIdx < pool.length) {
            if (sameRefs(pool[indexIdx], refs)) {
                return indexIdx;
            }
            indexIdx++;
        }
        pool.push(refs);
        return pool.length - 1;
    }

    static function sameRefs(a:Array<Int>, b:Array<Int>):Bool {
        if (a.length != b.length) {
            return false;
        }
        var indexIdx:Int = 0;
        while (indexIdx < a.length) {
            if (a[indexIdx] != b[indexIdx]) {
                return false;
            }
            indexIdx++;
        }
        return true;
    }

    static function writeTextRegion(writer:TableWriter, texts:Array<String>):Void {
        var totalIdx:Int = 0;
        while (totalIdx < texts.length) {
            writer.u32(Bytes.ofString(texts[totalIdx]).length);
            totalIdx++;
        }
        totalIdx = 0;
        while (totalIdx < texts.length) {
            writer.raw(Bytes.ofString(texts[totalIdx]));
            totalIdx++;
        }
    }

    static function writeValueRow(writer:TableWriter, row:ValueRow):Void {
        var slotIdx:Int = 0;
        while (slotIdx < row.values.length) {
            final value = row.values[slotIdx];
            if (value == null) {
                writer.absentF64();
            } else {
                writer.f64(value);
            }
            slotIdx++;
        }
    }

    static function featureRowBytes(refs:Array<Int>):Bytes {
        final row = new TableWriter();
        row.u16(refs.length);
        var indexIdx:Int = 0;
        while (indexIdx < refs.length) {
            row.u32(refs[indexIdx]);
            indexIdx++;
        }
        return row.finish();
    }

    static function readValueRow(reader:TableReader):ValueRow {
        final values = new Array<Null<Float>>();
        var slotIdx:Int = 0;
        while (slotIdx < 5) {
            final low = reader.u32();
            final high = reader.u32();
            if (high == ABSENT_HIGH && low == ABSENT_LOW) {
                values.push(null);
            } else {
                // i64ToDouble(low, high) is the required form (samples/boring/BinaryReader.hx:40-44).
                values.push(FPHelper.i64ToDouble(low, high));
            }
            slotIdx++;
        }
        return new ValueRow(values);
    }

}

private class StringInterner {
    public final strings:Array<String>;

    public function new(replayStrings:Array<String>) {
        strings = new Array<String>();
        var indexIdx:Int = 0;
        while (indexIdx < replayStrings.length) {
            strings.push(replayStrings[indexIdx]);
            indexIdx++;
        }
    }

    public function intern(text:String):Int {
        var indexIdx:Int = 0;
        while (indexIdx < strings.length) {
            if (strings[indexIdx] == text) {
                return indexIdx;
            }
            indexIdx++;
        }
        strings.push(text);
        return strings.length - 1;
    }
}

/**
 * Grows the table buffer through BytesBuffer; every multi-byte integer is
 * little-endian and every f64 rides its IEEE 754 bit pattern low word first
 * (stdlib/02:11,15 ruling; same shape as the canonical Writer). No
 * BytesInput/BytesOutput endian methods.
 */
private class TableWriter {
    final buf:BytesBuffer;

    public function new() {
        buf = new BytesBuffer();
    }

    public function raw(bytes:Bytes):Void {
        var indexIdx:Int = 0;
        while (indexIdx < bytes.length) {
            buf.addByte(bytes.get(indexIdx));
            indexIdx++;
        }
    }

    public function u8(value:Int):Void {
        buf.addByte(value & 0xFF);
    }

    public function u16(value:Int):Void {
        buf.addByte(value & 0xFF);
        buf.addByte((value >>> 8) & 0xFF);
    }

    public function u32(value:Int):Void {
        buf.addByte(value & 0xFF);
        buf.addByte((value >>> 8) & 0xFF);
        buf.addByte((value >>> 16) & 0xFF);
        buf.addByte((value >>> 24) & 0xFF);
    }

    public function f64(value:Float):Void {
        final bits = FPHelper.doubleToI64(value);
        u32(bits.low);
        u32(bits.high);
    }

    public function absentF64():Void {
        u32(SnapshotTableBinary.ABSENT_LOW);
        u32(SnapshotTableBinary.ABSENT_HIGH);
    }

    public function finish():Bytes {
        return buf.getBytes();
    }
}

/**
 * The symmetric read side: a cursor over Bytes with an explicit failure
 * flag, so a truncated or damaged file surfaces as TErr instead of an
 * exception. Bounds checking lives in this extraction layer (stdlib/02:217).
 */
private class TableReader {
    final bytes:Bytes;
    var pos:Int;
    public var failed:Bool;
    public var issue:String;

    public function new(bytes:Bytes) {
        this.bytes = bytes;
        pos = 0;
        failed = false;
        issue = "";
    }

    public function u8():Int {
        if (!need(1)) {
            return 0;
        }
        final value = bytes.get(pos);
        pos += 1;
        return value;
    }

    public function u16():Int {
        if (!need(2)) {
            return 0;
        }
        final value = bytes.get(pos) | (bytes.get(pos + 1) << 8);
        pos += 2;
        return value;
    }

    public function u32():Int {
        if (!need(4)) {
            return 0;
        }
        final value = (bytes.get(pos) | (bytes.get(pos + 1) << 8) | (bytes.get(pos + 2) << 16))
            + (bytes.get(pos + 3) * 0x1000000);
        pos += 4;
        return value;
    }

    public function f64():Float {
        final low = u32();
        final high = u32();
        if (failed) {
            return 0.0;
        }
        // i64ToDouble(low, high) is the required form (samples/boring/BinaryReader.hx:40-44).
        return FPHelper.i64ToDouble(low, high);
    }

    /** Compares the next 8 bytes against the expected magic; consumes them on match. */
    public function matchMagic():Bool {
        if (!need(8)) {
            return false;
        }
        final expected = Bytes.ofString(SnapshotTableBinary.MAGIC);
        var indexIdx:Int = 0;
        while (indexIdx < 8) {
            if (bytes.get(pos + indexIdx) != expected.get(indexIdx)) {
                failed = true;
                issue = "SnapshotTablesInvalid";
                return false;
            }
            indexIdx++;
        }
        pos += 8;
        return true;
    }

    public function featureRow():Array<Int> {
        final refs = new Array<Int>();
        final count = u16();
        if (failed) {
            return refs;
        }
        var indexIdx:Int = 0;
        while (indexIdx < count) {
            refs.push(u32());
            indexIdx++;
        }
        return refs;
    }

    public function textRegion(count:Int):Array<String> {
        final texts = new Array<String>();
        if (failed) {
            return texts;
        }
        final lengths = new Array<Int>();
        var running:Int = 0;
        var indexIdx:Int = 0;
        while (indexIdx < count) {
            final delta = u32();
            if (failed) {
                return texts;
            }
            running += delta;
            if (running < 0 || pos + running > bytes.length) {
                failed = true;
                issue = "SnapshotTablesInvalid";
                return texts;
            }
            lengths.push(delta);
            indexIdx++;
        }
        indexIdx = 0;
        while (indexIdx < lengths.length) {
            texts.push(bytes.getString(pos, lengths[indexIdx]));
            pos += lengths[indexIdx];
            indexIdx++;
        }
        return texts;
    }

    public function restText():String {
        if (!need(0)) {
            return "";
        }
        final value = bytes.getString(pos, bytes.length - pos);
        pos = bytes.length;
        return value;
    }

    function need(length:Int):Bool {
        if (failed) {
            return false;
        }
        if (length < 0 || pos + length > bytes.length) {
            failed = true;
            issue = "SnapshotTablesInvalid";
            return false;
        }
        return true;
    }
}