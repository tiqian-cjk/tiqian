package org.tiqian.layout;

import org.tiqian.core.LayoutResult;
import org.tiqian.core.*;
import org.tiqian.protocol.Plan;
import org.tiqian.protocol.PlanJson;
import org.tiqian.protocol.PlanJsonNumber;
import org.tiqian.protocol.PlanPacked;
import haxe.io.Bytes;


/** The structured plan-plus-diagnostics envelope (production form). */
typedef PlanWithDiagnostics = {
    var plan:Plan;
    var diagnostics:PlanDiagnostics;
}

typedef PlanDiagnostics = {
    var capabilityIssues:Array<PlanCapabilityIssue>;
    var advanceSuspects:Array<PlanAdvanceSuspect>;
}

typedef PlanCapabilityIssue = {
    var name:String;
    var reason:String;
    var rangeStart:Int;
    var rangeEnd:Int;
}

typedef PlanAdvanceSuspect = {
    var displayText:String;
    var advance:String;
    var reason:String;
    var rangeStart:Int;
    var rangeEnd:Int;
}

/** Prepared paragraph JSON serialization functions. */
class PreparedParagraphFns {
    public static function toPreparedParagraphJson(result:LayoutResult, renderEvidence:Bool = false):String {
        final plan = PlanLowering.toPlan(result, renderEvidence);
        return PlanJson.encode(plan);
    }

    public static function toPlanWithDiagnosticsJson(result:LayoutResult, renderEvidence:Bool, zeroAdvanceEpsilonPx:Float):String {
        final out:Array<String> = [];
        out.push("{\"plan\":");
        PlanJsonNumber.appendJsonString(out, toPreparedParagraphJson(result, renderEvidence));
        out.push(",\"diagnostics\":{\"capabilityIssues\":[");
        var first = true;
        final shapingDiagSrc = result.debug.shapingDecisions;
        for (di in 0...shapingDiagSrc.length) {
            final d = shapingDiagSrc[di];
            if (d.capabilityIssue != null) {
                if (!first)
                    out.push(",");
                first = false;
                out.push("{\"name\":");
                PlanJsonNumber.appendJsonString(out, d.capabilityIssue);
                out.push(",\"reason\":");
                PlanJsonNumber.appendJsonString(out, d.reason);
                out.push(",\"rangeStart\":");
                out.push(Std.string(d.range.start));
                out.push(",\"rangeEnd\":");
                out.push(Std.string(d.range.end));
                out.push("}");
            }
        }
        out.push("],\"advanceSuspects\":[");
        first = true;
        for (di in 0...shapingDiagSrc.length) {
            final d = shapingDiagSrc[di];
            if (!(Math.isFinite(d.advance) && d.advance > zeroAdvanceEpsilonPx)) {
                if (!first)
                    out.push(",");
                first = false;
                out.push("{\"displayText\":");
                PlanJsonNumber.appendJsonString(out, d.displayText);
                out.push(",\"advance\":\"");
                out.push(Math.isFinite(d.advance) ? PlanJsonNumber.ecmaJsonNumber(d.advance) : Std.string(d.advance));
                out.push("\",\"reason\":");
                PlanJsonNumber.appendJsonString(out, d.reason);
                out.push(",\"rangeStart\":");
                out.push(Std.string(d.range.start));
                out.push(",\"rangeEnd\":");
                out.push(Std.string(d.range.end));
                out.push("}");
            }
        }
        out.push("]}}");
        return out.join("");
    }

    public static function toPlanWithDiagnostics(result:LayoutResult, renderEvidence:Bool, zeroAdvanceEpsilonPx:Float):PlanWithDiagnostics {
        final plan = PlanLowering.toPlan(result, renderEvidence);
        final capabilityIssues:Array<PlanCapabilityIssue> = [];
        final advanceSuspects:Array<PlanAdvanceSuspect> = [];
        final shapingDiagSrc = result.debug.shapingDecisions;
        for (d in shapingDiagSrc) {
            final issue = d.capabilityIssue;
            if (issue != null) {
                capabilityIssues.push({
                    name: issue,
                    reason: d.reason,
                    rangeStart: d.range.start,
                    rangeEnd: d.range.end,
                });
            }
            if (!(Math.isFinite(d.advance) && d.advance > zeroAdvanceEpsilonPx)) {
                advanceSuspects.push({
                    displayText: d.displayText,
                    advance: Math.isFinite(d.advance) ? PlanJsonNumber.ecmaJsonNumber(d.advance) : Std.string(d.advance),
                    reason: d.reason,
                    rangeStart: d.range.start,
                    rangeEnd: d.range.end,
                });
            }
        }
        return {
            plan: plan,
            diagnostics: {
                capabilityIssues: capabilityIssues,
                advanceSuspects: advanceSuspects,
            },
        };
    }

    public static function toPackedPlanBytes(result:LayoutResult):Bytes {
        final plan = PlanLowering.toPlan(result, false);
        return PlanPacked.encode(plan);
    }

    /**
     * Top-level alias of PlanJsonNumber.ecmaJsonNumber in this package. The
     * handwritten engine published this helper from org.tiqian.layout; the
     * port kept the implementation in org.tiqian.protocol. The published
     * function was public but had no platform consumer (疑似内部细节).
     */
    @:topLevel
    public static function ecmaJsonNumber(floatValue:Float):String
        return PlanJsonNumber.ecmaJsonNumber(floatValue);
}