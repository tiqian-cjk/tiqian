package org.tiqian.layout;

import std.StringBuf;
import std.SortedMap;
import org.tiqian.core.LayoutResult;
import org.tiqian.core.*;
import org.tiqian.font.FontRole;

typedef PreparedParagraphDigitsAndExponent = {digits:String, exponent:Int};
typedef PreparedParagraphDecomposed = {mantissa:String, exp2:Int};
typedef PreparedParagraphF32Decomposed = {mant24:Int, exp2:Int};

/** Prepared paragraph JSON serialization functions. */
class PreparedParagraphFns {
    private static var fivePowersBuilder = null;
    private static var fivePowers:std.SortedMap<Int, String> = null;
    private static var twoPowersBuilder = null;
    private static var twoPowers:std.SortedMap<Int, String> = null;

    public static function toPreparedParagraphJson(result:LayoutResult, renderEvidence:Bool = false):String {
        final naturalB = SortedMap.builder();
        final featuresB = SortedMap.builder();
        final fontsB = SortedMap.builder();
        final glyphIdsB = SortedMap.builder();
        for (ri in 0...result.glyphRuns.length) {
            final run = result.glyphRuns[ri];
            for (gi in 0...run.glyphs.length) {
                final glyph = run.glyphs[gi];
                final k = rangeKey(glyph.clusterRange);
                final naturalPrior = naturalB.get(k);
                naturalB.put(k, (naturalPrior == null ? 0.0 : naturalPrior) + glyph.advance);
                if (run.openTypeFeatures.length > 0) {
                    var fs = featuresB.get(k);
                    if (fs == null)
                        fs = [];
                    for (fi in 0...run.openTypeFeatures.length) {
                        final f = run.openTypeFeatures[fi];
                        if (fs.indexOf(f) < 0)
                            fs.push(f);
                    }
                    featuresB.put(k, fs);
                }
                if (glyph.renderFontKey != null)
                    fontsB.put(k, glyph.renderFontKey);
                var ids = glyphIdsB.get(k);
                if (ids == null)
                    ids = [];
                ids.push(Std.string(glyph.id));
                glyphIdsB.put(k, ids);
            }
        }
        final zeroB = SortedMap.builder();
        final zeroSrc = result.debug.zeroWidthBreakDecisions;
        for (zi in 0...zeroSrc.length)
            zeroB.put(rangeKey(zeroSrc[zi].range), true);
        final shapingB = SortedMap.builder();
        final shapingSrc = result.debug.shapingDecisions;
        for (zi in 0...shapingSrc.length)
            shapingB.put(rangeKey(shapingSrc[zi].range), shapingSrc[zi]);
        final punctB = SortedMap.builder();
        final punctSrc = result.debug.punctuationDecisions;
        for (zi in 0...punctSrc.length)
            punctB.put(rangeKey(punctSrc[zi].range), punctSrc[zi]);
        final inlineAdvanceB = SortedMap.builder();
        final inlineObjSrc = result.input.inlineObjects;
        for (zi in 0...inlineObjSrc.length)
            inlineAdvanceB.put(rangeKey(inlineObjSrc[zi].range), inlineObjSrc[zi].advance);
        final edgeStartB = SortedMap.builder();
        final edgeEndB = SortedMap.builder();
        final boxSrc = result.input.inlineBoxes;
        for (bi in 0...boxSrc.length) {
            final b = boxSrc[bi];
            if (b.inlineStart != 0) {
                final sk = Std.string(b.range.start);
                final startPrior = edgeStartB.get(sk);
                edgeStartB.put(sk, (startPrior == null ? 0.0 : startPrior) + b.inlineStart);
            }
            if (b.inlineEnd != 0) {
                final ek = Std.string(b.range.end);
                final endPrior = edgeEndB.get(ek);
                edgeEndB.put(ek, (endPrior == null ? 0.0 : endPrior) + b.inlineEnd);
            }
        }
        final natural = naturalB.build();
        final features = featuresB.build();
        final fonts = fontsB.build();
        final glyphIds = glyphIdsB.build();
        final zero = zeroB.build();
        final shaping = shapingB.build();
        final punct = punctB.build();
        final inlineAdvance = inlineAdvanceB.build();
        final edgeStart = edgeStartB.build();
        final edgeEnd = edgeEndB.build();
        final out = new StringBuf();
        out.add("{");
        out.add("\"schema\":1,\"layoutRevision\":\"tiqian-layout-v2\",\"width\":");
        out.add(ecmaJsonNumber(result.input.constraints.maxWidth));
        out.add(",\"height\":");
        out.add(ecmaJsonNumber(result.size.height));
        out.add(",\"lines\":[");
        for (li in 0...result.lines.length) {
            if (li > 0)
                out.add(",");
            final line = result.lines[li];
            out.add("{\"rangeStart\":");
            out.add(Std.string(line.range.start));
            out.add(",\"rangeEnd\":");
            out.add(Std.string(line.range.end));
            out.add(",\"top\":");
            out.add(ecmaJsonNumber(line.top));
            out.add(",\"bottom\":");
            out.add(ecmaJsonNumber(line.bottom));
            out.add(",\"baseline\":");
            out.add(ecmaJsonNumber(line.baseline));
            out.add(",\"indent\":");
            out.add(ecmaJsonNumber(line.indent));
            out.add(",\"visualWidth\":");
            out.add(ecmaJsonNumber(line.visualWidth));
            out.add(",\"hyphenAdvance\":");
            out.add(ecmaJsonNumber(line.hyphenAdvance));
            out.add(",\"endReason\":");
            appendJsonString(out, Type.enumConstructor(line.endReason));
            out.add(",\"cells\":[");
            var ci = 0;
            for (p in LayoutQueries.positionedClustersForLine(result, line)) {
                final c = result.clusters[p.clusterIndex];
                final ck = rangeKey(c.range);
                if (!(c.displayText.length > 0 || zero.has(ck) || (renderEvidence && inlineAdvance.has(ck))))
                    continue;
                if (ci++ > 0)
                    out.add(",");
                out.add("{\"rangeStart\":");
                out.add(Std.string(c.range.start));
                out.add(",\"rangeEnd\":");
                out.add(Std.string(c.range.end));
                out.add(",\"source\":");
                appendJsonString(out, c.text);
                out.add(",\"display\":");
                appendJsonString(out, c.displayText);
                out.add(",\"drawX\":");
                out.add(ecmaJsonNumber(p.drawX));
                out.add(",\"naturalWidth\":");
                out.add(ecmaJsonNumber(natural.has(ck) ? natural.get(ck) : c.advance));
                out.add(",\"leadingLayoutAdvance\":");
                out.add(ecmaJsonNumber(c.leadingLayoutAdvance));
                if (c.range.end - c.range.start > 1)
                    out.add(",\"shapingBoundary\":true");
                if (features.has(ck)) {
                    out.add(",\"openTypeFeatures\":[");
                    var fi = 0;
                    for (f in features.get(ck)) {
                        if (fi++ > 0)
                            out.add(",");
                        appendJsonString(out, f);
                    }
                    out.add("]");
                }
                if (renderEvidence)
                    appendCellEvidence(out, result, c, natural, fonts, glyphIds, shaping, punct, inlineAdvance);
                out.add("}");
            }
            out.add("]}");
        }
        out.add("]");
        if (renderEvidence)
            appendParagraphEvidence(out, result, edgeStart, edgeEnd);
        out.add("}");
        return out.toString();
    }

