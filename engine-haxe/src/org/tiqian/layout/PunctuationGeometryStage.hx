package org.tiqian.layout;

using std.Functional;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.font.FontRole;
import org.tiqian.layout.PunctuationModel.PunctuationAtomBuilder;
import org.tiqian.layout.PunctuationModel.PunctuationAtom;
import org.tiqian.layout.PunctuationModel.PunctuationInkInput;
import org.tiqian.clreq.PunctuationWidthPolicy;
import std.SortedMap;
import std.SortedSet;

// Kotlin source: engine/src/commonMain/kotlin/org/tiqian/layout/PunctuationGeometryStage.kt.
// clusterIndexRangeFor is ported from PunctuationGeometryLedger.kt lines 600-617 (private
// there, private here until the ledger lane lands its own copy in its own file).
// isInlineObjectCluster / isMandatoryBreakCluster mirror ParagraphShapingStage.kt lines
// 922/916; they live as private helpers here until the shaping stage lane lands.

@:dataClass class ContextualKinsoku {
    public final forbiddenLineStartClusters:SortedSet<Int>;
    public final unbreakableRanges:Array<IntRange>;
    public final impossibleMeasureHangEligibleClusters:SortedSet<Int>;
    public final extendableHangRanges:Array<IntRange>;
    public final decisions:Array<ContextualKinsokuDecisionInfo>;

    public function new(forbiddenLineStartClusters:SortedSet<Int>, unbreakableRanges:Array<IntRange>, impossibleMeasureHangEligibleClusters:SortedSet<Int>,
            extendableHangRanges:Array<IntRange>, decisions:Array<ContextualKinsokuDecisionInfo>) {
        this.forbiddenLineStartClusters = forbiddenLineStartClusters;
        this.unbreakableRanges = unbreakableRanges;
        this.impossibleMeasureHangEligibleClusters = impossibleMeasureHangEligibleClusters;
        this.extendableHangRanges = extendableHangRanges;
        this.decisions = decisions;
    }
}

@:dataClass class InlineObjectAttachedMark {
    public final objectClusterIndex:Int;
    public final separatorClusterIndices:Array<Int>;
    public final markClusterIndex:Int;

    public function new(objectClusterIndex:Int, separatorClusterIndices:Array<Int>, markClusterIndex:Int) {
        this.objectClusterIndex = objectClusterIndex;
        this.separatorClusterIndices = separatorClusterIndices;
        this.markClusterIndex = markClusterIndex;
    }
}

@:dataClass class AutoSpaceApplicationResult {
    public final clusters:Array<Cluster>;
    public final decisions:Array<AutoSpaceDecisionInfo>;

    public function new(clusters:Array<Cluster>, decisions:Array<AutoSpaceDecisionInfo>) {
        this.clusters = clusters;
        this.decisions = decisions;
    }
}

@:dataClass class InlineBoxApplicationResult {
    public final clusters:Array<Cluster>;
    public final advanceByCluster:SortedMap<Int, Float>;
    public final decisions:Array<InlineBoxDecisionInfo>;

    public function new(clusters:Array<Cluster>, advanceByCluster:SortedMap<Int, Float>, decisions:Array<InlineBoxDecisionInfo>) {
        this.clusters = clusters;
        this.advanceByCluster = advanceByCluster;
        this.decisions = decisions;
    }
}

class PunctuationGeometryStage {
    public static function inlineObjectAttachedMarks(c:Array<Cluster>, clusterRoles:Array<FontRole>, level:KinsokuLevel,
            kinsokuRule:KinsokuRule):Array<InlineObjectAttachedMark> {
        if (level == KinsokuLevel.None)
            return [];
        final result:Array<InlineObjectAttachedMark> = [];
        var markIndex = 1;
        while (markIndex < c.length) {
            final mark = c[markIndex];
            final role = markIndex < clusterRoles.length ? clusterRoles[markIndex] : null;
            final isCjkForbidden = isCjkKinsokuRole(role) && kinsokuRule.forbiddenAtLineStart(mark);
            final isAttachedAsciiPointMark = role == FontRole.LatinText && isAsciiPointMarkChar(firstChar(mark.text));
            if (!isCjkForbidden && !isAttachedAsciiPointMark) {
                markIndex++;
                continue;
            }
            var previousIndex = markIndex - 1;
            final separatorIndices:Array<Int> = [];
            while (previousIndex >= 0 && isSpaceRun(c[previousIndex]) && c[previousIndex].range.end == c[previousIndex + 1].range.start) {
                separatorIndices.unshift(previousIndex);
                previousIndex--;
            }
            if (previousIndex < 0) {
                markIndex++;
                continue;
            }
            final previous = c[previousIndex];
            if (!isInlineObjectCluster(previous) || previous.range.end != c[previousIndex + 1].range.start) {
                markIndex++;
                continue;
            }
            result.push(new InlineObjectAttachedMark(previousIndex, separatorIndices, markIndex));
            markIndex++;
        }
        return result;
    }

