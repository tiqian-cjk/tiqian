package org.tiqian.layout;

import org.tiqian.core.LayoutInput;
import org.tiqian.core.TextRange;
import org.tiqian.core.IntRange;
import org.tiqian.core.TextStyle;
import org.tiqian.core.RubySpan;
import org.tiqian.clreq.ClreqProfile;
import org.tiqian.clreq.ClreqPunctuationGlyphSubstitutor;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.core.Glyph;
import org.tiqian.core.RoleOverrideInfo;
import org.tiqian.core.BreakOpportunityDecisionInfo;
import org.tiqian.core.EmergencyTrackingEligibilityDecisionInfo;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.core.ShapingDecisionInfo;
import org.tiqian.core.AutoSpaceDecisionInfo;
import org.tiqian.core.Cluster;
import org.tiqian.core.InlineObjectSpan;
import org.tiqian.core.InlineObjectPreferredStretch;
import org.tiqian.font.FontRole;
import org.tiqian.layout.KinsokuRule.ClreqKinsokuRule;
import org.tiqian.layout.PunctuationGeometryStage.InlineObjectAttachedMark;
import org.tiqian.core.InlineObjectPunctuationAttachmentDecisionInfo;
import org.tiqian.core.MandatoryBreakDecisionInfo;
import org.tiqian.core.ZeroWidthBreakDecisionInfo;
import org.tiqian.core.InlineAttachment;
import org.tiqian.core.LineLengthGridDecisionInfo;
import org.tiqian.layout.LineGeometryStage.ClusterMetricDecision;
import org.tiqian.layout.LineGeometryStage.ResolvedLineMetrics;
import org.tiqian.core.LineSpacingDecisionInfo;
import org.tiqian.core.FirstLineIndentDecisionInfo;
import org.tiqian.core.KinsokuDecisionInfo;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.QuotePairAnalyzer.QuotePair;
import org.tiqian.layout.AnnotationGeometryStage.RubyFontGeometry;
import org.tiqian.layout.LineOptimization.LineSolution;
import org.tiqian.clreq.AdjustmentStylePolicy;
import org.tiqian.clreq.PunctuationClass;
import org.tiqian.layout.PunctuationModel.PunctuationAtom;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingCompressionResult;
import org.tiqian.layout.PunctuationGeometryLedger.AttachedInlinePunctuationBoundaryResult;
import org.tiqian.layout.PunctuationGeometryLedger;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.UnbreakableRanges;
import org.tiqian.layout.PunctuationGeometryStage.ContextualKinsoku;
import org.tiqian.layout.UnicodePunctuationBoundaryResolver;
import org.tiqian.layout.UnicodePunctuationBoundaryResolver.UnicodePunctuationBoundaries;
import org.tiqian.core.EastAsianSpacingEdges;
import org.tiqian.clreq.ResolvedKinsoku;
import org.tiqian.clreq.LineAdjustmentStrategy;
import org.tiqian.clreq.HangingPunctuationStyle;
import org.tiqian.clreq.NumberSymbolCohesion;
import org.tiqian.core.LineBreakPolicy;
import org.tiqian.core.DecorationKind;
import org.tiqian.font.MetricBox;
import org.tiqian.font.LayoutFontMetrics;
import org.tiqian.font.FontMetrics.FontMetricsNormalizationInput;
import org.tiqian.font.FontMetrics.FontMetricsRequest;
import org.tiqian.layout.PunctuationGeometryStage.InlineBoxApplicationResult;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.LineGeometryStage.LineGeometryStageFns;
import org.tiqian.layout.ParagraphShapingStage;
import org.tiqian.layout.PunctuationGeometryStage;
import org.tiqian.layout.PunctuationGeometryLedger;
import org.tiqian.core.TiqianIllegalArgumentException;
import std.SortedSet;
import std.SortedMap;

