package org.tiqian.protocol;

import org.tiqian.protocol.Plan;

/**
 * Plan JSON serialization (Stage1-P3). Serialises a built Plan into the wire
 * JSON the Kotlin producer emitted by hand (PreparedParagraph.kt
 * toPreparedParagraphJson) and the Rust reader parsed by hand (plan.rs).
 * Field order and omission rules mirror PreparedParagraph.kt:73-154 exactly.
 *
 * Two boring-emitter constraints shape the code: struct array indexing
 * returns Null<T>, so loops iterate for-each with an explicit first flag
 * instead of an index; and Null<T> fields are bound to a local before use
 * because the emitters do not narrow a struct field to non-null.
 */
class PlanJson {
    public static function encode(plan:Plan):String {
        final out:Array<String> = [];
        out.push("{");
        out.push("\"schema\":");
        out.push(Std.string(PlanSchema.PLAN_SCHEMA));
        out.push(",\"layoutRevision\":\"");
        out.push(PlanSchema.PLAN_LAYOUT_REVISION);
        out.push("\",\"width\":");
        out.push(PlanJsonNumber.ecmaJsonNumber(plan.width));
        out.push(",\"height\":");
        out.push(PlanJsonNumber.ecmaJsonNumber(plan.height));
        out.push(",\"lines\":[");
        var firstLine = true;
        for (line in plan.lines) {
            if (!firstLine)
                out.push(",");
            firstLine = false;
            appendLine(out, line);
        }
        out.push("]");
        appendSpacingCarrierAdvances(out, plan);
        appendParagraphEvidence(out, plan);
        out.push("}");
        return out.join("");
    }

    static function appendLine(out:Array<String>, line:Plan.PlanLine):Void {
        out.push("{\"rangeStart\":");
        out.push(Std.string(line.rangeStart));
        out.push(",\"rangeEnd\":");
        out.push(Std.string(line.rangeEnd));
        out.push(",\"top\":");
        out.push(PlanJsonNumber.ecmaJsonNumber(line.top));
        out.push(",\"bottom\":");
        out.push(PlanJsonNumber.ecmaJsonNumber(line.bottom));
        out.push(",\"baseline\":");
        out.push(PlanJsonNumber.ecmaJsonNumber(line.baseline));
        out.push(",\"indent\":");
        out.push(PlanJsonNumber.ecmaJsonNumber(line.indent));
        out.push(",\"visualWidth\":");
        out.push(PlanJsonNumber.ecmaJsonNumber(line.visualWidth));
        out.push(",\"hyphenAdvance\":");
        out.push(PlanJsonNumber.ecmaJsonNumber(line.hyphenAdvance));
        out.push(",\"endReason\":");
        PlanJsonNumber.appendJsonString(out, endReasonName(line.endReason));
        out.push(",\"cells\":[");
        var firstCell = true;
        for (cell in line.cells) {
            if (!firstCell)
                out.push(",");
            firstCell = false;
            appendCell(out, cell);
        }
        out.push("]}");
    }

    static function appendCell(out:Array<String>, cell:Plan.PlanCell):Void {
        out.push("{\"rangeStart\":");
        out.push(Std.string(cell.rangeStart));
        out.push(",\"rangeEnd\":");
        out.push(Std.string(cell.rangeEnd));
        out.push(",\"source\":");
        PlanJsonNumber.appendJsonString(out, cell.source);
        out.push(",\"display\":");
        PlanJsonNumber.appendJsonString(out, cell.display);
        out.push(",\"drawX\":");
        out.push(PlanJsonNumber.ecmaJsonNumber(cell.drawX));
        out.push(",\"naturalWidth\":");
        out.push(PlanJsonNumber.ecmaJsonNumber(cell.naturalWidth));
        out.push(",\"leadingLayoutAdvance\":");
        out.push(PlanJsonNumber.ecmaJsonNumber(cell.leadingLayoutAdvance));
        if (cell.shapingBoundary)
            out.push(",\"shapingBoundary\":true");
        if (cell.openTypeFeatures.length > 0) {
            out.push(",\"openTypeFeatures\":[");
            var firstFeature = true;
            for (feature in cell.openTypeFeatures) {
                if (!firstFeature)
                    out.push(",");
                firstFeature = false;
                PlanJsonNumber.appendJsonString(out, feature);
            }
            out.push("]");
        }
        appendCellEvidence(out, cell);
        out.push("}");
    }