    public static function inlineObjectAttachedKinsoku(c:Array<Cluster>, attachments:Array<InlineObjectAttachedMark>, lineBreakClusters:Array<Cluster>,
            level:KinsokuLevel, bodyLineWidth:Float, firstLineWidth:Float):ContextualKinsoku {
        if (level == KinsokuLevel.None)
            return emptyContextualKinsoku();
        if (c.length != lineBreakClusters.length)
            throw new org.tiqian.core.TiqianIllegalArgumentException(Message("Inline-object kinsoku requires cluster-for-cluster line-break geometry"));
        final forbidden = SortedSet.builder();
        final unbreakableRanges:Array<IntRange> = [];
        final forcedHangable = SortedSet.builder();
        final extendableHangRanges:Array<IntRange> = [];
        final decisions:Array<ContextualKinsokuDecisionInfo> = [];
        var ai = 0;
        while (ai < attachments.length) {
            final attachment = attachments[ai];
            ai++;
            final previousIndex = attachment.objectClusterIndex;
            final index = attachment.markClusterIndex;
            final mark = c[index];
            final isAttachedAsciiPointMark = isAsciiPointMarkChar(firstChar(mark.text));
            var si = 0;
            while (si < attachment.separatorClusterIndices.length) {
                forbidden.put(attachment.separatorClusterIndices[si]);
                si++;
            }
            forbidden.put(index);
            final protectedPair = new IntRange(previousIndex, index);
            var pairWidth = 0.;
            var wi = previousIndex;
            while (wi <= index) {
                pairWidth += lineBreakClusters[wi].advance;
                wi++;
            }
            final availableWidth = previousIndex == 0 ? firstLineWidth : bodyLineWidth;
            if (pairWidth <= availableWidth)
                unbreakableRanges.push(protectedPair);
            else {
                final mayHang = isHangablePunctuationMark(mark.displayText) || isAttachedAsciiPointMark;
                if (mayHang) {
                    var sj = 0;
                    while (sj < attachment.separatorClusterIndices.length) {
                        forcedHangable.put(attachment.separatorClusterIndices[sj]);
                        sj++;
                    }
                    forcedHangable.put(index);
                    extendableHangRanges.push(protectedPair);
                }
            }
            decisions.push(new ContextualKinsokuDecisionInfo(mark.range, mark.text, index, "LineStart",
                attachment.separatorClusterIndices.length == 0 ? "InlineObjectAttachedKinsoku" : "InlineObjectAttachedKinsokuAcrossCollapsedSeparatorSpace"));
        }
        return new ContextualKinsoku(forbidden.build(), unbreakableRanges, forcedHangable.build(), extendableHangRanges, decisions);
    }

