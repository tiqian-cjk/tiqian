package org.tiqian.layout;

import org.tiqian.core.LayoutInput;
import org.tiqian.core.LayoutResult;
import org.tiqian.core.Size;
import org.tiqian.core.TextRange;
import org.tiqian.core.IntRange;
import org.tiqian.core.LineBox;
import org.tiqian.core.LineDebugInfo;
import org.tiqian.core.Cluster;
import org.tiqian.core.Glyph;
import org.tiqian.core.GlyphRun;
import org.tiqian.core.LineEndReason;
import org.tiqian.core.LastLineAlignment;
import org.tiqian.core.RubySpan;
import org.tiqian.core.RubyKind;
import org.tiqian.core.InlineObjectSpan;
import org.tiqian.core.LineEdgeTrimDecisionInfo;
import org.tiqian.core.MaxLinesDecisionInfo;
import org.tiqian.core.ContextualKinsokuDecisionInfo;
import org.tiqian.core.InlineObjectDecisionInfo;
import org.tiqian.core.DecorationDecisionInfo;
import org.tiqian.core.DecorationSegmentInfo;
import org.tiqian.core.RubyDecisionInfo;
import org.tiqian.core.BopomofoDecisionInfo;
import org.tiqian.core.ClusterGeometryDecisionInfo;
import org.tiqian.core.AutoSpaceDecisionInfo;
import org.tiqian.clreq.ClreqProfile;
import org.tiqian.clreq.LineEndPunctuationStyle;
import org.tiqian.clreq.PunctuationClass;
import org.tiqian.font.FontRole;
import org.tiqian.font.BaselineClass;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import org.tiqian.layout.PunctuationModel.GlueKind;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.LineBreakPlanningStage.ParagraphLayoutPrep;
import org.tiqian.layout.LineBreakPlanningStage.LineBreakPlanningStageResult;
import org.tiqian.layout.LineOptimization.LineSolution;
import org.tiqian.layout.LineOptimization.LineCandidate;
import org.tiqian.layout.LineOptimization.RepairOptions;
import org.tiqian.layout.Justifier.JustificationPlan;
import org.tiqian.layout.AnnotationGeometryStage.RubyFontGeometry;
import org.tiqian.layout.AnnotationGeometryStage.AnnotationGeometryStageResult;
import org.tiqian.layout.LineGeometryStage.ClusterMetricDecision;
import org.tiqian.layout.LineGeometryStage.LineBoxStageResult;
import org.tiqian.layout.LineGeometryStage.LineGeometryStageFns;
import org.tiqian.layout.LayoutDebugAssembly.LayoutDebugStageInput;
import org.tiqian.layout.LayoutDebugAssembly;
import org.tiqian.layout.ParagraphShapingStage;
import org.tiqian.layout.PunctuationGeometryStage;
import std.SortedSet;
import std.SortedMap;

class LineAdjustmentStage {
    private static inline final CURRENT_LINE_TECHNICAL_BODY_STRETCH_LIMIT_EM:Float = 0.0;
    private static inline final TECHNICAL_STRETCH_EPSILON_PX:Float = 0.001;

    private static function repairOptionName(repair:org.tiqian.layout.LineOptimization.RepairOption):String {
        return switch (repair) {
            case PushIn(_, _, _, _, _, _): "PushIn";
            case Hang(_, _, _): "Hang";
            case CarryPrevious(_, _, _, _): "CarryPrevious";
            case CarryNext(_, _, _): "CarryNext";
            case LeaveRagged(_, _, _): "LeaveRagged";
        };
    }

    private static function lineHyphenAdvanceAt(lineIndex:Int, lines:Array<LineCandidate>, hyphenOffsets:SortedSet<Int>, naturalClusters:Array<Cluster>,
            hyphenAdvance:Float):Float {
        if (hyphenOffsets.size() == 0 || lineIndex >= lines.length - 1)
            return 0.0;
        final next = lines[lineIndex + 1];
        if (next.clusterRange.isEmpty)
            return 0.0;
        final nextFirst = next.clusterRange.start;
        return hyphenOffsets.has(naturalClusters[nextFirst].range.start) ? hyphenAdvance : 0.0;
    }

    private static function renderableGlyphRunClusters(clusters:Array<Cluster>,
            openTypeFeaturesByClusterRange:SortedMap<TextRange, Array<String>>):Array<Array<Cluster>> {
        final renderable = new Array<Cluster>();
        for (c in clusters) {
            if (c.displayText.length > 0 && !ParagraphShapingStage.isInlineObjectCluster(c)) {
                renderable.push(c);
            }
        }
        if (renderable.length == 0)
            return [];

        final groups = new Array<Array<Cluster>>();
        var currentGroup = [renderable[0]];
        for (i in 1...renderable.length) {
            final prev = currentGroup[currentGroup.length - 1];
            final curr = renderable[i];
            final prevFeat = openTypeFeaturesByClusterRange.has(prev.range) ? openTypeFeaturesByClusterRange.get(prev.range) : [];
            final currFeat = openTypeFeaturesByClusterRange.has(curr.range) ? openTypeFeaturesByClusterRange.get(curr.range) : [];
            var sameFeatures = prevFeat.length == currFeat.length;
            if (sameFeatures) {
                for (f in 0...prevFeat.length) {
                    if (prevFeat[f] != currFeat[f]) {
                        sameFeatures = false;
                        break;
                    }
                }
            }
            if (prev.fontKey == curr.fontKey && prev.range.end == curr.range.start && sameFeatures) {
                currentGroup.push(curr);
            } else {
                groups.push(currentGroup);
                currentGroup = [curr];
            }
        }
        groups.push(currentGroup);
        return groups;
    }

