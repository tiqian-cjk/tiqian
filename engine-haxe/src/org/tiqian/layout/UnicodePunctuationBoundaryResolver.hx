package org.tiqian.layout;

using std.Functional;

import org.tiqian.core.Cluster;
import org.tiqian.core.ContextualKinsokuDecisionInfo;
import org.tiqian.core.EastAsianSpacingEdges;
import org.tiqian.core.EastAsianSpacingValue;
import org.tiqian.core.InlineAttachment;
import org.tiqian.core.IntRange;
import org.tiqian.font.FontRole;
import org.tiqian.layout.QuotePairAnalyzer.QuotePair;
import org.tiqian.linebreak.UnicodePunctuationLineBreak;
import org.tiqian.linebreak.UnicodePunctuationLineBreak.UnicodePunctuationLineBreakClass;
import org.tiqian.linebreak.LineBreakFns;
import std.SortedMap;
import std.SortedSet;

@:dataClass class SignificantCodePoint {
    public final offset:Int;
    public final codePoint:Int;

    public function new(offset:Int, codePoint:Int) {
        this.offset = offset;
        this.codePoint = codePoint;
    }
}

private enum Dir {
    Initial;
    Final;
    Unresolved;
    Word;
    None;
}

@:dataClass class UnicodePunctuationBoundaries {
    public final forbiddenLineStartClusters:SortedSet<Int>;
    public final forbiddenLineEndClusters:SortedSet<Int>;
    public final unbreakableRanges:Array<IntRange>;
    public final decisions:Array<ContextualKinsokuDecisionInfo>;

    public function new(forbiddenLineStartClusters:SortedSet<Int>, forbiddenLineEndClusters:SortedSet<Int>, unbreakableRanges:Array<IntRange>,
            decisions:Array<ContextualKinsokuDecisionInfo>) {
        this.forbiddenLineStartClusters = forbiddenLineStartClusters;
        this.forbiddenLineEndClusters = forbiddenLineEndClusters;
        this.unbreakableRanges = unbreakableRanges;
        this.decisions = decisions;
    }
}

@:dataClass class AttachedInlineVirtualBoundary {
    public final previousClusterIndex:Int;
    public final attachedClusterRange:IntRange;
    public final nextClusterIndex:Null<Int>;

    public function new(previousClusterIndex:Int, attachedClusterRange:IntRange, nextClusterIndex:Null<Int>) {
        this.previousClusterIndex = previousClusterIndex;
        this.attachedClusterRange = attachedClusterRange;
        this.nextClusterIndex = nextClusterIndex;
    }
}

@:dataClass class AttachedInlineInterCharBoundaries {
    public final ordinaryWesternBoundaryAfterClusters:SortedSet<Int>;
    public final suppressedPhysicalBoundaryAfterClusters:SortedSet<Int>;
    public final virtualBoundaryAfterClusters:SortedMap<Int, Int>;
    public final virtualSinoWesternBoundaryAfterClusters:SortedSet<Int>;

    public function new(ordinaryWesternBoundaryAfterClusters:SortedSet<Int>, suppressedPhysicalBoundaryAfterClusters:SortedSet<Int>,
            virtualBoundaryAfterClusters:SortedMap<Int, Int>, virtualSinoWesternBoundaryAfterClusters:SortedSet<Int>) {
        this.ordinaryWesternBoundaryAfterClusters = ordinaryWesternBoundaryAfterClusters;
        this.suppressedPhysicalBoundaryAfterClusters = suppressedPhysicalBoundaryAfterClusters;
        this.virtualBoundaryAfterClusters = virtualBoundaryAfterClusters;
        this.virtualSinoWesternBoundaryAfterClusters = virtualSinoWesternBoundaryAfterClusters;
    }
}

class UnicodePunctuationBoundaryResolver {
    public static function resolveWesternBracketCjkInterCharBoundaries(text:String, clusters:Array<Cluster>, roles:Array<FontRole>):SortedSet<Int> {
        final b = SortedSet.builder();
        var i = 0;
        while (i + 1 < clusters.length) {
            if (isWesternBracketCjkInterCharBoundary(text, clusters, roles, i, i + 1))
                b.put(i);
            i++;
        }
        return b.build();
    }

    public static function resolveAttachedInlineVirtualBoundaries(a:Array<InlineAttachment>):Array<AttachedInlineVirtualBoundary> {
        final r:Array<AttachedInlineVirtualBoundary> = [];
        var i = 0;
        while (i < a.length) {
            if (a[i] != InlineAttachment.Previous) {
                i++;
                continue;
            }
            final s = i;
            var e = s;
            while (e + 1 < a.length && a[e + 1] == InlineAttachment.Previous)
                e++;
            if (s > 0)
                r.push(new AttachedInlineVirtualBoundary(s - 1, new IntRange(s, e), e + 1 < a.length ? e + 1 : null));
            i = e + 1;
        }
        return r;
    }