    public static function toPlanWithDiagnosticsJson(result:LayoutResult, renderEvidence:Bool, zeroAdvanceEpsilonPx:Float):String {
        final out = new StringBuf();
        out.add("{\"plan\":");
        appendJsonString(out, toPreparedParagraphJson(result, renderEvidence));
        out.add(",\"diagnostics\":{\"capabilityIssues\":[");
        var first = true;
        final shapingDiagSrc = result.debug.shapingDecisions;
        for (di in 0...shapingDiagSrc.length) {
            final d = shapingDiagSrc[di];
            if (d.capabilityIssue != null) {
                if (!first)
                    out.add(",");
                first = false;
                out.add("{\"name\":");
                appendJsonString(out, d.capabilityIssue);
                out.add(",\"reason\":");
                appendJsonString(out, d.reason);
                out.add(",\"rangeStart\":");
                out.add(Std.string(d.range.start));
                out.add(",\"rangeEnd\":");
                out.add(Std.string(d.range.end));
                out.add("}");
            }
        }
        out.add("],\"advanceSuspects\":[");
        first = true;
        for (di in 0...shapingDiagSrc.length) {
            final d = shapingDiagSrc[di];
            if (!(Math.isFinite(d.advance) && d.advance > zeroAdvanceEpsilonPx)) {
                if (!first)
                    out.add(",");
                first = false;
                out.add("{\"displayText\":");
                appendJsonString(out, d.displayText);
                out.add(",\"advance\":\"");
                out.add(Math.isFinite(d.advance) ? ecmaJsonNumber(d.advance) : Std.string(d.advance));
                out.add("\",\"reason\":");
                appendJsonString(out, d.reason);
                out.add(",\"rangeStart\":");
                out.add(Std.string(d.range.start));
                out.add(",\"rangeEnd\":");
                out.add(Std.string(d.range.end));
                out.add("}");
            }
        }
        out.add("]}}");
        return out.toString();
    }