    static function appendCellEvidence(out:Array<String>, cell:Plan.PlanCell):Void {
        final inlineObject = cell.inlineObject;
        if (inlineObject != null) {
            out.push(",\"inlineObject\":");
            out.push(PlanJsonNumber.ecmaJsonNumber((inlineObject : Float)));
        }
        final advance = cell.advance;
        if (advance != null) {
            out.push(",\"advance\":");
            out.push(PlanJsonNumber.ecmaJsonNumber((advance : Float)));
        }
        final renderFontFamily = cell.renderFontFamily;
        if (renderFontFamily != null) {
            out.push(",\"renderFontFamily\":");
            PlanJsonNumber.appendJsonString(out, (renderFontFamily : String));
        }
        final dashStrategy = cell.dashStrategy;
        if (dashStrategy != null) {
            out.push(",\"dashStrategy\":");
            PlanJsonNumber.appendJsonString(out, (dashStrategy : String));
            final shapingLanguage = cell.shapingLanguage;
            if (shapingLanguage != null) {
                out.push(",\"shapingLanguage\":");
                PlanJsonNumber.appendJsonString(out, (shapingLanguage : String));
            }
            final resolvedFace = cell.resolvedFace;
            if (resolvedFace != null) {
                out.push(",\"resolvedFace\":");
                PlanJsonNumber.appendJsonString(out, (resolvedFace : String));
            }
            final glyphIds = cell.glyphIds;
            if (glyphIds != null) {
                out.push(",\"glyphIds\":");
                PlanJsonNumber.appendJsonString(out, (glyphIds : String));
            }
            final shapingEvidence = cell.shapingEvidence;
            if (shapingEvidence != null) {
                out.push(",\"shapingEvidence\":");
                PlanJsonNumber.appendJsonString(out, (shapingEvidence : String));
            }
        }
        final punctuationInkFloor = cell.punctuationInkFloor;
        if (punctuationInkFloor != null) {
            out.push(",\"punctuationInkFloor\":");
            out.push(PlanJsonNumber.ecmaJsonNumber((punctuationInkFloor : Float)));
            final punctuationBodyWidth = cell.punctuationBodyWidth;
            if (punctuationBodyWidth != null) {
                out.push(",\"punctuationBodyWidth\":");
                out.push(PlanJsonNumber.ecmaJsonNumber((punctuationBodyWidth : Float)));
            }
        }
        if (cell.latin)
            out.push(",\"latin\":true");
        final styleDelta = cell.styleDelta;
        if (styleDelta != null)
            appendStyleDelta(out, styleDelta);
    }

    static function appendStyleDelta(out:Array<String>, style:PlanStyleDelta):Void {
        out.push(",\"style\":{");
        var fieldCount = 0;
        final fontSize = style.fontSize;
        if (fontSize != null) {
            out.push("\"fontSize\":");
            out.push(PlanJsonNumber.ecmaJsonNumber((fontSize : Float)));
            fieldCount++;
        }
        final fontWeight = style.fontWeight;
        if (fontWeight != null) {
            if (fieldCount > 0)
                out.push(",");
            out.push("\"fontWeight\":");
            out.push(Std.string((fontWeight : Int)));
            fieldCount++;
        }
        final italic = style.italic;
        if (italic != null) {
            if (fieldCount > 0)
                out.push(",");
            out.push("\"italic\":");
            out.push(italic ? "true" : "false");
        }
        out.push("}");
    }

