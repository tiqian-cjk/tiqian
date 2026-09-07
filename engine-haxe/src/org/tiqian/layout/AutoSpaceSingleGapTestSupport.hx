package org.tiqian.layout;

import org.tiqian.clreq.AutoSpaceMode;
import org.tiqian.clreq.AutoSpacePolicy;
import org.tiqian.clreq.ClreqProfile;
import org.tiqian.clreq.ClreqProfileResolver;
import org.tiqian.core.Ic;
import org.tiqian.core.LayoutConstraints;
import org.tiqian.core.LayoutInput;
import org.tiqian.core.LayoutResult;
import org.tiqian.core.ParagraphStyle;
import org.tiqian.core.TextSpan;
import org.tiqian.core.TextRange;
import org.tiqian.core.AutoSpaceDecisionInfo;
import std.ReadOnlyArray;
import org.tiqian.core.TiqianTextContent;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;

class AutoSpaceSingleGapTestSupport {
    public static function renderAutoSpaceDecisions(list:ReadOnlyArray<AutoSpaceDecisionInfo>):String {
        final parts:Array<String> = [];
        for (i in 0...list.length) {
            final d = list[i];
            parts.push("AutoSpaceDecisionInfo(clusterRange=TextRange(start=" + d.clusterRange.start + ", end=" + d.clusterRange.end + "), side=" + d.side
                + ", boundaryRole=" + d.boundaryRole + ", mode=" + d.mode + ", charactersAffected=" + d.charactersAffected + ", reductionPerChar="
                + d.reductionPerChar + ", totalReduction=" + d.totalReduction + ", reason=" + d.reason + ")");
        }
        return "[" + parts.join(", ") + "]";
    }

    public static function layout(text:String, spans:Array<TextSpan>):LayoutResult {
        return new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent(text, spans), null,
            new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(320.0)));
    }

    public static function letterDigit():LayoutResult {
        final engine = new ExplainableStubParagraphLayoutEngine(null, null, new AutoSpaceLetterDigitResolver(), null, null, null, null, null, null, null,
            null, null, null);
        return engine.layout(new LayoutInput(new TiqianTextContent("甲A乙9丙"), null, new ParagraphStyle(null, null, null, Ic.Zero),
            new LayoutConstraints(320.0)));
    }

    public static function sameRange(first:TextRange, second:TextRange):Bool {
        return first.start == second.start && first.end == second.end;
    }

    public static function clustersWithText(result:LayoutResult, text:String):Array<org.tiqian.core.Cluster> {
        final matches = [];
        for (i in 0...result.clusters.length)
            if (result.clusters[i].text == text)
                matches.push(result.clusters[i]);
        return matches;
    }
}

class AutoSpaceLetterDigitResolver implements ClreqProfileResolver {
    public function new() {}

    public function resolve(profileId:org.tiqian.core.LayoutProfileId):ClreqProfile {
        final base = ClreqProfile.MainlandHorizontal;
        return new ClreqProfile(base.id, base.strictness, base.region, base.punctuationGlyphPolicy, null,
            new AutoSpacePolicy(AutoSpaceMode.Insert, AutoSpaceMode.Disabled), base.gluePlacement, base.adjustment, base.kinsokuMode, base.punctuationWidth);
    }
}