    private static function rangeKey(r:TextRange):String
        return Std.string(r.start) + ":" + Std.string(r.end);

    private static function appendJsonString(out:StringBuf, value:String):Void {
        out.add("\"");
        for (i in 0...value.length) {
            final c = value.charCodeAt(i);
            if (c == 34)
                out.add("\\\"");
            else if (c == 92)
                out.add("\\\\");
            else if (c == 8)
                out.add("\\b");
            else if (c == 12)
                out.add("\\f");
            else if (c == 10)
                out.add("\\n");
            else if (c == 13)
                out.add("\\r");
            else if (c == 9)
                out.add("\\t");
            else if (c < 32)
                out.add("\\u" + StringTools.hex(c, 4).toLowerCase());
            else
                out.addChar(c);
        }
        out.add("\"");
    }

    private static function appendCellEvidence(out:StringBuf, result:LayoutResult, c:Cluster, natural:SortedMap<String, Float>,
            fonts:SortedMap<String, String>, ids:SortedMap<String, Array<String>>, shaping:SortedMap<String, ShapingDecisionInfo>,
            punct:SortedMap<String, PunctuationDecisionInfo>, inlineAdvance:SortedMap<String, Float>):Void {
        final k = rangeKey(c.range);
        if (inlineAdvance.has(k)) {
            out.add(",\"inlineObject\":");
            out.add(ecmaJsonNumber(inlineAdvance.get(k)));
        }
        final width = inlineAdvance.has(k) ? inlineAdvance.get(k) : (natural.has(k) ? natural.get(k) : c.advance);
        if (c.advance != width) {
            out.add(",\"advance\":");
            out.add(ecmaJsonNumber(c.advance));
        }
        if (fonts.has(k)) {
            out.add(",\"renderFontFamily\":");
            appendJsonString(out, fonts.get(k));
        }
        final sd = shaping.get(k);
        if (sd != null && sd.strategy != null) {
            out.add(",\"dashStrategy\":");
            appendJsonString(out, sd.strategy);
            if (sd.language != null) {
                out.add(",\"shapingLanguage\":");
                appendJsonString(out, sd.language);
            }
            if (sd.resolvedFace != null) {
                out.add(",\"resolvedFace\":");
                appendJsonString(out, sd.resolvedFace);
            }
            if (ids.has(k) && ids.get(k).length > 0) {
                out.add(",\"glyphIds\":");
                appendJsonString(out, ids.get(k).join(","));
            }
            out.add(",\"shapingEvidence\":");
            appendJsonString(out, sd.reason);
        }
        final pd = punct.get(k);
        if (pd != null && pd.inkContainmentApplied && pd.inkContainmentBodyFloor != null) {
            out.add(",\"punctuationInkFloor\":");
            out.add(ecmaJsonNumber(pd.inkContainmentBodyFloor));
            out.add(",\"punctuationBodyWidth\":");
            out.add(ecmaJsonNumber(pd.bodyWidth));
        }
        var latin = false;
        {
            final fdSrc = result.debug.fontDecisions;
            for (fi in 0...fdSrc.length) {
                final fd = fdSrc[fi];
                if (c.range.start >= fd.range.start && c.range.end <= fd.range.end && fd.role == Type.enumConstructor(FontRole.LatinText))
                    latin = true;
            }
        }
        if (latin)
            out.add(",\"latin\":true");
        final style = styleAt(result, c.range.start);
        if (style != result.input.textStyle) {
            out.add(",\"style\":{");
            var n = 0;
            if (style.fontSize != result.input.textStyle.fontSize) {
                out.add("\"fontSize\":");
                out.add(ecmaJsonNumber(style.fontSize));
                n++;
            }
            if (style.fontWeight != result.input.textStyle.fontWeight) {
                if (n++ > 0)
                    out.add(",");
                out.add("\"fontWeight\":");
                out.add(Std.string(style.fontWeight));
            }
            if (style.italic != result.input.textStyle.italic) {
                if (n++ > 0)
                    out.add(",");
                out.add("\"italic\":");
                out.add(style.italic ? "true" : "false");
            }
            out.add("}");
        }
    }