    private static function centerDashInk(glyphs:Array<Glyph>, cluster:Cluster, atomClassByRange:SortedMap<TextRange, PunctuationClass>):Array<Glyph> {
        if (!atomClassByRange.has(cluster.range) || atomClassByRange.get(cluster.range) != PunctuationClass.Dash) {
            return glyphs;
        }
        if (glyphs.length != 1)
            return glyphs;
        final glyph = glyphs[0];
        final ink = glyph.bounds;
        if (ink == null)
            return glyphs;
        final inset = (cluster.advance - (ink.right - ink.left)) / 2.0 - ink.left;
        if (inset <= 0.5)
            return glyphs;
        return [
            new Glyph(glyph.id, glyph.clusterRange, glyph.advance, glyph.x + inset, glyph.y, glyph.renderFontKey, glyph.bounds, glyph.haltAdvance,
                glyph.haltPlacementX)
        ];
    }

    private static function buildLineBoxes(input:LayoutInput, lineSolution:LineSolution, trimmedClusters:Array<Cluster>, finalClusters:Array<Cluster>,
            firstLineIndent:Float, blockIndent:Float, measure:Float, gridBodyOffset:Float, lineBaseline:Array<Float>, lineTop:Array<Float>,
            lineBottom:Array<Float>, hyphenOffsets:SortedSet<Int>, naturalClusters:Array<Cluster>, hyphenAdvance:Float, hyphenGlyphs:Array<Glyph>,
            justificationPlans:Array<Null<JustificationPlan>>):LineBoxStageResult {
        final laidOutLines = new Array<LineBox>();
        for (lineIndex in 0...lineSolution.lines.length) {
            final lineCandidate = lineSolution.lines[lineIndex];
            var adjustedWidth = 0.0;
            if (!lineCandidate.clusterRange.isEmpty) {
                for (idx in lineCandidate.clusterRange.start...lineCandidate.clusterRange.end + 1) {
                    if (!lineCandidate.hangingClusterIndices.has(idx)) {
                        adjustedWidth += trimmedClusters[idx].advance;
                    }
                }
            }
            var visualWidth = 0.0;
            if (!lineCandidate.clusterRange.isEmpty) {
                for (idx in lineCandidate.clusterRange.start...lineCandidate.clusterRange.end + 1) {
                    visualWidth += finalClusters[idx].advance;
                }
            }
            if (std.Math.abs(visualWidth - std.Math.round(visualWidth)) < 0.0001) {
                visualWidth = std.Math.round(visualWidth);
            }
            if (std.Math.abs(adjustedWidth - std.Math.round(adjustedWidth)) < 0.0001) {
                adjustedWidth = std.Math.round(adjustedWidth);
            }
            var hangingPunctuationAdvance = 0.0;
            for (hIdx in 0...lineCandidate.hangingClusterIndices.size()) {
                final it = lineCandidate.hangingClusterIndices.at(hIdx);
                hangingPunctuationAdvance += finalClusters[it].advance;
            }
            if (std.Math.abs(hangingPunctuationAdvance - std.Math.round(hangingPunctuationAdvance)) < 0.0001) {
                hangingPunctuationAdvance = std.Math.round(hangingPunctuationAdvance);
            }
            var hasDrawableContent = false;
            if (!lineCandidate.clusterRange.isEmpty) {
                for (idx in lineCandidate.clusterRange.start...lineCandidate.clusterRange.end + 1) {
                    if (finalClusters[idx].displayText.length > 0) {
                        hasDrawableContent = true;
                        break;
                    }
                }
            }
            var baseIndent = 0.0;
            if (hasDrawableContent) {
                if (lineCandidate.clusterRange.start == 0) {
                    baseIndent = firstLineIndent;
                } else {
                    baseIndent = blockIndent;
                }
            }

            final lineHyphenAdvance = lineHyphenAdvanceAt(lineIndex, lineSolution.lines, hyphenOffsets, naturalClusters, hyphenAdvance);
            final limit = measure - baseIndent;
            var alignmentInset = 0.0;
            if (lineCandidate.endReason != LineEndReason.AutoWrap) {
                if (input.paragraphStyle.lastLineAlignment == LastLineAlignment.Center) {
                    final diff = (limit - visualWidth) / 2.0;
                    alignmentInset = diff < 0.0 ? 0.0 : diff;
                } else if (input.paragraphStyle.lastLineAlignment == LastLineAlignment.End) {
                    final diff = limit - visualWidth;
                    alignmentInset = diff < 0.0 ? 0.0 : diff;
                }
            }

            final repairStr = lineCandidate.repair != null ? (repairOptionName(lineCandidate.repair) + ":" + RepairOptions.reason(lineCandidate.repair)) : null;
            final notes = new Array<String>();
            if (lineCandidate.clusterRange.isEmpty) {
                notes.push("line:" + lineIndex + ":clusters=empty");
            } else {
                notes.push("line:" + lineIndex + ":clusters=" + lineCandidate.clusterRange.start + "-" + lineCandidate.clusterRange.end);
            }
            notes.push("end:" + Std.string(lineCandidate.endReason));
            notes.push("natural=" + lineCandidate.naturalWidth + ",adjusted=" + lineCandidate.adjustedWidth + ",visual=" + visualWidth);
            final planForLine = justificationPlans[lineIndex];
            if (planForLine != null && planForLine.fallbackReason != null) {
                notes.push("justify-fallback:" + planForLine.fallbackReason);
            }

            final hGlyphs = lineHyphenAdvance > 0.0 ? hyphenGlyphs : [];
            laidOutLines.push(new LineBox(lineCandidate.sourceRange, lineCandidate.clusterRange, lineBaseline[lineIndex], lineTop[lineIndex],
                lineBottom[lineIndex], lineCandidate.naturalWidth, adjustedWidth, visualWidth, hangingPunctuationAdvance,
                gridBodyOffset + baseIndent + alignmentInset, lineCandidate.endReason, lineHyphenAdvance, hGlyphs, new LineDebugInfo(repairStr, notes)));
        }

        final visibleLines = new Array<LineBox>();
        final maxLines = input.constraints.maxLines;
        final count = laidOutLines.length > maxLines ? maxLines : laidOutLines.length;
        for (i in 0...count) {
            visibleLines.push(laidOutLines[i]);
        }

        final maxLinesDecision = visibleLines.length < laidOutLines.length ? new MaxLinesDecisionInfo(laidOutLines.length, visibleLines.length) : null;

        final visibleLineRanges = new Array<IntRange>();
        for (i in 0...visibleLines.length) {
            visibleLineRanges.push(lineSolution.lines[i].clusterRange);
        }

        return new LineBoxStageResult(laidOutLines, visibleLines, maxLinesDecision, visibleLineRanges);
    }

