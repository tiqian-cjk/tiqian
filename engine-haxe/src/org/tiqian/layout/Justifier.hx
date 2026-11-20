package org.tiqian.layout;

using org.tiqian.layout.ProgressiveBreakTierPriority;

using std.Functional;

import org.tiqian.core.Cluster;
import org.tiqian.core.AccurateSum;
import org.tiqian.core.IntRange;
import org.tiqian.core.EastAsianSpacingEdges;
import org.tiqian.core.EastAsianSpacingValue;
import org.tiqian.core.InlineObjectPreferredStretch;
import org.tiqian.core.InlineObjectPreferredStretchKind;
import org.tiqian.font.FontRole;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.LineOptimization.PushInAllocation;
import std.SortedSet;
import std.SortedMap;
import org.tiqian.layout.PunctuationModel.GlueKind;

@:dataClass class JustificationOpportunity {
    public final targetClusterIndex:Int;
    public final kind:GlueKind;
    public final priority:Int;
    public final capacity:Float;
    public final reason:Null<String>;

    public function new(targetClusterIndex:Int, kind:GlueKind, priority:Int, capacity:Float, ?reason:Null<String>) {
        this.targetClusterIndex = targetClusterIndex;
        this.kind = kind;
        this.priority = priority;
        this.capacity = capacity;
        this.reason = reason;
    }
}

@:dataClass class JustificationAllocation {
    public final targetClusterIndex:Int;
    public final kind:GlueKind;
    public final priority:Int;
    public final delta:Float;
    public final reason:String;

    public function new(targetClusterIndex:Int, kind:GlueKind, priority:Int, delta:Float, reason:String) {
        this.targetClusterIndex = targetClusterIndex;
        this.kind = kind;
        this.priority = priority;
        this.delta = delta;
        this.reason = reason;
    }
}

@:dataClass class JustificationPlan {
    public final lineClusterRange:IntRange;
    public final allocations:Array<JustificationAllocation>;
    public final deficitBefore:Float;
    public final unfilledDeficit:Float;
    public final fallbackReason:Null<String>;

    public function new(lineClusterRange:IntRange, allocations:Array<JustificationAllocation>, deficitBefore:Float, unfilledDeficit:Float,
            ?fallbackReason:Null<String>) {
        this.lineClusterRange = lineClusterRange;
        this.allocations = allocations;
        this.deficitBefore = deficitBefore;
        this.unfilledDeficit = unfilledDeficit;
        this.fallbackReason = fallbackReason;
    }
}

@:dataClass class CompressionPlan {
    public final allocations:Array<PushInAllocation>;
    public final surplusBefore:Float;
    public final unfilledSurplus:Float;

    public function new(allocations:Array<PushInAllocation>, surplusBefore:Float, unfilledSurplus:Float) {
        this.allocations = allocations;
        this.surplusBefore = surplusBefore;
        this.unfilledSurplus = unfilledSurplus;
    }
}

class Justifier {
    public var wordSpaceMaxEm:Float;
    public var progressiveTechnicalWhitespaceStretchMaxEm:Float;

    public function new(?wordSpaceMaxEm:Null<Float>, ?progressiveTechnicalWhitespaceStretchMaxEm:Null<Float>) {
        this.wordSpaceMaxEm = wordSpaceMaxEm == null ? 0.5 : wordSpaceMaxEm;
        this.progressiveTechnicalWhitespaceStretchMaxEm = progressiveTechnicalWhitespaceStretchMaxEm == null ? 0.25 : progressiveTechnicalWhitespaceStretchMaxEm;
    }

    public function progressiveTechnicalWhitespaceStretchCapacity(fontSize:Float):Float
        return progressiveTechnicalWhitespaceStretchMaxEm * fontSize;