    private static function styleAt(result:LayoutResult, offset:Int):TextStyle {
        var found:Null<TextStyle> = null;
        {
            final spanSrc = result.input.content.spans;
            for (si in 0...spanSrc.length) {
                final span = spanSrc[si];
                if (offset >= span.range.start && offset < span.range.end)
                    found = span.style;
            }
        }
        return found == null ? result.input.textStyle : found;
    }

    private static function appendParagraphEvidence(out:StringBuf, result:LayoutResult, starts:SortedMap<String, Float>, ends:SortedMap<String, Float>):Void {
        out.add(",\"fontSize\":");
        out.add(ecmaJsonNumber(result.input.textStyle.fontSize));
        out.add(",\"overlayWidth\":");
        out.add(ecmaJsonNumber(result.size.width));
        var emph:Array<DecorationSpan> = [];
        {
            final decSrc = result.input.decorations;
            for (di in 0...decSrc.length) {
                final d = decSrc[di];
                if (d.kind == DecorationKind.Emphasis)
                    emph.push(d);
            }
        }
        if (emph.length > 0) {
            out.add(",\"emphasisRanges\":[");
            for (i in 0...emph.length) {
                if (i > 0)
                    out.add(",");
                out.add("[");
                out.add(Std.string(emph[i].range.start));
                out.add(",");
                out.add(Std.string(emph[i].range.end));
                out.add("]");
            }
            out.add("]");
        }
        var offsets:Array<Int> = [];
        for (oi in 0...starts.size())
            offsets.push(Std.parseInt(starts.keyAt(oi)));
        for (ei in 0...ends.size()) {
            final ev = Std.parseInt(ends.keyAt(ei));
            if (offsets.indexOf(ev) < 0)
                offsets.push(ev);
        }
        var oi = 1;
        while (oi < offsets.length) {
            var ov = offsets[oi];
            var oj = oi - 1;
            while (oj >= 0 && offsets[oj] > ov) {
                offsets[oj + 1] = offsets[oj];
                oj--;
            }
            offsets[oj + 1] = ov;
            oi++;
        }
        if (offsets.length > 0) {
            out.add(",\"inlineEdges\":[");
            for (i in 0...offsets.length) {
                if (i > 0)
                    out.add(",");
                var k = Std.string(offsets[i]);
                out.add("{\"offset\":");
                out.add(Std.string(offsets[i]));
                if (starts.has(k)) {
                    out.add(",\"inlineStart\":");
                    out.add(ecmaJsonNumber(starts.get(k)));
                }
                if (ends.has(k)) {
                    out.add(",\"inlineEnd\":");
                    out.add(ecmaJsonNumber(ends.get(k)));
                }
                out.add("}");
            }
            out.add("]");
        }
        if (result.debug.rubyDecisions.length > 0) {
            out.add(",\"rubyDecisions\":[");
            for (i in 0...result.debug.rubyDecisions.length) {
                if (i > 0)
                    out.add(",");
                var r = result.debug.rubyDecisions[i];
                out.add("{\"baseRangeStart\":");
                out.add(Std.string(r.baseRange.start));
                out.add(",\"baseRangeEnd\":");
                out.add(Std.string(r.baseRange.end));
                out.add(",\"text\":");
                appendJsonString(out, r.text);
                out.add(",\"centerX\":");
                out.add(ecmaJsonNumber(r.centerX));
                out.add(",\"baselineY\":");
                out.add(ecmaJsonNumber(r.baselineY));
                out.add(",\"fontSize\":");
                out.add(ecmaJsonNumber(r.fontSize));
                out.add(",\"ascent\":");
                out.add(ecmaJsonNumber(r.ascent));
                out.add(",\"fontWeight\":");
                out.add(Std.string(r.fontWeight));
                if (r.fontFamilies.length > 0) {
                    out.add(",\"fontFamilies\":[");
                    for (j in 0...r.fontFamilies.length) {
                        if (j > 0)
                            out.add(",");
                        appendJsonString(out, r.fontFamilies[j]);
                    }
                    out.add("]");
                }
                out.add("}");
            }
            out.add("]");
        }
        appendRemainingParagraphEvidence(out, result);
    }