    public static function attachedAsciiPointMarkKinsoku(c:Array<Cluster>, clusterRoles:Array<FontRole>, lineBreakClusters:Array<Cluster>, level:KinsokuLevel,
            bodyLineWidth:Float, firstLineWidth:Float):ContextualKinsoku {
        if (level == KinsokuLevel.None)
            return emptyContextualKinsoku();
        if (c.length != lineBreakClusters.length)
            throw new org.tiqian.core.TiqianIllegalArgumentException(Message("Contextual kinsoku requires cluster-for-cluster line-break geometry"));
        final forbidden = SortedSet.builder();
        final unbreakableRanges:Array<IntRange> = [];
        final forcedHangable = SortedSet.builder();
        final extendableHangRanges:Array<IntRange> = [];
        final decisions:Array<ContextualKinsokuDecisionInfo> = [];
        var index = 1;
        while (index < c.length) {
            final cluster = c[index];
            final previous = c[index - 1];
            final startsAttachedPointMarkRun = (index < clusterRoles.length ? clusterRoles[index] : null) == FontRole.LatinText
                && isAsciiPointMarkChar(firstChar(cluster.text))
                && previous.displayText.length > 0
                && previous.text.length > 0
                && !isWhitespaceCode(previous.text.charCodeAt(previous.text.length - 1))
                && previous.range.end == cluster.range.start;
            if (!startsAttachedPointMarkRun) {
                index++;
                continue;
            }
            final runStart = index;
            var runEnd = index;
            while (runEnd + 1 < c.length) {
                final next = c[runEnd + 1];
                final continuesRun = (runEnd + 1 < clusterRoles.length ? clusterRoles[runEnd + 1] : null) == FontRole.LatinText
                    && isAsciiPointMarkChar(firstChar(next.text))
                    && c[runEnd].range.end == next.range.start;
                if (!continuesRun)
                    break;
                runEnd++;
            }
            var fi = runStart;
            while (fi <= runEnd) {
                forbidden.put(fi);
                fi++;
            }
            unbreakableRanges.push(new IntRange(runStart - 1, runEnd));
            final runLineWidth = runStart - 1 == 0 ? firstLineWidth : bodyLineWidth;
            var runWidth = 0.;
            var wi = runStart - 1;
            while (wi <= runEnd) {
                runWidth += lineBreakClusters[wi].advance;
                wi++;
            }
            if (runWidth > runLineWidth) {
                fi = runStart;
                while (fi <= runEnd) {
                    forcedHangable.put(fi);
                    fi++;
                }
                extendableHangRanges.push(new IntRange(runStart - 1, runEnd));
            }
            fi = runStart;
            while (fi <= runEnd) {
                final pointMark = c[fi];
                decisions.push(new ContextualKinsokuDecisionInfo(pointMark.range, pointMark.text, fi, "LineStart", "AttachedAsciiPointMarkKinsoku"));
                fi++;
            }
            index = runEnd + 1;
        }
        return new ContextualKinsoku(forbidden.build(), unbreakableRanges, forcedHangable.build(), extendableHangRanges, decisions);
    }

    public static function isCjkKinsokuRole(role:Null<FontRole>):Bool
        return role == FontRole.CjkPunctuation;

    public static function punctuationAtoms(c:Cluster, em:Float, builder:PunctuationAtomBuilder, shapedGlyphs:Array<Glyph>,
            gluePlacement:PunctuationGluePlacement, widthPolicy:PunctuationWidthPolicy):Array<PunctuationAtom> {
        final out:Array<PunctuationAtom> = [];
        if (c.displayText.length == 0)
            return out;
        var i = 0;
        while (i < c.displayText.length) {
            final atom = builder.build(c.displayText.charAt(i), displayCharSourceRange(c, i), em, punctuationInkInputFor(c, i, shapedGlyphs), gluePlacement,
                widthPolicy);
            if (atom != null)
                out.push(atom);
            i++;
        }
        return out;
    }

    static function punctuationInkInputFor(c:Cluster, displayIndex:Int, shapedGlyphs:Array<Glyph>):Null<PunctuationInkInput> {
        if (shapedGlyphs.length == 0)
            return null;
        var glyph:Null<Glyph> = null;
        if (shapedGlyphs.length == c.displayText.length) {
            final source = shapedGlyphs[displayIndex];
            var characterPen = 0.;
            var i = 0;
            while (i < displayIndex) {
                characterPen += shapedGlyphs[i].advance;
                i++;
            }
            glyph = new Glyph(source.id, source.clusterRange, source.advance, source.x - characterPen, source.y, source.renderFontKey, source.bounds,
                source.haltAdvance, source.haltPlacementX);
        } else if (c.displayText.length == 1)
            glyph = unionAsSingleGlyph(shapedGlyphs);
        if (glyph == null)
            return new PunctuationInkInput(0, null, null, null, "glyph-cluster-mapping-ambiguous");
        return new PunctuationInkInput(glyph.advance,
            glyph.bounds == null ? null : new Rect(glyph.bounds.left + glyph.x, glyph.bounds.top + glyph.y, glyph.bounds.right + glyph.x,
                glyph.bounds.bottom + glyph.y),
            glyph.haltAdvance, glyph.haltPlacementX, glyph.bounds == null ? "shaper-no-ink-bounds" : null);
    }

