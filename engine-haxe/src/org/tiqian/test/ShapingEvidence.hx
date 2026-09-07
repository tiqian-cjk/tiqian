package org.tiqian.test;

import org.tiqian.core.Cluster;
import org.tiqian.core.Glyph;
import org.tiqian.core.GlyphRun;
import org.tiqian.core.Rect;
import org.tiqian.core.ShapingDecisionInfo;
import org.tiqian.core.TextRangeError;
import org.tiqian.core.TiqianIllegalArgumentException;
import org.tiqian.font.FontMetricSource;
import org.tiqian.font.FontMetrics.FontMetricsRequest;
import org.tiqian.font.FontMetrics.FontMetricsResolver;
import org.tiqian.font.RawFontMetrics;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.shaping.TextShaper.ITextShaper;
import std.SortedMap;

@:dataClass
class ShapingEvidenceEntry {
    public final key:ShapingEvidenceKey;
    public final result:RecordedShapingResult;

    public function new(key:ShapingEvidenceKey, result:RecordedShapingResult) {
        this.key = key;
        this.result = result;
    }
}

@:dataClass
class MetricsEvidenceEntry {
    public final key:MetricsEvidenceKey;
    public final result:RecordedFontMetrics;

    public function new(key:MetricsEvidenceKey, result:RecordedFontMetrics) {
        this.key = key;
        this.result = result;
    }
}

@:dataClass
class ShapingEvidence {
    public final meta:SortedMap<String, String>;
    public final shaping:Array<ShapingEvidenceEntry>;
    public final metrics:Array<MetricsEvidenceEntry>;

    public function new(meta:SortedMap<String, String>, shaping:Array<ShapingEvidenceEntry>, metrics:Array<MetricsEvidenceEntry>) {
        this.meta = meta;
        this.shaping = shaping;
        this.metrics = metrics;
    }
}

@:dataClass
class ShapingEvidenceKey {
    public final displayText:String;
    public final fontKey:String;
    public final fontFamily:String;
    public final role:String;
    public final styleFontFamilies:std.ReadOnlyArray<String>;
    public final fontSize:Float;
    public final fontWeight:Int;
    public final italic:Bool;
    public final locale:String;
    public final openTypeFeatures:std.ReadOnlyArray<String>;

    public function new(displayText:String, fontKey:String, fontFamily:String, role:String, styleFontFamilies:std.ReadOnlyArray<String>, fontSize:Float,
            fontWeight:Int, italic:Bool, locale:String, openTypeFeatures:std.ReadOnlyArray<String>) {
        this.displayText = displayText;
        this.fontKey = fontKey;
        this.fontFamily = fontFamily;
        this.role = role;
        this.styleFontFamilies = styleFontFamilies;
        this.fontSize = fontSize;
        this.fontWeight = fontWeight;
        this.italic = italic;
        this.locale = locale;
        this.openTypeFeatures = openTypeFeatures;
    }
}

class ShapingEvidenceFns {
    public static function shapingInputToEvidenceKey(input:ShapingInput):ShapingEvidenceKey {
        return new ShapingEvidenceKey(input.displayText, input.fontDecision.candidate.key, input.fontDecision.candidate.family,
            Std.string(input.fontDecision.role), input.style.fontFamilies, input.style.fontSize, input.style.fontWeight, input.style.italic,
            input.style.locale, input.openTypeFeatures);
    }

    public static function shapingResult(evidence:ShapingEvidence, key:ShapingEvidenceKey):Null<RecordedShapingResult> {
        for (i in 0...evidence.shaping.length) {
            if (shapingKeyEquals(evidence.shaping[i].key, key))
                return evidence.shaping[i].result;
        }
        return null;
    }

    public static function shapingKeyEquals(a:ShapingEvidenceKey, b:ShapingEvidenceKey):Bool {
        if (a == b)
            return true;
        if (a.displayText != b.displayText)
            return false;
        if (a.fontKey != b.fontKey)
            return false;
        if (a.fontFamily != b.fontFamily)
            return false;
        if (a.role != b.role)
            return false;
        if (!stringArrayEquals(a.styleFontFamilies, b.styleFontFamilies))
            return false;
        if (a.fontSize != b.fontSize)
            return false;
        if (a.fontWeight != b.fontWeight)
            return false;
        if (a.italic != b.italic)
            return false;
        if (a.locale != b.locale)
            return false;
        if (!stringArrayEquals(a.openTypeFeatures, b.openTypeFeatures))
            return false;
        return true;
    }