    private static function appendRemainingParagraphEvidence(out:StringBuf, result:LayoutResult):Void {
        if (result.debug.bopomofoDecisions.length > 0) {
            out.add(",\"bopomofoDecisions\":[");
            for (i in 0...result.debug.bopomofoDecisions.length) {
                if (i > 0)
                    out.add(",");
                var z = result.debug.bopomofoDecisions[i];
                out.add("{\"baseRangeStart\":");
                out.add(Std.string(z.baseRange.start));
                out.add(",\"baseRangeEnd\":");
                out.add(Std.string(z.baseRange.end));
                out.add(",\"text\":");
                appendJsonString(out, z.text);
                out.add(",\"fontWeight\":");
                out.add(Std.string(z.fontWeight));
                if (z.fontFamilies.length > 0) {
                    out.add(",\"fontFamilies\":[");
                    for (j in 0...z.fontFamilies.length) {
                        if (j > 0)
                            out.add(",");
                        appendJsonString(out, z.fontFamilies[j]);
                    }
                    out.add("]");
                }
                out.add(",\"placements\":[");
                for (j in 0...z.placements.length) {
                    if (j > 0)
                        out.add(",");
                    var p = z.placements[j];
                    out.add("{\"text\":");
                    appendJsonString(out, p.text);
                    out.add(",\"left\":");
                    out.add(ecmaJsonNumber(p.left));
                    out.add(",\"top\":");
                    out.add(ecmaJsonNumber(p.top));
                    out.add(",\"width\":");
                    out.add(ecmaJsonNumber(p.width));
                    out.add(",\"height\":");
                    out.add(ecmaJsonNumber(p.height));
                    out.add(",\"role\":");
                    appendJsonString(out, Type.enumConstructor(p.role));
                    out.add("}");
                }
                out.add("]}");
            }
            out.add("]");
        }
        var segs:Array<DecorationSegmentInfo> = [];
        {
            final segSrc = result.debug.decorationSegments;
            for (si in 0...segSrc.length) {
                final s = segSrc[si];
                if (s.kind == Type.enumConstructor(DecorationKind.ProperNoun) || s.kind == Type.enumConstructor(DecorationKind.BookTitle))
                    segs.push(s);
            }
        }
        if (segs.length > 0) {
            out.add(",\"decorationSegments\":[");
            for (i in 0...segs.length) {
                if (i > 0)
                    out.add(",");
                var s = segs[i];
                out.add("{\"kind\":");
                appendJsonString(out, s.kind);
                out.add(",\"left\":");
                out.add(ecmaJsonNumber(s.left));
                out.add(",\"top\":");
                out.add(ecmaJsonNumber(s.top));
                out.add(",\"right\":");
                out.add(ecmaJsonNumber(s.right));
                out.add(",\"sourceRangeStart\":");
                out.add(Std.string(s.sourceRange.start));
                out.add(",\"sourceRangeEnd\":");
                out.add(Std.string(s.sourceRange.end));
                out.add("}");
            }
            out.add("]");
        }
        var dots:Array<DecorationDecisionInfo> = [];
        {
            final dotSrc = result.debug.decorationDecisions;
            for (di in 0...dotSrc.length) {
                final d = dotSrc[di];
                if (d.applied && d.kind == Type.enumConstructor(DecorationKind.Emphasis) && d.dotDiameter > 0)
                    dots.push(d);
            }
        }
        if (dots.length > 0) {
            out.add(",\"emphasisDots\":[");
            for (i in 0...dots.length) {
                if (i > 0)
                    out.add(",");
                var d = dots[i];
                out.add("{\"clusterRangeStart\":");
                out.add(Std.string(d.clusterRange.start));
                out.add(",\"anchorX\":");
                out.add(ecmaJsonNumber(d.anchorX));
                out.add(",\"anchorY\":");
                out.add(ecmaJsonNumber(d.anchorY));
                out.add(",\"dotDiameter\":");
                out.add(ecmaJsonNumber(d.dotDiameter));
                out.add("}");
            }
            out.add("]");
        }
    }