    private static function isFixedBoundary(b:org.tiqian.core.InlineObjectBoundaryAdjustment):Bool {
        return !b.participatesInUniformStretch && b.preferredStretch == null && b.shrinkCapacity == 0.0 && b.lineEndDiscardableAdvance == 0.0
            && !b.preventsLineBreak;
    }

    public static function resolveAnnotationGeometry(engine:ExplainableStubParagraphLayoutEngine, input:LayoutInput, fontSize:Float,
            inlineObjectByClusterIndex:SortedMap<Int, InlineObjectSpan>, lineSolution:LineSolution, clreqProfile:ClreqProfile,
            geometryDecisions:Array<ClusterGeometryDecisionInfo>, autoSpaceDecisions:Array<AutoSpaceDecisionInfo>, visibleLineRanges:Array<IntRange>,
            lines:Array<LineBox>, finalClusters:Array<Cluster>, clusterRoles:Array<FontRole>, justifyDeltaByCluster:SortedMap<Int, Float>,
            rubyAndBopomofoSpread:SortedMap<Int, Float>, metricDecisions:Array<ClusterMetricDecision>, pinyinSpans:Array<RubySpan>,
            naturalClusters:Array<Cluster>, rubyFontGeometryBySpan:SortedMap<RubySpan, RubyFontGeometry>, rubyStackGap:Float, baseAscent:Float,
            rubyFontSize:Float, rubyFontWeight:Int, baseDescent:Float, bopomofoFontWeightAt:Int->Int):AnnotationGeometryStageResult {
        final inlineObjectDecisions = new Array<InlineObjectDecisionInfo>();
        for (i in 0...inlineObjectByClusterIndex.size()) {
            final clusterIndex = inlineObjectByClusterIndex.keyAt(i);
            final inlineObject = inlineObjectByClusterIndex.valueAt(i);
            var lineIdx = -1;
            for (l in 0...lineSolution.lines.length) {
                final cr = lineSolution.lines[l].clusterRange;
                if (!cr.isEmpty && clusterIndex >= cr.start && clusterIndex <= cr.end) {
                    lineIdx = l;
                    break;
                }
            }
            final leadingPreferred = inlineObject.leadingBoundary.preferredStretch;
            final trailingPreferred = inlineObject.trailingBoundary.preferredStretch;
            final reason = (!isFixedBoundary(inlineObject.leadingBoundary)
                || !isFixedBoundary(inlineObject.trailingBoundary)) ? "AdjustableInlineObject" : "MeasurableOpaqueInlineObject";

            inlineObjectDecisions.push(new InlineObjectDecisionInfo(inlineObject.range, inlineObject.advance, inlineObject.ascent, inlineObject.descent,
                clusterIndex, lineIdx, inlineObject.leadingBoundary.participatesInUniformStretch,
                leadingPreferred != null ? Std.string(leadingPreferred.kind) : null, leadingPreferred != null ? leadingPreferred.naturalWidth : 0.0,
                leadingPreferred != null ? leadingPreferred.targetWidth : 0.0, leadingPreferred != null ? leadingPreferred.capacity : 0.0,
                inlineObject.leadingBoundary.preventsLineBreak, inlineObject.leadingBoundary.shrinkCapacity,
                inlineObject.leadingBoundary.lineEndDiscardableAdvance, inlineObject.trailingBoundary.participatesInUniformStretch,
                trailingPreferred != null ? Std.string(trailingPreferred.kind) : null, trailingPreferred != null ? trailingPreferred.naturalWidth : 0.0,
                trailingPreferred != null ? trailingPreferred.targetWidth : 0.0, trailingPreferred != null ? trailingPreferred.capacity : 0.0,
                inlineObject.trailingBoundary.preventsLineBreak, inlineObject.trailingBoundary.shrinkCapacity,
                inlineObject.trailingBoundary.lineEndDiscardableAdvance, reason));
        }

        final decorationDecisions = AnnotationGeometryStage.computeDecorationDecisions(input.decorations, visibleLineRanges, lines, finalClusters,
            clusterRoles, justifyDeltaByCluster, rubyAndBopomofoSpread, metricDecisions, fontSize, input.paragraphStyle.emphasisDotGapEm);
        final autoSpaceGapPx = clreqProfile.autoSpace.gapEm * fontSize;
        final geometryByRangeBuilder = SortedMap.builder();
        for (gi in 0...geometryDecisions.length) {
            final gd = geometryDecisions[gi];
            geometryByRangeBuilder.put(gd.range, gd);
        }
        final geometryByRange = geometryByRangeBuilder.build();

        final leadingGapRangesBuilder = SortedSet.builder();
        final trailingGapRangesBuilder = SortedSet.builder();
        for (ai in 0...autoSpaceDecisions.length) {
            final ad = autoSpaceDecisions[ai];
            if (ad.side == "leading") {
                leadingGapRangesBuilder.put(ad.clusterRange);
            } else if (ad.side == "trailing") {
                trailingGapRangesBuilder.put(ad.clusterRange);
            }
        }
        final leadingGapRanges = leadingGapRangesBuilder.build();
        final trailingGapRanges = trailingGapRangesBuilder.build();

        final decorationSegments = AnnotationGeometryStage.computeDecorationSegments(input.decorations, visibleLineRanges, lines, finalClusters,
            justifyDeltaByCluster, geometryByRange, leadingGapRanges, trailingGapRanges, autoSpaceGapPx, fontSize);
        final rubyDecisions = AnnotationGeometryStage.computeRubyDecisions(pinyinSpans, visibleLineRanges, lines, finalClusters, naturalClusters,
            metricDecisions, rubyFontGeometryBySpan, rubyStackGap, baseAscent, rubyFontSize, rubyFontWeight, input.textStyle.locale);
        final bopomofoSpans = new Array<RubySpan>();
        for (ri in 0...input.rubySpans.length) {
            final rs = input.rubySpans[ri];
            if (rs.kind == RubyKind.Bopomofo) {
                bopomofoSpans.push(rs);
            }
        }
        final bopomofoDecisions = AnnotationGeometryStage.computeBopomofoDecisions(engine, bopomofoSpans, visibleLineRanges, lines, finalClusters,
            naturalClusters, baseAscent, baseDescent, fontSize, bopomofoFontWeightAt, input.textStyle);

        return new AnnotationGeometryStageResult(inlineObjectDecisions, decorationDecisions, decorationSegments, rubyDecisions, bopomofoDecisions);
    }

