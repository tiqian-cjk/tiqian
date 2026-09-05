package org.tiqian.layout;

using std.Functional;

import org.tiqian.core.RoleOverrideInfo;
import org.tiqian.core.TextRange;
import org.tiqian.core.UnicodeEastAsianSpacing;
import org.tiqian.core.UnicodeScriptEvidence;
import org.tiqian.core.UnicodeScriptEvidenceClassifier;
import org.tiqian.core.UnicodeWordCharacter;
import org.tiqian.font.FontRole;
import org.tiqian.font.FontRoleContext;
import org.tiqian.font.FontRoleContext.FontRoleClassifier;
import org.tiqian.linebreak.LineBreakFns;
import std.SortedMap;

@:dataClass class DashEllipsisRoleDecision {
    public final range:TextRange;
    public final role:FontRole;
    public final source:String;
    public final reason:String;

    public function new(range:TextRange, role:FontRole, source:String, reason:String) {
        this.range = range;
        this.role = role;
        this.source = source;
        this.reason = reason;
    }
}

class ContextualDashEllipsisRoleResolver {
    public function new() {}

    public function resolve(text:String, ?context:Null<FontRoleContext>):Array<DashEllipsisRoleDecision> {
        final actualContext:FontRoleContext = context == null ? new FontRoleContext() : context;
        var hasMark = false;
        var ci = 0;
        while (ci < text.length) {
            if (isContextualDashOrEllipsis(text.charCodeAt(ci))) {
                hasMark = true;
                break;
            }
            ci++;
        }
        if (!hasMark)
            return [];
        final strongScriptContext = new StrongScriptContextIndex(text);
        final runs = collectRuns(text);
        final pairResolutions = resolveParentheticalPairs(text, runs, strongScriptContext, actualContext);
        final result:Array<DashEllipsisRoleDecision> = [];
        var ri = 0;
        while (ri < runs.length) {
            final range = runs[ri];
            final paired:Null<Resolution> = pairResolutions.get(range.start);
            final resolution:Resolution = paired == null ? resolveSingleRun(range, strongScriptContext, actualContext) : paired;
            result.push(new DashEllipsisRoleDecision(range, resolution.role, resolution.source, resolution.reason));
            ri++;
        }
        return result;
    }

    private function collectRuns(text:String):Array<TextRange> {
        final runs:Array<TextRange> = [];
        var index = 0;
        while (index < text.length) {
            if (!isContextualDashOrEllipsis(text.charCodeAt(index))) {
                index += codePointLengthAt(text, index);
                continue;
            }
            final start = index;
            while (index < text.length && isContextualDashOrEllipsis(text.charCodeAt(index)))
                index++;
            runs.push(new TextRange(start, index));
        }
        return runs;
    }

    private function resolveSingleRun(range:TextRange, strongScriptContext:StrongScriptContextIndex, context:FontRoleContext):Resolution {
        final leftRole = strongScriptContext.leftOf(range.start);
        final rightRole = strongScriptContext.rightOf(range.end);
        if (leftRole != null && rightRole == leftRole)
            return new Resolution(leftRole, "DashEllipsisSurroundingScriptContext", "matching-surrounding-script");
        if (leftRole != null && rightRole == null)
            return new Resolution(leftRole, "DashEllipsisSurroundingScriptContext", "only-left-strong-script");
        if (rightRole != null && leftRole == null)
            return new Resolution(rightRole, "DashEllipsisSurroundingScriptContext", "only-right-strong-script");
        final reason = leftRole != null && rightRole != null ? "conflicting-surrounding-script" : "no-strong-script-context";
        return paragraphLanguageResolution(context, reason);
    }

    private function resolveParentheticalPairs(text:String, runs:Array<TextRange>, strongScriptContext:StrongScriptContextIndex,
            context:FontRoleContext):SortedMap<Int, Resolution> {
        final resolutions = SortedMap.builder();
        var index = 0;
        while (index + 1 < runs.length) {
            final first = runs[index];
            final second = runs[index + 1];
            if (!isParentheticalDashPair(text, first, second)) {
                index++;
                continue;
            }
            final leftRole = strongScriptContext.leftOf(first.start);
            final rightRole = strongScriptContext.rightOf(second.end);
            final resolution = parentheticalPairResolution(leftRole, rightRole, context);
            resolutions.put(first.start, resolution);
            resolutions.put(second.start, resolution);
            index += 2;
        }
        return resolutions.build();
    }