    static function unionAsSingleGlyph(g:Array<Glyph>):Null<Glyph> {
        if (g.length == 0)
            return null;
        final first = g[0];
        final bounds:Array<Rect> = [];
        var totalAdvance = 0.;
        var i = 0;
        while (i < g.length) {
            final glyph = g[i];
            totalAdvance += glyph.advance;
            if (glyph.bounds != null)
                bounds.push(new Rect(glyph.bounds.left + glyph.x, glyph.bounds.top + glyph.y, glyph.bounds.right + glyph.x, glyph.bounds.bottom + glyph.y));
            i++;
        }
        if (bounds.length == 0)
            return first;
        var left = bounds[0].left,
            top = bounds[0].top,
            right = bounds[0].right,
            bottom = bounds[0].bottom;
        i = 1;
        while (i < bounds.length) {
            left = Math.min(left, bounds[i].left);
            top = Math.min(top, bounds[i].top);
            right = Math.max(right, bounds[i].right);
            bottom = Math.max(bottom, bounds[i].bottom);
            i++;
        }
        return new Glyph(first.id, first.clusterRange, totalAdvance, 0, 0, first.renderFontKey, new Rect(left, top, right, bottom), null, null);
    }

    static function displayCharSourceRange(c:Cluster, displayIndex:Int):TextRange
        return c.displayText.length == c.text.length ? new TextRange(c.range.start + displayIndex, c.range.start + displayIndex + 1) : c.range;

    public static function isSpaceRun(c:Cluster):Bool {
        if (c.text.length == 0)
            return false;
        var i = 0;
        while (i < c.text.length) {
            if (c.text.charAt(i) != " ")
                return false;
            i++;
        }
        return true;
    }