@:dataClass class ParagraphLayoutPrep {
    public final input:LayoutInput;
    public final rejectedTechnicalTiersBySpan:std.SortedMap<TextRange, std.SortedSet<Int>>;
    public final text:String;
    public final fontSize:Float;
    public final styleAt:Int->TextStyle;
    public final fontSizeAt:Int->Float;
    public final bopomofoFontWeightAt:Int->Int;
    public final rubyFontSize:Float;
    public final rubyStackGap:Float;
    public final rubyFontWeight:Int;
    public final pinyinSpans:Array<RubySpan>;
    public final clreqProfile:ClreqProfile;
    public final punctuationGlyphSubstitutor:ClreqPunctuationGlyphSubstitutor;
    public final measure:Float;
    public final measureEm:Float;
    public final gridBodyOffset:Float;
    public final lineLengthGridDecision:LineLengthGridDecisionInfo;
    public final quotePairs:Array<QuotePair>;
    public final roleOverrideInfos:Array<RoleOverrideInfo>;
    public final fontDecisions:Array<FontDecision>;
    public final hyphenOffsets:std.SortedSet<Int>;
    public final hyphenAdvance:Float;
    public final hyphenGlyphs:Array<Glyph>;
    public final substitutionRollbacks:std.SortedMap<TextRange, String>;
    public final breakOpportunityDecisions:Array<BreakOpportunityDecisionInfo>;
    public final emergencyTrackingEligibilityDecisions:Array<EmergencyTrackingEligibilityDecisionInfo>;
    public final progressiveBreakOffsets:std.SortedMap<Int, ProgressiveBreakOpportunity>;
    public final shapedGlyphsByClusterRange:std.SortedMap<TextRange, Array<Glyph>>;
    public final openTypeFeaturesByClusterRange:std.SortedMap<TextRange, Array<String>>;
    public final shapingDecisions:Array<ShapingDecisionInfo>;
    public final eastAsianSpacingEdges:Array<EastAsianSpacingEdges>;
    public final autoSpaceDecisions:Array<AutoSpaceDecisionInfo>;
    public final inlineBoxResult:InlineBoxApplicationResult;
    public final naturalClusters:Array<Cluster>;
    public final inlineObjectByClusterIndex:std.SortedMap<Int, InlineObjectSpan>;
    public final uniformInlineObjectBoundaryAfterClusters:std.SortedSet<Int>;
    public final preferredInlineObjectBoundaryAfterClusters:std.SortedMap<Int, InlineObjectPreferredStretch>;
    public final inlineObjectBoundaryUnbreakableRanges:Array<IntRange>;
    public final clusterRoles:Array<FontRole>;
    public final resolvedKinsoku:ResolvedKinsoku;
    public final kinsokuRule:ClreqKinsokuRule;
    public final inlineObjectAttachedMarks:Array<InlineObjectAttachedMark>;
    public final inlineObjectSeparatorSpaceTrims:std.SortedMap<Int, Float>;
    public final inlineObjectAttachmentNoStretchBoundaries:std.SortedSet<Int>;
    public final inlineObjectPunctuationAttachmentDecisions:Array<InlineObjectPunctuationAttachmentDecisionInfo>;
    public final mandatoryBreakClusters:std.SortedSet<Int>;
    public final zeroWidthBreakClusters:std.SortedSet<Int>;
    public final mandatoryBreakDecisions:Array<MandatoryBreakDecisionInfo>;
    public final zeroWidthBreakDecisions:Array<ZeroWidthBreakDecisionInfo>;
    public final punctuationAtoms:Array<PunctuationAtom>;
    public final spacingPlan:PunctuationSpacingCompressionResult;
    public final rubyFontGeometryBySpan:std.SortedMap<RubySpan, RubyFontGeometry>;
    public final rubyAndBopomofoSpread:std.SortedMap<Int, Float>;
    public final naturalInlineAttachments:Array<InlineAttachment>;
    public final attachedPunctuationBoundary:AttachedInlinePunctuationBoundaryResult;
    public final baseGeometry:PunctuationGeometryLedger;
    public final attachedPunctuationTrailingGlueByCluster:std.SortedMap<Int, Float>;
    public final clusters:Array<Cluster>;
    public final adjustmentStyle:AdjustmentStylePolicy;
    public final atomClassByRange:std.SortedMap<TextRange, PunctuationClass>;
    public final shrinkOpportunities:Array<ShrinkOpportunity>;

    public function new(input:LayoutInput, rejectedTechnicalTiersBySpan:std.SortedMap<TextRange, std.SortedSet<Int>>, text:String, fontSize:Float,
            styleAt:Int->TextStyle, fontSizeAt:Int->Float, bopomofoFontWeightAt:Int->Int, rubyFontSize:Float, rubyStackGap:Float, rubyFontWeight:Int,
            pinyinSpans:Array<RubySpan>, clreqProfile:ClreqProfile, punctuationGlyphSubstitutor:ClreqPunctuationGlyphSubstitutor, measure:Float,
            measureEm:Float, gridBodyOffset:Float, lineLengthGridDecision:LineLengthGridDecisionInfo, quotePairs:Array<QuotePair>,
            roleOverrideInfos:Array<RoleOverrideInfo>, fontDecisions:Array<FontDecision>, hyphenOffsets:std.SortedSet<Int>, hyphenAdvance:Float,
            hyphenGlyphs:Array<Glyph>, substitutionRollbacks:std.SortedMap<TextRange, String>, breakOpportunityDecisions:Array<BreakOpportunityDecisionInfo>,
            emergencyTrackingEligibilityDecisions:Array<EmergencyTrackingEligibilityDecisionInfo>,
            progressiveBreakOffsets:std.SortedMap<Int, ProgressiveBreakOpportunity>, shapedGlyphsByClusterRange:std.SortedMap<TextRange, Array<Glyph>>,
            openTypeFeaturesByClusterRange:std.SortedMap<TextRange, Array<String>>, shapingDecisions:Array<ShapingDecisionInfo>,
            eastAsianSpacingEdges:Array<EastAsianSpacingEdges>, autoSpaceDecisions:Array<AutoSpaceDecisionInfo>, inlineBoxResult:InlineBoxApplicationResult,
            naturalClusters:Array<Cluster>, inlineObjectByClusterIndex:std.SortedMap<Int, InlineObjectSpan>,
            uniformInlineObjectBoundaryAfterClusters:std.SortedSet<Int>,
            preferredInlineObjectBoundaryAfterClusters:std.SortedMap<Int, InlineObjectPreferredStretch>,
            inlineObjectBoundaryUnbreakableRanges:Array<IntRange>, clusterRoles:Array<FontRole>, resolvedKinsoku:ResolvedKinsoku,
            kinsokuRule:ClreqKinsokuRule, inlineObjectAttachedMarks:Array<InlineObjectAttachedMark>,
            inlineObjectSeparatorSpaceTrims:std.SortedMap<Int, Float>, inlineObjectAttachmentNoStretchBoundaries:std.SortedSet<Int>,
            inlineObjectPunctuationAttachmentDecisions:Array<InlineObjectPunctuationAttachmentDecisionInfo>, mandatoryBreakClusters:std.SortedSet<Int>,
            zeroWidthBreakClusters:std.SortedSet<Int>, mandatoryBreakDecisions:Array<MandatoryBreakDecisionInfo>,
            zeroWidthBreakDecisions:Array<ZeroWidthBreakDecisionInfo>, punctuationAtoms:Array<PunctuationAtom>,
            spacingPlan:PunctuationSpacingCompressionResult, rubyFontGeometryBySpan:std.SortedMap<RubySpan, RubyFontGeometry>,
            rubyAndBopomofoSpread:std.SortedMap<Int, Float>, naturalInlineAttachments:Array<InlineAttachment>,
            attachedPunctuationBoundary:AttachedInlinePunctuationBoundaryResult, baseGeometry:PunctuationGeometryLedger,
            attachedPunctuationTrailingGlueByCluster:std.SortedMap<Int, Float>, clusters:Array<Cluster>, adjustmentStyle:AdjustmentStylePolicy,
            atomClassByRange:std.SortedMap<TextRange, PunctuationClass>, shrinkOpportunities:Array<ShrinkOpportunity>) {
        this.input = input;
        this.rejectedTechnicalTiersBySpan = rejectedTechnicalTiersBySpan;
        this.text = text;
        this.fontSize = fontSize;
        this.styleAt = styleAt;
        this.fontSizeAt = fontSizeAt;
        this.bopomofoFontWeightAt = bopomofoFontWeightAt;
        this.rubyFontSize = rubyFontSize;
        this.rubyStackGap = rubyStackGap;
        this.rubyFontWeight = rubyFontWeight;
        this.pinyinSpans = pinyinSpans;
        this.clreqProfile = clreqProfile;
        this.punctuationGlyphSubstitutor = punctuationGlyphSubstitutor;
        this.measure = measure;
        this.measureEm = measureEm;
        this.gridBodyOffset = gridBodyOffset;
        this.lineLengthGridDecision = lineLengthGridDecision;
        this.quotePairs = quotePairs;
        this.roleOverrideInfos = roleOverrideInfos;
        this.fontDecisions = fontDecisions;
        this.hyphenOffsets = hyphenOffsets;
        this.hyphenAdvance = hyphenAdvance;
        this.hyphenGlyphs = hyphenGlyphs;
        this.substitutionRollbacks = substitutionRollbacks;
        this.breakOpportunityDecisions = breakOpportunityDecisions;
        this.emergencyTrackingEligibilityDecisions = emergencyTrackingEligibilityDecisions;
        this.progressiveBreakOffsets = progressiveBreakOffsets;
        this.shapedGlyphsByClusterRange = shapedGlyphsByClusterRange;
        this.openTypeFeaturesByClusterRange = openTypeFeaturesByClusterRange;
        this.shapingDecisions = shapingDecisions;
        this.eastAsianSpacingEdges = eastAsianSpacingEdges;
        this.autoSpaceDecisions = autoSpaceDecisions;
        this.inlineBoxResult = inlineBoxResult;
        this.naturalClusters = naturalClusters;
        this.inlineObjectByClusterIndex = inlineObjectByClusterIndex;
        this.uniformInlineObjectBoundaryAfterClusters = uniformInlineObjectBoundaryAfterClusters;
        this.preferredInlineObjectBoundaryAfterClusters = preferredInlineObjectBoundaryAfterClusters;
        this.inlineObjectBoundaryUnbreakableRanges = inlineObjectBoundaryUnbreakableRanges;
        this.clusterRoles = clusterRoles;
        this.resolvedKinsoku = resolvedKinsoku;
        this.kinsokuRule = kinsokuRule;
        this.inlineObjectAttachedMarks = inlineObjectAttachedMarks;
        this.inlineObjectSeparatorSpaceTrims = inlineObjectSeparatorSpaceTrims;
        this.inlineObjectAttachmentNoStretchBoundaries = inlineObjectAttachmentNoStretchBoundaries;
        this.inlineObjectPunctuationAttachmentDecisions = inlineObjectPunctuationAttachmentDecisions;
        this.mandatoryBreakClusters = mandatoryBreakClusters;
        this.zeroWidthBreakClusters = zeroWidthBreakClusters;
        this.mandatoryBreakDecisions = mandatoryBreakDecisions;
        this.zeroWidthBreakDecisions = zeroWidthBreakDecisions;
        this.punctuationAtoms = punctuationAtoms;
        this.spacingPlan = spacingPlan;
        this.rubyFontGeometryBySpan = rubyFontGeometryBySpan;
        this.rubyAndBopomofoSpread = rubyAndBopomofoSpread;
        this.naturalInlineAttachments = naturalInlineAttachments;
        this.attachedPunctuationBoundary = attachedPunctuationBoundary;
        this.baseGeometry = baseGeometry;
        this.attachedPunctuationTrailingGlueByCluster = attachedPunctuationTrailingGlueByCluster;
        this.clusters = clusters;
        this.adjustmentStyle = adjustmentStyle;
        this.atomClassByRange = atomClassByRange;
        this.shrinkOpportunities = shrinkOpportunities;
    }
}

