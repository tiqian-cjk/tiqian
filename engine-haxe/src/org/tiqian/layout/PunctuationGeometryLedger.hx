package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.ClusterGeometryDecisionInfo;
import org.tiqian.core.InlineAttachment;
import org.tiqian.core.IntRange;
import org.tiqian.core.LineEdgeTrimDecisionInfo;
import org.tiqian.core.SpacingDecisionInfo;
import org.tiqian.core.TextRange;
import org.tiqian.layout.LineOptimization.LineCandidate;
import org.tiqian.layout.PunctuationModel.PunctuationAnchor;
import org.tiqian.layout.PunctuationModel.PunctuationAtom;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingCompressionResult;
import org.tiqian.clreq.PunctuationClass;
import org.tiqian.clreq.ClreqPunctuationPolicies;
import std.SortedMap;

@:dataClass class PunctuationGeometryLedger {
    public final naturalClusters:Array<Cluster>;
    public final geometries:SortedMap<Int, PunctuationClusterGeometry>;
    public final budgets:SortedMap<Int, GlueBudget>;
    public final justificationDeltaByCluster:SortedMap<Int, Float>;
    public final rawEdgeTrimByCluster:SortedMap<Int, Float>;
    public final rubySpreadByCluster:SortedMap<Int, Float>;
    public final inlineBoxAdvanceByCluster:SortedMap<Int, Float>;
    public final attachedInlineTrailingGlueByCluster:SortedMap<Int, Float>;

    public function new(naturalClusters:Array<Cluster>, geometries:SortedMap<Int, PunctuationClusterGeometry>, budgets:SortedMap<Int, GlueBudget>,
            ?justificationDeltaByCluster:Null<SortedMap<Int, Float>>, ?rawEdgeTrimByCluster:Null<SortedMap<Int, Float>>,
            ?rubySpreadByCluster:Null<SortedMap<Int, Float>>, ?inlineBoxAdvanceByCluster:Null<SortedMap<Int, Float>>,
            ?attachedInlineTrailingGlueByCluster:Null<SortedMap<Int, Float>>) {
        this.naturalClusters = naturalClusters;
        this.geometries = geometries;
        this.budgets = budgets;
        this.justificationDeltaByCluster = justificationDeltaByCluster == null ? emptyF() : justificationDeltaByCluster;
        this.rawEdgeTrimByCluster = rawEdgeTrimByCluster == null ? emptyF() : rawEdgeTrimByCluster;
        this.rubySpreadByCluster = rubySpreadByCluster == null ? emptyF() : rubySpreadByCluster;
        this.inlineBoxAdvanceByCluster = inlineBoxAdvanceByCluster == null ? emptyF() : inlineBoxAdvanceByCluster;
        this.attachedInlineTrailingGlueByCluster = attachedInlineTrailingGlueByCluster == null ? emptyF() : attachedInlineTrailingGlueByCluster;
    }

    static function emptyF():SortedMap<Int, Float>
        return SortedMap.builder().build();

    static function cloneF(x:SortedMap<Int, Float>):SortedMap<Int, Float> {
        final b = SortedMap.builder();
        for (i in 0...x.size())
            b.put(x.keyAt(i), x.valueAt(i));
        return b.build();
    }

    static function cloneB(x:SortedMap<Int, GlueBudget>):SortedMap<Int, GlueBudget> {
        final b = SortedMap.builder();
        for (i in 0...x.size())
            b.put(x.keyAt(i), x.valueAt(i));
        return b.build();
    }

    static function replace(x:PunctuationGeometryLedger, ?d:SortedMap<Int, Float>, ?r:SortedMap<Int, Float>, ?s:SortedMap<Int, Float>,
            ?i:SortedMap<Int, Float>, ?a:SortedMap<Int, Float>, ?b:SortedMap<Int, GlueBudget>):PunctuationGeometryLedger
        return new PunctuationGeometryLedger(x.naturalClusters, x.geometries, b == null ? x.budgets : b, d == null ? x.justificationDeltaByCluster : d,
            r == null ? x.rawEdgeTrimByCluster : r, s == null ? x.rubySpreadByCluster : s, i == null ? x.inlineBoxAdvanceByCluster : i,
            a == null ? x.attachedInlineTrailingGlueByCluster : a);

    public static function from(naturalClusters:Array<Cluster>, punctuationAtoms:Array<PunctuationAtom>,
            spacingPlan:PunctuationSpacingCompressionResult):PunctuationGeometryLedger {
        final geometryBuilder = SortedMap.builder();
        for (i in 0...naturalClusters.length) {
            final atomsForCluster:Array<PunctuationAtom> = [];
            for (atom in punctuationAtoms)
                if (isInside(atom.range, naturalClusters[i].range))
                    atomsForCluster.push(atom);
            if (atomsForCluster.length > 0) {
                var bodyWidth = 0.0;
                for (atom in atomsForCluster)
                    bodyWidth += atom.bodyWidth;
                geometryBuilder.put(i,
                    new PunctuationClusterGeometry(naturalClusters[i].range, naturalClusters[i].text, naturalClusters[i].displayText,
                        naturalClusters[i].advance, bodyWidth, atomsForCluster[0].leadingGlue.natural,
                        atomsForCluster[atomsForCluster.length - 1].trailingGlue.natural, atomsForCluster[0].leadingGlueInitiallyConsumed,
                        atomsForCluster[atomsForCluster.length - 1].trailingGlueInitiallyConsumed,
                        atomsForCluster.length == 1 ? atomsForCluster[0].glyphInlineShift : 0,
                        atomsForCluster.length == 1 ? atomsForCluster[0].glyphPlacementReason : null,
                        atomsForCluster.length == 1 ? atomsForCluster[0].anchor : null, atomsForCluster[0].geometrySource));
            }
        }
        final geometries = geometryBuilder.build();
        final budgetBuilder = SortedMap.builder();
        for (i in 0...geometries.size()) {
            final index = geometries.keyAt(i);
            final geometry = geometries.valueAt(i);
            budgetBuilder.put(index,
                new GlueBudget(geometry.leadingGlueNatural, geometry.leadingGlueInitiallyConsumed, geometry.trailingGlueNatural,
                    geometry.trailingGlueInitiallyConsumed));
        }
        return new PunctuationGeometryLedger(naturalClusters, geometries, budgetBuilder.build()).consumeSpacing(spacingPlan);
    }

    public function resolveClusters():Array<Cluster> {
        final result:Array<Cluster> = [];
        for (i in 0...naturalClusters.length) {
            final c = naturalClusters[i];
            final v = resolvedAdvance(i, c);
            final sh = geometries.has(i) ? geometries.get(i).glyphInlineShift : 0;
            result.push(v == c.advance
                && sh == 0 ? c : new Cluster(c.range, c.text, c.fontKey, v, c.displayText, c.baselineShift, c.leadingLayoutAdvance, c.glyphInlineShift + sh));
        }
        return result;
    }

    function resolvedAdvance(i:Int, c:Cluster):Float {
        final raw = rawEdgeTrimByCluster.has(i) ? rawEdgeTrimByCluster.get(i) : 0, sp = rubySpreadByCluster.has(i) ? rubySpreadByCluster.get(i) : 0,
        d = justificationDeltaByCluster.has(i) ? justificationDeltaByCluster.get(i) : 0,
        att = attachedInlineTrailingGlueByCluster.has(i) ? attachedInlineTrailingGlueByCluster.get(i) : 0,
        box = inlineBoxAdvanceByCluster.has(i) ? inlineBoxAdvanceByCluster.get(i) : 0;
        if (!geometries.has(i))
            return Math.max(0, c.advance + d + sp + att - raw);
        final g = geometries.get(i);
        if (!budgets.has(i))
            return Math.max(0, g.bodyWidth + box + d + sp - raw);
        final b = budgets.get(i);
        return Math.max(0, g.bodyWidth + box + b.leadingRemaining + b.trailingRemaining + d + sp + att - raw);
    }

    public function withInlineBoxAdvances(m:SortedMap<Int, Float>):PunctuationGeometryLedger
        return m.size() == 0 ? this : replace(this, null, null, null, m);

    public function withRubySpread(m:SortedMap<Int, Float>):PunctuationGeometryLedger
        return m.size() == 0 ? this : replace(this, null, null, m);

    public function withRawEdgeTrims(m:SortedMap<Int, Float>):PunctuationGeometryLedger {
        if (m.size() == 0)
            return this;
        var n:SortedMap<Int, Float> = cloneF(rawEdgeTrimByCluster);
        for (i in 0...m.size()) {
            final k = m.keyAt(i);
            final b = SortedMap.builder();
            for (j in 0...n.size())
                b.put(n.keyAt(j), n.valueAt(j));
            b.put(k, (n.has(k) ? n.get(k) : 0) + m.valueAt(i));
            n = b.build();
        }
        return replace(this, null, n);
    }

    public function addJustificationDeltas(m:SortedMap<Int, Float>):PunctuationGeometryLedger
        return replace(this, m);

    function consumeSide(m:SortedMap<Int, Float>, lead:Bool):PunctuationGeometryLedger {
        var n:SortedMap<Int, GlueBudget> = cloneB(budgets);
        for (i in 0...m.size()) {
            final k = m.keyAt(i);
            final amount = m.valueAt(i);
            if (n.has(k) && amount > 0) {
                final q = n.get(k);
                final replacement = lead ? new GlueBudget(q.leadingNatural, Math.min(q.leadingNatural, q.leadingConsumed + amount), q.trailingNatural,
                    q.trailingConsumed) : new GlueBudget(q.leadingNatural, q.leadingConsumed, q.trailingNatural,
                        Math.min(q.trailingNatural, q.trailingConsumed + amount));
                final b = SortedMap.builder();
                for (j in 0...n.size())
                    b.put(n.keyAt(j), n.valueAt(j));
                b.put(k, replacement);
                n = b.build();
            }
        }
        return replace(this, null, null, null, null, null, n);
    }

    public function consumeLeadingByCluster(m:SortedMap<Int, Float>):PunctuationGeometryLedger
        return consumeSide(m, true);

    public function consumeTrailingByCluster(m:SortedMap<Int, Float>):PunctuationGeometryLedger
        return consumeSide(m, false);

    public function glueCapacities():SortedMap<Int, GlueCapacity> {
        final b = SortedMap.builder();
        for (i in 0...budgets.size()) {
            final k = budgets.keyAt(i);
            final q = budgets.valueAt(i);
            if (q.leadingRemaining > 0 || q.trailingRemaining > 0)
                b.put(k, new GlueCapacity(q.leadingRemaining, q.trailingRemaining, geometries.has(k)
                    && geometries.get(k).anchor == PunctuationAnchor.Center));
        }
        return b.build();
    }

    public function toDecisionInfo():Array<ClusterGeometryDecisionInfo> {
        final r:Array<ClusterGeometryDecisionInfo> = [];
        for (i in 0...geometries.size()) {
            final k = geometries.keyAt(i);
            final g = geometries.valueAt(i), b = budgets.get(k);
            r.push(new ClusterGeometryDecisionInfo(g.range, g.sourceText, g.displayText, g.baseAdvance, g.bodyWidth, b.leadingNatural, b.leadingConsumed,
                b.trailingNatural, b.trailingConsumed, justificationDeltaByCluster.has(k) ? justificationDeltaByCluster.get(k) : 0,
                resolvedAdvance(k, naturalClusters[k]), "PunctuationGeometryLedger", g.reason, rubySpreadByCluster.has(k) ? rubySpreadByCluster.get(k) : 0,
                g.glyphInlineShift, g.glyphPlacementReason));
        }
        return r;
    }

    function consumeSpacing(p:PunctuationSpacingCompressionResult):PunctuationGeometryLedger {
        var n = cloneB(budgets);
        for (a in p.adjustments) {
            var idx = -1;
            for (i in 0...naturalClusters.length)
                if (PunctuationGeometryLedger.isInside(a.reductionTargetRange, naturalClusters[i].range)) {
                    idx = i;
                    break;
                }
            if (idx >= 0 && n.has(idx)) {
                final q = n.get(idx);
                var replacement:GlueBudget;
                if (geometries.get(idx).anchor == PunctuationAnchor.Center) {
                    final x = Math.min(a.reduction / 2, Math.min(q.leadingRemaining, q.trailingRemaining));
                    replacement = new GlueBudget(q.leadingNatural, q.leadingConsumed + x, q.trailingNatural, q.trailingConsumed + x);
                } else if (q.trailingRemaining >= q.leadingRemaining)
                    replacement = new GlueBudget(q.leadingNatural, q.leadingConsumed, q.trailingNatural,
                        Math.min(q.trailingNatural, q.trailingConsumed + a.reduction));
                else
                    replacement = new GlueBudget(q.leadingNatural, Math.min(q.leadingNatural, q.leadingConsumed + a.reduction), q.trailingNatural,
                        q.trailingConsumed);
                final b = SortedMap.builder();
                for (j in 0...n.size())
                    b.put(n.keyAt(j), n.valueAt(j));
                b.put(idx, replacement);
                n = b.build();
            }
        }
        return replace(this, null, null, null, null, null, n);
    }

    public function consumeLineEdgeGlue(lines:Array<LineCandidate>, ?force:Null<Bool>):LineEdgeTrimResult {
        if (lines.length == 0 || budgets.size() == 0)
            return new LineEdgeTrimResult(this, []);
        var lead:SortedMap<Int, Float> = emptyF();
        var trail:SortedMap<Int, Float> = emptyF();
        final ds:Array<LineEdgeTrimDecisionInfo> = [];
        final forceEnd = force == null ? true : force;
        function consumeAtEdge(line:LineCandidate, index:Int, edge:String):Void {
            if (!budgets.has(index))
                return;
            final q = budgets.get(index);
            final alreadyLead:Float = lead.get(index) == null ? 0 : lead.get(index);
            final alreadyTrail:Float = trail.get(index) == null ? 0 : trail.get(index);
            final lr = Math.max(0, q.leadingRemaining - alreadyLead), tr = Math.max(0, q.trailingRemaining - alreadyTrail);
            final paired = geometries.has(index) && geometries.get(index).anchor == PunctuationAnchor.Center;
            final lp = paired ? Math.min(lr, tr) : (edge == "Start" ? lr : 0);
            final tp = paired ? Math.min(lr, tr) : (edge == "End" ? tr : 0);
            final total = lp + tp;
            if (total <= 0)
                return;
            if (lp > 0)
                lead = putF(lead, index, alreadyLead + lp);
            if (tp > 0)
                trail = putF(trail, index, alreadyTrail + tp);
            var side = "";
            var consumed = 0.0;
            var natural = 0.0;
            var reason = "";
            if (paired) {
                side = "both";
                consumed = q.leadingConsumed + q.trailingConsumed;
                natural = q.leadingNatural + q.trailingNatural;
                reason = edge == "Start" ? "LineStartCenteredPunctuationPairedCompression" : "LineEndCenteredPunctuationPairedCompression";
            } else if (edge == "Start") {
                side = "leading";
                consumed = q.leadingConsumed;
                natural = q.leadingNatural;
                reason = "LineStartHalfWidthPunctuation";
            } else {
                side = "trailing";
                consumed = q.trailingConsumed;
                natural = q.trailingNatural;
                reason = "LineEndHalfWidthPunctuation";
            }
            ds.push(new LineEdgeTrimDecisionInfo(line.sourceRange, naturalClusters[index].range, side, total, consumed, natural, reason));
        }
        for (line in lines) {
            if (line.clusterRange.start > line.clusterRange.end)
                continue;
            final end = line.clusterRange.end;
            if (forceEnd)
                consumeAtEdge(line, end, "End");
            consumeAtEdge(line, line.clusterRange.start, "Start");
        }
        return new LineEdgeTrimResult(consumeLeadingByCluster(lead).consumeTrailingByCluster(trail), ds);
    }

    public function resolveAttachedInlinePunctuationBoundaries(a:Array<InlineAttachment>, atoms:Array<PunctuationAtom>,
            em:Float):AttachedInlinePunctuationBoundaryResult {
        if (a.length != naturalClusters.length)
            throw new org.tiqian.core.TiqianIllegalArgumentException(org.tiqian.core.TextRangeError.Message("Inline attachments must align with punctuation geometry clusters."));
        if (budgets.size() == 0)
            return new AttachedInlinePunctuationBoundaryResult(this, emptyF(), []);
        var hasPrevious = false;
        for (x in a)
            if (x == InlineAttachment.Previous)
                hasPrevious = true;
        if (!hasPrevious)
            return new AttachedInlinePunctuationBoundaryResult(this, emptyF(), []);
        var updated = cloneB(budgets);
        var trailing:SortedMap<Int, Float> = emptyF();
        var decisions:Array<SpacingDecisionInfo> = [];
        final boundaries = UnicodePunctuationBoundaryResolver.resolveAttachedInlineVirtualBoundaries(a);
        for (boundary in boundaries) {
            final previous = boundary.previousClusterIndex;
            final end = boundary.attachedClusterRange.end;
            final previousBudget = updated.has(previous) ? updated.get(previous) : null;
            final left = previousBudget == null ? 0 : previousBudget.trailingRemaining;
            var next = boundary.nextClusterIndex;
            if (next != null && naturalClusters[next].fontKey == "mandatory-break" && naturalClusters[next].displayText == "")
                next = null;
            final nextBudget = next != null && updated.has(next) ? updated.get(next) : null;
            final right = nextBudget == null ? 0 : nextBudget.leadingRemaining;
            var leftAtom:PunctuationAtom = null;
            for (atom in atoms)
                if (isInside(atom.range, naturalClusters[previous].range))
                    leftAtom = atom;
            var rightAtom:PunctuationAtom = null;
            if (next != null)
                for (atom in atoms)
                    if (isInside(atom.range, naturalClusters[next].range)) {
                        rightAtom = atom;
                        break;
                    }
            final nextChar = next == null ? null : naturalClusters[next].text.length > 0 ? naturalClusters[next].text.charAt(0) : null;
            final natural = left + right;
            final adjusted = next == null ? 0 : (leftAtom != null
                && rightAtom != null
                || leftAtom != null
                && leftAtom.punctuationClass == PunctuationClass.Closing
                && nextChar != null
                && ClreqPunctuationPolicies.isAsciiPointMark(nextChar)) ? Math.max(0, natural - em / 2) : natural;
            if (previousBudget != null && left > 0) {
                updated = putB(updated, previous,
                    new GlueBudget(previousBudget.leadingNatural, previousBudget.leadingConsumed, previousBudget.trailingNatural,
                        previousBudget.trailingNatural));
            }
            final kept = Math.min(right, adjusted);
            if (next != null && nextBudget != null && kept < right)
                updated = putB(updated, next,
                    new GlueBudget(nextBudget.leadingNatural, nextBudget.leadingNatural - kept, nextBudget.trailingNatural, nextBudget.trailingConsumed));
            final target = Math.max(0, adjusted - kept);
            if (target > 0)
                trailing = putF(trailing, end, target);
            if (left > 0 || right != adjusted) {
                final n = next == null ? null : naturalClusters[next];
                final reason = next == null ? "AttachedInlineVirtualPunctuationBoundary:line-end" : (leftAtom != null
                    && rightAtom != null ? "AttachedInlineVirtualPunctuationBoundary:adjacent-punctuation" : (leftAtom != null
                        && leftAtom.punctuationClass == PunctuationClass.Closing
                        && nextChar != null
                        && ClreqPunctuationPolicies.isAsciiPointMark(nextChar) ? "AttachedInlineVirtualPunctuationBoundary:ascii-point-mark" : "AttachedInlineVirtualPunctuationBoundary:natural"));
                decisions.push(new SpacingDecisionInfo(new TextRange(naturalClusters[previous].range.start,
                    n == null ? naturalClusters[end].range.end : n.range.end),
                    naturalClusters[previous].text.length > 0 ? naturalClusters[previous].text.charAt(naturalClusters[previous].text.length - 1) : "\u0000",
                    n == null ? "\u0000" : n.text.length > 0 ? n.text.charAt(0) : "\u0000", natural, adjusted, natural
                    - adjusted,
                    naturalClusters[previous].range, reason));
            }
        }
        var attached = cloneF(attachedInlineTrailingGlueByCluster);
        for (i in 0...trailing.size()) {
            var k = trailing.keyAt(i);
            attached = putF(attached, k, Math.max(attached.has(k) ? attached.get(k) : 0, trailing.valueAt(i)));
        }
        return new AttachedInlinePunctuationBoundaryResult(new PunctuationGeometryLedger(naturalClusters, geometries, updated, justificationDeltaByCluster,
            rawEdgeTrimByCluster, rubySpreadByCluster, inlineBoxAdvanceByCluster, attached),
            trailing, decisions);
    }

    static function putB(m:SortedMap<Int, GlueBudget>, k:Int, v:GlueBudget):SortedMap<Int, GlueBudget> {
        final b = SortedMap.builder();
        for (i in 0...m.size())
            b.put(m.keyAt(i), m.valueAt(i));
        b.put(k, v);
        return b.build();
    }

    static function putF(m:SortedMap<Int, Float>, k:Int, v:Float):SortedMap<Int, Float> {
        final b = SortedMap.builder();
        for (i in 0...m.size())
            b.put(m.keyAt(i), m.valueAt(i));
        b.put(k, v);
        return b.build();
    }

    public static function isInside(self:TextRange, other:TextRange):Bool
        return self.start >= other.start && self.end <= other.end;

    public static function clusterIndexRangeFor(self:Array<Cluster>, r:TextRange):Null<IntRange> {
        if (self.length == 0)
            return null;
        var low = 0;
        var high = self.length;
        while (low < high) {
            final mid = (low + high) >>> 1;
            if (self[mid].range.start < r.start)
                low = mid + 1;
            else
                high = mid;
        }
        final first = low;
        low = first;
        high = self.length;
        while (low < high) {
            final mid = (low + high) >>> 1;
            if (self[mid].range.end <= r.end)
                low = mid + 1;
            else
                high = mid;
        }
        final lastExclusive = low;
        return first < lastExclusive ? new IntRange(first, lastExclusive - 1) : null;
    }
}