    // Kotlin spells this as a `when` expression initializing `val resolution`;
    // the early-return helper keeps the initializer-expression shape.
    private function parentheticalPairResolution(leftRole:Null<FontRole>, rightRole:Null<FontRole>, context:FontRoleContext):Resolution {
        if (leftRole != null && rightRole == leftRole)
            return new Resolution(leftRole, "ParentheticalDashPairContext", "matching-outer-script");
        if (leftRole != null && rightRole == null)
            return new Resolution(leftRole, "ParentheticalDashPairContext", "only-left-outer-script");
        if (rightRole != null && leftRole == null)
            return new Resolution(rightRole, "ParentheticalDashPairContext", "only-right-outer-script");
        final reason = leftRole != null
            && rightRole != null ? "parenthetical-pair-conflicting-outer-script" : "parenthetical-pair-no-outer-context";
        return paragraphLanguageResolution(context, reason);
    }

    private function paragraphLanguageResolution(context:FontRoleContext, reason:String):Resolution {
        final role = UnicodeEastAsianSpacing.isChineseLanguageContext(context.locale) ? FontRole.CjkPunctuation : FontRole.LatinText;
        return new Resolution(role, "ParagraphLanguageDashEllipsisContext", reason + "; paragraph-language=" + context.locale);
    }

    private static function isContextualDashOrEllipsis(codePoint:Int):Bool
        return codePoint == 0x2014 || codePoint == 0x2026;

    private static function isParentheticalDashPair(text:String, first:TextRange, second:TextRange):Bool {
        if (!isPureDashRun(text, first) || !isPureDashRun(text, second))
            return false;
        if (first.end - first.start != second.end - second.start)
            return false;
        var index = first.end;
        while (index < second.start) {
            final cp = codePointAtCompat(text, index);
            if (cp != 0x20 && !UnicodeWordCharacter.contains(cp))
                return false;
            index += charCount(cp);
        }
        return true;
    }

    private static function isPureDashRun(text:String, range:TextRange):Bool {
        var index = range.start;
        while (index < range.end) {
            if (text.charCodeAt(index) != 0x2014)
                return false;
            index++;
        }
        return true;
    }

    public static function codePointAtCompat(text:String, index:Int):Int {
        final high = text.charCodeAt(index);
        if (high < 0xD800 || high > 0xDBFF || index + 1 >= text.length)
            return high;
        final low = text.charCodeAt(index + 1);
        if (low < 0xDC00 || low > 0xDFFF)
            return high;
        return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
    }

    public static function codePointLengthAt(text:String, index:Int):Int
        return charCount(codePointAtCompat(text, index));

    public static function charCount(codePoint:Int):Int
        return codePoint > 0xFFFF ? 2 : 1;
}

class ContextualDashEllipsisAwareFontRoleClassifier implements FontRoleClassifier {
    private final delegate:FontRoleClassifier;
    private final roleByIndex:SortedMap<Int, FontRole>;

    public function new(delegate:FontRoleClassifier, decisions:Array<DashEllipsisRoleDecision>) {
        this.delegate = delegate;
        final builder = SortedMap.builder();
        var di = 0;
        while (di < decisions.length) {
            final d = decisions[di];
            var index = d.range.start;
            while (index < d.range.end) {
                builder.put(index, d.role);
                index++;
            }
            di++;
        }
        roleByIndex = builder.build();
    }

    public function classify(text:String, range:TextRange, ?context:Null<FontRoleContext>):FontRole {
        final role = roleByIndex.get(range.start);
        return role == null ? delegate.classify(text, range, context) : role;
    }
}