    public function justify(adjustedClusters:Array<Cluster>, clusterRoles:Array<FontRole>, eastAsianSpacingEdges:Array<EastAsianSpacingEdges>, lineClusterRange:IntRange, maxWidth:Float, fontSize:Float,
            skip:Bool, ?skipReason:Null<String>, ?allowSinoWesternGapStretch:Bool = true, cjkLatinSpaceBaseEm:Float, cjkLatinSpaceMaxEm:Float, ?noStretchBoundaryClusters:Null<SortedSet<Int>>,
            ?noStretchBoundaryAfterClusters:Null<SortedSet<Int>>, ?westernBracketCjkInterCharBoundaryAfterClusters:Null<SortedSet<Int>>, ?attachedInlinePhysicalBoundaryAfterClusters:Null<SortedSet<Int>>, ?attachedInlineVirtualBoundaryAfterClusters:Null<SortedMap<Int, Int>>,
            ?attachedInlineVirtualSinoWesternBoundaryAfterClusters:Null<SortedSet<Int>>, ?uniformInlineObjectBoundaryAfterClusters:Null<SortedSet<Int>>, ?preferredInlineObjectBoundaryAfterClusters:Null<SortedMap<Int, InlineObjectPreferredStretch>>,
            ?technicalBoundaryAfterClusters:Null<SortedMap<Int, ProgressiveBreakTier>>, ?emergencyTrackingBoundaryAfterClusters:Null<SortedMap<Int, String>>,
            ?preferredEmergencyTrackingBoundaryAfterClusters:Null<SortedMap<Int, String>>):JustificationPlan {
        final ns = noStretchBoundaryClusters == null ? SortedSet.builder().build() : noStretchBoundaryClusters;
        final nsa = noStretchBoundaryAfterClusters == null ? SortedSet.builder().build() : noStretchBoundaryAfterClusters;
        final br = westernBracketCjkInterCharBoundaryAfterClusters == null ? SortedSet.builder().build() : westernBracketCjkInterCharBoundaryAfterClusters;
        final ph = attachedInlinePhysicalBoundaryAfterClusters == null ? SortedSet.builder().build() : attachedInlinePhysicalBoundaryAfterClusters;
        final vi = attachedInlineVirtualBoundaryAfterClusters == null ? SortedMap.builder().build() : attachedInlineVirtualBoundaryAfterClusters;
        final vs = attachedInlineVirtualSinoWesternBoundaryAfterClusters == null ? SortedSet.builder().build() : attachedInlineVirtualSinoWesternBoundaryAfterClusters;
        final uo = uniformInlineObjectBoundaryAfterClusters == null ? SortedSet.builder().build() : uniformInlineObjectBoundaryAfterClusters;
        final pref = preferredInlineObjectBoundaryAfterClusters == null ? SortedMap.builder().build() : preferredInlineObjectBoundaryAfterClusters;
        final te = technicalBoundaryAfterClusters == null ? SortedMap.builder().build() : technicalBoundaryAfterClusters;
        final emg = emergencyTrackingBoundaryAfterClusters == null ? SortedMap.builder().build() : emergencyTrackingBoundaryAfterClusters;
        final pem = preferredEmergencyTrackingBoundaryAfterClusters == null ? SortedMap.builder().build() : preferredEmergencyTrackingBoundaryAfterClusters;
        if (clusterRoles.length != adjustedClusters.length)
            throw new org.tiqian.core.TiqianIllegalArgumentException(org.tiqian.core.TextRangeError.Message("clusterRoles must align with adjustedClusters."));
        if (eastAsianSpacingEdges.length != adjustedClusters.length)
            throw new org.tiqian.core.TiqianIllegalArgumentException(org.tiqian.core.TextRangeError.Message("East_Asian_Spacing values must align with adjustedClusters."));
        // The reference accumulates the range in Double and narrows the
        // finished sum once, so a run of equal binary32 advances reaches its
        // exact total instead of rounding on every step.
        final widthTerms:Array<Float> = [];
        var i = lineClusterRange.start;
        while (i <= lineClusterRange.end) {
            widthTerms.push(adjustedClusters[i].advance);
            i++;
        }
        final width = AccurateSum.of(widthTerms);
        final deficit = Math.max(maxWidth - width, 0);
        if (skip || deficit <= 0)
            return new JustificationPlan(lineClusterRange, [], deficit, deficit, skip ? skipReason : null);
        var remaining = deficit;
        final out:Array<JustificationAllocation> = [];
        function boundaryIsClosed(l:Int, x:Int):Bool
            return nsa.has(l) || ns.has(l) || ns.has(x);
        function spaceGapIsClosed(x:Int):Bool
            return nsa.has(x - 1) || nsa.has(x) || ns.has(x - 1) || ns.has(x + 1);
        function alloc(ops:Array<JustificationOpportunity>, reason:String):Void {
            if (ops.length == 0 || remaining <= 0)
                return;
            // The reference writes opportunities.sumOf { it.capacity.toDouble() }
            // .toFloat(): one binary64 accumulator, narrowed once. Go through
            // AccurateSum rather than std.Functional.sumOfFloat directly: the
            // Kotlin backend renders that entry point as
            // sumOf { ... .toDouble() }.toFloat(), a narrowing that is right
            // only while the compilation's Float is binary32, and this
            // compilation's Float is binary64.
            final capacityTerms:Array<Float> = [];
            for (o in ops)
                capacityTerms.push(o.capacity);
            final total = AccurateSum.of(capacityTerms);
            if (total <= 0)
                return;
            if (total >= remaining) {
                final f = remaining / total;
                ops.forEach(o -> {
                    final d = o.capacity * f;
                    if (d > 0)
                        out.push(new JustificationAllocation(o.targetClusterIndex, o.kind, o.priority, d, o.reason == null ? reason : o.reason));
                });
                remaining = 0;
            } else {
                ops.forEach(o -> {
                    if (o.capacity > 0)
                        out.push(new JustificationAllocation(o.targetClusterIndex, o.kind, o.priority, o.capacity, o.reason == null ? reason : o.reason));
                });
                remaining -= total;
            }
        }
        function build(kind:GlueKind, priority:Int, cap:Float, reason:Null<String>, p:Int->Int->Bool):Array<JustificationOpportunity> {
            var a:Array<JustificationOpportunity> = [];
            if (cap <= 0)
                return a;
            var j = lineClusterRange.start;
            while (j < lineClusterRange.end) {
                if (p(j, j + 1))
                    a.push(new JustificationOpportunity(j, kind, priority, cap, reason));
                j++;
            }
            return a;
        }
        function finish(fallback:Null<String>):JustificationPlan
            return new JustificationPlan(lineClusterRange, out, deficit, Math.max(remaining, 0), fallback);
        var ops = build(GlueKind.ProgressiveTechnical, ProgressiveBreakTier.Whitespace.priority(), progressiveTechnicalWhitespaceStretchCapacity(fontSize),
            "ProgressiveTechnicalWhitespaceStretch", function(l, x) {
                var t = te.get(l);
                return t == ProgressiveBreakTier.Whitespace && allWhitespace(adjustedClusters[l].text);
        });
        alloc(ops, "ProgressiveTechnicalWhitespaceStretch");
        if (remaining <= 0)
            return finish(null);
        var ws:Array<JustificationOpportunity> = [];
        i = lineClusterRange.start;
        while (i <= lineClusterRange.end) {
            if (wordSpaceBetweenNarrow(adjustedClusters, i, eastAsianSpacingEdges) && !spaceGapIsClosed(i)) {
                var h = Math.max(wordSpaceMaxEm * fontSize - adjustedClusters[i].advance, 0);
                if (adjustedClusters[i].advance > 0 && h > 0)
                    ws.push(new JustificationOpportunity(i, GlueKind.WordSpace, 0, h, null));
            }
            i++;
        }
        alloc(ws, "WordSpace");
        if (remaining <= 0)
            return finish(null);
        var sino:Array<JustificationOpportunity> = [];
        if (allowSinoWesternGapStretch) {
            sino = build(GlueKind.CjkLatinSpace, 1, Math.max((cjkLatinSpaceMaxEm - cjkLatinSpaceBaseEm) * fontSize, 0), null, function(l, x) {
                return wideNarrowBoundary(l, x, eastAsianSpacingEdges) && !ph.has(l) && !boundaryIsClosed(l, x) && adjustedClusters[l].text.indexOf(" ") < 0 && adjustedClusters[x].text.indexOf(" ") != 0;
            });
            i = lineClusterRange.start;
            while (i <= lineClusterRange.end) {
                if (vs.has(i)) {
                    var prev = vi.get(i);
                    if (prev != null && i >= lineClusterRange.start && i + 1 <= lineClusterRange.end && !ns.has(prev) && !ns.has(i + 1))
                        sino.push(new JustificationOpportunity(i, GlueKind.CjkLatinSpace, 1, Math.max((cjkLatinSpaceMaxEm - cjkLatinSpaceBaseEm) * fontSize, 0),
                            "AttachedInlineVirtualAutoSpace"));
                }
                if (wideNarrowTypedSpace(adjustedClusters, i, eastAsianSpacingEdges) && !spaceGapIsClosed(i) && adjustedClusters[i].advance > 0) {
                    var h = Math.max(cjkLatinSpaceMaxEm * fontSize - adjustedClusters[i].advance, 0);
                    if (h > 0)
                        sino.push(new JustificationOpportunity(i, GlueKind.CjkLatinSpace, 1, h, null));
                }
                i++;
            }
        }
        alloc(sino, "CjkLatinSpace");
        if (remaining <= 0)
            return finish(null);
        var kinds = [
            InlineObjectPreferredStretchKind.PunctuationTrailing,
            InlineObjectPreferredStretchKind.Relation,
            InlineObjectPreferredStretchKind.BinaryOperator
        ];
        var ki = 0;
        while (ki < kinds.length) {
            var po:Array<JustificationOpportunity> = [];
            var mi = 0;
            while (mi < pref.size()) {
                var key = pref.keyAt(mi);
                var pv = pref.get(key);
                if (pv != null && pv.kind == kinds[ki] && key >= lineClusterRange.start && key < lineClusterRange.end && !boundaryIsClosed(key, key + 1))
                    po.push(new JustificationOpportunity(key, glueKind(kinds[ki]), 2, pv.capacity, reason(kinds[ki])));
                mi++;
            }
            alloc(po, reason(kinds[ki]));
            if (remaining <= 0)
                return finish(null);
            ki++;
        }
        ops = build(GlueKind.EmergencyGraphemeTracking, 3, remaining, null, function(l, x) {
            return pem.has(l);
        });
        final pe = ops.map(eo -> new JustificationOpportunity(eo.targetClusterIndex, eo.kind, eo.priority, eo.capacity,
            "TerminalTechnicalEmergencyTracking:" + pem.get(eo.targetClusterIndex)));
        alloc(pe, "TerminalTechnicalEmergencyTracking");
        if (remaining <= 0)
            return finish(null);
        var hasCjk = false;
        i = lineClusterRange.start;
        while (i <= lineClusterRange.end) {
            if (eastAsianSpacingEdges[i].containsWide)
                hasCjk = true;
            i++;
        }
        var hasU = false;
        i = lineClusterRange.start;
        while (i < lineClusterRange.end) {
            if (uo.has(i) && !boundaryIsClosed(i, i + 1))
                hasU = true;
            i++;
        }
        var hasE = false;
        i = lineClusterRange.start;
        while (i < lineClusterRange.end) {
            if (emg.has(i))
                hasE = true;
            i++;
        }
        if (!hasCjk && !hasU && !hasE)
            return finish("WesternDominantLineNaturalSpacing");
        var all:Array<JustificationOpportunity> = [];
        var textOps = build(GlueKind.CjkInterChar, 3, remaining, null, function(l, x) {
            var both = isCjk(clusterRoles[l]) && isCjk(clusterRoles[x]);
            var pw = clusterRoles[l] == FontRole.CjkPunctuation
                && eastAsianSpacingEdges[x].leading == EastAsianSpacingValue.Narrow
                || eastAsianSpacingEdges[l].trailing == EastAsianSpacingValue.Narrow
                && clusterRoles[x] == FontRole.CjkPunctuation;
            var vw = allowSinoWesternGapStretch && wideNarrowBoundary(l, x, eastAsianSpacingEdges);
            return (both || pw || vw) && !br.has(l) && !ph.has(l) && !vi.has(l) && !uo.has(l) && !boundaryIsClosed(l, x);
        });
        all = all.concat(textOps);
        all = all.concat(build(GlueKind.CjkInterChar, 3, remaining, "WesternBracketCjkInterChar", function(l, x) {
            return br.has(l) && !ph.has(l) && !uo.has(l) && !boundaryIsClosed(l, x);
        }));
        all = all.concat(build(GlueKind.CjkInterChar, 3, remaining, "AttachedInlineVirtualInterChar", function(l, x) {
            var pv = vi.get(l);
            return pv != null && (allowSinoWesternGapStretch || !vs.has(l)) && !uo.has(l) && !ns.has(pv) && !ns.has(x) && !nsa.has(pv);
        }));
        all = all.concat(build(GlueKind.InlineObjectBoundary, 3, remaining, null, function(l, x) {
            return uo.has(l) && !boundaryIsClosed(l, x);
        }));
        i = lineClusterRange.start;
        while (i <= lineClusterRange.end) {
            if ((wordSpaceBetweenNarrow(adjustedClusters, i, eastAsianSpacingEdges) || (allowSinoWesternGapStretch && wideNarrowTypedSpace(adjustedClusters, i, eastAsianSpacingEdges)))
                && !spaceGapIsClosed(i)
                && adjustedClusters[i].advance > 0)
                all.push(new JustificationOpportunity(i, GlueKind.CjkInterChar, 3, remaining, null));
            i++;
        }
        alloc(all, "CjkInterChar");
        if (remaining <= 0)
            return finish(null);
        ops = build(GlueKind.EmergencyGraphemeTracking, 4, remaining, null, function(l, x) {
            return emg.has(l) && !pem.has(l);
        });
        final ee = ops.map(o -> new JustificationOpportunity(o.targetClusterIndex, o.kind, o.priority, o.capacity,
            "EmergencyGraphemeTracking:" + emg.get(o.targetClusterIndex)));
        alloc(ee, "EmergencyGraphemeTracking");
        return finish(remaining > 0 && hasE ? "EmergencyTrackingNoOpenBoundary" : null);
    }