@:dataClass class LineBreakPlanningStageResult {
    public final metricDecisions:Array<ClusterMetricDecision>;
    public final metricDecisionByRange:std.SortedMap<TextRange, ClusterMetricDecision>;
    public final baseAscent:Float;
    public final baseDescent:Float;
    public final baseBoxDescent:Float;
    public final baseFaceHeight:Float;
    public final existingInterlineSpace:Float;
    public final rubyExtent:Float;
    public final baseLineMetrics:ResolvedLineMetrics;
    public final lineSpacingDecision:Null<LineSpacingDecisionInfo>;
    public final blockIndent:Float;
    public final firstLineIndent:Float;
    public final firstLineIndentDecision:FirstLineIndentDecisionInfo;
    public final kinsokuDecision:KinsokuDecisionInfo;
    public final asciiPointMarkKinsoku:ContextualKinsoku;
    public final inlineObjectKinsoku:ContextualKinsoku;
    public final unicodePunctuationBoundaries:UnicodePunctuationBoundaries;
    public final westernBracketCjkInterCharBoundaryAfterClusters:std.SortedSet<Int>;
    public final attachedInlinePhysicalBoundaryAfterClusters:std.SortedSet<Int>;
    public final attachedInlineVirtualBoundaryAfterClusters:std.SortedMap<Int, Int>;
    public final attachedInlineVirtualSinoWesternBoundaryAfterClusters:std.SortedSet<Int>;
    public final noStretchBoundaryClusters:std.SortedSet<Int>;
    public final noStretchBoundaryAfterClusters:std.SortedSet<Int>;
    public final technicalBoundaryAfterClusters:std.SortedMap<Int, ProgressiveBreakTier>;
    public final emergencyTrackingBoundaryAfterClusters:std.SortedMap<Int, String>;
    public final progressiveBreakOpportunities:std.SortedMap<Int, ProgressiveBreakOpportunity>;
    public final lineSolution:LineSolution;

    public function new(metricDecisions:Array<ClusterMetricDecision>, metricDecisionByRange:std.SortedMap<TextRange, ClusterMetricDecision>, baseAscent:Float,
            baseDescent:Float, baseBoxDescent:Float, baseFaceHeight:Float, existingInterlineSpace:Float, rubyExtent:Float,
            baseLineMetrics:ResolvedLineMetrics, lineSpacingDecision:Null<LineSpacingDecisionInfo>, blockIndent:Float, firstLineIndent:Float,
            firstLineIndentDecision:FirstLineIndentDecisionInfo, kinsokuDecision:KinsokuDecisionInfo, asciiPointMarkKinsoku:ContextualKinsoku,
            inlineObjectKinsoku:ContextualKinsoku, unicodePunctuationBoundaries:UnicodePunctuationBoundaries,
            westernBracketCjkInterCharBoundaryAfterClusters:std.SortedSet<Int>, attachedInlinePhysicalBoundaryAfterClusters:std.SortedSet<Int>,
            attachedInlineVirtualBoundaryAfterClusters:std.SortedMap<Int, Int>, attachedInlineVirtualSinoWesternBoundaryAfterClusters:std.SortedSet<Int>,
            noStretchBoundaryClusters:std.SortedSet<Int>, noStretchBoundaryAfterClusters:std.SortedSet<Int>,
            technicalBoundaryAfterClusters:std.SortedMap<Int, ProgressiveBreakTier>, emergencyTrackingBoundaryAfterClusters:std.SortedMap<Int, String>,
            progressiveBreakOpportunities:std.SortedMap<Int, ProgressiveBreakOpportunity>, lineSolution:LineSolution) {
        this.metricDecisions = metricDecisions;
        this.metricDecisionByRange = metricDecisionByRange;
        this.baseAscent = baseAscent;
        this.baseDescent = baseDescent;
        this.baseBoxDescent = baseBoxDescent;
        this.baseFaceHeight = baseFaceHeight;
        this.existingInterlineSpace = existingInterlineSpace;
        this.rubyExtent = rubyExtent;
        this.baseLineMetrics = baseLineMetrics;
        this.lineSpacingDecision = lineSpacingDecision;
        this.blockIndent = blockIndent;
        this.firstLineIndent = firstLineIndent;
        this.firstLineIndentDecision = firstLineIndentDecision;
        this.kinsokuDecision = kinsokuDecision;
        this.asciiPointMarkKinsoku = asciiPointMarkKinsoku;
        this.inlineObjectKinsoku = inlineObjectKinsoku;
        this.unicodePunctuationBoundaries = unicodePunctuationBoundaries;
        this.westernBracketCjkInterCharBoundaryAfterClusters = westernBracketCjkInterCharBoundaryAfterClusters;
        this.attachedInlinePhysicalBoundaryAfterClusters = attachedInlinePhysicalBoundaryAfterClusters;
        this.attachedInlineVirtualBoundaryAfterClusters = attachedInlineVirtualBoundaryAfterClusters;
        this.attachedInlineVirtualSinoWesternBoundaryAfterClusters = attachedInlineVirtualSinoWesternBoundaryAfterClusters;
        this.noStretchBoundaryClusters = noStretchBoundaryClusters;
        this.noStretchBoundaryAfterClusters = noStretchBoundaryAfterClusters;
        this.technicalBoundaryAfterClusters = technicalBoundaryAfterClusters;
        this.emergencyTrackingBoundaryAfterClusters = emergencyTrackingBoundaryAfterClusters;
        this.progressiveBreakOpportunities = progressiveBreakOpportunities;
        this.lineSolution = lineSolution;
    }
}

