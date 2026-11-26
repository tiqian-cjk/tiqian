package org.tiqian.font;

import org.tiqian.core.TextRange;
import org.tiqian.font.CjkFontRoleClassifier;
import org.tiqian.font.FontRole;
import org.tiqian.font.FontRoleContext;
import org.tiqian.font.FontRoleContext.FontRoleClassifier;
import org.tiqian.layout.ContextualDashEllipsisRoleResolver.ContextualDashEllipsisRoles;
import org.tiqian.layout.QuotePairAnalyzer.QuotePairAwareFontRoleClassifier;

/**
    Role classification shared by the shaping and lowering paths: the CJK
    classifier wrapped with the quote-aware and contextual dash/ellipsis
    rules. The wrapper pair is memoized for the last text/locale input.
**/
class FontRoleClassification {
    static var memoKey:Null<String> = null;
    static var memo:Null<FontRoleClassifier> = null;

    public static function classify(text:String, range:TextRange, locale:String):FontRole {
        final context = new FontRoleContext(locale);
        return classifier(text, context).classify(text, range, context);
    }

    public static function classifyAll(text:String, ranges:Array<TextRange>, locale:String):Array<FontRole> {
        final context = new FontRoleContext(locale);
        final effective = classifier(text, context);
        final out:Array<FontRole> = [];
        for (range in ranges) out.push(effective.classify(text, range, context));
        return out;
    }

    static function classifier(text:String, context:FontRoleContext):FontRoleClassifier {
        final key = text + "\u0000" + context.locale;
        if (memoKey != key || memo == null) {
            memo = ContextualDashEllipsisRoles.withContextualDashEllipsisRoles(
                QuotePairAwareFontRoleClassifier.withContextualQuoteRoles(new CjkFontRoleClassifier(), text, context),
                text,
                context
            );
            memoKey = key;
        }
        return memo;
    }
}