    public static function resolveAttachedInlineInterCharBoundaries(text:String, clusters:Array<Cluster>, roles:Array<FontRole>,
            edges:Array<EastAsianSpacingEdges>, western:SortedSet<Int>, attachments:Array<InlineAttachment>):AttachedInlineInterCharBoundaries {
        if (clusters.length != roles.length || clusters.length != edges.length)
            throw new org.tiqian.core.TiqianIllegalArgumentException(Message("Clusters, roles and East_Asian_Spacing edges must align."));
        if (clusters.length != attachments.length)
            throw new org.tiqian.core.TiqianIllegalArgumentException(Message("Inline attachments must align with clusters."));
        final vb = resolveAttachedInlineVirtualBoundaries(attachments);
        final sup = SortedSet.builder();
        var i = 0;
        while (i < vb.length) {
            sup.put(vb[i].previousClusterIndex);
            if (vb[i].nextClusterIndex != null)
                sup.put(vb[i].attachedClusterRange.end);
            i++;
        }
        final supSet = sup.build();
        final ordinary = SortedSet.builder();
        i = 0;
        while (i < western.size()) {
            final x = western.at(i);
            if (!supSet.has(x))
                ordinary.put(x);
            i++;
        }
        final vm = SortedMap.builder();
        final vs = SortedSet.builder();
        i = 0;
        while (i < vb.length) {
            final q = vb[i];
            i++;
            if (q.nextClusterIndex == null)
                continue;
            final n = q.nextClusterIndex;
            final p = q.previousClusterIndex;
            final both = isCjk(roles[p]) && isCjk(roles[n]);
            final punct = (roles[p] == FontRole.CjkPunctuation && edges[n].leading == EastAsianSpacingValue.Narrow)
                || (edges[p].trailing == EastAsianSpacingValue.Narrow && roles[n] == FontRole.CjkPunctuation);
            final sino = wideNarrow(edges[p].trailing, edges[n].leading);
            final bracket = isWesternBracketCjkInterCharBoundary(text, clusters, roles, p, n);
            if (both || punct || sino || bracket)
                vm.put(q.attachedClusterRange.end, p);
            if (sino)
                vs.put(q.attachedClusterRange.end);
        }
        return new AttachedInlineInterCharBoundaries(ordinary.build(), sup.build(), vm.build(), vs.build());
    }

    public static function resolveUnicodePunctuationBoundaries(text:String, clusters:Array<Cluster>, roles:Array<FontRole>,
            pairs:Array<QuotePair>):UnicodePunctuationBoundaries {
        final opens = SortedSet.builder();
        final closes = SortedSet.builder();
        var i = 0;
        while (i < pairs.length) {
            opens.put(pairs[i].openIndex);
            closes.put(pairs[i].closeIndex);
            i++;
        }
        final openSet = opens.build();
        final closeSet = closes.build();
        final start = SortedSet.builder();
        final end = SortedSet.builder();
        final ranges:Array<IntRange> = [];
        final decisions:Array<ContextualKinsokuDecisionInfo> = [];
        i = 0;
        while (i < clusters.length) {
            final c = clusters[i];
            i++;
            final ix = i - 1;
            if (ix >= roles.length || roles[ix] == FontRole.CjkPunctuation || c.range.start >= c.range.end)
                continue;
            final source = text.substring(c.range.start, c.range.end);
            final first = firstSig(source);
            if (first == null)
                continue;
            final last = lastSig(source);
            if (last == null)
                continue;
            final fc = UnicodePunctuationLineBreak.classOf(first.codePoint);
            final lc = UnicodePunctuationLineBreak.classOf(last.codePoint);
            final fo = c.range.start + first.offset;
            final lo = c.range.start + last.offset;
            final fdir = quoteDir(text, fo, first.codePoint, fc);
            final ldir = quoteDir(text, lo, last.codePoint, lc);
            final pairedClose = closeSet.has(fo);
            final authored = follows(text, fo);
            var forbidStart = authored ? false : (pairedClose
                || fdir == Final
                || fdir == Unresolved
                || (fc == UnicodePunctuationLineBreakClass.InfixNumericSeparator && !decimalAfterSpace(ix, text, clusters))
                || forbidClass(fc));
            if (forbidStart) {
                start.put(ix);
                final p = previous(ix, text, clusters);
                if (p != null)
                    ranges.push(new IntRange(p, ix));
                var reason = pairedClose ? "Uax14WesternPunctuationBoundary:PairedClosingQuote" : (fdir == Final
                    || fdir == Unresolved ? "Uax14WesternPunctuationBoundary:LB19" : "Uax14WesternPunctuationBoundary:" + rule(fc));
                decisions.push(new ContextualKinsokuDecisionInfo(c.range, source, ix, "LineStart", reason));
            }
            final pairedOpen = openSet.has(lo);
            final forbidEnd = pairedOpen
                || ldir == Initial
                || ldir == Unresolved
                || lc == UnicodePunctuationLineBreakClass.OpenPunctuation;
            if (forbidEnd) {
                end.put(ix);
                final n = next(ix, text, clusters);
                if (n != null)
                    ranges.push(new IntRange(ix, n));
                final reason = pairedOpen ? "Uax14WesternPunctuationBoundary:PairedOpeningQuote" : (ldir == Initial
                    || ldir == Unresolved ? "Uax14WesternPunctuationBoundary:LB19" : "Uax14WesternPunctuationBoundary:LB14");
                decisions.push(new ContextualKinsokuDecisionInfo(c.range, source, ix, "LineEnd", reason));
            }
        }
        return new UnicodePunctuationBoundaries(start.build(), end.build(), distinct(ranges), decisions);
    }