    public static function ecmaJsonNumber(floatValue:Float):String {
        if (Math.isNaN(floatValue))
            return "NaN";
        if (Math.isFinite(floatValue) == false)
            return floatValue < 0 ? "-Infinity" : "Infinity";
        if (floatValue == 0)
            return "0";
        final negative = floatValue < 0;
        final magnitudeValue = negative ? -floatValue : floatValue;
        final shortest = shortestRoundTripDigits(magnitudeValue);
        final digits = canonicalFloatDigits(magnitudeValue, shortest.digits);
        final k = digits.length;
        final n = shortest.exponent;
        final sign = negative ? "-" : "";
        if (k <= n && n <= 21)
            return sign + digits + zeros(n - k);
        if (0 < n && n <= 21)
            return sign + digits.substr(0, n) + "." + digits.substr(n);
        if (-6 < n && n <= 0)
            return sign + "0." + zeros(-n) + digits;
        final mantissa = k > 1 ? digits.substr(0, 1) + "." + digits.substr(1) : digits;
        final ev = n - 1;
        final esign = ev < 0 ? "-" : "+";
        final absoluteExponent:Int = ev < 0 ? -ev : ev;
        return sign + mantissa + "e" + esign + Std.string(absoluteExponent);
    }

    public static function shortestRoundTripDigits(magnitude:Float):PreparedParagraphDigitsAndExponent {
        final d = decompose(magnitude);
        final f = d.exp2;
        final expansion = dyadicDecimal(d.mantissa, f);
        final exact = trimZeros(expansion.digits);
        final n = expansion.exponent;
        // The Haxe Float is an f32 value widened to the runtime double. Build
        // that exact 53-bit (or normalized subnormal) mantissa as decimal
        // digits; it cannot be held in a signed Int.
        final base = d.mantissa;
        final doubled = timesSmall(base, 2);
        final hi = dyadicDecimalString(addDecimal(doubled, "1"), d.exp2 - 1);
        var lo:PreparedParagraphDigitsAndExponent;
        if (base == "4503599627370496") {
            lo = dyadicDecimalString(decrementDecimal(timesSmall(base, 4)), d.exp2 - 2);
        } else {
            lo = dyadicDecimalString(decrementDecimal(doubled), d.exp2 - 1);
        }
        final inclusive = (base.charCodeAt(base.length - 1) - 48) % 2 == 0;
        var length = 1;
        while (length <= 17) {
            final keep = exact.substr(0, length);
            final up = incrementDecimal(keep);
            final upN = n + up.length - length;
            if (inInterval(keep, n, lo, hi, inclusive) || inInterval(up, upN, lo, hi, inclusive)) {
                final rounded = roundToSignificant(exact, length);
                return {digits: rounded.digits, exponent: n + rounded.exponent};
            }
            length += 1;
        }
        return {digits: exact, exponent: n};
    }

    private static function inInterval(digits:String, n:Int, lo:PreparedParagraphDigitsAndExponent, hi:PreparedParagraphDigitsAndExponent,
            inclusive:Bool):Bool {
        final low = compareDecimal(digits, n, lo.digits, lo.exponent);
        final high = compareDecimal(digits, n, hi.digits, hi.exponent);
        return (low > 0 || (low == 0 && inclusive)) && (high < 0 || (high == 0 && inclusive));
    }

    private static function canonicalFloatDigits(magnitude:Float, doubleDigits:String):String {
        final d = decomposeF32(magnitude);
        final exact = d.mant24 == 0 ? "0" : (d.exp2 >= 0 ? timesLong(twoToThe(d.exp2), d.mant24) : timesLong(fiveToThe(-d.exp2), d.mant24));
        final stripped = trimZeros(exact);
        if (stripped.length <= doubleDigits.length)
            return doubleDigits;
        final rounded = roundToSignificant(stripped, doubleDigits.length);
        return rounded.digits.length == doubleDigits.length ? rounded.digits : doubleDigits;
    }