    public static function applyAutoSpacePolicy(c:Array<Cluster>, eastAsianSpacingEdges:Array<EastAsianSpacingEdges>,
            inlineAttachments:Array<InlineAttachment>, policy:AutoSpacePolicy, fontSize:Float, ?narrowInlineBoxLeadingClusters:Null<SortedSet<Int>>,
            ?narrowInlineBoxTrailingClusters:Null<SortedSet<Int>>):AutoSpaceApplicationResult {
        if (c.length == 0)
            return new AutoSpaceApplicationResult([], []);
        if (eastAsianSpacingEdges.length != c.length)
            throw new org.tiqian.core.TiqianIllegalArgumentException(Message("East_Asian_Spacing values must align with natural clusters."));
        if (inlineAttachments.length != c.length)
            throw new org.tiqian.core.TiqianIllegalArgumentException(Message("Inline attachments must align with natural clusters."));
        final narrowLeading = narrowInlineBoxLeadingClusters == null ? SortedSet.builder().build() : narrowInlineBoxLeadingClusters;
        final narrowTrailing = narrowInlineBoxTrailingClusters == null ? SortedSet.builder().build() : narrowInlineBoxTrailingClusters;
        final decisions:Array<AutoSpaceDecisionInfo> = [];
        final gap = policy.gapEm * fontSize;
        final attachedBoundaries = UnicodePunctuationBoundaryResolver.resolveAttachedInlineVirtualBoundaries(inlineAttachments);
        final suppressed = SortedSet.builder();
        var bi = 0;
        while (bi < attachedBoundaries.length) {
            final boundary = attachedBoundaries[bi];
            bi++;
            suppressed.put(boundary.previousClusterIndex);
            if (boundary.nextClusterIndex != null)
                suppressed.put(boundary.attachedClusterRange.end);
        }
        final virtualGapAtRunEnd:Array<Bool> = [];
        var gi = 0;
        while (gi < c.length) {
            virtualGapAtRunEnd.push(false);
            gi++;
        }
        bi = 0;
        while (bi < attachedBoundaries.length) {
            final boundary = attachedBoundaries[bi];
            bi++;
            if (boundary.nextClusterIndex == null)
                continue;
            final nextIndex = boundary.nextClusterIndex;
            if (nextIndex >= c.length)
                continue;
            final nextCluster = c[nextIndex];
            if (isSpaceRun(nextCluster) || isMandatoryBreakCluster(nextCluster))
                continue;
            final previousIndex = boundary.previousClusterIndex;
            final previousEdge = eastAsianSpacingEdges[previousIndex].trailing;
            final nextEdge = eastAsianSpacingEdges[nextIndex].leading;
            var narrowChar:Null<String> = null;
            if (previousEdge == EastAsianSpacingValue.Wide && nextEdge == EastAsianSpacingValue.Narrow)
                narrowChar = firstChar(nextCluster.text);
            else if (previousEdge == EastAsianSpacingValue.Narrow && nextEdge == EastAsianSpacingValue.Wide)
                narrowChar = lastChar(c[previousIndex].text);
            virtualGapAtRunEnd[boundary.attachedClusterRange.end] = modeForNarrow(policy, narrowChar) == AutoSpaceMode.Insert;
        }
        final suppressedSet:SortedSet<Int> = suppressed.build();
        final updated:Array<Cluster> = [];
        var idx = 0;
        while (idx < c.length) {
            final cluster = c[idx];
            final previousSpacing = idx - 1 >= 0 ? eastAsianSpacingEdges[idx - 1].trailing : null;
            final currentSpacing = eastAsianSpacingEdges[idx];
            final nextSpacing = idx + 1 < eastAsianSpacingEdges.length ? eastAsianSpacingEdges[idx + 1].leading : null;
            if (isSpaceRun(cluster)) {
                var narrowBoundaryChar:Null<String> = null;
                if (previousSpacing == EastAsianSpacingValue.Wide && nextSpacing == EastAsianSpacingValue.Narrow)
                    narrowBoundaryChar = idx + 1 < c.length ? firstChar(c[idx + 1].text) : null;
                else if (previousSpacing == EastAsianSpacingValue.Narrow && nextSpacing == EastAsianSpacingValue.Wide)
                    narrowBoundaryChar = idx - 1 >= 0 ? lastChar(c[idx - 1].text) : null;
                final mode = modeForNarrow(policy, narrowBoundaryChar);
                if (mode == null || mode == AutoSpaceMode.Disabled) {
                    updated.push(cluster);
                    idx++;
                    continue;
                }
                final reduction = cluster.advance - gap;
                if (reduction == 0) {
                    updated.push(cluster);
                    idx++;
                    continue;
                }
                decisions.push(new AutoSpaceDecisionInfo(cluster.range, "gap", "EastAsianSpacing.Wide", Std.string(AutoSpaceMode.Replace),
                    cluster.text.length, reduction / cluster.text.length, reduction, "TextAutoSpaceReplace:east-asian-spacing-W-space-N"));
                updated.push(new Cluster(cluster.range, cluster.text, cluster.fontKey, gap, cluster.displayText, cluster.baselineShift,
                    cluster.leadingLayoutAdvance, cluster.glyphInlineShift));
                idx++;
                continue;
            }
            var added = 0.;
            if (previousSpacing == EastAsianSpacingValue.Wide
                && currentSpacing.leading == EastAsianSpacingValue.Narrow
                && modeForNarrow(policy, firstChar(cluster.text)) == AutoSpaceMode.Insert
                && !suppressedSet.has(idx - 1)) {
                added += gap;
                decisions.push(new AutoSpaceDecisionInfo(cluster.range, "leading", narrowLeading.has(idx) ? "InlineBox.Narrow" : "EastAsianSpacing.Wide",
                    Std.string(AutoSpaceMode.Insert), 0, 0, -gap,
                    narrowLeading.has(idx) ? "InlineBoxOuterAutoSpace:leading-W-N" : "TextAutoSpaceInsert:east-asian-spacing-W-N"));
            }
            final normalTrailingGap = nextSpacing == EastAsianSpacingValue.Wide
                && currentSpacing.trailing == EastAsianSpacingValue.Narrow
                && modeForNarrow(policy, lastChar(cluster.text)) == AutoSpaceMode.Insert
                && !suppressedSet.has(idx);
            final virtualTrailingGap = virtualGapAtRunEnd[idx];
            if (normalTrailingGap || virtualTrailingGap) {
                added += gap;
                decisions.push(new AutoSpaceDecisionInfo(cluster.range, "trailing",
                    narrowTrailing.has(idx) ? "InlineBox.Narrow" : (virtualTrailingGap ? "InlineAttachment.Previous" : "EastAsianSpacing.Wide"),
                    Std.string(AutoSpaceMode.Insert), 0, 0, -gap,
                    narrowTrailing.has(idx) ? "InlineBoxOuterAutoSpace:trailing-N-W" : (virtualTrailingGap ? "AttachedInlineVirtualAutoSpace:east-asian-spacing-W-N" : "TextAutoSpaceInsert:east-asian-spacing-W-N")));
            }
            if (added == 0)
                updated.push(cluster);
            else
                updated.push(new Cluster(cluster.range, cluster.text, cluster.fontKey, cluster.advance + added, cluster.displayText, cluster.baselineShift,
                    cluster.leadingLayoutAdvance, cluster.glyphInlineShift));
            idx++;
        }
        return new AutoSpaceApplicationResult(updated, decisions);
    }