    static function isCjk(r:FontRole):Bool
        return r == FontRole.CjkText || r == FontRole.CjkPunctuation;

    static function wideNarrow(a:EastAsianSpacingValue, b:EastAsianSpacingValue):Bool
        return (a == EastAsianSpacingValue.Wide && b == EastAsianSpacingValue.Narrow)
            || (a == EastAsianSpacingValue.Narrow && b == EastAsianSpacingValue.Wide);

    static function isWesternBracketCjkInterCharBoundary(t:String, c:Array<Cluster>, r:Array<FontRole>, a:Int, b:Int):Bool {
        final l = r[a] != FontRole.CjkPunctuation && westernCp(lastSig(t.substring(c[a].range.start, c[a].range.end)));
        final q = r[b] != FontRole.CjkPunctuation && westernCp(firstSig(t.substring(c[b].range.start, c[b].range.end)));
        return (l && r[b] == FontRole.CjkText) || (r[a] == FontRole.CjkText && q);
    }

    static function westernCp(s:Null<SignificantCodePoint>):Bool
        return s != null
            && (UnicodePunctuationLineBreak.classOf(s.codePoint) == UnicodePunctuationLineBreakClass.OpenPunctuation
                || UnicodePunctuationLineBreak.classOf(s.codePoint) == UnicodePunctuationLineBreakClass.ClosePunctuation
                || UnicodePunctuationLineBreak.classOf(s.codePoint) == UnicodePunctuationLineBreakClass.CloseParenthesis);

    static function forbidClass(c:UnicodePunctuationLineBreakClass):Bool
        return c == UnicodePunctuationLineBreakClass.ClosePunctuation
            || c == UnicodePunctuationLineBreakClass.CloseParenthesis
            || c == UnicodePunctuationLineBreakClass.Exclamation
            || c == UnicodePunctuationLineBreakClass.InfixNumericSeparator;

    static function rule(c:UnicodePunctuationLineBreakClass):String
        return c == UnicodePunctuationLineBreakClass.InfixNumericSeparator ? "LB15d" : "LB13";

    static function decimalAfterSpace(i:Int, t:String, c:Array<Cluster>):Bool {
        if (i <= 0)
            return false;
        final p = t.substring(c[i - 1].range.start, c[i - 1].range.end);
        if (p.length == 0)
            return false;
        var j = 0;
        while (j < p.length) {
            if (!isWs(p.charCodeAt(j)))
                return false;
            j++;
        }
        final cur = t.substring(c[i].range.start, c[i].range.end);
        var cp = cur.length > 1 ? cpAt(cur, 1) : (i + 1 < c.length ? cpAt(t.substring(c[i + 1].range.start, c[i + 1].range.end), 0) : null);
        return cp != null && cp >= 48 && cp <= 57;
    }

    static function quoteDir(t:String, o:Int, cp:Int, c:UnicodePunctuationLineBreakClass):Dir {
        if (c != UnicodePunctuationLineBreakClass.Quotation)
            return None;
        if (cp == 0x2019) {
            final l = word(cpBefore(t, o));
            final rr = word(cpAt(t, o + 1));
            return l && rr ? Word : (l ? Final : (rr ? Initial : Final));
        }
        return cp == 0x00AB
            || cp == 0x2018
            || cp == 0x201B
            || cp == 0x201C
            || cp == 0x201F
            || cp == 0x2039 ? Initial : (cp == 0x00BB || cp == 0x2019 || cp == 0x201D || cp == 0x203A ? Final : Unresolved);
    }