class ContextualDashEllipsisRoles {
    public static function withContextualDashEllipsisRoles(base:FontRoleClassifier, text:String, ?context:Null<FontRoleContext>):FontRoleClassifier {
        final decisions = new ContextualDashEllipsisRoleResolver().resolve(text, context);
        return decisions.length == 0 ? base : new ContextualDashEllipsisAwareFontRoleClassifier(base, decisions);
    }

    public static function toRoleOverrideInfos(decisions:Array<DashEllipsisRoleDecision>, text:String, baseClassifier:FontRoleClassifier,
            context:FontRoleContext):Array<RoleOverrideInfo> {
        final result:Array<RoleOverrideInfo> = [];
        var index = 0;
        while (index < decisions.length) {
            final d = decisions[index];
            final first = new TextRange(d.range.start, d.range.start + 1);
            result.push(new RoleOverrideInfo(d.range, text.substring(d.range.start, d.range.end), Std.string(baseClassifier.classify(text, first, context)),
                Std.string(d.role), d.source, d.reason));
            index++;
        }
        return result;
    }
}

private class Resolution {
    public final role:FontRole;
    public final source:String;
    public final reason:String;

    public function new(role:FontRole, source:String, reason:String) {
        this.role = role;
        this.source = source;
        this.reason = reason;
    }
}

private class StrongScriptContextIndex {
    private final leftRoleBeforeBoundary:Array<Null<FontRole>>;
    private final rightRoleFromBoundary:Array<Null<FontRole>>;

    public function new(text:String) {
        leftRoleBeforeBoundary = [];
        rightRoleFromBoundary = [];
        var i = 0;
        while (i <= text.length) {
            leftRoleBeforeBoundary[i] = null;
            rightRoleFromBoundary[i] = null;
            i++;
        }
        var currentRole:Null<FontRole> = null;
        var scalarStart = 0;
        while (scalarStart < text.length) {
            final cp = ContextualDashEllipsisRoleResolver.codePointAtCompat(text, scalarStart);
            final scalarEnd = scalarStart + ContextualDashEllipsisRoleResolver.charCount(cp);
            currentRole = nextStrongScriptRole(cp, currentRole);
            var boundary = scalarStart + 1;
            while (boundary <= scalarEnd) {
                leftRoleBeforeBoundary[boundary] = currentRole;
                boundary++;
            }
            scalarStart = scalarEnd;
        }
        currentRole = null;
        var scalarEnd = text.length;
        while (scalarEnd > 0) {
            scalarStart = scalarStartBefore(text, scalarEnd);
            final cp = ContextualDashEllipsisRoleResolver.codePointAtCompat(text, scalarStart);
            currentRole = nextStrongScriptRole(cp, currentRole);
            var boundary = scalarStart;
            while (boundary < scalarEnd) {
                rightRoleFromBoundary[boundary] = currentRole;
                boundary++;
            }
            scalarEnd = scalarStart;
        }
    }

    public function leftOf(boundary:Int):Null<FontRole>
        return leftRoleBeforeBoundary[boundary];

    public function rightOf(boundary:Int):Null<FontRole>
        return rightRoleFromBoundary[boundary];

    private static function nextStrongScriptRole(codePoint:Int, currentRole:Null<FontRole>):Null<FontRole> {
        if (LineBreakFns.isMandatoryBreakCodePoint(codePoint))
            return null;
        final evidence = UnicodeScriptEvidenceClassifier.classify(codePoint);
        return switch (evidence) {
            case UnicodeScriptEvidence.EastAsian: FontRole.CjkPunctuation;
            case UnicodeScriptEvidence.Other: FontRole.LatinText;
            case UnicodeScriptEvidence.Neutral: currentRole;
        };
    }

    private static function scalarStartBefore(text:String, endExclusive:Int):Int {
        final lastIndex = endExclusive - 1;
        final last = text.charCodeAt(lastIndex);
        if (last >= 0xDC00 && last <= 0xDFFF && lastIndex > 0) {
            final before = text.charCodeAt(lastIndex - 1);
            if (before >= 0xD800 && before <= 0xDBFF)
                return lastIndex - 1;
        }
        return lastIndex;
    }
}