    public static function stringArrayEquals(a:std.ReadOnlyArray<String>, b:std.ReadOnlyArray<String>):Bool {
        if (a.length != b.length)
            return false;
        for (i in 0...a.length) {
            if (a[i] != b[i])
                return false;
        }
        return true;
    }
}

@:dataClass
class RecordedGlyph {
    public final id:Int;
    public final advance:Float;
    public final x:Float;
    public final y:Float;
    public final bounds:Null<Rect>;
    public final haltAdvance:Null<Float>;
    public final haltPlacementX:Null<Float>;

    public function new(id:Int, advance:Float, x:Float, y:Float, bounds:Null<Rect>, haltAdvance:Null<Float>, haltPlacementX:Null<Float>) {
        this.id = id;
        this.advance = advance;
        this.x = x;
        this.y = y;
        this.bounds = bounds;
        this.haltAdvance = haltAdvance;
        this.haltPlacementX = haltPlacementX;
    }
}

@:dataClass
class RecordedShapingDecision {
    public final glyphCount:Int;
    public final advance:Float;
    public final source:String;
    public final reason:String;
    public final glyphsWithoutInkBounds:Int;
    public final missingGlyphs:Int;
    public final resolvedFace:Null<String>;
    public final script:Null<String>;
    public final language:Null<String>;
    public final strategy:Null<String>;
    public final featureEvidence:Null<String>;
    public final capabilityIssue:Null<String>;

    public function new(glyphCount:Int, advance:Float, source:String, reason:String, glyphsWithoutInkBounds:Int, missingGlyphs:Int, resolvedFace:Null<String>,
            script:Null<String>, language:Null<String>, strategy:Null<String>, featureEvidence:Null<String>, capabilityIssue:Null<String>) {
        this.glyphCount = glyphCount;
        this.advance = advance;
        this.source = source;
        this.reason = reason;
        this.glyphsWithoutInkBounds = glyphsWithoutInkBounds;
        this.missingGlyphs = missingGlyphs;
        this.resolvedFace = resolvedFace;
        this.script = script;
        this.language = language;
        this.strategy = strategy;
        this.featureEvidence = featureEvidence;
        this.capabilityIssue = capabilityIssue;
    }
}

@:dataClass
class RecordedShapingResult {
    public final clusterAdvance:Float;
    public final runAdvance:Float;
    public final runFeatures:Array<String>;
    public final glyphs:Array<RecordedGlyph>;
    public final decisions:Array<RecordedShapingDecision>;

    public function new(clusterAdvance:Float, runAdvance:Float, runFeatures:Array<String>, glyphs:Array<RecordedGlyph>,
            decisions:Array<RecordedShapingDecision>) {
        this.clusterAdvance = clusterAdvance;
        this.runAdvance = runAdvance;
        this.runFeatures = runFeatures;
        this.glyphs = glyphs;
        this.decisions = decisions;
    }
}

@:dataClass
class MetricsEvidenceKey {
    public final fontKey:String;
    public final fontSize:Float;
    public final role:String;
    public final locale:String;
    public final fontFamilies:std.ReadOnlyArray<String>;
    public final fontWeight:Int;
    public final italic:Bool;
    public final faceSelectionText:String;

    public function new(fontKey:String, fontSize:Float, role:String, locale:String, fontFamilies:std.ReadOnlyArray<String>, fontWeight:Int, italic:Bool,
            faceSelectionText:String) {
        this.fontKey = fontKey;
        this.fontSize = fontSize;
        this.role = role;
        this.locale = locale;
        this.fontFamilies = fontFamilies;
        this.fontWeight = fontWeight;
        this.italic = italic;
        this.faceSelectionText = faceSelectionText;
    }
}

class MetricsEvidenceFns {
    public static function fontMetricsRequestToEvidenceKey(request:FontMetricsRequest):MetricsEvidenceKey {
        return new MetricsEvidenceKey(request.fontKey, request.fontSize, Std.string(request.role), request.locale, request.fontFamilies, request.fontWeight,
            request.italic, request.faceSelectionText);
    }

    public static function metricsResult(evidence:ShapingEvidence, key:MetricsEvidenceKey):Null<RecordedFontMetrics> {
        for (i in 0...evidence.metrics.length) {
            if (metricsKeyEquals(evidence.metrics[i].key, key))
                return evidence.metrics[i].result;
        }
        return null;
    }