    public function compress(surplus:Float, shrinkOpportunities:Array<ShrinkOpportunity>):CompressionPlan {
        if (surplus <= 0)
            return new CompressionPlan([], 0, 0);
        var rem = surplus;
        var out:Array<PushInAllocation> = [];
        final m = shrinkOpportunities.filter(o -> o.capacity > 0).groupBy(o -> {key: o.tier, value: o});
        var k = 0;
        while (k < m.size()) {
            if (rem <= 0)
                break;
            var group:Array<ShrinkOpportunity> = m.valueAt(k);
            final groupTerms:Array<Float> = [];
            for (gi in 0...group.length)
                groupTerms.push(group[gi].capacity);
            final total = AccurateSum.of(groupTerms);
            if (total <= 0) {
                k++;
                continue;
            }
            var f = Math.min(1, rem / total);
            group.forEach(q -> {
                var d = q.capacity * f;
                if (d > 0)
                    out.push(new PushInAllocation(q.clusterIndex, d, q.capacity, q.channel));
            });
            rem -= total * f;
            k++;
        }
        return new CompressionPlan(out, surplus, Math.max(rem, 0));
    }
}

function allWhitespace(s:String):Bool {
    if (s.length == 0)
        return false;
    var i = 0;
    while (i < s.length) {
        if (!StringTools.isSpace(s, i))
            return false;
        i++;
    }
    return true;
}

