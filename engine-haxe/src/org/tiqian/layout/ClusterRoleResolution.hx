package org.tiqian.layout;

using std.Functional;

import org.tiqian.core.Cluster;
import org.tiqian.core.TextRange;
import org.tiqian.core.RoleOverrideInfo;
import org.tiqian.font.FontRole;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.font.FontRoleContext;
import org.tiqian.font.FontRoleContext.FontRoleClassifier;
import org.tiqian.font.UnicodeEmojiData;
import org.tiqian.font.UnicodeEmojiStyleVariationData;
import org.tiqian.core.UnicodeEmojiModifierBaseData;
import org.tiqian.clreq.ClreqProfile;
import org.tiqian.core.UnicodeCombiningMarkData;
import org.tiqian.linebreak.LineBreakFns;
import std.SortedMap;

@:dataClass class ResolvedClusterRange {
    public final range:TextRange;
    public final role:FontRole;
    public final mandatoryBreak:Bool;
    public final zeroWidthSoftBreak:Bool;
    public final roleOverride:Null<RoleOverrideInfo>;

    public function new(range:TextRange, role:FontRole, ?mandatoryBreak:Null<Bool>, ?zeroWidthSoftBreak:Null<Bool>, ?roleOverride:Null<RoleOverrideInfo>) {
        this.range = range;
        this.role = role;
        this.mandatoryBreak = mandatoryBreak == null ? false : mandatoryBreak;
        this.zeroWidthSoftBreak = zeroWidthSoftBreak == null ? false : zeroWidthSoftBreak;
        this.roleOverride = roleOverride;
    }
}

class ClusterRoleResolution {
    public static function clusterRoleRanges(text:String, classifier:FontRoleClassifier, context:FontRoleContext, profile:ClreqProfile,
            spanBoundaries:std.SortedSet<Int>, emojiShapingBoundaries:std.SortedSet<Int>,
            ?inlineObjectsByStart:Null<SortedMap<Int, org.tiqian.core.InlineObjectSpan>>):Array<ResolvedClusterRange> {
        final graphemes = org.tiqian.core.SourceInteractionBoundaries.sourceGraphemeBoundaries(text, new TextRange(0, text.length));
        final out:Array<ResolvedClusterRange> = [];
        var index = 0;
        var gi = text.length == 0 ? 0 : 1;
        var gs = graphemes[0];
        var ge = gi < graphemes.length ? graphemes[gi] : text.length;
        while (index < text.length) {
            while (index >= ge && gi < graphemes.length - 1) {
                gs = ge;
                gi++;
                ge = graphemes[gi];
            }
            final io = inlineObjectsByStart == null ? null : inlineObjectsByStart.get(index);
            if (io != null) {
                out.push(new ResolvedClusterRange(io.range, FontRole.Unknown));
                index = io.range.end;
                continue;
            }
            final cp = ClusterRoleResolution.codePoint(text, index);
            final count = cp > 0xFFFF ? 2 : 1;
            final start = index;
            if (ClusterRoleResolution.isMandatory(text, index, cp)) {
                var end = (cp == 13 && index + 1 < text.length && text.charCodeAt(index + 1) == 10) ? index + 2 : index + count;
                out.push(new ResolvedClusterRange(new TextRange(start, end), FontRole.Unknown, true));
                index = end;
                continue;
            }
            if (LineBreakFns.isZeroWidthSpaceCodePoint(cp)) {
                out.push(new ResolvedClusterRange(new TextRange(start, index + count), FontRole.Unknown, false, true));
                index += count;
                continue;
            }
            final classified = classifier.classify(text, new TextRange(start, start + count), context);
            final promotion = ClusterRoleResolution.emojiPromotion(text, start, ge);
            final role = (classified == FontRole.Emoji || promotion != null) ? FontRole.Emoji : classified;
            final prev = out.length == 0 ? null : out[out.length - 1];
            final attached = role == FontRole.LatinText
                && ClusterRoleResolution.isAsciiPoint(cp)
                && prev != null
                && prev.role != FontRole.Unknown
                && !ClusterRoleResolution.isWs(text.charCodeAt(prev.range.end - 1))
                && prev.range.end == start;
            index += count;
            if (role == FontRole.Emoji) {
                var b = ge;
                var bi = 0;
                while (bi < emojiShapingBoundaries.size()) {
                    final k = emojiShapingBoundaries.at(bi);
                    if (k > start && k < ge && (b == ge || k < b))
                        b = k;
                    bi++;
                }
                index = b;
            } else if (role == FontRole.LatinText) {
                if ((cp == 0x2014 || cp == 0x2026) && ClusterRoleResolution.contains(profile.coalesceRepeatablePunctuation, cp)) {
                    while (index < text.length && !spanBoundaries.has(index) && ClusterRoleResolution.codePoint(text, index) == cp)
                        index += cp > 0xFFFF ? 2 : 1;
                } else if (attached) {
                    while (index < text.length
                        && !spanBoundaries.has(index)
                        && ClusterRoleResolution.isAsciiPoint(ClusterRoleResolution.codePoint(text, index)))
                        index += 1;
                } else {
                    while (index < text.length && !spanBoundaries.has(index)) {
                        final n = ClusterRoleResolution.codePoint(text, index);
                        if (n == 0x2014
                            || n == 0x2026
                            || classifier.classify(text, new TextRange(index, index + (n > 0xFFFF ? 2 : 1)), context) != FontRole.LatinText
                            || ClusterRoleResolution.emojiPromotion(text, index, text.length) != null)
                            break;
                        index += n > 0xFFFF ? 2 : 1;
                    }
                }
            } else if (role == FontRole.CjkPunctuation && ClusterRoleResolution.contains(profile.coalesceRepeatablePunctuation, cp)) {
                while (index < text.length && !spanBoundaries.has(index) && ClusterRoleResolution.codePoint(text, index) == cp)
                    index += cp > 0xFFFF ? 2 : 1;
            }
            while (index < text.length && !spanBoundaries.has(index)) {
                final e = ClusterRoleResolution.codePoint(text, index);
                if (!ClusterRoleResolution.isCombining(e) && !isVariation(e))
                    break;
                index += e > 0xFFFF ? 2 : 1;
            }
            final r = new TextRange(start, index);
            var roleInfo:Null<RoleOverrideInfo> = null;
            if (role == FontRole.Emoji && classified != FontRole.Emoji)
                roleInfo = new RoleOverrideInfo(r, text.substring(r.start, r.end), Std.string(classified), Std.string(role),
                    "UnicodeEmojiSequenceRolePromotion", promotion == null ? "EmojiPresentationCodePoint" : promotion);
            out.push(new ResolvedClusterRange(r, role, false, false, roleInfo));
        }
        return out;
    }