    private static function trimEdge(lineSourceRange:TextRange, clusterIdx:Int, side:String, naturalClusters:Array<Cluster>,
            autoSpaceDecisions:Array<AutoSpaceDecisionInfo>, autoSpaceGap:Float, autoSpaceEdgeTrims:Array<Float>,
            autoSpaceEdgeDecisions:Array<LineEdgeTrimDecisionInfo>):Void {
        var foundDecision:Null<AutoSpaceDecisionInfo> = null;
        final cRange = naturalClusters[clusterIdx].range;
        for (dec in autoSpaceDecisions) {
            if (dec.clusterRange.start == cRange.start && dec.clusterRange.end == cRange.end && dec.side == side) {
                foundDecision = dec;
                break;
            }
        }
        if (foundDecision != null) {
            autoSpaceEdgeTrims[clusterIdx] += autoSpaceGap;
            autoSpaceEdgeDecisions.push(new LineEdgeTrimDecisionInfo(lineSourceRange, foundDecision.clusterRange, side, autoSpaceGap, 0.0, autoSpaceGap,
                "TextAutoSpaceLineEdgeTrim"));
        }
    }

    private static function collapseEdgeSpace(lineSourceRange:TextRange, clusterIdx:Int, side:String, naturalClusters:Array<Cluster>,
            inlineObjectSeparatorSpaceTrims:SortedMap<Int, Float>, autoSpaceEdgeTrims:Array<Float>,
            autoSpaceEdgeDecisions:Array<LineEdgeTrimDecisionInfo>):Void {
        final cluster = naturalClusters[clusterIdx];
        if (!PunctuationGeometryStage.isSpaceRun(cluster))
            return;
        if (inlineObjectSeparatorSpaceTrims.has(clusterIdx))
            return;
        final advance = cluster.advance;
        if (advance <= 0.0)
            return;
        autoSpaceEdgeTrims[clusterIdx] += advance;
        autoSpaceEdgeDecisions.push(new LineEdgeTrimDecisionInfo(lineSourceRange, cluster.range, side, advance, 0.0, advance, "LineEdgeWordSpaceCollapse"));
    }

