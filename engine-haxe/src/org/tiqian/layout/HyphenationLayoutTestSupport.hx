package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.linebreak.Hyphenator;
import org.tiqian.linebreak.Hyphenator.NoHyphenator;

class HyphenationLayoutTestSupport {
    public static final TEXT:String = "中文internationalization中文";

    public static function layoutWith(h:Hyphenator, content:String, width:Float):LayoutResult {
        final text = content;
        final w = width;
        return new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, null,
            h).layout(new LayoutInput(new TiqianTextContent(text), null, new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(w)));
    }

    public static function pushOutResolver():ClreqProfileResolver
        return new PushOutResolver();

    public static function isLatin(s:String):Bool {
        for (i in 0...s.length) {
            final c = s.charCodeAt(i);
            if (!((c >= 97 && c <= 122) || (c >= 65 && c <= 90)))
                return false;
        }
        return true;
    }

    public static function rebuild(word:String, points:std.ReadOnlyArray<Int>):String {
        final parts:Array<String> = [];
        var prev = 0;
        for (i in 0...points.length) {
            final p = points[i];
            parts.push(word.substring(prev, p));
            prev = p;
        }
        parts.push(word.substring(prev));
        return parts.join("-");
    }
}

class PushOutResolver implements ClreqProfileResolver {
    public function new() {}

    public function resolve(id:LayoutProfileId):ClreqProfile {
        final p = ClreqProfile.MainlandHorizontal;
        return new ClreqProfile(p.id, p.strictness, p.region, p.punctuationGlyphPolicy, null, p.autoSpace, p.gluePlacement,
            new AdjustmentStylePolicy(p.adjustment.lineEndPunctuation, p.adjustment.allowInlineStopCompression, p.adjustment.allowSinoWesternGapAdjustment,
                LineAdjustmentStrategy.PushOutOnly),
            p.kinsokuMode, p.punctuationWidth);
    }
}