    public static function metricsKeyEquals(a:MetricsEvidenceKey, b:MetricsEvidenceKey):Bool {
        if (a == b)
            return true;
        if (a.fontKey != b.fontKey)
            return false;
        if (a.fontSize != b.fontSize)
            return false;
        if (a.role != b.role)
            return false;
        if (a.locale != b.locale)
            return false;
        if (!ShapingEvidenceFns.stringArrayEquals(a.fontFamilies, b.fontFamilies))
            return false;
        if (a.fontWeight != b.fontWeight)
            return false;
        if (a.italic != b.italic)
            return false;
        if (a.faceSelectionText != b.faceSelectionText)
            return false;
        return true;
    }
}

@:dataClass
class RecordedFontMetrics {
    public final ascent:Float;
    public final descent:Float;
    public final leading:Float;
    public final source:String;
    public final typoAscent:Null<Float>;
    public final typoDescent:Null<Float>;

    public function new(ascent:Float, descent:Float, leading:Float, source:String, typoAscent:Null<Float>, typoDescent:Null<Float>) {
        this.ascent = ascent;
        this.descent = descent;
        this.leading = leading;
        this.source = source;
        this.typoAscent = typoAscent;
        this.typoDescent = typoDescent;
    }

    public function toRawFontMetrics():RawFontMetrics {
        var sourceValue:Null<FontMetricSource> = null;
        if (source == "RawTables") {
            sourceValue = RawTables;
        } else if (source == "OpenTypeBase") {
            sourceValue = OpenTypeBase;
        } else if (source == "GlyphSampling") {
            sourceValue = GlyphSampling;
        } else if (source == "ManualOverride") {
            sourceValue = ManualOverride;
        } else if (source == "SynthesizedIdeographicBox") {
            sourceValue = SynthesizedIdeographicBox;
        }
        if (sourceValue == null) {
            throw new TiqianIllegalArgumentException(TextRangeError.Message("Unknown font metric source: " + source));
        }
        return new RawFontMetrics(ascent, descent, leading, sourceValue, typoAscent, typoDescent);
    }
}

class RecordedEvidenceTextShaper implements ITextShaper {
    private final evidence:ShapingEvidence;

    public function new(evidence:ShapingEvidence) {
        this.evidence = evidence;
    }

    public function shape(input:ShapingInput):ShapingResult {
        final key = ShapingEvidenceFns.shapingInputToEvidenceKey(input);
        final recorded = ShapingEvidenceFns.shapingResult(evidence, key);
        if (recorded == null) {
            throw new TiqianIllegalArgumentException(TextRangeError.Message("No recorded shaping evidence for "
                + Std.string(key)
                + " — re-record on the JVM with "
                + "TIQIAN_RECORD_SHAPING=1 ./gradlew :engine:jvmTest --tests '*ShapingEvidenceRecorder*'"));
        }
        final sourceText = input.text.substring(input.range.start, input.range.end);
        final fontKey = input.fontDecision.candidate.key;
        final cluster = new Cluster(input.range, sourceText, fontKey, recorded.clusterAdvance, input.displayText);
        final glyphs:Array<Glyph> = [];
        for (g in recorded.glyphs) {
            glyphs.push(new Glyph(g.id, input.range, g.advance, g.x, g.y, null, g.bounds, g.haltAdvance, g.haltPlacementX));
        }
        final run = new GlyphRun(input.range, fontKey, glyphs, recorded.runAdvance, recorded.runFeatures);
        final decisions:Array<ShapingDecisionInfo> = [];
        for (d in recorded.decisions) {
            decisions.push(new ShapingDecisionInfo(input.range, sourceText, input.displayText, fontKey, d.glyphCount, d.advance, d.source, d.reason,
                d.glyphsWithoutInkBounds, d.missingGlyphs, d.resolvedFace, d.script, d.language, d.strategy, d.featureEvidence, d.capabilityIssue));
        }
        return new ShapingResult([cluster], [run], decisions);
    }
}

class RecordedEvidenceFontMetricsResolver implements FontMetricsResolver {
    private final evidence:ShapingEvidence;

    public function new(evidence:ShapingEvidence) {
        this.evidence = evidence;
    }

    public function resolve(request:FontMetricsRequest):RawFontMetrics {
        final key = MetricsEvidenceFns.fontMetricsRequestToEvidenceKey(request);
        final recorded = MetricsEvidenceFns.metricsResult(evidence, key);
        if (recorded == null) {
            throw new TiqianIllegalArgumentException(TextRangeError.Message("No recorded font metrics evidence for "
                + Std.string(key)
                + " — re-record on the JVM with "
                + "TIQIAN_RECORD_SHAPING=1 ./gradlew :engine:jvmTest --tests '*ShapingEvidenceRecorder*'"));
        }
        return recorded.toRawFontMetrics();
    }
}