    public static function finishParagraphLayout(engine:ExplainableStubParagraphLayoutEngine, prep:ParagraphLayoutPrep,
            plan:LineBreakPlanningStageResult):LayoutResult {
        final appliedHangingClustersBuilder = SortedSet.builder();
        for (line in plan.lineSolution.lines) {
            for (i in 0...line.hangingClusterIndices.size()) {
                appliedHangingClustersBuilder.put(line.hangingClusterIndices.at(i));
            }
        }
        final appliedHangingClusters = appliedHangingClustersBuilder.build();

        final impossibleMeasureContextualHangClustersBuilder = SortedSet.builder();
        for (i in 0...plan.asciiPointMarkKinsoku.impossibleMeasureHangEligibleClusters.size()) {
            impossibleMeasureContextualHangClustersBuilder.put(plan.asciiPointMarkKinsoku.impossibleMeasureHangEligibleClusters.at(i));
        }
        for (i in 0...plan.inlineObjectKinsoku.impossibleMeasureHangEligibleClusters.size()) {
            impossibleMeasureContextualHangClustersBuilder.put(plan.inlineObjectKinsoku.impossibleMeasureHangEligibleClusters.at(i));
        }
        final impossibleMeasureContextualHangClusters = impossibleMeasureContextualHangClustersBuilder.build();

        final rawDecisions = new Array<ContextualKinsokuDecisionInfo>();
        for (d in plan.asciiPointMarkKinsoku.decisions)
            rawDecisions.push(d);
        for (d in plan.inlineObjectKinsoku.decisions)
            rawDecisions.push(d);
        for (d in plan.unicodePunctuationBoundaries.decisions)
            rawDecisions.push(d);

        final seenDecisionKeys = new Array<String>();
        final contextualKinsokuDecisions = new Array<ContextualKinsokuDecisionInfo>();
        for (decision in rawDecisions) {
            final key = decision.range.toString() + ":" + decision.forbiddenPosition;
            var alreadySeen = false;
            for (s in seenDecisionKeys) {
                if (s == key) {
                    alreadySeen = true;
                    break;
                }
            }
            if (!alreadySeen) {
                seenDecisionKeys.push(key);
                final cIdx = decision.clusterIndex;
                if (impossibleMeasureContextualHangClusters.has(cIdx) && appliedHangingClusters.has(cIdx)) {
                    final fallback = decision.reason == "AttachedAsciiPointMarkKinsoku" ? "AttachedAsciiPointMarkImpossibleMeasureHang" : "InlineObjectAttachedMarkImpossibleMeasureHang";
                    contextualKinsokuDecisions.push(new ContextualKinsokuDecisionInfo(decision.range, decision.sourceText, decision.clusterIndex,
                        decision.forbiddenPosition, decision.reason, fallback));
                } else {
                    contextualKinsokuDecisions.push(decision);
                }
            }
        }

        final pushInTrailing = new Array<Float>();
        final pushInLeading = new Array<Float>();
        final pushInRawTrims = new Array<Float>();
        for (i in 0...prep.naturalClusters.length) {
            pushInTrailing.push(0.0);
            pushInLeading.push(0.0);
            pushInRawTrims.push(0.0);
        }

        for (lIdx in 0...plan.lineSolution.lines.length) {
            final line = plan.lineSolution.lines[lIdx];
            final repair = line.repair;
            if (repair != null) {
                final allocations = RepairOptions.pushInAllocations(repair);
                if (allocations != null) {
                    for (aIdx in 0...allocations.length) {
                        final alloc = allocations[aIdx];
                        if (alloc.clusterIndex >= 0 && alloc.clusterIndex < prep.naturalClusters.length) {
                            if (alloc.channel == TrailingGlue) {
                                pushInTrailing[alloc.clusterIndex] += alloc.shrink;
                            } else if (alloc.channel == LeadingGlue) {
                                pushInLeading[alloc.clusterIndex] += alloc.shrink;
                            } else if (alloc.channel == LeadingAndTrailingGlue) {
                                pushInLeading[alloc.clusterIndex] += alloc.shrink / 2.0;
                                pushInTrailing[alloc.clusterIndex] += alloc.shrink / 2.0;
                            } else if (alloc.channel == RawAdvance) {
                                pushInRawTrims[alloc.clusterIndex] += alloc.shrink;
                            }
                        }
                    }
                }
            }
        }

        if (prep.hyphenOffsets.size() > 0) {
            for (lineIndex in 0...plan.lineSolution.lines.length) {
                final line = plan.lineSolution.lines[lineIndex];
                if (line.clusterRange.isEmpty)
                    continue;
                final hyphen = lineHyphenAdvanceAt(lineIndex, plan.lineSolution.lines, prep.hyphenOffsets, prep.naturalClusters, prep.hyphenAdvance);
                if (hyphen <= 0.0)
                    continue;
                final lineLimit = line.clusterRange.start == 0 ? prep.measure - plan.firstLineIndent : prep.measure - plan.blockIndent;
                var content = 0.0;
                for (cIdx in line.clusterRange.start...line.clusterRange.end + 1) {
                    content += prep.clusters[cIdx].advance;
                }
                var shortfall = content + hyphen - lineLimit;
                if (shortfall <= 0.001)
                    continue;

                final sortedOpportunities = new Array<org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity>();
                for (opp in prep.shrinkOpportunities) {
                    if (opp.clusterIndex >= line.clusterRange.start && opp.clusterIndex <= line.clusterRange.end && !opp.lineEndOnly) {
                        sortedOpportunities.push(opp);
                    }
                }
                var rIdx = 1;
                while (rIdx < sortedOpportunities.length) {
                    final curr = sortedOpportunities[rIdx];
                    var j = rIdx - 1;
                    while (j >= 0 && sortedOpportunities[j].tier > curr.tier) {
                        sortedOpportunities[j + 1] = sortedOpportunities[j];
                        j--;
                    }
                    sortedOpportunities[j + 1] = curr;
                    rIdx++;
                }

                for (oIdx in 0...sortedOpportunities.length) {
                    final opp = sortedOpportunities[oIdx];
                    if (shortfall <= 0.001)
                        break;
                    var used = 0.0;
                    if (opp.channel == TrailingGlue) {
                        used = pushInTrailing[opp.clusterIndex];
                    } else if (opp.channel == LeadingGlue) {
                        used = pushInLeading[opp.clusterIndex];
                    } else if (opp.channel == RawAdvance) {
                        used = pushInRawTrims[opp.clusterIndex];
                    } else if (opp.channel == LeadingAndTrailingGlue) {
                        used = pushInLeading[opp.clusterIndex] + pushInTrailing[opp.clusterIndex];
                    }
                    final avail = opp.capacity - used;
                    final target = shortfall < avail ? shortfall : avail;
                    final take = target < 0.0 ? 0.0 : target;
                    if (take <= 0.0)
                        continue;
                    if (opp.channel == TrailingGlue) {
                        pushInTrailing[opp.clusterIndex] += take;
                    } else if (opp.channel == LeadingGlue) {
                        pushInLeading[opp.clusterIndex] += take;
                    } else if (opp.channel == LeadingAndTrailingGlue) {
                        pushInLeading[opp.clusterIndex] += take / 2.0;
                        pushInTrailing[opp.clusterIndex] += take / 2.0;
                    } else if (opp.channel == RawAdvance) {
                        pushInRawTrims[opp.clusterIndex] += take;
                    }
                    shortfall -= take;
                }
            }
        }

        final pushInTrailingMapBuilder = SortedMap.builder();
        final pushInLeadingMapBuilder = SortedMap.builder();
        for (i in 0...prep.naturalClusters.length) {
            if (pushInTrailing[i] != 0.0)
                pushInTrailingMapBuilder.put(i, pushInTrailing[i]);
            if (pushInLeading[i] != 0.0)
                pushInLeadingMapBuilder.put(i, pushInLeading[i]);
        }
        final pushInGeometry = prep.baseGeometry.consumeTrailingByCluster(pushInTrailingMapBuilder.build())
            .consumeLeadingByCluster(pushInLeadingMapBuilder.build());

        final edgeTrimResult = pushInGeometry.consumeLineEdgeGlue(plan.lineSolution.lines,
            prep.adjustmentStyle.lineEndPunctuation == LineEndPunctuationStyle.ForceHalfWidth);

        final autoSpaceGap = prep.clreqProfile.autoSpace.gapEm * prep.fontSize;
        final autoSpaceEdgeTrims = new Array<Float>();
        for (i in 0...prep.naturalClusters.length)
            autoSpaceEdgeTrims.push(0.0);
        final autoSpaceEdgeDecisions = new Array<LineEdgeTrimDecisionInfo>();

        for (line in plan.lineSolution.lines) {
            if (line.clusterRange.isEmpty)
                continue;

            trimEdge(line.sourceRange, line.clusterRange.end, "trailing", prep.naturalClusters, prep.autoSpaceDecisions, autoSpaceGap, autoSpaceEdgeTrims,
                autoSpaceEdgeDecisions);
            trimEdge(line.sourceRange, line.clusterRange.start, "leading", prep.naturalClusters, prep.autoSpaceDecisions, autoSpaceGap, autoSpaceEdgeTrims,
                autoSpaceEdgeDecisions);

            collapseEdgeSpace(line.sourceRange, line.clusterRange.end, "trailing", prep.naturalClusters, prep.inlineObjectSeparatorSpaceTrims,
                autoSpaceEdgeTrims, autoSpaceEdgeDecisions);
            collapseEdgeSpace(line.sourceRange, line.clusterRange.start, "leading", prep.naturalClusters, prep.inlineObjectSeparatorSpaceTrims,
                autoSpaceEdgeTrims, autoSpaceEdgeDecisions);

            final attachedGlueCluster = line.clusterRange.end;
            final attachedGlue = prep.attachedPunctuationTrailingGlueByCluster.has(attachedGlueCluster) ? prep.attachedPunctuationTrailingGlueByCluster.get(attachedGlueCluster) : 0.0;
            if (attachedGlue > 0.0) {
                autoSpaceEdgeTrims[attachedGlueCluster] += attachedGlue;
                autoSpaceEdgeDecisions.push(new LineEdgeTrimDecisionInfo(line.sourceRange, prep.naturalClusters[attachedGlueCluster].range, "trailing",
                    attachedGlue, 0.0, attachedGlue, "AttachedInlineVirtualBoundaryLineEndTrim"));
            }

            if (line.endReason == LineEndReason.AutoWrap) {
                final clusterIdx = line.clusterRange.end;
                final discardable = prep.inlineObjectByClusterIndex.has(clusterIdx) ? prep.inlineObjectByClusterIndex.get(clusterIdx)
                    .trailingBoundary.lineEndDiscardableAdvance : 0.0;
                final consumedBefore = pushInRawTrims[clusterIdx] < discardable ? pushInRawTrims[clusterIdx] : discardable;
                final diff = discardable - consumedBefore;
                final remaining = diff < 0.0 ? 0.0 : diff;
                if (remaining > 0.0) {
                    autoSpaceEdgeTrims[clusterIdx] += remaining;
                    autoSpaceEdgeDecisions.push(new LineEdgeTrimDecisionInfo(line.sourceRange, prep.naturalClusters[clusterIdx].range, "trailing", remaining,
                        consumedBefore, discardable, "InlineObjectLineEndDiscardableGlue"));
                }
            }
        }

        final rawTrimsBuilder = SortedMap.builder();
        for (i in 0...prep.naturalClusters.length) {
            final total = autoSpaceEdgeTrims[i] + pushInRawTrims[i];
            if (total != 0.0) {
                rawTrimsBuilder.put(i, total);
            }
        }
        final trimmedGeometry = edgeTrimResult.geometry.withRawEdgeTrims(rawTrimsBuilder.build());
        final trimmedClusters = trimmedGeometry.resolveClusters();

        final edgeTrimDecisions = new Array<LineEdgeTrimDecisionInfo>();
        for (d in edgeTrimResult.decisions)
            edgeTrimDecisions.push(d);
        for (d in autoSpaceEdgeDecisions)
            edgeTrimDecisions.push(d);

        final justificationPlans = new Array<Null<JustificationPlan>>();
        for (lineIndex in 0...plan.lineSolution.lines.length) {
            final lineCandidate = plan.lineSolution.lines[lineIndex];
            final isLast = lineIndex == plan.lineSolution.lines.length - 1;
            if (isLast || lineCandidate.clusterRange.isEmpty || lineCandidate.endReason != LineEndReason.AutoWrap) {
                justificationPlans.push(null);
            } else {
                final nextIdx = lineCandidate.clusterRange.end + 1;
                final selectedTechnicalBreak = plan.progressiveBreakOpportunities.has(nextIdx) ? plan.progressiveBreakOpportunities.get(nextIdx) : null;
                final preferredTrackingSpan = (selectedTechnicalBreak != null
                    && selectedTechnicalBreak.tier == ProgressiveBreakTier.Emergency) ? selectedTechnicalBreak.spanRange : null;

                final preferredEmergencyTrackingBoundariesBuilder = SortedMap.builder();
                if (preferredTrackingSpan != null) {
                    for (i in 0...plan.emergencyTrackingBoundaryAfterClusters.size()) {
                        final leftIndex = plan.emergencyTrackingBoundaryAfterClusters.keyAt(i);
                        final reason = plan.emergencyTrackingBoundaryAfterClusters.valueAt(i);
                        final rightIndex = leftIndex + 1;
                        if (prep.naturalClusters[leftIndex].range.start >= preferredTrackingSpan.start
                            && prep.naturalClusters[rightIndex].range.end <= preferredTrackingSpan.end) {
                            preferredEmergencyTrackingBoundariesBuilder.put(leftIndex, reason);
                        }
                    }
                }
                final preferredEmergencyTrackingBoundaries = preferredEmergencyTrackingBoundariesBuilder.build();

                final hyphenAdvanceForLine = lineHyphenAdvanceAt(lineIndex, plan.lineSolution.lines, prep.hyphenOffsets, prep.naturalClusters,
                    prep.hyphenAdvance);
                final lineLimit = (lineCandidate.clusterRange.start == 0 ? (prep.measure - plan.firstLineIndent) : (prep.measure - plan.blockIndent))
                    - hyphenAdvanceForLine;

                final planResult = engine.justifier.justify(trimmedClusters, prep.clusterRoles, prep.eastAsianSpacingEdges,
                    lineCandidate.inMeasureClusterRange, lineLimit, prep.fontSize, false, null, prep.adjustmentStyle.allowSinoWesternGapAdjustment,
                    prep.clreqProfile.autoSpace.gapEm, prep.clreqProfile.autoSpace.stretchMaxEm, plan.noStretchBoundaryClusters,
                    plan.noStretchBoundaryAfterClusters, plan.westernBracketCjkInterCharBoundaryAfterClusters,
                    plan.attachedInlinePhysicalBoundaryAfterClusters, plan.attachedInlineVirtualBoundaryAfterClusters,
                    plan.attachedInlineVirtualSinoWesternBoundaryAfterClusters, prep.uniformInlineObjectBoundaryAfterClusters,
                    prep.preferredInlineObjectBoundaryAfterClusters, plan.technicalBoundaryAfterClusters, plan.emergencyTrackingBoundaryAfterClusters,
                    preferredEmergencyTrackingBoundaries);
                justificationPlans.push(planResult);
            }
        }

        final currentLineTechnicalBodyStretchLimit = CURRENT_LINE_TECHNICAL_BODY_STRETCH_LIMIT_EM * prep.fontSize;
        final newlyRejectedSpans = new Array<TextRange>();
        final newlyRejectedTiersList = new Array<SortedSet<Int>>();

        for (lineIndex in 0...plan.lineSolution.lines.length) {
            final line = plan.lineSolution.lines[lineIndex];
            if (line.endReason != LineEndReason.AutoWrap || line.clusterRange.start > line.clusterRange.end) {
                continue;
            }
            final nextCluster = line.clusterRange.end + 1;
            if (!plan.progressiveBreakOpportunities.has(nextCluster)) {
                continue;
            }
            final selectedTechnicalBreak = plan.progressiveBreakOpportunities.get(nextCluster);
            if (selectedTechnicalBreak.tier == ProgressiveBreakTier.Emergency) {
                continue;
            }
            final spanRange = selectedTechnicalBreak.spanRange;
            if (prep.rejectedTechnicalTiersBySpan.has(spanRange)) {
                final rejectedForSpan = prep.rejectedTechnicalTiersBySpan.get(spanRange);
                if (rejectedForSpan.has(selectedTechnicalBreak.tier)) {
                    continue;
                }
            }
            final currentLinePlan = justificationPlans[lineIndex];
            if (currentLinePlan == null)
                continue;

            var currentLineUsesUnboundedTracking = false;
            for (alloc in currentLinePlan.allocations) {
                if ((alloc.kind == GlueKind.CjkInterChar || alloc.kind == GlueKind.EmergencyGraphemeTracking)
                    && alloc.delta > currentLineTechnicalBodyStretchLimit + TECHNICAL_STRETCH_EPSILON_PX) {
                    currentLineUsesUnboundedTracking = true;
                    break;
                }
            }
            if (currentLineUsesUnboundedTracking) {
                var foundSpanIdx = -1;
                for (sIdx in 0...newlyRejectedSpans.length) {
                    if (newlyRejectedSpans[sIdx].start == spanRange.start && newlyRejectedSpans[sIdx].end == spanRange.end) {
                        foundSpanIdx = sIdx;
                        break;
                    }
                }
                if (foundSpanIdx < 0) {
                    newlyRejectedSpans.push(spanRange);
                    final b:std.SortedSetBuilder<Int> = std.SortedSet.builder();
                    b.put(selectedTechnicalBreak.tier.priority);
                    newlyRejectedTiersList.push(b.build());
                } else {
                    final b:std.SortedSetBuilder<Int> = std.SortedSet.builder();
                    final existing = newlyRejectedTiersList[foundSpanIdx];
                    for (e in 0...existing.size())
                        b.put(existing.at(e));
                    b.put(selectedTechnicalBreak.tier.priority);
                    newlyRejectedTiersList[foundSpanIdx] = b.build();
                }
            }
        }

        if (newlyRejectedSpans.length > 0) {
            final updatedRejectedTiersBuilder = SortedMap.builder();
            for (i in 0...prep.rejectedTechnicalTiersBySpan.size()) {
                final span = prep.rejectedTechnicalTiersBySpan.keyAt(i);
                final tiers = prep.rejectedTechnicalTiersBySpan.valueAt(i);
                final b:std.SortedSetBuilder<Int> = std.SortedSet.builder();
                for (t in 0...tiers.size())
                    b.put(tiers.at(t));
                for (nIdx in 0...newlyRejectedSpans.length) {
                    if (newlyRejectedSpans[nIdx].start == span.start && newlyRejectedSpans[nIdx].end == span.end) {
                        final addTiers = newlyRejectedTiersList[nIdx];
                        for (at in 0...addTiers.size())
                            b.put(addTiers.at(at));
                    }
                }
                updatedRejectedTiersBuilder.put(span, b.build());
            }
            for (nIdx in 0...newlyRejectedSpans.length) {
                final span = newlyRejectedSpans[nIdx];
                if (!prep.rejectedTechnicalTiersBySpan.has(span)) {
                    updatedRejectedTiersBuilder.put(span, newlyRejectedTiersList[nIdx]);
                }
            }
            return engine.layoutWithRejectedTechnicalTiers(prep.input, updatedRejectedTiersBuilder.build());
        }

        final justifyDeltas = new Array<Float>();
        for (i in 0...prep.naturalClusters.length)
            justifyDeltas.push(0.0);
        for (p in justificationPlans) {
            if (p != null) {
                for (alloc in p.allocations) {
                    if (alloc.targetClusterIndex >= 0 && alloc.targetClusterIndex < justifyDeltas.length) {
                        justifyDeltas[alloc.targetClusterIndex] += alloc.delta;
                    }
                }
            }
        }
        final justifyDeltaBuilder = SortedMap.builder();
        for (i in 0...justifyDeltas.length) {
            if (justifyDeltas[i] != 0.0) {
                justifyDeltaBuilder.put(i, justifyDeltas[i]);
            }
        }
        final justifyDeltaByCluster = justifyDeltaBuilder.build();
        final finalGeometry = trimmedGeometry.addJustificationDeltas(justifyDeltaByCluster);
        final resolvedFinalClusters = finalGeometry.resolveClusters();
        final finalClusters = new Array<Cluster>();
        for (c in resolvedFinalClusters) {
            if (!plan.metricDecisionByRange.has(c.range)) {
                finalClusters.push(c);
            } else {
                final m = plan.metricDecisionByRange.get(c.range).layoutMetrics;
                final metricShift = m.baselineClass == BaselineClass.Roman ? 0.0 : plan.baseBoxDescent - m.descent;
                final shift = c.baselineShift + metricShift + prep.styleAt(c.range.start).baselineShift;
                if (shift > -0.01 && shift < 0.01) {
                    finalClusters.push(c);
                } else {
                    finalClusters.push(new Cluster(c.range, c.text, c.fontKey, c.advance, c.displayText, shift, c.leadingLayoutAdvance, c.glyphInlineShift));
                }
            }
        }
        final geometryDecisions = finalGeometry.toDecisionInfo();

        final runGroups = renderableGlyphRunClusters(finalClusters, prep.openTypeFeaturesByClusterRange);
        final glyphRuns = new Array<GlyphRun>();
        for (runClusters in runGroups) {
            final firstC = runClusters[0];
            final lastC = runClusters[runClusters.length - 1];
            final openTypeFeatures = prep.openTypeFeaturesByClusterRange.has(firstC.range) ? prep.openTypeFeaturesByClusterRange.get(firstC.range) : [];
            final runGlyphs = new Array<Glyph>();
            var runAdvance = 0.0;
            for (clusterIdx in 0...runClusters.length) {
                final cluster = runClusters[clusterIdx];
                runAdvance += cluster.advance;
                if (prep.shapedGlyphsByClusterRange.has(cluster.range)) {
                    final shaped = prep.shapedGlyphsByClusterRange.get(cluster.range);
                    final mapped = ParagraphShapingStage.mapToClusterRange(shaped, cluster);
                    final centered = centerDashInk(mapped, cluster, prep.atomClassByRange);
                    for (g in centered)
                        runGlyphs.push(g);
                } else {
                    runGlyphs.push(new Glyph(clusterIdx, cluster.range, cluster.advance));
                }
            }
            glyphRuns.push(new GlyphRun(new TextRange(firstC.range.start, lastC.range.end), firstC.fontKey, runGlyphs, runAdvance, openTypeFeatures));
        }
        final verticalGeometry = LineGeometryStageFns.resolveLineVerticalGeometrySorted(prep.input, prep.fontSize, prep.pinyinSpans, prep.naturalClusters,
            plan.lineSolution, prep.rubyFontGeometryBySpan, plan.existingInterlineSpace, plan.baseLineMetrics, plan.baseFaceHeight, plan.rubyExtent,
            prep.inlineObjectByClusterIndex, plan.baseAscent, plan.baseDescent);
        final rubyLineHeightDecision = verticalGeometry.rubyLineHeightDecision;
        final inlineObjectLineHeightDecision = verticalGeometry.inlineObjectLineHeightDecision;
        final lineBaseline = verticalGeometry.lineBaseline;
        final lineTop = verticalGeometry.lineTop;
        final lineBottom = verticalGeometry.lineBottom;

        final lineBoxes = buildLineBoxes(prep.input, plan.lineSolution, trimmedClusters, finalClusters, plan.firstLineIndent, plan.blockIndent, prep.measure,
            prep.gridBodyOffset, lineBaseline, lineTop, lineBottom, prep.hyphenOffsets, prep.naturalClusters, prep.hyphenAdvance, prep.hyphenGlyphs,
            justificationPlans);
        final laidOutLines = lineBoxes.laidOutLines;
        final lines = lineBoxes.visibleLines;
        final maxLinesDecision = lineBoxes.maxLinesDecision;
        final visibleLineRanges = lineBoxes.visibleLineRanges;

        final annotationGeometry = resolveAnnotationGeometry(engine, prep.input, prep.fontSize, prep.inlineObjectByClusterIndex, plan.lineSolution,
            prep.clreqProfile, geometryDecisions, prep.autoSpaceDecisions, visibleLineRanges, lines, finalClusters, prep.clusterRoles, justifyDeltaByCluster,
            prep.rubyAndBopomofoSpread, plan.metricDecisions, prep.pinyinSpans, prep.naturalClusters, prep.rubyFontGeometryBySpan, prep.rubyStackGap,
            plan.baseAscent, prep.rubyFontSize, prep.rubyFontWeight, plan.baseDescent, prep.bopomofoFontWeightAt);
        final inlineObjectDecisions = annotationGeometry.inlineObjectDecisions;
        final decorationDecisions = annotationGeometry.decorationDecisions;
        final decorationSegments = annotationGeometry.decorationSegments;
        final rubyDecisions = annotationGeometry.rubyDecisions;
        final bopomofoDecisions = annotationGeometry.bopomofoDecisions;

        var widestLine:Float = 0.0;
        for (i in 0...lines.length) {
            final line = lines[i];
            final w = line.indent + line.visualWidth + line.hyphenAdvance;
            if (w > widestLine)
                widestLine = w;
        }
        var totalHeight:Float = 0.0;
        if (lines.length > 0) {
            totalHeight = lines[lines.length - 1].bottom;
        } else if (prep.text.length == 0) {
            totalHeight = 0.0;
        } else {
            totalHeight = plan.baseLineMetrics.height;
        }
        final maxWidthConstraint = prep.input.constraints.maxWidth;
        final resultWidth = widestLine > maxWidthConstraint ? maxWidthConstraint : widestLine;

        return new LayoutResult(prep.input, new Size(resultWidth, totalHeight), finalClusters, glyphRuns, lines,
            LayoutDebugAssembly.buildLayoutDebugInfo(engine,
                new LayoutDebugStageInput(prep.text, prep.fontDecisions, prep.punctuationGlyphSubstitutor, prep.substitutionRollbacks, prep.shapingDecisions,
                    plan.metricDecisions, prep.punctuationAtoms, geometryDecisions, prep.spacingPlan, prep.attachedPunctuationBoundary,
                    prep.roleOverrideInfos, laidOutLines, plan.lineSolution, prep.clusters, justificationPlans, prep.autoSpaceDecisions, edgeTrimDecisions,
                    decorationDecisions, decorationSegments, rubyDecisions, bopomofoDecisions, prep.mandatoryBreakDecisions, maxLinesDecision,
                    plan.lineSpacingDecision, rubyLineHeightDecision, inlineObjectLineHeightDecision, plan.kinsokuDecision, contextualKinsokuDecisions,
                    prep.lineLengthGridDecision, plan.firstLineIndentDecision, prep.inlineBoxResult.decisions, inlineObjectDecisions,
                    prep.inlineObjectPunctuationAttachmentDecisions, prep.zeroWidthBreakDecisions, prep.breakOpportunityDecisions,
                    prep.emergencyTrackingEligibilityDecisions, plan.progressiveBreakOpportunities)));
    }
}
