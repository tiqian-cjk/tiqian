package org.tiqian.clreq;

class BopomofoParser {
    private static final NEUTRAL_MARK:Int = 0x02D9;
    private static final YANGPING_MARK:Int = 0x02CA;
    private static final SHANG_MARK:Int = 0x02C7;
    private static final QU_MARK:Int = 0x02CB;
    private static final YINPING_MACRON_MARK:Int = 0x02C9;

    public static function parse(reading:String):BopomofoReading {
        if (reading.length == 0) {
            return new BopomofoReading([], BopomofoTone.Yinping);
        }
        if (reading.charCodeAt(0) == NEUTRAL_MARK) {
            return new BopomofoReading(symbolsOf(reading.substring(1)), BopomofoTone.Neutral);
        }
        final last:Int = reading.charCodeAt(reading.length - 1);
        // Scalar-keyed branch: the Kotlin lowering only renders enum switches,
        // so the tone dispatch stays an if/else chain (features/15 permits a
        // chain on the discriminant).
        var tone:BopomofoTone = BopomofoTone.Yinping;
        if (last == YANGPING_MARK) {
            tone = BopomofoTone.Yangping;
        } else if (last == SHANG_MARK) {
            tone = BopomofoTone.Shang;
        } else if (last == QU_MARK) {
            tone = BopomofoTone.Qu;
        }
        final hasSuffixMark:Bool = last == YANGPING_MARK || last == SHANG_MARK || last == QU_MARK || last == YINPING_MACRON_MARK;
        final body:String = hasSuffixMark ? reading.substring(0, reading.length - 1) : reading;
        return new BopomofoReading(symbolsOf(body), tone);
    }

    private static function symbolsOf(body:String):Array<String> {
        final symbols:Array<String> = [];
        var index:Int = 0;
        while (index < body.length) {
            symbols.push(body.substring(index, index + 1));
            index += 1;
        }
        return symbols;
    }
}