class IntervalOverlapIndex {
    private final byStart:Array<TextRange>;
    private final prefixMaxEnd:Array<Int>;

    public function new(ranges:Array<TextRange>) {
        final sorted = new Array<TextRange>();
        for (i in 0...ranges.length)
            sorted.push(ranges[i]);
        var rIdx = 1;
        while (rIdx < sorted.length) {
            final curr = sorted[rIdx];
            var j = rIdx - 1;
            while (j >= 0 && sorted[j].start > curr.start) {
                sorted[j + 1] = sorted[j];
                j--;
            }
            sorted[j + 1] = curr;
            rIdx++;
        }
        this.byStart = sorted;
        this.prefixMaxEnd = new Array<Int>();
        var running = -2147483648;
        for (i in 0...sorted.length) {
            if (sorted[i].end > running)
                running = sorted[i].end;
            prefixMaxEnd.push(running);
        }
    }

    public function overlaps(start:Int, endExclusive:Int):Bool {
        if (byStart.length == 0)
            return false;
        var low = 0;
        var high = byStart.length;
        while (low < high) {
            final mid = (low + high) >>> 1;
            if (byStart[mid].start < endExclusive) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        return low > 0 && prefixMaxEnd[low - 1] > start;
    }
}

class LineBreakPlanningStage {
    public static inline final CJK_FACE_ASCENT_FALLBACK_EM:Float = 0.88;
    public static inline final CJK_FACE_DESCENT_FALLBACK_EM:Float = 0.12;
    private static inline final DEFAULT_BODY_LINE_HEIGHT_EM:Float = 1.5;
    private static inline final HYPHEN_LAST_RESORT_CJK_STRETCH_EM:Float = 0.5;
    private static inline final HYPHEN_SINO_WESTERN_STRETCH_CAP_EM:Float = 0.25;

    private static function isHangablePunctuation(str:String):Bool {
        return str == "、" || str == "，" || str == "。";
    }

    private static function isWhitespaceOnly(str:String):Bool {
        if (str.length == 0)
            return false;
        for (i in 0...str.length) {
            if (!ParagraphShapingStage.isWhitespace(str.charCodeAt(i))) {
                return false;
            }
        }
        return true;
    }

    private static function containingClusterMetricDecisions(clusters:Array<Cluster>,
            decisions:Array<ClusterMetricDecision>):Array<Null<ClusterMetricDecision>> {
        var itemIndex = 0;
        final result = new Array<Null<ClusterMetricDecision>>();
        for (i in 0...clusters.length) {
            final cluster = clusters[i];
            while (itemIndex < decisions.length && decisions[itemIndex].range.end <= cluster.range.start) {
                itemIndex += 1;
            }
            if (itemIndex < decisions.length) {
                final item = decisions[itemIndex];
                if (cluster.range.start >= item.range.start && cluster.range.end <= item.range.end) {
                    result.push(item);
                } else {
                    result.push(null);
                }
            } else {
                result.push(null);
            }
        }
        return result;
    }