    public static function requireCoveredBy(clusters:Array<Cluster>, decisions:Array<FontDecision>):Void {
        var ci = 0;
        var di = 0;
        while (di < decisions.length) {
            final d = decisions[di++];
            while (ci < clusters.length && clusters[ci].range.end <= d.range.start)
                ci++;
            var cursor = d.range.start;
            while (ci < clusters.length && clusters[ci].range.start < d.range.end) {
                final c = clusters[ci];
                if (!(c.range.start >= d.range.start && c.range.end <= d.range.end))
                    throw new org.tiqian.core.TiqianIllegalArgumentException(org.tiqian.core.TextRangeError.Message("TextShaper returned cluster " + c.range
                        + " crossing " + d.range));
                if (c.range.start != cursor)
                    throw new org.tiqian.core.TiqianIllegalArgumentException(org.tiqian.core.TextRangeError.Message("TextShaper returned non-contiguous clusters for "
                        + d.range + "; expected start=" + cursor + ", actual=" + c.range));
                cursor = c.range.end;
                ci++;
            }
            if (cursor != d.range.end)
                throw new org.tiqian.core.TiqianIllegalArgumentException(org.tiqian.core.TextRangeError.Message("TextShaper must return clusters covering "
                    + d.range + "; coveredUntil=" + cursor));
        }
    }

    static function codePoint(t:String, i:Int):Int {
        final h = t.charCodeAt(i);
        if (h < 0xD800 || h > 0xDBFF || i + 1 >= t.length)
            return h;
        final l = t.charCodeAt(i + 1);
        return l < 0xDC00 || l > 0xDFFF ? h : 0x10000 + ((h - 0xD800) << 10) + (l - 0xDC00);
    }

    static function isMandatory(t:String, i:Int, c:Int):Bool {
        return LineBreakFns.isMandatoryBreakCodePoint(c) && !(c == 10 && i > 0 && t.charCodeAt(i - 1) == 13);
    }

    static function contains(a:std.ReadOnlyArray<Int>, v:Int):Bool {
        var i = 0;
        while (i < a.length) {
            if (a[i] == v)
                return true;
            i++;
        }
        return false;
    }

    static function isVariation(c:Int):Bool {
        return c >= 0xFE00 && c <= 0xFE0F || c >= 0xE0100 && c <= 0xE01EF;
    }

    static function isCombining(c:Int):Bool {
        return c <= 0xFFFF && UnicodeCombiningMarkData.contains(c);
    }

    // Mirrors Kotlin Char.isWhitespace on the JVM: Character.isWhitespace || Character.isSpaceChar
    // (the union includes non-breaking spaces); copied from UnicodePunctuationBoundaryResolver.hx.
    static function isWs(cp:Int):Bool {
        return cp <= 0xFFFF
            && ((cp >= 9 && cp <= 13) || (cp >= 0x1C && cp <= 0x20) || cp == 0xA0 || cp == 0x1680 || (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028
                || cp == 0x2029 || cp == 0x202F || cp == 0x205F || cp == 0x3000);
    }

    static function isAsciiPoint(c:Int):Bool {
        return c == 44 || c == 46 || c == 59 || c == 58 || c == 33 || c == 63;
    }

    static function emojiPromotion(t:String, s:Int, e:Int):Null<String> {
        final b = codePoint(t, s);
        var n = s + (b > 0xFFFF ? 2 : 1);
        if ((b == 35 || b == 42 || b >= 48 && b <= 57)) {
            if (n < e && codePoint(t, n) == 0xFE0F)
                n++;
            if (n < e && codePoint(t, n) == 0x20E3)
                return "KeycapSequence";
        }
        if (UnicodeEmojiData.contains(b) && UnicodeEmojiStyleVariationData.contains(b) && n < e && codePoint(t, n) == 0xFE0F)
            return "EmojiStyleVariationSequence";
        if (UnicodeEmojiModifierBaseData.contains(b)) {
            while (n < e && (isCombining(codePoint(t, n)) || isVariation(codePoint(t, n))))
                n += codePoint(t, n) > 0xFFFF ? 2 : 1;
            final m = codePoint(t, n);
            if (m >= 0x1F3FB && m <= 0x1F3FF)
                return "EmojiModifierSequence";
        }
        return null;
    }
}
