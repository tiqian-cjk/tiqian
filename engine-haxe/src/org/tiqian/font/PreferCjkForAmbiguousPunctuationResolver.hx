package org.tiqian.font;

import org.tiqian.font.FontPolicy.FallbackResolver;
import org.tiqian.font.FontPolicy.FontRequest;
import org.tiqian.font.FontPolicy.FontCandidate;
import org.tiqian.font.FontPolicy.FontDecision;

class PreferCjkForAmbiguousPunctuationResolver implements FallbackResolver {
    final cjkFontKey:String;
    final latinFontKey:String;
    final symbolFontKey:String;

    public function new(?cjkFontKey:Null<String>, ?latinFontKey:Null<String>, ?symbolFontKey:Null<String>) {
        this.cjkFontKey = cjkFontKey == null ? "cjk-primary" : cjkFontKey;
        this.latinFontKey = latinFontKey == null ? "latin-primary" : latinFontKey;
        this.symbolFontKey = symbolFontKey == null ? "symbol-fallback" : symbolFontKey;
    }

    public function resolve(text:String, range:org.tiqian.core.TextRange, request:FontRequest):FontDecision {
        final c = PreferCjkForAmbiguousPunctuationResolver.candidateFor(request, cjkFontKey, latinFontKey, symbolFontKey);
        return new FontDecision(range, c, request.role, "PreferCjkForAmbiguousPunctuationResolver:" + request.role);
    }

    static function candidateFor(request:FontRequest, cjkFontKey:String, latinFontKey:String, symbolFontKey:String):FontCandidate {
        final role = request.role;
        return switch (role) {
            case CjkText | CjkPunctuation: new FontCandidate(cjkFontKey, request.preferredFamilies.length == 0 ? cjkFontKey : request.preferredFamilies[0],
                    request.role);
            case LatinText: new FontCandidate(latinFontKey, latinFontKey, request.role);
            case Symbol | Emoji | Unknown: new FontCandidate(symbolFontKey, symbolFontKey, request.role);
        };
    }
}
