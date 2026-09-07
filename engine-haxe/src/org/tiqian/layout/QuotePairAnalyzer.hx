package org.tiqian.layout;

using std.Functional;

import org.tiqian.core.TextRange;
import org.tiqian.core.UnicodeScriptEvidence;
import org.tiqian.core.UnicodeScriptEvidenceClassifier;
import org.tiqian.core.UnicodeNumber;
import org.tiqian.core.UnicodeWordCharacter;
import org.tiqian.font.FontRole;
import org.tiqian.font.FontRoleContext;
import org.tiqian.font.FontRoleContext.FontRoleClassifier;
import std.SortedMap;

@:dataClass class QuotePair {
    public final openIndex:Int;
    public final closeIndex:Int;
    public final quoteType:QuoteType;

    public function new(openIndex:Int, closeIndex:Int, quoteType:QuoteType) {
        this.openIndex = openIndex;
        this.closeIndex = closeIndex;
        this.quoteType = quoteType;
    }
}

enum QuoteType {
    Double;
    Single;
}

@:dataClass class QuoteRoleDecision {
    public final index:Int;
    public final role:FontRole;
    public final source:String;
    public final reason:String;

    public function new(index:Int, role:FontRole, source:String, reason:String) {
        this.index = index;
        this.role = role;
        this.source = source;
        this.reason = reason;
    }
}

private typedef OpenQuoteEntry = {
    var index:Int;
    var type:QuoteType;
};

/** Finds structurally paired curly quotes and delegates their script role to ContextualQuoteRoleResolver. */
class QuotePairAnalyzer {
    public function new() {}

    public function analyze(text:String):Array<QuotePair> {
        final stack:Array<OpenQuoteEntry> = [];
        final pairs:Array<QuotePair> = [];
        var index = 0;
        while (index < text.length) {
            final c = text.charCodeAt(index);
            if (c == 0x201C) {
                stack.push({index: index, type: QuoteType.Double});
            } else if (c == 0x2018) {
                stack.push({index: index, type: QuoteType.Single});
            } else if (c == 0x201D) {
                if (stack.length > 0 && stack[stack.length - 1].type == QuoteType.Double) {
                    final match = stack.pop();
                    pairs.push(new QuotePair(match.index, index, QuoteType.Double));
                }
            } else if (c == 0x2019) {
                if (!QuotePairAnalyzer.isNonCjkInWordApostrophe(text, index)
                    && stack.length > 0
                    && stack[stack.length - 1].type == QuoteType.Single) {
                    final match = stack.pop();
                    pairs.push(new QuotePair(match.index, index, QuoteType.Single));
                }
            }
            index++;
        }
        return pairs;
    }

    public function classifyPairs(text:String, pairs:Array<QuotePair>, ?context:Null<FontRoleContext>):SortedMap<Int, FontRole> {
        return mapDecisions(classifyQuoteRoles(text, pairs, context));
    }

    /** Source-compatible entry point retained for callers of the first alpha. */
    public function classifyPairsWithClassifier(text:String, pairs:Array<QuotePair>, fontRoleClassifier:FontRoleClassifier,
            ?context:Null<FontRoleContext>):SortedMap<Int, FontRole> {
        return classifyPairs(text, pairs, context);
    }

    public function classifyQuoteRoles(text:String, pairs:Array<QuotePair>, ?context:Null<FontRoleContext>):Array<QuoteRoleDecision> {
        return new ContextualQuoteRoleResolver(text, pairs, context == null ? new FontRoleContext() : context).resolve();
    }

    /** Source-compatible counterpart to classifyPairs. */
    public function classifyQuoteRolesWithClassifier(text:String, pairs:Array<QuotePair>, fontRoleClassifier:FontRoleClassifier,
            ?context:Null<FontRoleContext>):Array<QuoteRoleDecision> {
        return classifyQuoteRoles(text, pairs, context);
    }

    static function mapDecisions(decisions:Array<QuoteRoleDecision>):SortedMap<Int, FontRole> {
        final out = SortedMap.builder();
        decisions.forEach(d -> out.put(d.index, d.role));
        return out.build();
    }