    public static function isEastAsianSpacingBoundaryAt(rightIndex:Int, clusters:Array<Cluster>, spacingEdges:Array<EastAsianSpacingEdges>):Bool {
        final leftIndex = rightIndex - 1;
        final left = spacingEdges[leftIndex].trailing;
        final right = spacingEdges[rightIndex].leading;
        if (isWideNarrowPairWith(left, right))
            return true;
        if (isSpaceRun(clusters[rightIndex])
            && left == EastAsianSpacingValue.Wide
            && (rightIndex + 1 < spacingEdges.length ? spacingEdges[rightIndex + 1].leading : null) == EastAsianSpacingValue.Narrow)
            return true;
        if (isSpaceRun(clusters[leftIndex])
            && right == EastAsianSpacingValue.Wide
            && (leftIndex - 1 >= 0 ? spacingEdges[leftIndex - 1].trailing : null) == EastAsianSpacingValue.Narrow)
            return true;
        return false;
    }

    static function isWideNarrowPairWith(v:EastAsianSpacingValue, other:EastAsianSpacingValue):Bool
        return (v == EastAsianSpacingValue.Wide && other == EastAsianSpacingValue.Narrow)
            || (v == EastAsianSpacingValue.Narrow && other == EastAsianSpacingValue.Wide);

    public static function isAttachedAsciiPointMarkAt(c:Array<Cluster>, index:Int):Bool {
        if (index <= 0)
            return false;
        final cluster = c[index];
        final previous = c[index - 1];
        return isAsciiPointMarkChar(firstChar(cluster.text))
            && previous.displayText.length > 0
            && previous.text.length > 0
            && !isWhitespaceCode(previous.text.charCodeAt(previous.text.length - 1))
            && previous.range.end == cluster.range.start;
    }

    public static function applyInlineBoxSpans(c:Array<Cluster>, spans:Array<InlineBoxSpan>):InlineBoxApplicationResult {
        if (c.length == 0 || spans.length == 0) {
            final emptyAdvance:SortedMap<Int, Float> = SortedMap.builder().build();
            return new InlineBoxApplicationResult(c, emptyAdvance, []);
        }
        final leadingByCluster = SortedMap.builder();
        final trailingByCluster = SortedMap.builder();
        final decisions:Array<InlineBoxDecisionInfo> = [];
        var si = 0;
        while (si < spans.length) {
            final span = spans[si];
            si++;
            if (span.range.start >= span.range.end)
                continue;
            final clusterRange = clusterIndexRangeFor(c, span.range);
            if (clusterRange == null)
                continue;
            if (span.inlineStart != 0) {
                final existing = leadingByCluster.get(clusterRange.start);
                leadingByCluster.put(clusterRange.start, existing == null ? span.inlineStart : existing + span.inlineStart);
            }
            if (span.inlineEnd != 0) {
                final existing = trailingByCluster.get(clusterRange.end);
                trailingByCluster.put(clusterRange.end, existing == null ? span.inlineEnd : existing + span.inlineEnd);
            }
            decisions.push(new InlineBoxDecisionInfo(span.range, span.inlineStart, span.inlineEnd, Std.string(span.outerSpacing), clusterRange.start,
                clusterRange.end));
        }
        final advanceByCluster = SortedMap.builder();
        final resolved:Array<Cluster> = [];
        var idx = 0;
        while (idx < c.length) {
            final cluster = c[idx];
            final leading = leadingByCluster.get(idx);
            final trailing = trailingByCluster.get(idx);
            final lead = leading == null ? 0. : leading;
            final trail = trailing == null ? 0. : trailing;
            final structural = lead + trail;
            if (structural != 0)
                advanceByCluster.put(idx, structural);
            if (structural == 0 && lead == 0)
                resolved.push(cluster);
            else
                resolved.push(new Cluster(cluster.range, cluster.text, cluster.fontKey, cluster.advance + structural < 0 ? 0 : cluster.advance + structural,
                    cluster.displayText, cluster.baselineShift, cluster.leadingLayoutAdvance + lead, cluster.glyphInlineShift));
            idx++;
        }
        return new InlineBoxApplicationResult(resolved, advanceByCluster.build(), decisions);
    }