    public static function planParagraphLines(engine:ExplainableStubParagraphLayoutEngine, prep:ParagraphLayoutPrep):LineBreakPlanningStageResult {
        var metricClusterIndex = 0;
        final metricDecisions = new Array<ClusterMetricDecision>();
        for (decIdx in 0...prep.fontDecisions.length) {
            final decision = prep.fontDecisions[decIdx];
            while (metricClusterIndex < prep.naturalClusters.length
                && prep.naturalClusters[metricClusterIndex].range.end <= decision.range.start) {
                metricClusterIndex += 1;
            }
            final textBuf = new StringBuf();
            while (metricClusterIndex < prep.naturalClusters.length
                && prep.naturalClusters[metricClusterIndex].range.start < decision.range.end) {
                final cluster = prep.naturalClusters[metricClusterIndex];
                if (cluster.range.start < decision.range.start || cluster.range.end > decision.range.end) {
                    throw new TiqianIllegalArgumentException(org.tiqian.core.TextRangeError.Message("Shaped cluster " + cluster.range.toString()
                        + " crosses font decision " + decision.range.toString()));
                }
                textBuf.add(cluster.displayText);
                metricClusterIndex += 1;
            }
            final bufStr = textBuf.toString();
            final displayedFaceSelectionText = bufStr.length > 0 ? bufStr : prep.text.substring(decision.range.start, decision.range.end);
            final decStyle = prep.styleAt(decision.range.start);
            final fontFamiliesCopy = new Array<String>();
            for (f in 0...decStyle.fontFamilies.length)
                fontFamiliesCopy.push(decStyle.fontFamilies[f]);
            final request = new FontMetricsRequest(decision.candidate.key, prep.fontSizeAt(decision.range.start), decision.role, prep.input.textStyle.locale,
                fontFamiliesCopy, decStyle.fontWeight, decStyle.italic, displayedFaceSelectionText);
            final rawMetrics = engine.fontMetricsResolver.resolve(request);
            final layoutMetrics = engine.fontMetricsNormalizer.normalize(new FontMetricsNormalizationInput(request, rawMetrics));
            metricDecisions.push(new ClusterMetricDecision(decision.range, prep.text.substring(decision.range.start, decision.range.end), request, rawMetrics,
                layoutMetrics));
        }

        final ideographicDecisions = new Array<ClusterMetricDecision>();
        for (i in 0...metricDecisions.length) {
            if (metricDecisions[i].layoutMetrics.metricBox == MetricBox.IdeographicEmBox) {
                ideographicDecisions.push(metricDecisions[i]);
            }
        }
        final baseMetricDecisions = ideographicDecisions.length > 0 ? ideographicDecisions : metricDecisions;
        var maxAscent:Null<Float> = null;
        var maxDescent:Null<Float> = null;
        for (i in 0...baseMetricDecisions.length) {
            final asc = baseMetricDecisions[i].layoutMetrics.ascent;
            final dsc = baseMetricDecisions[i].layoutMetrics.descent;
            if (maxAscent == null || asc > maxAscent)
                maxAscent = asc;
            if (maxDescent == null || dsc > maxDescent)
                maxDescent = dsc;
        }
        final baseAscent = maxAscent != null ? maxAscent : (prep.fontSize * CJK_FACE_ASCENT_FALLBACK_EM);
        final baseDescent = maxDescent != null ? maxDescent : (prep.fontSize * CJK_FACE_DESCENT_FALLBACK_EM);

        var baseRefMetrics:Null<LayoutFontMetrics> = null;
        for (i in 0...metricDecisions.length) {
            if (metricDecisions[i].layoutMetrics.metricBox == MetricBox.IdeographicEmBox
                && metricDecisions[i].request.fontSize == prep.fontSize) {
                baseRefMetrics = metricDecisions[i].layoutMetrics;
                break;
            }
        }
        final baseBoxDescent = baseRefMetrics != null ? baseRefMetrics.descent : baseDescent;

        var maxRubyExtent:Float = 0.0;
        for (i in 0...prep.rubyFontGeometryBySpan.size()) {
            final geom = prep.rubyFontGeometryBySpan.valueAt(i);
            if (geom.requiredExtent > maxRubyExtent)
                maxRubyExtent = geom.requiredExtent;
        }
        final rubyExtent = maxRubyExtent;

        final interlinearSpacingFloor = prep.input.decorations.length == 0 ? 0.0 : 0.5 * prep.fontSize;
        final defaultBodyLineHeight = prep.fontSize * DEFAULT_BODY_LINE_HEIGHT_EM;
        final baseLineMetrics = LineGeometryStageFns.lineMetrics(metricDecisions, prep.input.paragraphStyle.lineHeight, defaultBodyLineHeight,
            interlinearSpacingFloor);

        final containingDecisions = containingClusterMetricDecisions(prep.naturalClusters, metricDecisions);
        final metricDecisionByRangeBuilder = SortedMap.builder();
        for (i in 0...prep.naturalClusters.length) {
            final d = containingDecisions[i];
            if (d != null) {
                metricDecisionByRangeBuilder.put(prep.naturalClusters[i].range, d);
            }
        }
        final metricDecisionByRange = metricDecisionByRangeBuilder.build();

        final baseFaceHeight = baseAscent + baseDescent;
        var existingInterlineSpace = baseLineMetrics.height - baseFaceHeight;
        if (existingInterlineSpace < 0.0)
            existingInterlineSpace = 0.0;

        var lineSpacingDecision:Null<LineSpacingDecisionInfo> = null;
        if (baseLineMetrics.height > 0.0) {
            final natural = baseLineMetrics.height - baseLineMetrics.extraLeading;
            final requested = prep.input.paragraphStyle.lineHeight;
            final reqOrDefault = requested != null ? requested : defaultBodyLineHeight;
            final markFloorBinds = interlinearSpacingFloor > 0.0 && (natural + interlinearSpacingFloor > reqOrDefault + 0.001);
            var reason = "CjkBodyLineHeightDefault";
            if (requested != null && !markFloorBinds) {
                reason = "ExplicitLineHeight";
            } else if (markFloorBinds) {
                reason = "InterlinearMarkLineSpacingFloor";
            }
            lineSpacingDecision = new LineSpacingDecisionInfo(natural, requested, baseLineMetrics.height, interlinearSpacingFloor, markFloorBinds, reason);
        }

        var explicitIndentEm:Null<Float> = null;
        final fIndent = prep.input.paragraphStyle.firstLineIndent;
        if (fIndent != null) {
            explicitIndentEm = fIndent.toPx(1.0);
        }
        final indentPolicy = prep.input.paragraphStyle.firstLineIndentPolicy;
        final blockIndent = prep.input.paragraphStyle.blockIndent.toPx(prep.fontSize);
        final resolvedIndentEm:Float = explicitIndentEm != null ? explicitIndentEm : indentPolicy.resolveEm(prep.measureEm);
        var firstLineIndent = blockIndent + resolvedIndentEm * prep.fontSize;
        if (firstLineIndent < 0.0)
            firstLineIndent = 0.0;
        final firstLineIndentDecision = new FirstLineIndentDecisionInfo(explicitIndentEm != null ? "Explicit" : "MeasureAdaptiveFirstLineIndent",
            prep.measureEm, indentPolicy.shortBelowEm, resolvedIndentEm);

        final kinsokuDecision = new KinsokuDecisionInfo(prep.measureEm, Std.string(prep.resolvedKinsoku.level), Std.string(prep.resolvedKinsoku.hanging),
            prep.resolvedKinsoku.reason);

        final hangableClustersBuilder = SortedSet.builder();
        if (prep.resolvedKinsoku.hanging == HangingPunctuationStyle.PauseStops) {
            for (idx in 0...prep.naturalClusters.length) {
                if (isHangablePunctuation(prep.naturalClusters[idx].displayText)) {
                    hangableClustersBuilder.put(idx);
                }
            }
        }
        final hangableClusters = hangableClustersBuilder.build();

        final asciiPointMarkKinsoku = PunctuationGeometryStage.attachedAsciiPointMarkKinsoku(prep.naturalClusters, prep.clusterRoles, prep.clusters,
            prep.resolvedKinsoku.level, prep.measure - blockIndent, prep.measure - firstLineIndent);
        final inlineObjectKinsoku = PunctuationGeometryStage.inlineObjectAttachedKinsoku(prep.naturalClusters, prep.inlineObjectAttachedMarks, prep.clusters,
            prep.resolvedKinsoku.level, prep.measure - blockIndent, prep.measure - firstLineIndent);

        final resolvedHangableClustersBuilder = SortedSet.builder();
        for (i in 0...hangableClusters.size())
            resolvedHangableClustersBuilder.put(hangableClusters.at(i));
        for (i in 0...asciiPointMarkKinsoku.impossibleMeasureHangEligibleClusters.size()) {
            resolvedHangableClustersBuilder.put(asciiPointMarkKinsoku.impossibleMeasureHangEligibleClusters.at(i));
        }
        for (i in 0...inlineObjectKinsoku.impossibleMeasureHangEligibleClusters.size()) {
            resolvedHangableClustersBuilder.put(inlineObjectKinsoku.impossibleMeasureHangEligibleClusters.at(i));
        }
        final resolvedHangableClusters = resolvedHangableClustersBuilder.build();

        final unicodePunctuationBoundaries = UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries(prep.text, prep.naturalClusters,
            prep.clusterRoles, prep.quotePairs);
        final inlineAttachments = prep.naturalInlineAttachments;
        final westernBracketBoundaries = UnicodePunctuationBoundaryResolver.resolveWesternBracketCjkInterCharBoundaries(prep.text, prep.naturalClusters,
            prep.clusterRoles);
        final attachedInlineInterCharBoundaries = UnicodePunctuationBoundaryResolver.resolveAttachedInlineInterCharBoundaries(prep.text, prep.naturalClusters,
            prep.clusterRoles, prep.eastAsianSpacingEdges, westernBracketBoundaries, inlineAttachments);
        final westernBracketCjkInterCharBoundaryAfterClusters = attachedInlineInterCharBoundaries.ordinaryWesternBoundaryAfterClusters;
        final attachedInlinePhysicalBoundaryAfterClusters = attachedInlineInterCharBoundaries.suppressedPhysicalBoundaryAfterClusters;
        final attachedInlineVirtualBoundaryAfterClusters = attachedInlineInterCharBoundaries.virtualBoundaryAfterClusters;
        final attachedInlineVirtualSinoWesternBoundaryAfterClusters = attachedInlineInterCharBoundaries.virtualSinoWesternBoundaryAfterClusters;

        final attachedInlineForbiddenLineStartClustersBuilder = SortedSet.builder();
        for (it in 0...inlineAttachments.length) {
            if (inlineAttachments[it] == InlineAttachment.Previous) {
                attachedInlineForbiddenLineStartClustersBuilder.put(it);
            }
        }
        final attachedInlineForbiddenLineStartClusters = attachedInlineForbiddenLineStartClustersBuilder.build();

        final forbiddenLineStartClustersBuilder = SortedSet.builder();
        for (idx in 0...prep.naturalClusters.length) {
            if (attachedInlineForbiddenLineStartClusters.has(idx)
                || prep.zeroWidthBreakClusters.has(idx)
                || (PunctuationGeometryStage.isCjkKinsokuRole(prep.clusterRoles[idx])
                    && prep.kinsokuRule.forbiddenAtLineStart(prep.naturalClusters[idx]))
                || unicodePunctuationBoundaries.forbiddenLineStartClusters.has(idx)
                || asciiPointMarkKinsoku.forbiddenLineStartClusters.has(idx)
                || inlineObjectKinsoku.forbiddenLineStartClusters.has(idx)) {
                forbiddenLineStartClustersBuilder.put(idx);
            }
        }
        final forbiddenLineStartClusters = forbiddenLineStartClustersBuilder.build();

        final forbiddenLineEndClustersBuilder = SortedSet.builder();
        for (idx in 0...prep.naturalClusters.length) {
            if ((PunctuationGeometryStage.isCjkKinsokuRole(prep.clusterRoles[idx])
                && prep.kinsokuRule.forbiddenAtLineEnd(prep.naturalClusters[idx]))
                || unicodePunctuationBoundaries.forbiddenLineEndClusters.has(idx)) {
                forbiddenLineEndClustersBuilder.put(idx);
            }
        }
        final forbiddenLineEndClusters = forbiddenLineEndClustersBuilder.build();

        final hyphenBreakClustersBuilder = SortedSet.builder();
        if (prep.hyphenOffsets.size() > 0) {
            for (it in 0...prep.naturalClusters.length) {
                if (prep.hyphenOffsets.has(prep.naturalClusters[it].range.start)) {
                    hyphenBreakClustersBuilder.put(it);
                }
            }
        }
        final hyphenBreakClusters = hyphenBreakClustersBuilder.build();

        final clusterIndexBySourceStartBuilder = SortedMap.builder();
        for (it in 0...prep.naturalClusters.length) {
            clusterIndexBySourceStartBuilder.put(prep.naturalClusters[it].range.start, it);
        }
        final clusterIndexBySourceStart = clusterIndexBySourceStartBuilder.build();
        final progressiveTechnicalWhitespaceStretchCapacity = engine.justifier.progressiveTechnicalWhitespaceStretchCapacity(prep.fontSize);

        final progressiveBreakOpportunitiesBuilder:SortedMapBuilder<Int, ProgressiveBreakOpportunity> = SortedMap.builder();
        for (i in 0...prep.progressiveBreakOffsets.size()) {
            final sourceOffset = prep.progressiveBreakOffsets.keyAt(i);
            final opportunity = prep.progressiveBreakOffsets.valueAt(i);
            if (clusterIndexBySourceStart.has(sourceOffset)) {
                final clusterIndex = clusterIndexBySourceStart.get(sourceOffset);
                final opp = opportunity.tier == ProgressiveBreakTier.Whitespace ? new ProgressiveBreakOpportunity(opportunity.tier, opportunity.spanRange,
                    progressiveTechnicalWhitespaceStretchCapacity) : opportunity;
                progressiveBreakOpportunitiesBuilder.put(clusterIndex, opp);
            }
        }
        final progressiveBreakOpportunities = progressiveBreakOpportunitiesBuilder.build();

        final progressiveTechnicalRanges = new Array<TextRange>();
        for (i in 0...prep.input.content.lineBreakSpans.length) {
            if (prep.input.content.lineBreakSpans[i].policy == LineBreakPolicy.ProgressiveTechnical) {
                progressiveTechnicalRanges.push(prep.input.content.lineBreakSpans[i].range);
            }
        }
        final progressiveTechnicalOverlap = new IntervalOverlapIndex(progressiveTechnicalRanges);

        final rawNumberSymbolRanges = NumberSymbolCohesion.unbreakableRanges(prep.text);
        final numberSymbolClusterRanges = new Array<IntRange>();
        for (i in 0...rawNumberSymbolRanges.length) {
            final sourceRange = rawNumberSymbolRanges[i];
            if (!progressiveTechnicalOverlap.overlaps(sourceRange.start, sourceRange.end + 1)) {
                final idxRange = PunctuationGeometryLedger.clusterIndexRangeFor(prep.naturalClusters, new TextRange(sourceRange.start, sourceRange.end + 1));
                if (idxRange != null) {
                    numberSymbolClusterRanges.push(idxRange);
                }
            }
        }

        final numberSymbolUnbreakableRanges = new Array<IntRange>();
        for (i in 0...numberSymbolClusterRanges.length) {
            final idxRange = numberSymbolClusterRanges[i];
            var rangeAdv = 0.0;
            for (cIdx in idxRange.start...idxRange.end + 1) {
                rangeAdv += prep.naturalClusters[cIdx].advance;
            }
            if (rangeAdv <= prep.measure) {
                numberSymbolUnbreakableRanges.push(idxRange);
            }
        }

        final noStretchBoundaryClustersBuilder = SortedSet.builder();
        for (idx in 0...prep.naturalClusters.length) {
            final cls = prep.atomClassByRange.has(prep.naturalClusters[idx].range) ? prep.atomClassByRange.get(prep.naturalClusters[idx].range) : null;
            if (cls == PunctuationClass.Connector || cls == PunctuationClass.Solidus || cls == PunctuationClass.Dash || cls == PunctuationClass.Ellipsis) {
                noStretchBoundaryClustersBuilder.put(idx);
            }
        }
        final noStretchBoundaryClusters = noStretchBoundaryClustersBuilder.build();

        final noStretchBoundaryAfterClustersBuilder = SortedSet.builder();
        for (i in 0...numberSymbolClusterRanges.length) {
            final range = numberSymbolClusterRanges[i];
            for (cIdx in range.start...range.end) {
                noStretchBoundaryAfterClustersBuilder.put(cIdx);
            }
        }
        for (i in 0...prep.inlineObjectAttachmentNoStretchBoundaries.size()) {
            noStretchBoundaryAfterClustersBuilder.put(prep.inlineObjectAttachmentNoStretchBoundaries.at(i));
        }
        final noStretchBoundaryAfterClusters = noStretchBoundaryAfterClustersBuilder.build();

        final technicalBoundaryAfterClustersBuilder = SortedMap.builder();
        for (i in 0...progressiveBreakOpportunities.size()) {
            final rightIndex = progressiveBreakOpportunities.keyAt(i);
            final opportunity = progressiveBreakOpportunities.valueAt(i);
            if (opportunity.tier == ProgressiveBreakTier.Whitespace) {
                technicalBoundaryAfterClustersBuilder.put(rightIndex - 1, opportunity.tier);
            }
        }
        final technicalBoundaryAfterClusters = technicalBoundaryAfterClustersBuilder.build();

        final boundaryEligible = new Array<Bool>();
        for (i in 0...prep.naturalClusters.length)
            boundaryEligible.push(false);
        for (leftIndex in 0...prep.naturalClusters.length - 1) {
            final rightIndex = leftIndex + 1;
            final left = prep.naturalClusters[leftIndex];
            final right = prep.naturalClusters[rightIndex];
            if (left.range.end != right.range.start)
                continue;
            if (prep.inlineObjectByClusterIndex.has(leftIndex)
                || prep.inlineObjectByClusterIndex.has(rightIndex)
                || prep.zeroWidthBreakClusters.has(leftIndex)
                || prep.zeroWidthBreakClusters.has(rightIndex)
                || prep.mandatoryBreakClusters.has(leftIndex)
                || prep.mandatoryBreakClusters.has(rightIndex)
                || left.text.length == 0
                || right.text.length == 0
                || isWhitespaceOnly(left.text)
                || isWhitespaceOnly(right.text)) {
                continue;
            }
            boundaryEligible[leftIndex] = true;
        }

        final addedKeys = new Array<Bool>();
        for (i in 0...prep.naturalClusters.length)
            addedKeys.push(false);
        final emergencyTrackingBoundaryAfterClustersBuilder = SortedMap.builder();
        for (i in 0...prep.emergencyTrackingEligibilityDecisions.length) {
            final decision = prep.emergencyTrackingEligibilityDecisions[i];
            final span = PunctuationGeometryLedger.clusterIndexRangeFor(prep.naturalClusters, decision.range);
            if (span == null)
                continue;
            for (leftIndex in span.start...span.end) {
                if (!boundaryEligible[leftIndex] || addedKeys[leftIndex])
                    continue;
                addedKeys[leftIndex] = true;
                emergencyTrackingBoundaryAfterClustersBuilder.put(leftIndex, decision.reason);
            }
        }
        final emergencyTrackingBoundaryAfterClusters = emergencyTrackingBoundaryAfterClustersBuilder.build();

        final adjustableInlineBoundaryRightClustersBuilder = SortedSet.builder();
        for (i in 0...prep.uniformInlineObjectBoundaryAfterClusters.size()) {
            final leftIndex = prep.uniformInlineObjectBoundaryAfterClusters.at(i);
            final rightIndex = leftIndex + 1;
            if (noStretchBoundaryAfterClusters.has(leftIndex)
                || noStretchBoundaryClusters.has(leftIndex)
                || noStretchBoundaryClusters.has(rightIndex)) {
                // skip
            } else {
                adjustableInlineBoundaryRightClustersBuilder.put(rightIndex);
            }
        }
        final adjustableInlineBoundaryRightClusters = adjustableInlineBoundaryRightClustersBuilder.build();

        final cjkInterCharBoundariesBuilder = SortedSet.builder();
        for (it in 1...prep.naturalClusters.length) {
            if (!attachedInlinePhysicalBoundaryAfterClusters.has(it - 1)
                && !noStretchBoundaryAfterClusters.has(it - 1)
                && prep.clusterRoles[it - 1] == FontRole.CjkText
                && prep.clusterRoles[it] == FontRole.CjkText) {
                cjkInterCharBoundariesBuilder.put(it);
            }
        }
        for (i in 0...adjustableInlineBoundaryRightClusters.size()) {
            cjkInterCharBoundariesBuilder.put(adjustableInlineBoundaryRightClusters.at(i));
        }
        for (i in 0...westernBracketCjkInterCharBoundaryAfterClusters.size()) {
            cjkInterCharBoundariesBuilder.put(westernBracketCjkInterCharBoundaryAfterClusters.at(i) + 1);
        }
        for (i in 0...attachedInlineVirtualBoundaryAfterClusters.size()) {
            cjkInterCharBoundariesBuilder.put(attachedInlineVirtualBoundaryAfterClusters.keyAt(i) + 1);
        }
        final cjkInterCharBoundaries = cjkInterCharBoundariesBuilder.build();

        final sinoWesternBoundariesBuilder = SortedSet.builder();
        for (it in 1...prep.naturalClusters.length) {
            if (!attachedInlinePhysicalBoundaryAfterClusters.has(it - 1)
                && !noStretchBoundaryAfterClusters.has(it - 1)
                && PunctuationGeometryStage.isEastAsianSpacingBoundaryAt(it, prep.naturalClusters, prep.eastAsianSpacingEdges)) {
                sinoWesternBoundariesBuilder.put(it);
            }
        }
        for (i in 0...attachedInlineVirtualSinoWesternBoundaryAfterClusters.size()) {
            sinoWesternBoundariesBuilder.put(attachedInlineVirtualSinoWesternBoundaryAfterClusters.at(i) + 1);
        }
        final sinoWesternBoundaries = sinoWesternBoundariesBuilder.build();

        final virtualBoundaries = UnicodePunctuationBoundaryResolver.resolveAttachedInlineVirtualBoundaries(inlineAttachments);
        final attachedInlineUnbreakableRanges = new Array<IntRange>();
        for (i in 0...virtualBoundaries.length) {
            final boundary = virtualBoundaries[i];
            attachedInlineUnbreakableRanges.push(new IntRange(boundary.previousClusterIndex, boundary.attachedClusterRange.end));
        }

        final allUnbreakables = new Array<IntRange>();
        for (i in 0...prep.input.decorations.length) {
            final d = prep.input.decorations[i];
            if (d.kind == DecorationKind.Mourning) {
                final r = PunctuationGeometryLedger.clusterIndexRangeFor(prep.naturalClusters, d.range);
                if (r != null)
                    allUnbreakables.push(r);
            }
        }
        for (i in 0...prep.pinyinSpans.length) {
            final r = PunctuationGeometryLedger.clusterIndexRangeFor(prep.naturalClusters, prep.pinyinSpans[i].baseRange);
            if (r != null)
                allUnbreakables.push(r);
        }
        for (i in 0...attachedInlineUnbreakableRanges.length)
            allUnbreakables.push(attachedInlineUnbreakableRanges[i]);
        for (i in 0...numberSymbolUnbreakableRanges.length)
            allUnbreakables.push(numberSymbolUnbreakableRanges[i]);
        for (i in 0...unicodePunctuationBoundaries.unbreakableRanges.length)
            allUnbreakables.push(unicodePunctuationBoundaries.unbreakableRanges[i]);
        for (i in 0...asciiPointMarkKinsoku.unbreakableRanges.length)
            allUnbreakables.push(asciiPointMarkKinsoku.unbreakableRanges[i]);
        for (i in 0...inlineObjectKinsoku.unbreakableRanges.length)
            allUnbreakables.push(inlineObjectKinsoku.unbreakableRanges[i]);
        for (i in 0...prep.inlineObjectBoundaryUnbreakableRanges.length)
            allUnbreakables.push(prep.inlineObjectBoundaryUnbreakableRanges[i]);
        final unbreakableRanges = new UnbreakableRanges(allUnbreakables);

        final combinedExtendableHangRanges = new Array<IntRange>();
        for (i in 0...asciiPointMarkKinsoku.extendableHangRanges.length)
            combinedExtendableHangRanges.push(asciiPointMarkKinsoku.extendableHangRanges[i]);
        for (i in 0...inlineObjectKinsoku.extendableHangRanges.length)
            combinedExtendableHangRanges.push(inlineObjectKinsoku.extendableHangRanges[i]);

        var lineSolution = new LineSolution([]);
        if (prep.text.length > 0) {
            var lineAdjustmentCompressBias = 0.0;
            if (prep.adjustmentStyle.lineAdjustment == LineAdjustmentStrategy.PushInFirst) {
                lineAdjustmentCompressBias = 1000000.0;
            } else if (prep.adjustmentStyle.lineAdjustment == LineAdjustmentStrategy.PushOutFirst) {
                lineAdjustmentCompressBias = 0.5;
            }
            lineSolution = engine.lineBreaker.breakLines(prep.naturalClusters, prep.clusters, prep.measure - blockIndent, prep.shrinkOpportunities,
                unbreakableRanges, firstLineIndent - blockIndent, resolvedHangableClusters, combinedExtendableHangRanges, forbiddenLineStartClusters,
                forbiddenLineEndClusters, hyphenBreakClusters, cjkInterCharBoundaries, HYPHEN_LAST_RESORT_CJK_STRETCH_EM * prep.fontSize,
                sinoWesternBoundaries, HYPHEN_SINO_WESTERN_STRETCH_CAP_EM * prep.fontSize,
                prep.adjustmentStyle.lineAdjustment != LineAdjustmentStrategy.PushOutOnly, lineAdjustmentCompressBias, prep.mandatoryBreakClusters,
                prep.zeroWidthBreakClusters, progressiveBreakOpportunities);
        }

        return new LineBreakPlanningStageResult(metricDecisions, metricDecisionByRange, baseAscent, baseDescent, baseBoxDescent, baseFaceHeight,
            existingInterlineSpace, rubyExtent, baseLineMetrics, lineSpacingDecision, blockIndent, firstLineIndent, firstLineIndentDecision, kinsokuDecision,
            asciiPointMarkKinsoku, inlineObjectKinsoku, unicodePunctuationBoundaries, westernBracketCjkInterCharBoundaryAfterClusters,
            attachedInlinePhysicalBoundaryAfterClusters, attachedInlineVirtualBoundaryAfterClusters, attachedInlineVirtualSinoWesternBoundaryAfterClusters,
            noStretchBoundaryClusters, noStretchBoundaryAfterClusters, technicalBoundaryAfterClusters, emergencyTrackingBoundaryAfterClusters,
            progressiveBreakOpportunities, lineSolution);
    }
}
