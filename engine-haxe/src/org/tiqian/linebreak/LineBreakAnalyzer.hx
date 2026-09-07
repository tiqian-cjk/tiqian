package org.tiqian.linebreak;

interface LineBreakAnalyzer {
    public function analyze(text:String):std.ReadOnlyArray<BreakOpportunity>;
}

class SimpleCharacterLineBreakAnalyzer implements LineBreakAnalyzer {
    public function new() {}

    public function analyze(text:String):std.ReadOnlyArray<BreakOpportunity> {
        final result = new Array<BreakOpportunity>();
        if (text.length == 0)
            return result;
        var index = 1;
        while (index <= text.length) {
            final prev = text.charCodeAt(index - 1);
            final mandatory = LineBreakFns.isMandatoryBreakCodePoint(prev)
                && !(prev == 0x000D && index < text.length && text.charCodeAt(index) == 0x000A);
            result.push(new BreakOpportunity(index, index == text.length || mandatory ? BreakKind.Required : BreakKind.Allowed,
                mandatory ? "MandatoryBreak" : "SimpleCharacterLineBreakAnalyzer"));
            index += 1;
        }
        return result;
    }
}