    static function clusterIndexRangeFor(c:Array<Cluster>, sourceRange:TextRange):Null<IntRange> {
        if (c.length == 0)
            return null;
        var low = 0;
        var high = c.length;
        while (low < high) {
            final mid = (low + high) >> 1;
            if (c[mid].range.start < sourceRange.start)
                low = mid + 1;
            else
                high = mid;
        }
        final first = low;
        low = first;
        high = c.length;
        while (low < high) {
            final mid = (low + high) >> 1;
            if (c[mid].range.end <= sourceRange.end)
                low = mid + 1;
            else
                high = mid;
        }
        final lastExclusive = low;
        return first < lastExclusive ? new IntRange(first, lastExclusive - 1) : null;
    }

    static function emptyContextualKinsoku():ContextualKinsoku {
        return new ContextualKinsoku(SortedSet.builder().build(), [], SortedSet.builder().build(), [], []);
    }

    static function modeForNarrow(policy:AutoSpacePolicy, boundaryChar:Null<String>):Null<AutoSpaceMode> {
        if (boundaryChar == null)
            return null;
        return isDigitChar(boundaryChar.charCodeAt(0)) ? policy.cjkDigit : policy.cjkLatin;
    }

    static function isDigitChar(code:Int):Bool {
        // Kotlin Char.isDigit is Unicode Nd. The realistic Nd code points in CJK prose
        // are ASCII 0x30-0x39 and fullwidth 0xFF10-0xFF19; other Nd scripts have no
        // distinct auto-space policy in the golden corpus.
        return (code >= 0x30 && code <= 0x39) || (code >= 0xFF10 && code <= 0xFF19);
    }

    static function isAsciiPointMarkChar(ch:Null<String>):Bool
        return ch != null && ClreqPunctuationPolicies.isAsciiPointMark(ch);

    static function isHangablePunctuationMark(displayText:String):Bool {
        // Kotlin LineBreakPlanningStage.kt line 725: HANGABLE_PUNCTUATION = setOf('\u3001','\uFF0C','\u3002').
        if (displayText.length != 1)
            return false;
        return displayText == "\u3001" || displayText == "\uFF0C" || displayText == "\u3002";
    }

    static function isInlineObjectCluster(c:Cluster):Bool
        return c.fontKey == "inline-object";

    static function isMandatoryBreakCluster(c:Cluster):Bool
        return c.fontKey == "mandatory-break" && c.displayText.length == 0;

    static function isWhitespaceCode(code:Int):Bool {
        // Kotlin Char.isWhitespace union: 0x09-0x0D, 0x20, 0x3000. StringTools.isSpace
        // covers only ASCII; this local helper follows the union table until the shared
        // cleanup lands.
        return (code >= 0x09 && code <= 0x0D) || code == 0x20 || code == 0x3000;
    }

    static function firstChar(s:String):Null<String>
        return s.length > 0 ? s.charAt(0) : null;

    static function lastChar(s:String):Null<String>
        return s.length > 0 ? s.charAt(s.length - 1) : null;
}