    private static function dyadicDecimal(p:String, f:Int):PreparedParagraphDigitsAndExponent {
        return dyadicDecimalString(p, f);
    }

    private static function dyadicDecimalString(p:String, f:Int):PreparedParagraphDigitsAndExponent {
        final digits = f < 0 ? multiplyDecimal(fiveToThe(-f), p) : multiplyDecimal(twoToThe(f), p);
        return {digits: digits, exponent: f < 0 ? digits.length + f : digits.length};
    }

    private static function multiplyDecimal(a:String, b:String):String {
        var result = "0";
        var shift = 0;
        var i = b.length - 1;
        while (i >= 0) {
            final digit = b.charCodeAt(i) - 48;
            if (digit != 0) {
                var part = timesSmall(a, digit);
                if (shift > 0)
                    part += zeros(shift);
                result = addDecimal(result, part);
            }
            shift++;
            i--;
        }
        return result;
    }

    private static function fiveToThe(k:Int):String {
        if (fivePowersBuilder == null) {
            fivePowersBuilder = std.SortedMap.builder();
            fivePowers = fivePowersBuilder.build();
        }
        final cached = fivePowers.get(k);
        if (cached != null)
            return cached;
        var anchor = 0;
        var digits = "1";
        var i = 0;
        while (i < fivePowers.size()) {
            if (fivePowers.keyAt(i) < k && fivePowers.keyAt(i) > anchor) {
                anchor = fivePowers.keyAt(i);
                digits = fivePowers.valueAt(i);
            }
            i++;
        }
        i = anchor;
        while (i < k) {
            digits = timesSmall(digits, 5);
            i++;
        }
        fivePowersBuilder.put(k, digits);
        fivePowers = fivePowersBuilder.build();
        return digits;
    }

    private static function twoToThe(k:Int):String {
        if (twoPowersBuilder == null) {
            twoPowersBuilder = std.SortedMap.builder();
            twoPowers = twoPowersBuilder.build();
        }
        final cached = twoPowers.get(k);
        if (cached != null)
            return cached;
        var anchor = 0;
        var digits = "1";
        var i = 0;
        while (i < twoPowers.size()) {
            if (twoPowers.keyAt(i) < k && twoPowers.keyAt(i) > anchor) {
                anchor = twoPowers.keyAt(i);
                digits = twoPowers.valueAt(i);
            }
            i++;
        }
        i = anchor;
        while (i < k) {
            digits = timesSmall(digits, 2);
            i++;
        }
        twoPowersBuilder.put(k, digits);
        twoPowers = twoPowersBuilder.build();
        return digits;
    }

    private static function timesLong(digits:String, factor:Int):String {
        if (factor == 0)
            return "0";
        var result:String = null;
        var shift = 0;
        var remaining = factor;
        while (remaining > 0) {
            final chunk = remaining % 100000000;
            remaining = Std.int(remaining / 100000000);
            if (chunk != 0) {
                var part = timesSmall(digits, chunk);
                if (shift > 0)
                    part += zeros(shift);
                result = result == null ? part : addDecimal(result, part);
            }
            shift += 8;
        }
        return result == null ? "0" : result;
    }

    private static function addDecimal(a:String, b:String):String {
        final out = new StringBuf();
        var i = a.length - 1;
        var j = b.length - 1;
        var carry = 0;
        while (i >= 0 || j >= 0 || carry > 0) {
            final sum = (i >= 0 ? a.charCodeAt(i) - 48 : 0) + (j >= 0 ? b.charCodeAt(j) - 48 : 0) + carry;
            out.addChar(48 + sum % 10);
            carry = Std.int(sum / 10);
            i--;
            j--;
        }
        return reverse(out.toString());
    }

