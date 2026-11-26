package org.tiqian.layout;

import org.tiqian.clreq.AutoSpaceMode;
import org.tiqian.clreq.PunctuationClass;
import org.tiqian.clreq.ResolvedKinsoku;
import org.tiqian.core.AccurateSum;
import org.tiqian.core.AutoSpaceDecisionInfo;
import org.tiqian.core.Cluster;
import org.tiqian.core.EastAsianSpacingEdges;
import org.tiqian.core.EastAsianSpacingValue;
import org.tiqian.core.Glyph;
import org.tiqian.core.InlineAttachment;
import org.tiqian.core.InlineBoxOuterSpacing;
import org.tiqian.core.InlineBoxSpan;
import org.tiqian.core.InlineObjectBoundaryAdjustment;
import org.tiqian.core.InlineObjectPreferredStretch;
import org.tiqian.core.InlineObjectPunctuationAttachmentDecisionInfo;
import org.tiqian.core.InlineObjectSpan;
import org.tiqian.core.IntRange;
import org.tiqian.core.LayoutInput;
import org.tiqian.core.MandatoryBreakDecisionInfo;
import org.tiqian.core.RubyKind;
import org.tiqian.core.RubySpan;
import org.tiqian.core.ShapingDecisionInfo;
import org.tiqian.core.TextRange;
import org.tiqian.core.UnicodeEastAsianSpacing;
import org.tiqian.core.ZeroWidthBreakDecisionInfo;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.font.FontRole;
import org.tiqian.layout.AnnotationGeometryStage.RubyFontGeometry;
import org.tiqian.layout.ClusterRoleResolution;
import org.tiqian.layout.KinsokuRule.ClreqKinsokuRule;
import org.tiqian.layout.ParagraphPrepParts.KinsokuDependentPrep;
import org.tiqian.layout.ParagraphPrepParts.ShapedParagraphBase;
import org.tiqian.layout.ParagraphShapingStage.ParagraphShapingStageResult;
import org.tiqian.layout.ParagraphShapingStage;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.PunctuationGeometryLedger;
import org.tiqian.layout.PunctuationGeometryStage;
import org.tiqian.layout.PunctuationModel.PunctuationAtom;
import org.tiqian.layout.PunctuationModel.PunctuationAtomBuilder;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingCompressionResult;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingCompressor;
import org.tiqian.layout.WidthIndependentAnnotationCache.WidthIndependentParagraphAnnotation;
import std.SortedMap;
import std.SortedSet;

/**
 * `ParagraphPrepPartsBuilder`: builds the two cacheable parts of a `ParagraphLayoutPrep`,
 * `ShapedParagraphBase` and `KinsokuDependentPrep` (see `ParagraphPrepParts`), together with the
 * helpers only these builders use. `WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep`
 * calls the builders on a cache miss of the prep's `WidthIndependentLayoutMemo`.
 */
class ParagraphPrepPartsBuilder {
    private static inline final RUBY_MIN_GAP_EM_OF_RUBY:Float = 0.25;
    private static inline final WORD_SPACE_MIN_EM:Float = 0.25;
    private static inline final SINO_WESTERN_GAP_MIN_EM:Float = 0.125;

    private static function isFixedBoundary(b:InlineObjectBoundaryAdjustment):Bool {
        return !b.participatesInUniformStretch && b.preferredStretch == null && b.shrinkCapacity == 0.0 && b.lineEndDiscardableAdvance == 0.0
            && !b.preventsLineBreak;
    }

    public static function isContainedIn(r:TextRange, other:TextRange):Bool {
        return r.start >= other.start && r.end <= other.end;
    }