function isCjk(r:FontRole):Bool
    return r == FontRole.CjkText || r == FontRole.CjkPunctuation;

function glueKind(k:InlineObjectPreferredStretchKind):GlueKind
    return switch (k) {
        case PunctuationTrailing: GlueKind.InlineObjectPunctuationTrailing;
        case Relation: GlueKind.InlineObjectRelation;
        case BinaryOperator: GlueKind.InlineObjectBinaryOperator;
    };

function reason(k:InlineObjectPreferredStretchKind):String
    return switch (k) {
        case PunctuationTrailing: "InlineObjectPunctuationTrailing";
        case Relation: "InlineObjectRelation";
        case BinaryOperator: "InlineObjectBinaryOperator";
    };

function wideNarrowBoundary(l:Int, x:Int, e:Array<EastAsianSpacingEdges>):Bool
    return wideNarrowPairWith(e[l].trailing, e[x].leading);

function wideNarrowPairWith(a:Null<EastAsianSpacingValue>, b:Null<EastAsianSpacingValue>):Bool
    return (a == EastAsianSpacingValue.Wide && b == EastAsianSpacingValue.Narrow)
        || (a == EastAsianSpacingValue.Narrow && b == EastAsianSpacingValue.Wide);

function wordSpaceBetweenNarrow(c:Array<Cluster>, i:Int, e:Array<EastAsianSpacingEdges>):Bool {
    if (i < 0 || i >= c.length || !allSpaces(c[i].text))
        return false;
    return i > 0
        && i < c.length - 1
        && e[i - 1].trailing == EastAsianSpacingValue.Narrow
        && e[i + 1].leading == EastAsianSpacingValue.Narrow
        && !allSpaces(c[i - 1].text)
        && !allSpaces(c[i + 1].text);
}

function wideNarrowTypedSpace(c:Array<Cluster>, i:Int, e:Array<EastAsianSpacingEdges>):Bool {
    if (i < 0 || i >= c.length || !allSpaces(c[i].text))
        return false;
    var l:Null<EastAsianSpacingValue> = i > 0 ? e[i - 1].trailing : null;
    var x:Null<EastAsianSpacingValue> = i + 1 < c.length ? e[i + 1].leading : null;
    return wideNarrowPairWith(l, x);
}

function allSpaces(s:String):Bool {
    if (s.length == 0)
        return false;
    var i = 0;
    while (i < s.length) {
        if (s.charAt(i) != " ")
            return false;
        i++;
    }
    return true;
}
