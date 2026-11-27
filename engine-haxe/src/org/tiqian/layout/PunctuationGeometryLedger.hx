package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.AccurateSum;
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
import std.SortedMap.SortedMapBuilder;

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
        // Both arrays are ordered by source position, so one forward cursor
        // replaces the nested scan. The nested form cost clusters x atoms,
        // which is what made punctuation-heavy paragraphs quadratic.
        var atomCursor = 0;
        for (i in 0...naturalClusters.length) {
            final clusterRange = naturalClusters[i].range;
            while (atomCursor < punctuationAtoms.length
                && punctuationAtoms[atomCursor].range.end <= clusterRange.start)
                atomCursor++;
            final atomsForCluster:Array<PunctuationAtom> = [];
            var atomIndex = atomCursor;
            while (atomIndex < punctuationAtoms.length
                && punctuationAtoms[atomIndex].range.start < clusterRange.end) {
                if (isInside(punctuationAtoms[atomIndex].range, clusterRange))
                    atomsForCluster.push(punctuationAtoms[atomIndex]);
                atomIndex++;
            }
            if (atomsForCluster.length > 0) {
                final bodyTerms:Array<Float> = [];
                for (atom in atomsForCluster)
                    bodyTerms.push(atom.bodyWidth);
                final bodyWidth = AccurateSum.of(bodyTerms);
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

    /**
     * Every cluster after the ledger's adjustments. A cluster with no entry in any of the ledger's
     * maps is resolved by `untouchedCluster` without the map lookups; every other cluster goes
     * through `resolveCluster`.
     */
    public function resolveClusters():Array<Cluster> {
        final n = naturalClusters.length;
        final touched = new Array<Bool>();
        for (i in 0...n)
            touched.push(false);
        markKeys(touched, geometries.size(), i -> geometries.keyAt(i));
        markKeys(touched, budgets.size(), i -> budgets.keyAt(i));
        markKeys(touched, justificationDeltaByCluster.size(), i -> justificationDeltaByCluster.keyAt(i));
        markKeys(touched, rawEdgeTrimByCluster.size(), i -> rawEdgeTrimByCluster.keyAt(i));
        markKeys(touched, rubySpreadByCluster.size(), i -> rubySpreadByCluster.keyAt(i));
        markKeys(touched, inlineBoxAdvanceByCluster.size(), i -> inlineBoxAdvanceByCluster.keyAt(i));
        markKeys(touched, attachedInlineTrailingGlueByCluster.size(), i -> attachedInlineTrailingGlueByCluster.keyAt(i));
        final result = new Array<Cluster>();
        for (i in 0...n)
            result.push(touched[i] ? resolveCluster(i) : untouchedCluster(naturalClusters[i]));
        return result;
    }

    static function markKeys(touched:Array<Bool>, count:Int, keyAt:Int->Int):Void {
        for (i in 0...count) {
            final k = keyAt(i);
            if (k >= 0 && k < touched.length)
                touched[k] = true;
        }
    }

    /**
     * `resolveCluster` of a cluster with no entry in any map: every amount is 0 and there is no
     * geometry, so the advance is `resolvedAdvance`'s no-geometry formula with zero amounts, added
     * in the same order.
     */
    static function untouchedCluster(c:Cluster):Cluster {
        final zero:Float = 0;
        final v = Math.max(0, c.advance + zero + zero + zero - zero);
        return v == c.advance ? c : new Cluster(c.range, c.text, c.fontKey, v, c.displayText, c.baselineShift, c.leadingLayoutAdvance, c.glyphInlineShift
            + zero);
    }

    /**
     * `resolveClusters()` of this ledger, given `previous`, the `resolveClusters()` of a ledger
     * that differs from this one only in its justification deltas, `previousDeltas`
     * (`addJustificationDeltas` replaces nothing else). A cluster with a delta in neither ledger
     * reads the same values in both, so its entry is the entry of `previous`; every cluster with a
     * delta in either ledger is resolved again.
     */
    public function resolveClustersChangedFrom(previous:Array<Cluster>, previousDeltas:SortedMap<Int, Float>):Array<Cluster> {
        final result = new Array<Cluster>();
        for (i in 0...previous.length)
            result.push(previous[i]);
        for (i in 0...previousDeltas.size()) {
            final k = previousDeltas.keyAt(i);
            result[k] = resolveCluster(k);
        }
        for (i in 0...justificationDeltaByCluster.size()) {
            final k = justificationDeltaByCluster.keyAt(i);
            result[k] = resolveCluster(k);
        }
        return result;
    }

    function resolveCluster(i:Int):Cluster {
        final c = naturalClusters[i];
        final v = resolvedAdvance(i, c);
        final geometry = geometries.get(i);
        final sh = geometry == null ? 0 : geometry.glyphInlineShift;
        return v == c.advance
            && sh == 0 ? c : new Cluster(c.range, c.text, c.fontKey, v, c.displayText, c.baselineShift, c.leadingLayoutAdvance, c.glyphInlineShift + sh);
    }

    function resolvedAdvance(i:Int, c:Cluster):Float {
        final rawEntry = rawEdgeTrimByCluster.get(i);
        final raw:Float = rawEntry == null ? 0 : rawEntry;
        final spreadEntry = rubySpreadByCluster.get(i);
        final sp:Float = spreadEntry == null ? 0 : spreadEntry;
        final deltaEntry = justificationDeltaByCluster.get(i);
        final d:Float = deltaEntry == null ? 0 : deltaEntry;
        final attachedEntry = attachedInlineTrailingGlueByCluster.get(i);
        final att:Float = attachedEntry == null ? 0 : attachedEntry;
        final boxEntry = inlineBoxAdvanceByCluster.get(i);
        final box:Float = boxEntry == null ? 0 : boxEntry;
        final g = geometries.get(i);
        if (g == null)
            return Math.max(0, c.advance + d + sp + att - raw);
        final b = budgets.get(i);
        if (b == null)
            return Math.max(0, g.bodyWidth + box + d + sp - raw);
        return Math.max(0, g.bodyWidth + box + b.leadingRemaining + b.trailingRemaining + d + sp + att - raw);
    }

    public function withInlineBoxAdvances(advanceByCluster:SortedMap<Int, Float>):PunctuationGeometryLedger
        return advanceByCluster.size() == 0 ? this : replace(this, null, null, null, advanceByCluster);

    public function withRubySpread(spreadByCluster:SortedMap<Int, Float>):PunctuationGeometryLedger
        return spreadByCluster.size() == 0 ? this : replace(this, null, null, spreadByCluster);

    public function withRawEdgeTrims(trimByCluster:SortedMap<Int, Float>):PunctuationGeometryLedger {
        if (trimByCluster.size() == 0)
            return this;
        // One builder holds every existing trim, then one put per trimmed cluster; a later put of
        // the same key wins, and each key of `trimByCluster` adds to the trim it had before.
        final b = SortedMap.builder();
        for (j in 0...rawEdgeTrimByCluster.size())
            b.put(rawEdgeTrimByCluster.keyAt(j), rawEdgeTrimByCluster.valueAt(j));
        for (i in 0...trimByCluster.size()) {
            final k = trimByCluster.keyAt(i);
            final existing = rawEdgeTrimByCluster.get(k);
            b.put(k, (existing == null ? 0 : existing) + trimByCluster.valueAt(i));
        }
        return replace(this, null, b.build());
    }

    public function addJustificationDeltas(deltaByCluster:SortedMap<Int, Float>):PunctuationGeometryLedger
        return replace(this, deltaByCluster);

    function consumeSide(deltaByCluster:SortedMap<Int, Float>, lead:Bool):PunctuationGeometryLedger {
        // One pass over the budgets in key order puts each key once: the budget a consumed cluster
        // gets, or the budget it had. A ledger whose budgets all stay the same is returned as is.
        if (deltaByCluster.size() == 0)
            return this;
        var changed = false;
        final b:SortedMapBuilder<Int, GlueBudget> = SortedMap.builder();
        for (j in 0...budgets.size()) {
            final k = budgets.keyAt(j);
            final q = budgets.valueAt(j);
            final amountEntry = deltaByCluster.get(k);
            final amount:Float = amountEntry == null ? 0 : amountEntry;
            if (amount > 0) {
                changed = true;
                b.put(k, lead ? new GlueBudget(q.leadingNatural, Math.min(q.leadingNatural, q.leadingConsumed + amount), q.trailingNatural,
                    q.trailingConsumed) : new GlueBudget(q.leadingNatural, q.leadingConsumed, q.trailingNatural,
                        Math.min(q.trailingNatural, q.trailingConsumed + amount)));
            } else {
                b.put(k, q);
            }
        }
        return changed ? replace(this, null, null, null, null, null, b.build()) : this;
    }

    public function consumeLeadingByCluster(consumptionByCluster:SortedMap<Int, Float>):PunctuationGeometryLedger
        return consumeSide(consumptionByCluster, true);

    /**
     * `consumeLeadingByCluster(leading).consumeTrailingByCluster(trailing)` in one rebuild of the
     * budgets, with each side given as an array indexed by cluster (0 where nothing is consumed).
     * The leading consumption changes only `leadingConsumed` and the trailing one only
     * `trailingConsumed`, so applying both to each budget gives the budget the two calls give, in
     * either order. One pass over the budgets in key order puts each key once; a ledger whose
     * budgets all stay the same is returned as is.
     */
    public function consumeLeadingAndTrailingByIndex(leading:Array<Float>, trailing:Array<Float>):PunctuationGeometryLedger {
        var changed = false;
        final b:SortedMapBuilder<Int, GlueBudget> = SortedMap.builder();
        for (j in 0...budgets.size()) {
            final k = budgets.keyAt(j);
            final q = budgets.valueAt(j);
            final lead:Float = k < leading.length ? leading[k] : 0;
            final trail:Float = k < trailing.length ? trailing[k] : 0;
            final replacement = consumedBudget(q, lead, trail);
            if (replacement != null) {
                changed = true;
                b.put(k, replacement);
            } else {
                b.put(k, q);
            }
        }
        return changed ? replace(this, null, null, null, null, null, b.build()) : this;
    }

    /** `q` after consuming `lead` and `trail`, or null when neither amount is positive. */
    static function consumedBudget(q:GlueBudget, lead:Float, trail:Float):Null<GlueBudget> {
        if (lead <= 0 && trail <= 0)
            return null;
        return new GlueBudget(q.leadingNatural, lead > 0 ? Math.min(q.leadingNatural, q.leadingConsumed + lead) : q.leadingConsumed, q.trailingNatural,
            trail > 0 ? Math.min(q.trailingNatural, q.trailingConsumed + trail) : q.trailingConsumed);
    }

    public function consumeTrailingByCluster(consumptionByCluster:SortedMap<Int, Float>):PunctuationGeometryLedger
        return consumeSide(consumptionByCluster, false);

    public function glueCapacities():SortedMap<Int, GlueCapacity> {
        final b = SortedMap.builder();
        for (i in 0...budgets.size()) {
            final k = budgets.keyAt(i);
            final q = budgets.valueAt(i);
            if (q.leadingRemaining > 0 || q.trailingRemaining > 0) {
                final geometry = geometries.get(k);
                b.put(k, new GlueCapacity(q.leadingRemaining, q.trailingRemaining, geometry == null ? false : geometry.anchor == PunctuationAnchor.Center));
            }
        }
        return b.build();
    }

    public function toDecisionInfo():Array<ClusterGeometryDecisionInfo> {
        final r:Array<ClusterGeometryDecisionInfo> = [];
        for (i in 0...geometries.size()) {
            final k = geometries.keyAt(i);
            final g = geometries.valueAt(i), b = budgets.get(k);
            final deltaEntry = justificationDeltaByCluster.get(k);
            final spreadEntry = rubySpreadByCluster.get(k);
            r.push(new ClusterGeometryDecisionInfo(g.range, g.sourceText, g.displayText, g.baseAdvance, g.bodyWidth, b.leadingNatural, b.leadingConsumed,
                b.trailingNatural, b.trailingConsumed, deltaEntry == null ? 0 : deltaEntry, resolvedAdvance(k, naturalClusters[k]),
                "PunctuationGeometryLedger", g.reason, spreadEntry == null ? 0 : spreadEntry, g.glyphInlineShift, g.glyphPlacementReason));
        }
        return r;
    }

    function consumeSpacing(p:PunctuationSpacingCompressionResult):PunctuationGeometryLedger {
        // Keys are the cluster indices present in budgets, ascending. Updating
        // the values in place and rebuilding the map once replaces the previous
        // rebuild-per-adjustment, which cost adjustments x clusters.
        final keys = new Array<Int>();
        final values = new Array<GlueBudget>();
        for (i in 0...budgets.size()) {
            keys.push(budgets.keyAt(i));
            values.push(budgets.valueAt(i));
        }
        for (a in p.adjustments) {
            var idx = -1;
            var low = 0;
            var high = naturalClusters.length - 1;
            while (low <= high) {
                final middle = (low + high) >> 1;
                final clusterRange = naturalClusters[middle].range;
                if (a.reductionTargetRange.start < clusterRange.start)
                    high = middle - 1;
                else if (a.reductionTargetRange.start >= clusterRange.end)
                    low = middle + 1;
                else {
                    if (PunctuationGeometryLedger.isInside(a.reductionTargetRange, clusterRange))
                        idx = middle;
                    break;
                }
            }
            if (idx < 0)
                continue;
            var pos = -1;
            var lo = 0;
            var hi = keys.length - 1;
            while (lo <= hi) {
                final mid = (lo + hi) >> 1;
                if (keys[mid] < idx)
                    lo = mid + 1;
                else if (keys[mid] > idx)
                    hi = mid - 1;
                else {
                    pos = mid;
                    break;
                }
            }
            if (pos < 0)
                continue;
            final q = values[pos];
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
            values[pos] = replacement;
        }
        final b = SortedMap.builder();
        for (i in 0...keys.length)
            b.put(keys[i], values[i]);
        return replace(this, null, null, null, null, null, b.build());
    }

    public function consumeLineEdgeGlue(lines:Array<LineCandidate>, ?forceLineEndHalfWidth:Null<Bool>):LineEdgeTrimResult {
        if (lines.length == 0 || budgets.size() == 0)
            return new LineEdgeTrimResult(this, []);
        // Each edge records its consumption in two parallel arrays (cluster index, amount); a later
        // write of the same index replaces the amount, as the former per-edge map rebuild did, and
        // each side becomes one map after the last line.
        final leadKeys = new Array<Int>();
        final leadValues = new Array<Float>();
        final trailKeys = new Array<Int>();
        final trailValues = new Array<Float>();
        final ds:Array<LineEdgeTrimDecisionInfo> = [];
        final forceEnd = forceLineEndHalfWidth == null ? true : forceLineEndHalfWidth;
        // The edges of each line run in an inner loop, not a local function: boring's Rust target
        // passes an array captured by a local function to a mutating parameter as
        // `&mut array.borrow()` (`renderCallArgs` in `RustExpr.hx`), which does not compile.
        for (line in lines) {
            if (line.clusterRange.start > line.clusterRange.end)
                continue;
            final edges:Array<String> = [];
            if (forceEnd)
                edges.push("End");
            edges.push("Start");
            for (edge in edges) {
                final index = edge == "End" ? line.clusterRange.end : line.clusterRange.start;
                final q = budgets.get(index);
                if (q == null)
                    continue;
                final alreadyLead = amountAt(leadKeys, leadValues, index);
                final alreadyTrail = amountAt(trailKeys, trailValues, index);
                final lr = Math.max(0, q.leadingRemaining - alreadyLead), tr = Math.max(0, q.trailingRemaining - alreadyTrail);
                final indexGeometry = geometries.get(index);
                final paired = indexGeometry == null ? false : indexGeometry.anchor == PunctuationAnchor.Center;
                final lp = paired ? Math.min(lr, tr) : (edge == "Start" ? lr : 0);
                final tp = paired ? Math.min(lr, tr) : (edge == "End" ? tr : 0);
                final total = lp + tp;
                if (total <= 0)
                    continue;
                if (lp > 0)
                    setAmount(leadKeys, leadValues, index, alreadyLead + lp);
                if (tp > 0)
                    setAmount(trailKeys, trailValues, index, alreadyTrail + tp);
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
        }
        return new LineEdgeTrimResult(consumeLeadingAndTrailingAmounts(leadKeys, leadValues, trailKeys, trailValues), ds);
    }

    /**
     * `consumeLeadingAndTrailingByIndex` with each side given as parallel arrays (cluster index,
     * amount) instead of an array indexed by cluster. Every recorded amount is positive and an
     * index absent from a side reads 0, which `consumedBudget` treats as no consumption.
     */
    function consumeLeadingAndTrailingAmounts(leadKeys:Array<Int>, leadValues:Array<Float>, trailKeys:Array<Int>,
            trailValues:Array<Float>):PunctuationGeometryLedger {
        if (leadKeys.length == 0 && trailKeys.length == 0)
            return this;
        var changed = false;
        final b:SortedMapBuilder<Int, GlueBudget> = SortedMap.builder();
        for (j in 0...budgets.size()) {
            final k = budgets.keyAt(j);
            final q = budgets.valueAt(j);
            final replacement = consumedBudget(q, amountAt(leadKeys, leadValues, k), amountAt(trailKeys, trailValues, k));
            if (replacement != null) {
                changed = true;
                b.put(k, replacement);
            } else {
                b.put(k, q);
            }
        }
        return changed ? replace(this, null, null, null, null, null, b.build()) : this;
    }

    /** The amount recorded for `index` in the parallel arrays, or 0. */
    static function amountAt(keys:Array<Int>, values:Array<Float>, index:Int):Float {
        for (i in 0...keys.length)
            if (keys[i] == index)
                return values[i];
        return 0;
    }

    /** Records `amount` for `index`, replacing an earlier amount of the same index. */
    static function setAmount(keys:Array<Int>, values:Array<Float>, index:Int, amount:Float):Void {
        for (i in 0...keys.length) {
            if (keys[i] == index) {
                values[i] = amount;
                return;
            }
        }
        keys.push(index);
        values.push(amount);
    }

    public function resolveAttachedInlinePunctuationBoundaries(inlineAttachments:Array<InlineAttachment>, punctuationAtoms:Array<PunctuationAtom>,
            em:Float):AttachedInlinePunctuationBoundaryResult {
        if (inlineAttachments.length != naturalClusters.length)
            throw new org.tiqian.core.TiqianIllegalArgumentException(org.tiqian.core.TextRangeError.Message("Inline attachments must align with punctuation geometry clusters."));
        if (budgets.size() == 0)
            return new AttachedInlinePunctuationBoundaryResult(this, emptyF(), []);
        var hasPrevious = false;
        for (x in inlineAttachments)
            if (x == InlineAttachment.Previous)
                hasPrevious = true;
        if (!hasPrevious)
            return new AttachedInlinePunctuationBoundaryResult(this, emptyF(), []);
        var updated = cloneB(budgets);
        var trailing:SortedMap<Int, Float> = emptyF();
        var decisions:Array<SpacingDecisionInfo> = [];
        final boundaries = UnicodePunctuationBoundaryResolver.resolveAttachedInlineVirtualBoundaries(inlineAttachments);
        for (boundary in boundaries) {
            final previous = boundary.previousClusterIndex;
            final end = boundary.attachedClusterRange.end;
            final previousBudget = updated.get(previous);
            final left = previousBudget == null ? 0 : previousBudget.trailingRemaining;
            var next = boundary.nextClusterIndex;
            if (next != null && naturalClusters[next].fontKey == "mandatory-break" && naturalClusters[next].displayText == "")
                next = null;
            final nextBudget = next != null ? updated.get(next) : null;
            final right = nextBudget == null ? 0 : nextBudget.leadingRemaining;
            var leftAtom:PunctuationAtom = null;
            for (atom in punctuationAtoms)
                if (isInside(atom.range, naturalClusters[previous].range))
                    leftAtom = atom;
            var rightAtom:PunctuationAtom = null;
            if (next != null)
                for (atom in punctuationAtoms)
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
        final attachedBuilder = SortedMap.builder();
        for (j in 0...attachedInlineTrailingGlueByCluster.size())
            attachedBuilder.put(attachedInlineTrailingGlueByCluster.keyAt(j), attachedInlineTrailingGlueByCluster.valueAt(j));
        for (i in 0...trailing.size()) {
            final k = trailing.keyAt(i);
            final attachedEntry = attachedInlineTrailingGlueByCluster.get(k);
            attachedBuilder.put(k, Math.max(attachedEntry == null ? 0 : attachedEntry, trailing.valueAt(i)));
        }
        final attached:SortedMap<Int, Float> = attachedBuilder.build();
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

@:dataClass class AttachedInlinePunctuationBoundaryResult {
    public final geometry:PunctuationGeometryLedger;
    public final trailingGlueByCluster:SortedMap<Int, Float>;
    public final decisions:Array<SpacingDecisionInfo>;

    public function new(geometry:PunctuationGeometryLedger, trailingGlueByCluster:SortedMap<Int, Float>, decisions:Array<SpacingDecisionInfo>) {
        this.geometry = geometry;
        this.trailingGlueByCluster = trailingGlueByCluster;
        this.decisions = decisions;
    }
}

@:dataClass class PunctuationClusterGeometry {
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

    public function new(range:TextRange, sourceText:String, displayText:String, baseAdvance:Float, bodyWidth:Float,
            leadingGlueNatural:Float, trailingGlueNatural:Float, leadingGlueInitiallyConsumed:Float,
            trailingGlueInitiallyConsumed:Float, glyphInlineShift:Float, glyphPlacementReason:Null<String>,
            anchor:Null<PunctuationAnchor>, reason:String) {
        this.range = range;
        this.sourceText = sourceText;
        this.displayText = displayText;
        this.baseAdvance = baseAdvance;
        this.bodyWidth = bodyWidth;
        this.leadingGlueNatural = leadingGlueNatural;
        this.trailingGlueNatural = trailingGlueNatural;
        this.leadingGlueInitiallyConsumed = leadingGlueInitiallyConsumed;
        this.trailingGlueInitiallyConsumed = trailingGlueInitiallyConsumed;
        this.glyphInlineShift = glyphInlineShift;
        this.glyphPlacementReason = glyphPlacementReason;
        this.anchor = anchor;
        this.reason = reason;
    }
}

@:dataClass class GlueBudget {
    public final leadingNatural:Float;
    public final leadingConsumed:Float;
    public final trailingNatural:Float;
    public final trailingConsumed:Float;

    public function new(leadingNatural:Float, leadingConsumed:Float, trailingNatural:Float, trailingConsumed:Float) {
        this.leadingNatural = leadingNatural;
        this.leadingConsumed = leadingConsumed;
        this.trailingNatural = trailingNatural;
        this.trailingConsumed = trailingConsumed;
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