class AttachedInlinePunctuationBoundaryResult {
    public final geometry:PunctuationGeometryLedger;
    public final trailingGlueByCluster:SortedMap<Int, Float>;
    public final decisions:Array<SpacingDecisionInfo>;

    public function new(g:PunctuationGeometryLedger, t:SortedMap<Int, Float>, d:Array<SpacingDecisionInfo>) {
        geometry = g;
        trailingGlueByCluster = t;
        decisions = d;
    }
}

class PunctuationClusterGeometry {
    public final range:TextRange;
    public final sourceText:String;
    public final displayText:String;
    public final baseAdvance:Float;
    public final bodyWidth:Float;
    public final leadingGlueNatural:Float;
    public final trailingGlueNatural:Float;
    public final leadingGlueInitiallyConsumed:Float;
    public final trailingGlueInitiallyConsumed:Float;
    public final glyphInlineShift:Float;
    public final glyphPlacementReason:Null<String>;
    public final anchor:Null<PunctuationAnchor>;
    public final reason:String;

    public function new(r:TextRange, s:String, d:String, b:Float, w:Float, ln:Float, tn:Float, lc:Float, tc:Float, sh:Float, pr:Null<String>,
            a:Null<PunctuationAnchor>, reason:String) {
        range = r;
        sourceText = s;
        displayText = d;
        baseAdvance = b;
        bodyWidth = w;
        leadingGlueNatural = ln;
        trailingGlueNatural = tn;
        leadingGlueInitiallyConsumed = lc;
        trailingGlueInitiallyConsumed = tc;
        glyphInlineShift = sh;
        glyphPlacementReason = pr;
        anchor = a;
        this.reason = reason;
    }
}

class GlueBudget {
    public final leadingNatural:Float;
    public final leadingConsumed:Float;
    public final trailingNatural:Float;
    public final trailingConsumed:Float;

    public function new(a:Float, b:Float, c:Float, d:Float) {
        leadingNatural = a;
        leadingConsumed = b;
        trailingNatural = c;
        trailingConsumed = d;
    }

    public var leadingRemaining(get, never):Float;

    function get_leadingRemaining():Float
        return Math.max(0, leadingNatural - leadingConsumed);

    public var trailingRemaining(get, never):Float;

    function get_trailingRemaining():Float
        return Math.max(0, trailingNatural - trailingConsumed);
}

class LineEdgeTrimResult {
    public final geometry:PunctuationGeometryLedger;
    public final decisions:Array<LineEdgeTrimDecisionInfo>;

    public function new(g:PunctuationGeometryLedger, d:Array<LineEdgeTrimDecisionInfo>) {
        geometry = g;
        decisions = d;
    }
}

class GlueCapacity {
    public final leading:Float;
    public final trailing:Float;
    public final paired:Bool;

    public function new(l:Float, t:Float, p:Bool) {
        leading = l;
        trailing = t;
        paired = p;
    }
}