    public static function isNonCjkInWordApostrophe(text:String, index:Int):Bool {
        final before = codePointBefore(text, index);
        if (before == null)
            return false;
        final after = codePointAtOrNull(text, index + 1);
        if (after == null)
            return false;
        return isNonCjkWordCharacter(before)
            && isNonCjkWordCharacter(after)
            && (isNonCjkNonNumericWordCharacter(before) || isNonCjkNonNumericWordCharacter(after));
    }

    public static function isDigitBoundClosingQuote(text:String, index:Int):Bool
        return (text.charCodeAt(index) == 0x2019 || text.charCodeAt(index) == 0x201D)
            && codePointBefore(text, index) != null
            && UnicodeNumber.contains(codePointBefore(text, index));

    public static function isNonCjkWordInternalQuotePair(text:String, pair:QuotePair):Bool {
        final before = codePointBefore(text, pair.openIndex);
        final after = codePointAtOrNull(text, pair.closeIndex + 1);
        if (before == null || after == null || !isNonCjkNonNumericWordCharacter(before) || !isNonCjkNonNumericWordCharacter(after))
            return false;
        var index = pair.openIndex + 1;
        while (index < pair.closeIndex) {
            final cp = codePointAtOrNull(text, index);
            if (cp == null || !isNonCjkWordCharacter(cp))
                return false;
            index += cp > 0xFFFF ? 2 : 1;
        }
        return true;
    }

    static function isNonCjkWordCharacter(cp:Int):Bool
        return UnicodeWordCharacter.contains(cp) && UnicodeScriptEvidenceClassifier.classify(cp) != UnicodeScriptEvidence.EastAsian;

    static function isNonCjkNonNumericWordCharacter(cp:Int):Bool
        return isNonCjkWordCharacter(cp) && !UnicodeNumber.contains(cp) && !isFullwidthEastAsianWidth(cp);

    static function isFullwidthEastAsianWidth(cp:Int):Bool
        return cp == 0x3000 || (cp >= 0xFF01 && cp <= 0xFF60) || (cp >= 0xFFE0 && cp <= 0xFFE6);

    public static function codePointBefore(text:String, index:Int):Null<Int> {
        if (index <= 0)
            return null;
        final low = text.charCodeAt(index - 1);
        if ((low < 0xDC00 || low > 0xDFFF) || index < 2)
            return low;
        final high = text.charCodeAt(index - 2);
        if (high < 0xD800 || high > 0xDBFF)
            return low;
        return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
    }

    public static function codePointAtOrNull(text:String, index:Int):Null<Int> {
        if (index < 0 || index >= text.length)
            return null;
        final high = text.charCodeAt(index);
        if (high < 0xD800 || high > 0xDBFF || index + 1 >= text.length)
            return high;
        final low = text.charCodeAt(index + 1);
        if (low < 0xDC00 || low > 0xDFFF)
            return high;
        return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
    }
}

class QuotePairAwareFontRoleClassifier implements FontRoleClassifier {
    private final delegate:FontRoleClassifier;
    private final quoteRoles:SortedMap<Int, FontRole>;

    public function new(delegate:FontRoleClassifier, quoteRoles:SortedMap<Int, FontRole>) {
        this.delegate = delegate;
        this.quoteRoles = quoteRoles;
    }

    public function classify(text:String, range:TextRange, ?context:Null<FontRoleContext>):FontRole {
        final role = quoteRoles.get(range.start);
        return role == null ? delegate.classify(text, range, context) : role;
    }

    /** Resolves contextual curly-quote roles for callers classifying ranges from one paragraph. */
    public static function withContextualQuoteRoles(base:FontRoleClassifier, text:String, ?context:Null<FontRoleContext>):FontRoleClassifier {
        final analyzer = new QuotePairAnalyzer();
        final decisions = analyzer.classifyQuoteRoles(text, analyzer.analyze(text), context);
        if (decisions.length == 0)
            return base;
        final roles = SortedMap.builder();
        decisions.forEach(decision -> roles.put(decision.index, decision.role));
        return new QuotePairAwareFontRoleClassifier(base, roles.build());
    }
}