    static function word(cp:Null<Int>):Bool
        return cp != null
            && ((cp >= 65 && cp <= 90) || (cp >= 97 && cp <= 122) || (cp >= 48 && cp <= 57) || (cp >= 0x00C0 && cp <= 0x024F));

    static function follows(t:String, o:Int):Bool {
        var x = o;
        while (x > 0) {
            final p = cpBefore(t, x);
            if (p == null || LineBreakFns.isMandatoryBreakCodePoint(p) || LineBreakFns.isZeroWidthSpaceCodePoint(p))
                return true;
            if (!isWs(p))
                return false;
            x--;
        }
        return true;
    }

    // Kotlin Int.isWhitespaceCodePoint calls Char.isWhitespace(), which on the JVM is
    // Character.isWhitespace||isSpaceChar: the union includes non-breaking spaces.
    static function isWs(cp:Int):Bool
        return cp <= 0xFFFF
            && ((cp >= 9 && cp <= 13) || (cp >= 0x1C && cp <= 0x20) || cp == 0xA0 || cp == 0x1680 || (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028
                || cp == 0x2029 || cp == 0x202F || cp == 0x205F || cp == 0x3000);

    static function previous(i:Int, t:String, c:Array<Cluster>):Null<Int> {
        var x = i - 1;
        while (x >= 0) {
            final s = t.substring(c[x].range.start, c[x].range.end);
            if (hasBreak(s))
                return null;
            if (firstSig(s) != null)
                return x;
            x--;
        }
        return null;
    }

    static function next(i:Int, t:String, c:Array<Cluster>):Null<Int> {
        var x = i + 1;
        while (x < c.length) {
            final s = t.substring(c[x].range.start, c[x].range.end);
            if (hasBreak(s))
                return null;
            if (firstSig(s) != null)
                return x;
            x++;
        }
        return null;
    }

    static function hasBreak(s:String):Bool {
        var i = 0;
        while (i < s.length) {
            final p = cpAt(s, i);
            if (p == null)
                return false;
            if (LineBreakFns.isMandatoryBreakCodePoint(p) || LineBreakFns.isZeroWidthSpaceCodePoint(p))
                return true;
            i += p > 0xFFFF ? 2 : 1;
        }
        return false;
    }

    static function cpAt(s:String, i:Int):Null<Int> {
        if (i < 0 || i >= s.length)
            return null;
        final h = s.charCodeAt(i);
        if (h < 0xD800 || h > 0xDBFF || i + 1 >= s.length)
            return h;
        final l = s.charCodeAt(i + 1);
        return l >= 0xDC00 && l <= 0xDFFF ? 0x10000 + ((h - 0xD800) << 10) + (l - 0xDC00) : h;
    }

    static function cpBefore(s:String, i:Int):Null<Int> {
        if (i <= 0 || i > s.length)
            return null;
        final l = s.charCodeAt(i - 1);
        if (l >= 0xDC00 && l <= 0xDFFF && i > 1) {
            final h = s.charCodeAt(i - 2);
            if (h >= 0xD800 && h <= 0xDBFF)
                return 0x10000 + ((h - 0xD800) << 10) + (l - 0xDC00);
        }
        return l;
    }

    static function firstSig(s:String):Null<SignificantCodePoint> {
        var i = 0;
        while (i < s.length) {
            final p = cpAt(s, i);
            if (p == null)
                return null;
            if (!isWs(p))
                return new SignificantCodePoint(i, p);
            i++;
        }
        return null;
    }

    static function lastSig(s:String):Null<SignificantCodePoint> {
        var e = s.length;
        while (e > 0) {
            final i = (s.charCodeAt(e - 1) >= 0xDC00 && s.charCodeAt(e - 1) <= 0xDFFF) ? e - 2 : e - 1;
            final p = cpAt(s, i);
            if (p == null)
                return null;
            if (!isWs(p))
                return new SignificantCodePoint(i, p);
            e = i;
        }
        return null;
    }

    static function distinct(a:Array<IntRange>):Array<IntRange> {
        final r:Array<IntRange> = [];
        var i = 0;
        while (i < a.length) {
            var found = false;
            var j = 0;
            while (j < r.length) {
                if (r[j].start == a[i].start && r[j].end == a[i].end)
                    found = true;
                j++;
            }
            if (!found)
                r.push(a[i]);
            i++;
        }
        return r;
    }
}