    private static function roundToSignificant(exact:String, length:Int):PreparedParagraphDigitsAndExponent {
        if (length >= exact.length)
            return {digits: exact, exponent: 0};
        final keep = exact.substr(0, length);
        final rem = exact.substr(length);
        var up = false;
        if (rem.charCodeAt(0) > 53)
            up = true;
        else if (rem.charCodeAt(0) == 53) {
            var tail = 1;
            while (tail < rem.length && rem.charCodeAt(tail) == 48)
                tail++;
            up = tail < rem.length || ((keep.charCodeAt(keep.length - 1) - 48) % 2 != 0);
        }
        final rounded = up ? incrementDecimal(keep) : keep;
        return {digits: trimZeros(rounded), exponent: rounded.length - length};
    }

    private static function compareDecimal(a:String, nA:Int, b:String, nB:Int):Int {
        final eA = nA - a.length;
        final eB = nB - b.length;
        final aa = eA >= eB ? a + zeros(eA - eB) : a;
        final bb = eB >= eA ? b + zeros(eB - eA) : b;
        if (aa.length != bb.length)
            return aa.length - bb.length;
        return compareDigitStrings(aa, bb);
    }

    private static function timesSmall(digits:String, factor:Int):String {
        final out = new StringBuf();
        var carry = 0;
        var i = digits.length - 1;
        while (i >= 0) {
            final product = (digits.charCodeAt(i) - 48) * factor + carry;
            out.addChar(48 + product % 10);
            carry = Std.int(product / 10);
            i--;
        }
        while (carry > 0) {
            out.addChar(48 + carry % 10);
            carry = Std.int(carry / 10);
        }
        return reverse(out.toString());
    }

    private static function incrementDecimal(digits:String):String {
        var a = digits.split("");
        var i = a.length - 1;
        while (true) {
            if (a[i] != "9") {
                a[i] = String.fromCharCode(a[i].charCodeAt(0) + 1);
                return a.join("");
            }
            a[i] = "0";
            if (i == 0)
                return "1" + a.join("");
            i--;
        }
    }

    private static function decrementDecimal(digits:String):String {
        var a = digits.split("");
        var i = a.length - 1;
        while (i >= 0 && a[i] == "0") {
            a[i] = "9";
            i--;
        }
        if (i >= 0)
            a[i] = String.fromCharCode(a[i].charCodeAt(0) - 1);
        var out = a.join("");
        var start = 0;
        while (start < out.length - 1 && out.charCodeAt(start) == 48)
            start++;
        return out.substr(start);
    }

    private static function decompose(v:Float):PreparedParagraphDecomposed {
        final f = decomposeF32(v);
        var mantissa = Std.string(f.mant24);
        var exponent = f.exp2;
        if (f.mant24 >= 0x800000) {
            mantissa = timesLong(mantissa, 536870912);
            exponent -= 29;
        }
        // Normalize to the exact 53-bit significand used by the widened f64.
        while (mantissa.length < 16 || (mantissa.length == 16 && compareDigitStrings(mantissa, "4503599627370496") < 0)) {
            mantissa = timesSmall(mantissa, 2);
            exponent--;
        }
        return {mantissa: mantissa, exp2: exponent};
    }

    private static function decomposeF32(v:Float):PreparedParagraphF32Decomposed {
        final bits = haxe.io.FPHelper.floatToI32(v);
        final rawExponent = (bits >>> 23) & 0xff;
        final rawMantissa = bits & 0x7fffff;
        if (rawExponent == 0)
            return {mant24: rawMantissa, exp2: -149};
        return {mant24: rawMantissa | 0x800000, exp2: rawExponent - 150};
    }

    private static function compareDigitStrings(a:String, b:String):Int {
        if (a.length != b.length)
            return a.length - b.length;
        var i = 0;
        while (i < a.length) {
            final da = a.charCodeAt(i);
            final db = b.charCodeAt(i);
            if (da != db)
                return da - db;
            i++;
        }
        return 0;
    }

    private static function zeros(n:Int):String {
        var s = "";
        var i = 0;
        while (i < n) {
            s += "0";
            i++;
        }
        return s;
    }

    private static function trimZeros(s:String):String {
        var e = s.length;
        while (e > 1 && s.charCodeAt(e - 1) == 48)
            e--;
        return s.substr(0, e);
    }

    private static function reverse(s:String):String {
        var r = "";
        var i = s.length - 1;
        while (i >= 0) {
            r += s.charAt(i);
            i--;
        }
        return r;
    }
}