    /** Rides both plain and evidence plans, ahead of every evidence-only field. */
    static function appendSpacingCarrierAdvances(out:Array<String>, plan:Plan):Void {
        if (plan.spacingCarrierAdvances.length > 0) {
            out.push(",\"spacingCarrierAdvances\":[");
            var firstCarrier = true;
            for (carrier in plan.spacingCarrierAdvances) {
                if (!firstCarrier)
                    out.push(",");
                firstCarrier = false;
                out.push("{\"rangeStart\":");
                out.push(Std.string(carrier.rangeStart));
                out.push(",\"rangeEnd\":");
                out.push(Std.string(carrier.rangeEnd));
                out.push(",\"advance\":");
                out.push(PlanJsonNumber.ecmaJsonNumber(carrier.advance));
                out.push("}");
            }
            out.push("]");
        }
    }

    static function appendParagraphEvidence(out:Array<String>, plan:Plan):Void {
        final fontSize = plan.fontSize;
        if (fontSize != null) {
            out.push(",\"fontSize\":");
            out.push(PlanJsonNumber.ecmaJsonNumber((fontSize : Float)));
        }
        final overlayWidth = plan.overlayWidth;
        if (overlayWidth != null) {
            out.push(",\"overlayWidth\":");
            out.push(PlanJsonNumber.ecmaJsonNumber((overlayWidth : Float)));
        }
        if (plan.emphasisRanges.length > 0) {
            out.push(",\"emphasisRanges\":[");
            var firstRange = true;
            for (range in plan.emphasisRanges) {
                if (!firstRange)
                    out.push(",");
                firstRange = false;
                out.push("[");
                out.push(Std.string(range.start));
                out.push(",");
                out.push(Std.string(range.end));
                out.push("]");
            }
            out.push("]");
        }
        if (plan.inlineEdges.length > 0) {
            out.push(",\"inlineEdges\":[");
            var firstEdge = true;
            for (edge in plan.inlineEdges) {
                if (!firstEdge)
                    out.push(",");
                firstEdge = false;
                out.push("{\"offset\":");
                out.push(Std.string(edge.offset));
                final inlineStart = edge.inlineStart;
                if (inlineStart != null) {
                    out.push(",\"inlineStart\":");
                    out.push(PlanJsonNumber.ecmaJsonNumber((inlineStart : Float)));
                }
                final inlineEnd = edge.inlineEnd;
                if (inlineEnd != null) {
                    out.push(",\"inlineEnd\":");
                    out.push(PlanJsonNumber.ecmaJsonNumber((inlineEnd : Float)));
                }
                out.push("}");
            }
            out.push("]");
        }
        if (plan.rubyDecisions.length > 0) {
            out.push(",\"rubyDecisions\":[");
            var firstRuby = true;
            for (ruby in plan.rubyDecisions) {
                if (!firstRuby)
                    out.push(",");
                firstRuby = false;
                out.push("{\"baseRangeStart\":");
                out.push(Std.string(ruby.baseRangeStart));
                out.push(",\"baseRangeEnd\":");
                out.push(Std.string(ruby.baseRangeEnd));
                out.push(",\"text\":");
                PlanJsonNumber.appendJsonString(out, ruby.text);
                out.push(",\"centerX\":");
                out.push(PlanJsonNumber.ecmaJsonNumber(ruby.centerX));
                out.push(",\"baselineY\":");
                out.push(PlanJsonNumber.ecmaJsonNumber(ruby.baselineY));
                out.push(",\"fontSize\":");
                out.push(PlanJsonNumber.ecmaJsonNumber(ruby.fontSize));
                final ascent = ruby.ascent;
                if (ascent != null) {
                    out.push(",\"ascent\":");
                    out.push(PlanJsonNumber.ecmaJsonNumber((ascent : Float)));
                }
                out.push(",\"fontWeight\":");
                out.push(Std.string(ruby.fontWeight));
                if (ruby.fontFamilies.length > 0) {
                    out.push(",\"fontFamilies\":[");
                    var firstFamily = true;
                    for (family in ruby.fontFamilies) {
                        if (!firstFamily)
                            out.push(",");
                        firstFamily = false;
                        PlanJsonNumber.appendJsonString(out, family);
                    }
                    out.push("]");
                }
                out.push("}");
            }
            out.push("]");
        }
        if (plan.bopomofoDecisions.length > 0) {
            out.push(",\"bopomofoDecisions\":[");
            var firstBopomofo = true;
            for (bopomofo in plan.bopomofoDecisions) {
                if (!firstBopomofo)
                    out.push(",");
                firstBopomofo = false;
                out.push("{\"baseRangeStart\":");
                out.push(Std.string(bopomofo.baseRangeStart));
                out.push(",\"baseRangeEnd\":");
                out.push(Std.string(bopomofo.baseRangeEnd));
                out.push(",\"text\":");
                PlanJsonNumber.appendJsonString(out, bopomofo.text);
                out.push(",\"fontWeight\":");
                out.push(Std.string(bopomofo.fontWeight));
                if (bopomofo.fontFamilies.length > 0) {
                    out.push(",\"fontFamilies\":[");
                    var firstFamily = true;
                    for (family in bopomofo.fontFamilies) {
                        if (!firstFamily)
                            out.push(",");
                        firstFamily = false;
                        PlanJsonNumber.appendJsonString(out, family);
                    }
                    out.push("]");
                }
                out.push(",\"placements\":[");
                var firstPlacement = true;
                for (placement in bopomofo.placements) {
                    if (!firstPlacement)
                        out.push(",");
                    firstPlacement = false;
                    out.push("{\"text\":");
                    PlanJsonNumber.appendJsonString(out, placement.text);
                    out.push(",\"left\":");
                    out.push(PlanJsonNumber.ecmaJsonNumber(placement.left));
                    out.push(",\"top\":");
                    out.push(PlanJsonNumber.ecmaJsonNumber(placement.top));
                    out.push(",\"width\":");
                    out.push(PlanJsonNumber.ecmaJsonNumber(placement.width));
                    out.push(",\"height\":");
                    out.push(PlanJsonNumber.ecmaJsonNumber(placement.height));
                    out.push(",\"role\":");
                    PlanJsonNumber.appendJsonString(out, placement.role);
                    out.push("}");
                }
                out.push("]}");
            }
            out.push("]");
        }
        if (plan.decorationSegments.length > 0) {
            out.push(",\"decorationSegments\":[");
            var firstSegment = true;
            for (seg in plan.decorationSegments) {
                if (!firstSegment)
                    out.push(",");
                firstSegment = false;
                out.push("{\"kind\":");
                PlanJsonNumber.appendJsonString(out, seg.kind);
                out.push(",\"left\":");
                out.push(PlanJsonNumber.ecmaJsonNumber(seg.left));
                out.push(",\"top\":");
                out.push(PlanJsonNumber.ecmaJsonNumber(seg.top));
                out.push(",\"right\":");
                out.push(PlanJsonNumber.ecmaJsonNumber(seg.right));
                out.push(",\"sourceRangeStart\":");
                out.push(Std.string(seg.sourceRangeStart));
                out.push(",\"sourceRangeEnd\":");
                out.push(Std.string(seg.sourceRangeEnd));
                out.push("}");
            }
            out.push("]");
        }
        if (plan.emphasisDots.length > 0) {
            out.push(",\"emphasisDots\":[");
            var firstDot = true;
            for (dot in plan.emphasisDots) {
                if (!firstDot)
                    out.push(",");
                firstDot = false;
                out.push("{\"clusterRangeStart\":");
                final clusterRangeStart = dot.clusterRangeStart;
                if (clusterRangeStart != null) {
                    out.push(PlanJsonNumber.ecmaJsonNumber((clusterRangeStart : Float)));
                } else {
                    out.push("null");
                }
                out.push(",\"anchorX\":");
                out.push(PlanJsonNumber.ecmaJsonNumber(dot.anchorX));
                out.push(",\"anchorY\":");
                out.push(PlanJsonNumber.ecmaJsonNumber(dot.anchorY));
                out.push(",\"dotDiameter\":");
                out.push(PlanJsonNumber.ecmaJsonNumber(dot.dotDiameter));
                out.push("}");
            }
            out.push("]");
        }
    }

    static function endReasonName(reason:PlanEndReason):String {
        return switch (reason) {
            case AutoWrap: "AutoWrap";
            case MandatoryBreak: "MandatoryBreak";
            case ParagraphEnd: "ParagraphEnd";
        };
    }
}