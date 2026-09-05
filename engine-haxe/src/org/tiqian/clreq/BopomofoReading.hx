package org.tiqian.clreq;

using std.Functional;

import std.ReadOnlyArray;

@:dataClass
class BopomofoReading {
    public final symbols:ReadOnlyArray<String>;
    public final tone:BopomofoTone;

    public function new(symbols:Array<String>, tone:BopomofoTone) {
        this.symbols = symbols;
        this.tone = tone;
    }

    public function copy():BopomofoReading {
        final copiedSymbols:Array<String> = [];
        var index:Int = 0;
        while (index < symbols.length) {
            copiedSymbols.push(symbols[index]);
            index += 1;
        }
        return new BopomofoReading(copiedSymbols, tone);
    }

    public function hashCode():Int {
        var hash:Int = 17;
        hash = hash * 31 + toneIndex();
        var index:Int = 0;
        while (index < symbols.length) {
            final symbol = symbols[index];
            var unitIndex:Int = 0;
            while (unitIndex < symbol.length) {
                hash = hash * 31 + symbol.charCodeAt(unitIndex);
                unitIndex += 1;
            }
            index += 1;
        }
        return hash;
    }

    private function toneIndex():Int {
        // The typer hoists a field subject into a temp block the Kotlin
        // target cannot lower; reading it into a local first keeps the
        // switch a plain variant switch.
        final value:BopomofoTone = tone;
        return switch (value) {
            case BopomofoTone.Yinping:
                0;
            case BopomofoTone.Yangping:
                1;
            case BopomofoTone.Shang:
                2;
            case BopomofoTone.Qu:
                3;
            case BopomofoTone.Neutral:
                4;
            case BopomofoTone.Ru:
                5;
        };
    }
}