    public static function containingFontDecisions(clusters:Array<Cluster>, items:Array<FontDecision>):Array<Null<FontDecision>> {
        var itemIndex = 0;
        final result = new Array<Null<FontDecision>>();
        for (i in 0...clusters.length) {
            final cluster = clusters[i];
            while (itemIndex < items.length && items[itemIndex].range.end <= cluster.range.start) {
                itemIndex += 1;
            }
            if (itemIndex < items.length) {
                final item = items[itemIndex];
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

    public static function firstContainedAtom(clusters:Array<Cluster>, items:Array<PunctuationAtom>):Array<Null<PunctuationAtom>> {
        var itemIndex = 0;
        final result = new Array<Null<PunctuationAtom>>();
        for (i in 0...clusters.length) {
            final cluster = clusters[i];
            while (itemIndex < items.length && items[itemIndex].range.end <= cluster.range.start) {
                itemIndex += 1;
            }
            if (itemIndex < items.length) {
                final item = items[itemIndex];
                if (item.range.start >= cluster.range.start && item.range.end <= cluster.range.end) {
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

    private static function isInlineStop(code:Int):Bool {
        return code == 0x3002 || code == 0xFF01 || code == 0xFF1F || code == 0xFF0E;
    }

    private static function computeRubySpread(natural:Array<Cluster>, rubySize:Float, pinyinSpans:Array<RubySpan>,
            rubyFontGeometryBySpan:SortedMap<RubySpan, RubyFontGeometry>):SortedMap<Int, Float> {
        if (pinyinSpans.length == 0)
            return SortedMap.builder().build();
        final wordSpace = rubySize * RUBY_MIN_GAP_EM_OF_RUBY;
        final leftX = new Array<Float>();
        var acc = 0.0;
        for (i in 0...natural.length) {
            leftX.push(acc);
            acc += natural[i].advance;
        }

        final measuresFirstCluster = new Array<Int>();
        final measuresCenter = new Array<Float>();
        final measuresRw = new Array<Float>();
        for (i in 0...pinyinSpans.length) {
            final ruby = pinyinSpans[i];
            final idxRange = PunctuationGeometryLedger.clusterIndexRangeFor(natural, ruby.baseRange);
            if (idxRange == null)
                continue;
            final center = (leftX[idxRange.start] + leftX[idxRange.end] + natural[idxRange.end].advance) / 2.0;
            final geom = rubyFontGeometryBySpan.get(ruby);
            measuresFirstCluster.push(idxRange.start);
            measuresCenter.push(center);
            measuresRw.push(geom.width);
        }
        var mIdx = 1;
        while (mIdx < measuresFirstCluster.length) {
            final currFc = measuresFirstCluster[mIdx];
            final currCenter = measuresCenter[mIdx];
            final currRw = measuresRw[mIdx];
            var j = mIdx - 1;
            while (j >= 0 && measuresFirstCluster[j] > currFc) {
                measuresFirstCluster[j + 1] = measuresFirstCluster[j];
                measuresCenter[j + 1] = measuresCenter[j];
                measuresRw[j + 1] = measuresRw[j];
                j--;
            }
            measuresFirstCluster[j + 1] = currFc;
            measuresCenter[j + 1] = currCenter;
            measuresRw[j + 1] = currRw;
            mIdx++;
        }

        final spreadBuilder = SortedMap.builder();
        final spreadKeys = new Array<Int>();
        final spreadValues = new Array<Float>();
        function getSpread(key:Int):Float {
            for (i in 0...spreadKeys.length) {
                if (spreadKeys[i] == key)
                    return spreadValues[i];
            }
            return 0.0;
        }
        function putSpread(key:Int, val:Float):Void {
            for (i in 0...spreadKeys.length) {
                if (spreadKeys[i] == key) {
                    spreadValues[i] = val;
                    return;
                }
            }
            spreadKeys.push(key);
            spreadValues.push(val);
        }

        var shift = 0.0;
        var prevRight = -1e9;
        for (m in 0...measuresFirstCluster.length) {
            final firstCluster = measuresFirstCluster[m];
            final rw = measuresRw[m];
            var center = measuresCenter[m] + shift;
            final needed = prevRight + wordSpace - (center - rw / 2.0);
            if (needed > 0.0 && firstCluster > 0) {
                final key = firstCluster - 1;
                putSpread(key, getSpread(key) + needed);
                shift += needed;
                center += needed;
            }
            prevRight = center + rw / 2.0;
        }
        for (i in 0...spreadKeys.length) {
            spreadBuilder.put(spreadKeys[i], spreadValues[i]);
        }
        return spreadBuilder.build();
    }

    private static function addGeometryAwareOpportunity(shrinkOpportunities:Array<ShrinkOpportunity>,
            caps:org.tiqian.layout.PunctuationGeometryLedger.GlueCapacity, idx:Int, tier:Int, lineEndOnly:Bool = false):Void {
        if (caps.paired) {
            final minGlue = caps.leading < caps.trailing ? caps.leading : caps.trailing;
            final pairedCapacity = 2.0 * minGlue;
            if (pairedCapacity > 0.0) {
                shrinkOpportunities.push(new ShrinkOpportunity(idx, tier, pairedCapacity, ShrinkChannel.LeadingAndTrailingGlue, lineEndOnly));
            }
        } else {
            if (caps.leading > 0.0) {
                shrinkOpportunities.push(new ShrinkOpportunity(idx, tier, caps.leading, ShrinkChannel.LeadingGlue, lineEndOnly));
            }
            if (caps.trailing > 0.0) {
                shrinkOpportunities.push(new ShrinkOpportunity(idx, tier, caps.trailing, ShrinkChannel.TrailingGlue, lineEndOnly));
            }
        }
    }

    /** Adjacent-punctuation compression followed by CJK-closing-before-ASCII-point-mark compression of `punctuationAtoms`. */
    private static function compressPunctuationSpacing(punctuationSpacingCompressor:PunctuationSpacingCompressor, punctuationAtoms:Array<PunctuationAtom>,
            text:String, fontSize:Float):PunctuationSpacingCompressionResult {
        final adjacentPunctuationSpacingPlan = punctuationSpacingCompressor.compress(punctuationAtoms, fontSize);
        final cjkClosingBeforeAsciiPointMarkPlan = punctuationSpacingCompressor.compressCjkClosingBeforeAsciiPointMark(punctuationAtoms, text, fontSize);
        final allAdjustments = new Array<org.tiqian.layout.PunctuationModel.PunctuationSpacingAdjustment>();
        for (i in 0...adjacentPunctuationSpacingPlan.adjustments.length)
            allAdjustments.push(adjacentPunctuationSpacingPlan.adjustments[i]);
        for (i in 0...cjkClosingBeforeAsciiPointMarkPlan.adjustments.length)
            allAdjustments.push(cjkClosingBeforeAsciiPointMarkPlan.adjustments[i]);
        return new PunctuationSpacingCompressionResult(allAdjustments);
    }

    /**
     * The `ShapedParagraphBase` of one shaping stage; see that class for what it holds. It takes the
     * two engine components it uses instead of the engine: boring's Rust target narrows an engine
     * parameter to the engine fields a function reads, and a helper that also reads fields of
     * another object parameter misattributes them to the engine.
     */
    public static function buildShapedParagraphBase(punctuationAtomBuilder:PunctuationAtomBuilder,
            punctuationSpacingCompressor:PunctuationSpacingCompressor, input:LayoutInput, annotation:WidthIndependentParagraphAnnotation,
            shapingStage:ParagraphShapingStageResult):ShapedParagraphBase {
        final text = annotation.text;
        final fontSize = input.textStyle.fontSize;

        final shapingResults = shapingStage.shapingResults;
        final rawNaturalClusters = new Array<Cluster>();
        for (i in 0...shapingResults.length) {
            final res = shapingResults[i];
            for (c in 0...res.clusters.length)
                rawNaturalClusters.push(res.clusters[c]);
        }

        final shapedGlyphsByClusterRangeBuilder = SortedMap.builder();
        final openTypeFeaturesByClusterRangeBuilder = SortedMap.builder();

        final glyphsByClusterRangeKeys = new Array<TextRange>();
        final glyphsByClusterRangeValues = new Array<Array<Glyph>>();
        final openTypeFeatureKeys = new Array<TextRange>();
        final openTypeFeatureValues = new Array<Array<String>>();
        // Glyphs arrive in text order, so the entry a glyph needs is the last
        // one, and a range past it is new. Both cases are constant; only an
        // out-of-order range falls back to the scan. The unconditional scan
        // cost glyphs x keys.
        function addGlyphToClusterRange(range:TextRange, g:Glyph):Void {
            final keyCount = glyphsByClusterRangeKeys.length;
            if (keyCount > 0) {
                final lastKey = glyphsByClusterRangeKeys[keyCount - 1];
                if (lastKey.start == range.start && lastKey.end == range.end) {
                    glyphsByClusterRangeValues[keyCount - 1].push(g);
                    return;
                }
                if (range.start > lastKey.start) {
                    glyphsByClusterRangeKeys.push(range);
                    glyphsByClusterRangeValues.push([g]);
                    return;
                }
            }
            for (i in 0...glyphsByClusterRangeKeys.length) {
                if (glyphsByClusterRangeKeys[i].start == range.start && glyphsByClusterRangeKeys[i].end == range.end) {
                    glyphsByClusterRangeValues[i].push(g);
                    return;
                }
            }
            glyphsByClusterRangeKeys.push(range);
            glyphsByClusterRangeValues.push([g]);
        }

        for (i in 0...shapingResults.length) {
            final res = shapingResults[i];
            for (r in 0...res.glyphRuns.length) {
                final run = res.glyphRuns[r];
                final seenRanges = new Array<TextRange>();
                for (g in 0...run.glyphs.length) {
                    final glyph = run.glyphs[g];
                    addGlyphToClusterRange(glyph.clusterRange, glyph);
                    var rangeSeen = false;
                    for (sr in 0...seenRanges.length) {
                        if (seenRanges[sr].start == glyph.clusterRange.start && seenRanges[sr].end == glyph.clusterRange.end) {
                            rangeSeen = true;
                            break;
                        }
                    }
                    if (!rangeSeen)
                        seenRanges.push(glyph.clusterRange);
                }
                for (sr in 0...seenRanges.length) {
                    final range = seenRanges[sr];
                    final featCopy = new Array<String>();
                    for (fi in 0...run.openTypeFeatures.length)
                        featCopy.push(run.openTypeFeatures[fi]);
                    // Ranges arrive in text order: the previous entry is the last
                    // key, and a range past it has no previous entry.
                    var previousFeatures:Array<String> = null;
                    var featureLookupDone = false;
                    final featureKeyCount = openTypeFeatureKeys.length;
                    if (featureKeyCount > 0) {
                        final lastFeatureKey = openTypeFeatureKeys[featureKeyCount - 1];
                        if (lastFeatureKey.start == range.start && lastFeatureKey.end == range.end) {
                            previousFeatures = openTypeFeatureValues[featureKeyCount - 1];
                            featureLookupDone = true;
                        } else if (range.start > lastFeatureKey.start) {
                            featureLookupDone = true;
                        }
                    }
                    if (!featureLookupDone) {
                        for (pi in 0...openTypeFeatureKeys.length) {
                        if (openTypeFeatureKeys[pi].start == range.start && openTypeFeatureKeys[pi].end == range.end) {
                            previousFeatures = openTypeFeatureValues[pi];
                            break;
                        }
                    }
                    }
                    if (previousFeatures != null) {
                        var sameFeatures = previousFeatures.length == featCopy.length;
                        if (sameFeatures) {
                            for (fi in 0...previousFeatures.length) {
                                if (previousFeatures[fi] != featCopy[fi]) {
                                    sameFeatures = false;
                                    break;
                                }
                            }
                        }
                        if (!sameFeatures)
                            throw new org.tiqian.core.TiqianIllegalArgumentException(org.tiqian.core.TextRangeError.Message("Conflicting OpenType features for shaped cluster "
                                + Std.string(range)));
                    }
                    openTypeFeatureKeys.push(range);
                    openTypeFeatureValues.push(featCopy);
                    openTypeFeaturesByClusterRangeBuilder.put(range, featCopy);
                }
            }
        }
        for (i in 0...glyphsByClusterRangeKeys.length) {
            shapedGlyphsByClusterRangeBuilder.put(glyphsByClusterRangeKeys[i], glyphsByClusterRangeValues[i]);
        }
        final shapedGlyphsByClusterRange = shapedGlyphsByClusterRangeBuilder.build();
        final openTypeFeaturesByClusterRange = openTypeFeaturesByClusterRangeBuilder.build();

        ClusterRoleResolution.requireCoveredBy(rawNaturalClusters, annotation.fontDecisions);

        final inlineObjectRanges = new Array<TextRange>();
        for (i in 0...input.inlineObjects.length)
            inlineObjectRanges.push(input.inlineObjects[i].range);

        final narrowInlineBoxRanges = new Array<TextRange>();
        for (i in 0...input.inlineBoxes.length) {
            final box = input.inlineBoxes[i];
            if (box.outerSpacing == InlineBoxOuterSpacing.Narrow) {
                narrowInlineBoxRanges.push(box.range);
            }
        }

        final narrowInlineBoxLeadingClustersBuilder = SortedSet.builder();
        final narrowInlineBoxTrailingClustersBuilder = SortedSet.builder();
        for (idx in 0...rawNaturalClusters.length) {
            final cl = rawNaturalClusters[idx];
            for (j in 0...narrowInlineBoxRanges.length) {
                if (narrowInlineBoxRanges[j].start == cl.range.start) {
                    narrowInlineBoxLeadingClustersBuilder.put(idx);
                }
                if (narrowInlineBoxRanges[j].end == cl.range.end) {
                    narrowInlineBoxTrailingClustersBuilder.put(idx);
                }
            }
        }
        final narrowInlineBoxLeadingClusters = narrowInlineBoxLeadingClustersBuilder.build();
        final narrowInlineBoxTrailingClusters = narrowInlineBoxTrailingClustersBuilder.build();

        final resolvedSpacingEdges = new Array<EastAsianSpacingEdges>();
        for (index in 0...rawNaturalClusters.length) {
            final cluster = rawNaturalClusters[index];
            var isContained = false;
            for (j in 0...inlineObjectRanges.length) {
                if (isContainedIn(cluster.range, inlineObjectRanges[j])) {
                    isContained = true;
                    break;
                }
            }
            if (isContained
                || (PunctuationGeometryStage.isAttachedAsciiPointMarkAt(rawNaturalClusters, index)
                    && !narrowInlineBoxLeadingClusters.has(index))) {
                resolvedSpacingEdges.push(new EastAsianSpacingEdges(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other, false));
            } else {
                final resolved = UnicodeEastAsianSpacing.resolvedEdges(cluster.text, input.textStyle.locale);
                final leadingVal = narrowInlineBoxLeadingClusters.has(index) ? EastAsianSpacingValue.Narrow : resolved.leading;
                final trailingVal = narrowInlineBoxTrailingClusters.has(index) ? EastAsianSpacingValue.Narrow : resolved.trailing;
                resolvedSpacingEdges.push(new EastAsianSpacingEdges(leadingVal, trailingVal, resolved.containsWide));
            }
        }

        final verbatimRanges = input.content.autoSpaceSuppressedRanges;
        function verbatimSuppressedBoundary(offset:Int):Bool {
            for (i in 0...verbatimRanges.length) {
                final vr = verbatimRanges[i];
                if (vr.start < offset && offset < vr.end)
                    return true;
            }
            return false;
        }

        var eastAsianSpacingEdges = resolvedSpacingEdges;
        if (verbatimRanges.length > 0) {
            final list = new Array<EastAsianSpacingEdges>();
            for (index in 0...resolvedSpacingEdges.length) {
                final edges = resolvedSpacingEdges[index];
                final cluster = rawNaturalClusters[index];
                final leadingSuppressed = !narrowInlineBoxLeadingClusters.has(index) && verbatimSuppressedBoundary(cluster.range.start);
                final trailingSuppressed = !narrowInlineBoxTrailingClusters.has(index) && verbatimSuppressedBoundary(cluster.range.end);
                if (!leadingSuppressed && !trailingSuppressed) {
                    list.push(edges);
                } else {
                    list.push(new EastAsianSpacingEdges(leadingSuppressed ? EastAsianSpacingValue.Other : edges.leading,
                        trailingSuppressed ? EastAsianSpacingValue.Other : edges.trailing, edges.containsWide));
                }
            }
            eastAsianSpacingEdges = list;
        }

        final verbatimSuppressionDecisions = new Array<AutoSpaceDecisionInfo>();
        if (verbatimRanges.length > 0) {
            for (index in 1...rawNaturalClusters.length) {
                final offset = rawNaturalClusters[index].range.start;
                if (!verbatimSuppressedBoundary(offset))
                    continue;
                final left = resolvedSpacingEdges[index - 1].trailing;
                final right = resolvedSpacingEdges[index].leading;
                final wideNarrowPair = (left == EastAsianSpacingValue.Wide && right == EastAsianSpacingValue.Narrow)
                    || (left == EastAsianSpacingValue.Narrow && right == EastAsianSpacingValue.Wide);
                if (!wideNarrowPair)
                    continue;
                verbatimSuppressionDecisions.push(new AutoSpaceDecisionInfo(rawNaturalClusters[index].range, "leading", "EastAsianSpacing.Wide",
                    Std.string(AutoSpaceMode.Disabled), 0, 0.0, 0.0, "VerbatimRangeAutoSpace:east-asian-spacing-W-N-suppressed"));
            }
        }

        final naturalInlineAttachments = new Array<InlineAttachment>();
        for (i in 0...rawNaturalClusters.length) {
            naturalInlineAttachments.push(annotation.styleAt(rawNaturalClusters[i].range.start).inlineAttachment);
        }

        final autoSpaceResult = PunctuationGeometryStage.applyAutoSpacePolicy(rawNaturalClusters, eastAsianSpacingEdges, naturalInlineAttachments,
            annotation.clreqProfile.autoSpace, fontSize, narrowInlineBoxLeadingClusters, narrowInlineBoxTrailingClusters);

        final inlineBoxesCopy = new Array<InlineBoxSpan>();
        for (i in 0...input.inlineBoxes.length)
            inlineBoxesCopy.push(input.inlineBoxes[i]);
        final inlineBoxResult = PunctuationGeometryStage.applyInlineBoxSpans(autoSpaceResult.clusters, inlineBoxesCopy);
        final naturalClusters = inlineBoxResult.clusters;

        final inlineObjectByClusterIndexBuilder:SortedMapBuilder<Int, InlineObjectSpan> = SortedMap.builder();
        final boundaryIndices = new Array<Int>();
        final boundaryAdjustments = new Array<InlineObjectBoundaryAdjustment>();

        function getRegisteredBoundary(leftClusterIndex:Int):Null<InlineObjectBoundaryAdjustment> {
            for (i in 0...boundaryIndices.length) {
                if (boundaryIndices[i] == leftClusterIndex)
                    return boundaryAdjustments[i];
            }
            return null;
        }

        function setRegisteredBoundary(leftClusterIndex:Int, boundary:InlineObjectBoundaryAdjustment):Void {
            for (i in 0...boundaryIndices.length) {
                if (boundaryIndices[i] == leftClusterIndex) {
                    boundaryAdjustments[i] = boundary;
                    return;
                }
            }
            boundaryIndices.push(leftClusterIndex);
            boundaryAdjustments.push(boundary);
        }

        function registerInlineObjectBoundary(leftClusterIndex:Int, boundary:InlineObjectBoundaryAdjustment):Void {
            final previous = getRegisteredBoundary(leftClusterIndex);
            if (previous == null) {
                setRegisteredBoundary(leftClusterIndex, boundary);
                return;
            }
            var prevKind = previous.preferredStretch != null ? previous.preferredStretch.kind : null;
            var boundKind = boundary.preferredStretch != null ? boundary.preferredStretch.kind : null;
            if (prevKind != null && boundKind != null && prevKind != boundKind) {
                throw new org.tiqian.core.TiqianIllegalArgumentException(org.tiqian.core.TextRangeError.Message("Conflicting inline-object stretch classes at cluster boundary "
                    + leftClusterIndex));
            }
            var preferred:Null<InlineObjectPreferredStretch> = null;
            if (previous.preferredStretch != null && boundary.preferredStretch != null) {
                preferred = previous.preferredStretch.capacity >= boundary.preferredStretch.capacity ? previous.preferredStretch : boundary.preferredStretch;
            } else if (previous.preferredStretch != null) {
                preferred = previous.preferredStretch;
            } else {
                preferred = boundary.preferredStretch;
            }
            setRegisteredBoundary(leftClusterIndex,
                new InlineObjectBoundaryAdjustment(previous.participatesInUniformStretch
                    || boundary.participatesInUniformStretch, preferred,
                    Math.max(previous.shrinkCapacity, boundary.shrinkCapacity),
                    Math.max(previous.lineEndDiscardableAdvance, boundary.lineEndDiscardableAdvance), previous.preventsLineBreak || boundary.preventsLineBreak));
        }

        for (clusterIndex in 0...naturalClusters.length) {
            final cluster = naturalClusters[clusterIndex];
            final inlineObject = annotation.inlineObjectByRange.get(cluster.range);
            if (inlineObject != null) {
                inlineObjectByClusterIndexBuilder.put(clusterIndex, inlineObject);
                if (clusterIndex > 0 && !isFixedBoundary(inlineObject.leadingBoundary)) {
                    registerInlineObjectBoundary(clusterIndex - 1, inlineObject.leadingBoundary);
                }
                if (clusterIndex < naturalClusters.length - 1 && !isFixedBoundary(inlineObject.trailingBoundary)) {
                    registerInlineObjectBoundary(clusterIndex, inlineObject.trailingBoundary);
                }
            }
        }
        final inlineObjectByClusterIndex = inlineObjectByClusterIndexBuilder.build();

        final uniformInlineObjectBoundaryBuilder = SortedSet.builder();
        final preferredInlineObjectBoundaryBuilder:SortedMapBuilder<Int, InlineObjectPreferredStretch> = SortedMap.builder();
        final inlineObjectBoundaryUnbreakableRanges = new Array<IntRange>();

        for (i in 0...boundaryIndices.length) {
            final bIdx = boundaryIndices[i];
            final bAdj = boundaryAdjustments[i];
            if (bAdj.participatesInUniformStretch) {
                uniformInlineObjectBoundaryBuilder.put(bIdx);
            }
            if (bAdj.preferredStretch != null) {
                preferredInlineObjectBoundaryBuilder.put(bIdx, bAdj.preferredStretch);
            }
            if (bAdj.preventsLineBreak) {
                inlineObjectBoundaryUnbreakableRanges.push(new IntRange(bIdx, bIdx + 1));
            }
        }
        final uniformInlineObjectBoundaryAfterClusters = uniformInlineObjectBoundaryBuilder.build();
        final preferredInlineObjectBoundaryAfterClusters = preferredInlineObjectBoundaryBuilder.build();

        final autoSpaceDecisions = new Array<AutoSpaceDecisionInfo>();
        for (i in 0...autoSpaceResult.decisions.length)
            autoSpaceDecisions.push(autoSpaceResult.decisions[i]);
        for (i in 0...verbatimSuppressionDecisions.length)
            autoSpaceDecisions.push(verbatimSuppressionDecisions[i]);

        final clusterRolesDecisions = containingFontDecisions(naturalClusters, annotation.fontDecisions);
        final clusterRoles = new Array<FontRole>();
        for (i in 0...clusterRolesDecisions.length) {
            final d = clusterRolesDecisions[i];
            clusterRoles.push(d != null ? d.role : FontRole.Unknown);
        }

        final mandatoryBreakClustersBuilder = SortedSet.builder();
        final zeroWidthBreakClustersBuilder = SortedSet.builder();
        final mandatoryBreakDecisions = new Array<MandatoryBreakDecisionInfo>();
        final zeroWidthBreakDecisions = new Array<ZeroWidthBreakDecisionInfo>();

        for (idx in 0...naturalClusters.length) {
            final cluster = naturalClusters[idx];
            if (ParagraphShapingStage.isMandatoryBreakCluster(cluster)) {
                mandatoryBreakClustersBuilder.put(idx);
                mandatoryBreakDecisions.push(new MandatoryBreakDecisionInfo(cluster.range, cluster.text, idx, "MandatoryBreakNoShape"));
            }
            if (ParagraphShapingStage.isZeroWidthSoftBreakCluster(cluster)) {
                zeroWidthBreakClustersBuilder.put(idx);
                zeroWidthBreakDecisions.push(new ZeroWidthBreakDecisionInfo(cluster.range, cluster.text, idx));
            }
        }
        final mandatoryBreakClusters = mandatoryBreakClustersBuilder.build();
        final zeroWidthBreakClusters = zeroWidthBreakClustersBuilder.build();

        final punctuationAtoms = new Array<PunctuationAtom>();
        for (idx in 0...naturalClusters.length) {
            if (clusterRoles[idx] == FontRole.LatinText)
                continue;
            final cluster = naturalClusters[idx];
            final shapedGlyphsEntry = shapedGlyphsByClusterRange.get(cluster.range);
            final shapedGlyphs:Array<Glyph> = shapedGlyphsEntry == null ? [] : shapedGlyphsEntry;
            final atoms = PunctuationGeometryStage.punctuationAtoms(cluster, fontSize, punctuationAtomBuilder, shapedGlyphs,
                annotation.clreqProfile.gluePlacement, annotation.clreqProfile.punctuationWidth);
            for (a in 0...atoms.length)
                punctuationAtoms.push(atoms[a]);
        }

        final spacingPlan = compressPunctuationSpacing(punctuationSpacingCompressor, punctuationAtoms, text, fontSize);

        final rubySpread = computeRubySpread(naturalClusters, annotation.rubyFontSize, annotation.pinyinSpans, annotation.rubyFontGeometryBySpan);

        final bopomofoSpans = new Array<RubySpan>();
        for (i in 0...input.rubySpans.length) {
            final rs = input.rubySpans[i];
            if (rs.kind == RubyKind.Bopomofo)
                bopomofoSpans.push(rs);
        }

        var rubyAndBopomofoSpread = rubySpread;
        if (bopomofoSpans.length > 0) {
            final mergedBuilder = SortedMap.builder();
            final mergedKeys = new Array<Int>();
            final mergedVals = new Array<Float>();
            for (i in 0...rubySpread.size()) {
                mergedKeys.push(rubySpread.keyAt(i));
                mergedVals.push(rubySpread.valueAt(i));
            }
            for (i in 0...bopomofoSpans.length) {
                final z = bopomofoSpans[i];
                final r = PunctuationGeometryLedger.clusterIndexRangeFor(naturalClusters, z.baseRange);
                if (r == null)
                    continue;
                final lastIdx = r.end;
                var found = false;
                for (j in 0...mergedKeys.length) {
                    if (mergedKeys[j] == lastIdx) {
                        mergedVals[j] += 0.5 * fontSize;
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    mergedKeys.push(lastIdx);
                    mergedVals.push(0.5 * fontSize);
                }
            }
            for (i in 0...mergedKeys.length) {
                mergedBuilder.put(mergedKeys[i], mergedVals[i]);
            }
            rubyAndBopomofoSpread = mergedBuilder.build();
        }

        final shapingDecisionsList = new Array<ShapingDecisionInfo>();
        for (srIdx in 0...shapingStage.shapingResults.length) {
            final sr = shapingStage.shapingResults[srIdx];
            for (dIdx in 0...sr.decisions.length) {
                shapingDecisionsList.push(sr.decisions[dIdx]);
            }
        }

        return new ShapedParagraphBase(shapedGlyphsByClusterRange, openTypeFeaturesByClusterRange, eastAsianSpacingEdges, autoSpaceDecisions,
            inlineBoxResult, naturalClusters, inlineObjectByClusterIndex, uniformInlineObjectBoundaryAfterClusters,
            preferredInlineObjectBoundaryAfterClusters, inlineObjectBoundaryUnbreakableRanges, clusterRoles, mandatoryBreakClusters,
            zeroWidthBreakClusters, mandatoryBreakDecisions, zeroWidthBreakDecisions, punctuationAtoms, spacingPlan, rubyAndBopomofoSpread,
            shapingDecisionsList);
    }

    /** The `KinsokuDependentPrep` of one base at one resolved kinsoku level; see that class for what it holds. */
    public static function buildKinsokuDependentPrep(input:LayoutInput, annotation:WidthIndependentParagraphAnnotation, base:ShapedParagraphBase,
            resolvedKinsoku:ResolvedKinsoku, kinsokuRule:ClreqKinsokuRule):KinsokuDependentPrep {
        final fontSize = input.textStyle.fontSize;
        final naturalClusters = base.naturalClusters;
        final clusterRoles = base.clusterRoles;
        final punctuationAtoms = base.punctuationAtoms;
        final spacingPlan = base.spacingPlan;
        final inlineBoxResult = base.inlineBoxResult;
        final rubyAndBopomofoSpread = base.rubyAndBopomofoSpread;
        final autoSpaceDecisions = base.autoSpaceDecisions;
        final inlineObjectByClusterIndex = base.inlineObjectByClusterIndex;

        final inlineObjectAttachedMarks = PunctuationGeometryStage.inlineObjectAttachedMarks(naturalClusters, clusterRoles, resolvedKinsoku.level, kinsokuRule);

        final inlineObjectSeparatorSpaceTrimsBuilder = SortedMap.builder();
        final inlineObjectAttachmentNoStretchBoundariesBuilder = SortedSet.builder();
        final inlineObjectPunctuationAttachmentDecisions = new Array<InlineObjectPunctuationAttachmentDecisionInfo>();

        for (a in 0...inlineObjectAttachedMarks.length) {
            final attachment = inlineObjectAttachedMarks[a];
            for (s in 0...attachment.separatorClusterIndices.length) {
                final clusterIndex = attachment.separatorClusterIndices[s];
                inlineObjectSeparatorSpaceTrimsBuilder.put(clusterIndex, naturalClusters[clusterIndex].advance);
            }
            for (idx in attachment.objectClusterIndex...attachment.markClusterIndex) {
                inlineObjectAttachmentNoStretchBoundariesBuilder.put(idx);
            }
            if (attachment.separatorClusterIndices.length > 0) {
                final separatorFirst = naturalClusters[attachment.separatorClusterIndices[0]];
                final separatorLast = naturalClusters[
                    attachment.separatorClusterIndices[attachment.separatorClusterIndices.length - 1]
                ];
                final mark = naturalClusters[attachment.markClusterIndex];
                final collapsedTerms:Array<Float> = [];
                for (s in 0...attachment.separatorClusterIndices.length) {
                    collapsedTerms.push(naturalClusters[attachment.separatorClusterIndices[s]].advance);
                }
                final collapsedAdv = AccurateSum.of(collapsedTerms);
                inlineObjectPunctuationAttachmentDecisions.push(new InlineObjectPunctuationAttachmentDecisionInfo(naturalClusters[attachment.objectClusterIndex].range,
                    new TextRange(separatorFirst.range.start, separatorLast.range.end), mark.range,
                    mark.text, new TextRange(naturalClusters[attachment.objectClusterIndex].range.start, mark.range.end), collapsedAdv));
            }
        }
        final inlineObjectSeparatorSpaceTrims = inlineObjectSeparatorSpaceTrimsBuilder.build();
        final inlineObjectAttachmentNoStretchBoundaries = inlineObjectAttachmentNoStretchBoundariesBuilder.build();

        final adjustmentStyle = annotation.clreqProfile.adjustment;

        final punctuationBaseGeometry = PunctuationGeometryLedger.from(naturalClusters, punctuationAtoms, spacingPlan)
            .withInlineBoxAdvances(inlineBoxResult.advanceByCluster)
            .withRubySpread(rubyAndBopomofoSpread)
            .withRawEdgeTrims(inlineObjectSeparatorSpaceTrims);

        final finalNaturalInlineAttachments = new Array<InlineAttachment>();
        for (i in 0...naturalClusters.length) {
            finalNaturalInlineAttachments.push(annotation.styleAt(naturalClusters[i].range.start).inlineAttachment);
        }

        final attachedPunctuationBoundary = punctuationBaseGeometry.resolveAttachedInlinePunctuationBoundaries(finalNaturalInlineAttachments,
            punctuationAtoms, fontSize);

        final baseGeometry = attachedPunctuationBoundary.geometry;
        final attachedPunctuationTrailingGlueByCluster = attachedPunctuationBoundary.trailingGlueByCluster;
        final clusters = baseGeometry.resolveClusters();

        final glueCaps = baseGeometry.glueCapacities();

        final gapClusterRanges = new Array<TextRange>();
        for (i in 0...autoSpaceDecisions.length) {
            final d = autoSpaceDecisions[i];
            if (d.side == "gap")
                gapClusterRanges.push(d.clusterRange);
        }

        final containedAtoms = firstContainedAtom(naturalClusters, punctuationAtoms);
        final atomClassByRangeBuilder = SortedMap.builder();
        for (i in 0...naturalClusters.length) {
            final atom = containedAtoms[i];
            if (atom != null) {
                atomClassByRangeBuilder.put(naturalClusters[i].range, atom.punctuationClass);
            }
        }
        final atomClassByRange = atomClassByRangeBuilder.build();

        final shrinkOpportunities = new Array<ShrinkOpportunity>();

        for (idx in 0...naturalClusters.length) {
            final cluster = naturalClusters[idx];
            final caps = glueCaps.get(idx);
            if (caps != null) {
                final cls = atomClassByRange.get(cluster.range);

                if (cls == PunctuationClass.Interpunct || cls == PunctuationClass.MiddleDot) {
                    addGeometryAwareOpportunity(shrinkOpportunities, caps, idx, 3);
                } else if (cls == PunctuationClass.Opening || cls == PunctuationClass.Closing) {
                    addGeometryAwareOpportunity(shrinkOpportunities, caps, idx, 4);
                } else if (cls == PunctuationClass.PauseOrStop) {
                    final firstChar = cluster.displayText.length > 0 ? cluster.displayText.charCodeAt(0) : 0;
                    final isStop = isInlineStop(firstChar);
                    final tier = isStop ? 7 : 5;
                    final lineEndOnly = isStop && !adjustmentStyle.allowInlineStopCompression;
                    addGeometryAwareOpportunity(shrinkOpportunities, caps, idx, tier, lineEndOnly);
                } else {
                    addGeometryAwareOpportunity(shrinkOpportunities, caps, idx, 5);
                }
            } else if (PunctuationGeometryStage.isSpaceRun(cluster) && !inlineObjectSeparatorSpaceTrims.has(idx)) {
                var inGap = false;
                for (g in 0...gapClusterRanges.length) {
                    final gr = gapClusterRanges[g];
                    if (gr.start == cluster.range.start && gr.end == cluster.range.end) {
                        inGap = true;
                        break;
                    }
                }
                if (inGap) {
                    final cap = cluster.advance - SINO_WESTERN_GAP_MIN_EM * fontSize;
                    if (adjustmentStyle.allowSinoWesternGapAdjustment && cap > 0.0) {
                        shrinkOpportunities.push(new ShrinkOpportunity(idx, 6, cap, ShrinkChannel.RawAdvance));
                    }
                } else {
                    final cap = cluster.advance - WORD_SPACE_MIN_EM * fontSize;
                    if (cap > 0.0) {
                        shrinkOpportunities.push(new ShrinkOpportunity(idx, 2, cap, ShrinkChannel.RawAdvance));
                    }
                }
            }
        }

        for (i in 0...inlineObjectByClusterIndex.size()) {
            final idx = inlineObjectByClusterIndex.keyAt(i);
            final inlineObject = inlineObjectByClusterIndex.valueAt(i);
            final trailing = inlineObject.trailingBoundary.shrinkCapacity;
            if (trailing > 0.0) {
                shrinkOpportunities.push(new ShrinkOpportunity(idx, 8, trailing, ShrinkChannel.RawAdvance));
            }
        }

        return new KinsokuDependentPrep(inlineObjectAttachedMarks, inlineObjectSeparatorSpaceTrims, inlineObjectAttachmentNoStretchBoundaries,
            inlineObjectPunctuationAttachmentDecisions, finalNaturalInlineAttachments, attachedPunctuationBoundary, baseGeometry,
            attachedPunctuationTrailingGlueByCluster, clusters, atomClassByRange, shrinkOpportunities);
    }
}
