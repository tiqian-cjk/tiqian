package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.font.FontRole;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.linebreak.Hyphenator.NoHyphenator;
import org.tiqian.core.RoleOverrideInfo;
import org.tiqian.core.PunctuationDecisionInfo;
import std.UString;

class QuoteClassificationEngineTest {
    @:test public static function keepsLatinTechnicalPunctuationInLatinRun():Void {
        var t = QuoteClassificationEngineTestSupport.begin("keepsLatinTechnicalPunctuationInLatinRun");
        var r = QuoteClassificationEngineTestSupport.layout("well-known/path", 320);
        var x = "";
        var all = true;
        var any = false;
        for (i in 0...r.clusters.length) {
            var c = r.clusters[i];
            x += c.text;
            all = all && c.fontKey == "latin-primary";
            any = any || c.text == "well-";
        }
        TracedAssertions.assertEqualsString("well-known/path", x);
        TracedAssertions.assertTrue(all);
        TracedAssertions.assertTrue(any);
    }

    @:test public static function classifiesAsciiBracketsAsLatinRegardlessOfSurroundingContext():Void {
        var t = QuoteClassificationEngineTestSupport.begin("classifiesAsciiBracketsAsLatinRegardlessOfSurroundingContext");
        var r = QuoteClassificationEngineTestSupport.layout("中文(English)中文", 320);
        var c:Null<Cluster> = null;
        for (i in 0...r.clusters.length) {
            var v = r.clusters[i];
            if (v.text == "(English)")
                c = v;
        }
        TracedAssertions.assertEqualsString("latin-primary", c.fontKey);
        var d:org.tiqian.core.FontDecisionInfo = null;
        for (i in 0...r.debug.fontDecisions.length) {
            var v = r.debug.fontDecisions[i];
            if (v.sourceText == "(English)")
                d = v;
        }
        TracedAssertions.assertEqualsString("LatinText", d.role);
    }

    @:test public static function classifiesAsciiBracketsAsLatinInsidePureCjkContent():Void {
        var t = QuoteClassificationEngineTestSupport.begin("classifiesAsciiBracketsAsLatinInsidePureCjkContent");
        var r = QuoteClassificationEngineTestSupport.layout("中文(中文)", 320);
        var a:Null<Cluster> = null;
        var b:Null<Cluster> = null;
        for (i in 0...r.clusters.length) {
            var c = r.clusters[i];
            if (c.text == "(")
                a = c;
            if (c.text == ")")
                b = c;
        }
        TracedAssertions.assertEqualsString("latin-primary", a.fontKey);
        TracedAssertions.assertEqualsString("latin-primary", b.fontKey);
    }

    @:test public static function asciiClosingBracketWithCjkInteriorIsForbiddenAtLineStart():Void {
        var t = QuoteClassificationEngineTestSupport.begin("asciiClosingBracketWithCjkInteriorIsForbiddenAtLineStart");
        var text = "如今已占据超七成份额(国产品牌)，互联网大厂排队抢购？";
        var r = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null,
            new LookaheadLineBreaker()).layout(QuoteClassificationEngineTestSupport.input(text, 232));
        var debugLines = "";
        for (i in 0...r.lines.length) {
            var l = r.lines[i];
            var s = UString.slice(text, l.range.start, l.range.end);
            if (i > 0)
                debugLines += "\n";
            debugLines += l.clusterRange.toString() + " " + Std.string(l.range) + " " + Std.string(l.endReason) + " \"" + s + "\"";
        }
        var ok = true;
        for (i in 0...r.lines.length) {
            var l = r.lines[i];
            ok = ok && !QuoteClassificationEngineTestSupport.startsWith(text, l.range, ")");
        }
        TracedAssertions.assertTrue(ok, debugLines);
        var c:Null<Cluster> = null;
        for (i in 0...r.clusters.length) {
            var v = r.clusters[i];
            if (v.text == ")")
                c = v;
        }
        TracedAssertions.assertEqualsString("latin-primary", c.fontKey);
    }

    @:test public static function asciiOpeningBracketWithCjkInteriorIsForbiddenAtLineEnd():Void {
        var t = QuoteClassificationEngineTestSupport.begin("asciiOpeningBracketWithCjkInteriorIsForbiddenAtLineEnd");
        var text = "如今已占据超七成份额(国产品牌)，互联网大厂排队抢购？";
        var r = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null,
            new LookaheadLineBreaker()).layout(QuoteClassificationEngineTestSupport.input(text, 168));
        var debugLines = "";
        for (i in 0...r.lines.length) {
            var l = r.lines[i];
            var s = UString.slice(text, l.range.start, l.range.end);
            if (i > 0)
                debugLines += "\n";
            debugLines += l.clusterRange.toString() + " " + Std.string(l.range) + " " + Std.string(l.endReason) + " \"" + s + "\"";
        }
        var ok = true;
        for (i in 0...r.lines.length) {
            var l = r.lines[i];
            ok = ok && !QuoteClassificationEngineTestSupport.endsWith(text, l.range, "(");
        }
        TracedAssertions.assertTrue(ok, debugLines);
        var c:Null<Cluster> = null;
        for (i in 0...r.clusters.length) {
            var v = r.clusters[i];
            if (v.text == "(")
                c = v;
        }
        TracedAssertions.assertEqualsString("latin-primary", c.fontKey);
    }

    @:test public static function keepsTextStartLatinQuotePairInLatinRun():Void {
        var t = QuoteClassificationEngineTestSupport.begin("keepsTextStartLatinQuotePairInLatinRun");
        var r = QuoteClassificationEngineTestSupport.layout("“Hello” world", 320);
        TracedAssertions.assertEquals(3, r.clusters.length);
        TracedAssertions.assertEqualsString("“Hello”", r.clusters[0].text);
        TracedAssertions.assertEqualsString("latin-primary", r.clusters[0].fontKey);
        var ok = false;
        for (i in 0...r.debug.fontDecisions.length) {
            var d = r.debug.fontDecisions[i];
            ok = ok || (d.sourceText == "“Hello” world" && d.role == "LatinText");
        }
        TracedAssertions.assertTrue(ok);
    }

    @:test public static function mixedQuoteContextsReachTheFontAndPunctuationPipeline():Void {
        var t = QuoteClassificationEngineTestSupport.begin("mixedQuoteContextsReachTheFontAndPunctuationPipeline");
        var text = "中“文”中；that’s；（如 ‘O’, ‘Q’）；他说：“She said ‘hello’.”";
        var r = QuoteClassificationEngineTestSupport.layout(text, 1000);
        var c = QuoteClassificationEngineTestSupport.indices(text);
        var ck = QuoteClassificationEngineTestSupport.set([1, 3, 29, 47]);
        var b = std.SortedSet.builder();
        for (i in 0...r.debug.punctuationDecisions.length) {
            var d = r.debug.punctuationDecisions[i];
            if (QuoteClassificationEngineTestSupport.isCurlyQuoteForTest(d.char))
                b.put(d.range.start);
        }
        var ps = b.build();
        var cjkOk = true;
        var latinOk = true;
        for (i in c) {
            if (ck.has(i))
                cjkOk = cjkOk && QuoteClassificationEngineTestSupport.roleAt(r, i) == "CjkPunctuation";
            else
                latinOk = latinOk && QuoteClassificationEngineTestSupport.roleAt(r, i) == "LatinText";
        }
        var rb = std.SortedMap.builder();
        for (i in 0...r.debug.roleOverrides.length) {
            var d = r.debug.roleOverrides[i];
            rb.put(d.range.start, d.overriddenRole);
        }
        var roles = rb.build();
        var expected = std.SortedMap.builder();
        for (i in c)
            expected.put(i, ck.has(i) ? "CjkPunctuation" : "LatinText");
        TracedAssertions.assertTrue(cjkOk);
        TracedAssertions.assertTrue(latinOk);
        TracedAssertions.assertEqualsIntSet(ck, ps);
        TracedAssertions.assertEqualsRendered(QuoteClassificationEngineTestSupport.renderRoleMap(expected.build()),
            QuoteClassificationEngineTestSupport.renderRoleMap(roles));
        TracedAssertions.assertEqualsString(text, r.input.content.text);
    }

    @:test public static function quoteRolesSurviveStyleAndSourceBoundaries():Void {
        var t = QuoteClassificationEngineTestSupport.begin("quoteRolesSurviveStyleAndSourceBoundaries");
        var text = "中‘that’s’中";
        var input = new LayoutInput(new TiqianTextContent(text, [new TextSpan(new TextRange(2, 7), new TextStyle(null, null, null, 700, null))],
            [1, 2, 6, 7, 8, 9]), null, null,
            new LayoutConstraints(320));
        var r = new ExplainableStubParagraphLayoutEngine().layout(input);
        var b = std.SortedMap.builder();
        for (i in 0...r.debug.roleOverrides.length) {
            var d = r.debug.roleOverrides[i];
            b.put(d.range.start, d.overriddenRole);
        }
        var roles = b.build();
        TracedAssertions.assertEqualsNullableString("CjkPunctuation", roles.get(1));
        TracedAssertions.assertEqualsNullableString("LatinText", roles.get(6));
        TracedAssertions.assertEqualsNullableString("CjkPunctuation", roles.get(8));
        var f:Null<String> = null;
        for (i in 0...r.clusters.length) {
            var c = r.clusters[i];
            if (c.range.start == 6)
                f = c.fontKey;
        }
        TracedAssertions.assertEqualsString("latin-primary", f);
        var x = "";
        for (i in 0...r.clusters.length)
            x += r.clusters[i].text;
        TracedAssertions.assertEqualsString(text, x);
    }

    @:test public static function adjacentQuotedListItemsKeepCjkQuoteGeometryAcrossMixedContent():Void {
        var t = QuoteClassificationEngineTestSupport.begin("adjacentQuotedListItemsKeepCjkQuoteGeometryAcrossMixedContent");
        var texts = ["便延伸出了“乃子”“大波”“大灯”“大雷”“大扎”“对A”“波霸”这些词", "这些太直白了是吧，\n “欧派”“double”“double may”呢"];
        for (ti in 0...texts.length) {
            var text = texts[ti];
            var r = QuoteClassificationEngineTestSupport.layout(text, 1000);
            var qi = QuoteClassificationEngineTestSupport.indices(text);
            var a:Array<Int> = [];
            for (i in 0...r.debug.fontDecisions.length) {
                var d = r.debug.fontDecisions[i];
                if (d.role == "CjkPunctuation" && qi.indexOf(d.range.start) >= 0)
                    a.push(d.range.start);
            }
            TracedAssertions.assertEqualsIntArray(qi, a, text);
            var p:Array<Int> = [];
            for (i in 0...r.debug.punctuationDecisions.length) {
                var d = r.debug.punctuationDecisions[i];
                if (QuoteClassificationEngineTestSupport.isCurlyQuoteForTest(d.char))
                    p.push(d.range.start);
            }
            TracedAssertions.assertEqualsIntArray(qi, p, text);
            var f = [
                QuoteClassificationEngineTestSupport.lastIndex(text, "“"),
                QuoteClassificationEngineTestSupport.lastIndex(text, "”")
            ];
            var o:Array<Int> = [];
            for (i in 0...r.debug.roleOverrides.length) {
                var d = r.debug.roleOverrides[i];
                if (f.indexOf(d.range.start) >= 0)
                    o.push(d.range.start);
            }
            TracedAssertions.assertEqualsIntArray(f, o, text);
            var good = true;
            for (i in 0...r.debug.roleOverrides.length) {
                var d = r.debug.roleOverrides[i];
                if (f.indexOf(d.range.start) >= 0)
                    good = good && d.source == "PairedPunctuationOuterScriptContext";
            }
            TracedAssertions.assertTrue(good, text);
            TracedAssertions.assertEqualsString(text, r.input.content.text);
        }
    }

    @:test public static function mi10sAdjacentLatinTranscriptionsKeepTheFinalQuotePairInCjkContext():Void {
        var t = QuoteClassificationEngineTestSupport.begin("mi10sAdjacentLatinTranscriptionsKeepTheFinalQuotePairInCjkContext");
        var text = "所以这个和 “骑ji” “说shui”“斜xiá”不一样，港台是从众的，大陆读音大多数源自韵书。";
        var e = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, new LookaheadLineBreaker(), null, null,
            new NoHyphenator());
        var r = e.layout(QuoteClassificationEngineTestSupport.input(text, 160));
        var f = [
            QuoteClassificationEngineTestSupport.lastIndex(text, "“"),
            QuoteClassificationEngineTestSupport.lastIndex(text, "”")
        ];
        var a:Array<Int> = [];
        for (i in 0...r.debug.roleOverrides.length) {
            var d = r.debug.roleOverrides[i];
            if (f.indexOf(d.range.start) >= 0)
                a.push(d.range.start);
        }
        TracedAssertions.assertEqualsIntArray([19, 24], a);
        var rolesOk = true;
        var sourcesOk = true;
        for (i in 0...r.debug.roleOverrides.length) {
            var d = r.debug.roleOverrides[i];
            if (f.indexOf(d.range.start) >= 0) {
                rolesOk = rolesOk && d.overriddenRole == "CjkPunctuation";
                sourcesOk = sourcesOk && d.source == "PairedPunctuationOuterScriptContext";
            }
        }
        TracedAssertions.assertTrue(rolesOk);
        TracedAssertions.assertTrue(sourcesOk);
        var no = true;
        var lm = "";
        for (i in 0...r.lines.length) {
            var l = r.lines[i];
            var s = UString.slice(text, l.range.start, l.range.end);
            no = no && s.indexOf("”") != 0;
            if (i > 0)
                lm += ", ";
            lm += s;
        }
        TracedAssertions.assertTrue(no, lm);
    }

    @:test public static function skipsNeutralDashBeforeLatinQuotePairInLayout():Void {
        var t = QuoteClassificationEngineTestSupport.begin("skipsNeutralDashBeforeLatinQuotePairInLayout");
        var r = QuoteClassificationEngineTestSupport.layout("English — “hello”", 320);
        var c:Null<Cluster> = null;
        for (i in 0...r.clusters.length) {
            var v = r.clusters[i];
            if (v.text.indexOf("“hello”") >= 0)
                c = v;
        }
        TracedAssertions.assertEqualsString("latin-primary", c.fontKey);
    }

    @:test public static function keepsSlashLedLatinTechnicalRunOutOfCjkPunctuationGeometry():Void {
        var t = QuoteClassificationEngineTestSupport.begin("keepsSlashLedLatinTechnicalRunOutOfCjkPunctuationGeometry");
        var r = QuoteClassificationEngineTestSupport.layout("恐跨/TERFism。如果", 320);
        var d:org.tiqian.core.FontDecisionInfo = null;
        for (i in 0...r.debug.fontDecisions.length) {
            var x = r.debug.fontDecisions[i];
            if (x.sourceText == "/TERFism")
                d = x;
        }
        TracedAssertions.assertEqualsString("LatinText", d.role);
        var none = true;
        for (i in 0...r.debug.punctuationDecisions.length)
            none = none || r.debug.punctuationDecisions[i].range.start != d.range.start;
        TracedAssertions.assertTrue(none);
        var c:Null<Cluster> = null;
        for (i in 0...r.clusters.length) {
            var x = r.clusters[i];
            if (x.text == "/TERFism")
                c = x;
        }
        TracedAssertions.assertEqualsString("latin-primary", c.fontKey);
        TracedAssertions.assertTrue(c.advance > 16);
    }

    @:test public static function recordsRoleOverridesForResolvedQuotePairs():Void {
        var t = QuoteClassificationEngineTestSupport.begin("recordsRoleOverridesForResolvedQuotePairs");
        var r = QuoteClassificationEngineTestSupport.layout("“Hello” world", 320);
        var a:Null<RoleOverrideInfo> = null;
        var b:Null<RoleOverrideInfo> = null;
        for (i in 0...r.debug.roleOverrides.length) {
            var d = r.debug.roleOverrides[i];
            if (d.range.start == 0)
                a = d;
            if (d.range.start == 6)
                b = d;
        }
        TracedAssertions.assertEqualsNullableString("LatinText", a.overriddenRole);
        TracedAssertions.assertEqualsNullableString("CjkPunctuation", a.originalRole);
        TracedAssertions.assertEqualsNullableString("PairedPunctuationOuterScriptContext", a.source);
        TracedAssertions.assertEqualsNullableString("LatinText", b.overriddenRole);
    }

    @:test public static function mixedChineseQuestionAtParagraphStartKeepsCjkQuoteGeometry():Void {
        var t = QuoteClassificationEngineTestSupport.begin("mixedChineseQuestionAtParagraphStartKeepsCjkQuoteGeometry");
        var text = "“Json是谁？”";
        var r = QuoteClassificationEngineTestSupport.layout(text, 320);
        var q = QuoteClassificationEngineTestSupport.set([0, 8]);
        var o = std.SortedSet.builder();
        for (i in 0...r.debug.roleOverrides.length) {
            var d = r.debug.roleOverrides[i];
            if (q.has(d.range.start))
                o.put(d.range.start);
        }
        var os = o.build();
        var rolesOk = true;
        var sourcesOk = true;
        for (i in 0...r.debug.roleOverrides.length) {
            var d = r.debug.roleOverrides[i];
            if (q.has(d.range.start)) {
                rolesOk = rolesOk && d.overriddenRole == "CjkPunctuation";
                sourcesOk = sourcesOk && d.source == "ParagraphLanguageQuoteContext";
            }
        }
        var p = std.SortedSet.builder();
        for (i in 0...r.debug.punctuationDecisions.length) {
            var d = r.debug.punctuationDecisions[i];
            if (d.char == "“" || d.char == "”")
                p.put(d.range.start);
        }
        var ps = p.build();
        var x = "";
        for (i in 0...r.clusters.length)
            x += r.clusters[i].text;
        TracedAssertions.assertEqualsIntSet(q, os);
        TracedAssertions.assertTrue(rolesOk);
        TracedAssertions.assertTrue(sourcesOk);
        TracedAssertions.assertEqualsIntSet(q, ps);
        TracedAssertions.assertEqualsString(text, x);
    }

    @:test public static function keepsNumberedCjkQuotePairOnCjkFace():Void {
        var t = QuoteClassificationEngineTestSupport.begin("keepsNumberedCjkQuotePairOnCjkFace");
        var r = QuoteClassificationEngineTestSupport.layout("1.\u201C\u4F60\u77E5\u9053\u674E\u767D\u662F\u600E\u4E48\u6B7B\u7684\u5417\uFF1F\u201D", 320);
        var d:org.tiqian.core.FontDecisionInfo = null;
        for (i in 0...r.debug.fontDecisions.length) {
            var x = r.debug.fontDecisions[i];
            if (x.range.start == 2)
                d = x;
        }
        TracedAssertions.assertEqualsString("CjkPunctuation", d.role);
        TracedAssertions.assertEqualsString("cjk-primary", d.fontKey);
        var o:org.tiqian.core.RoleOverrideInfo = null;
        for (i in 0...r.debug.roleOverrides.length) {
            var x = r.debug.roleOverrides[i];
            if (x.range.start == 2)
                o = x;
        }
        TracedAssertions.assertEqualsString("PairedPunctuationContentScriptContext", o.source);
        TracedAssertions.assertEqualsString("quoted-content-script", o.reason);
        TracedAssertions.assertEqualsString("CjkPunctuation", o.overriddenRole);
    }

    @:test public static function requestsFullWidthCjkQuotesAndSynthesizesTheCellWhenTheFontStaysProportional():Void {
        QuoteClassificationEngineTestSupport.fullWidthTest();
    }

    @:test public static function leavesLatinContextCurlyQuotesOutsideCjkPunctuationGeometry():Void {
        var t = QuoteClassificationEngineTestSupport.begin("leavesLatinContextCurlyQuotesOutsideCjkPunctuationGeometry");
        var r = QuoteClassificationEngineTestSupport.layout("“Hello” world", 320);
        var ok = true;
        for (i in 0...r.debug.punctuationDecisions.length)
            ok = ok && !(r.debug.punctuationDecisions[i].char == "“" || r.debug.punctuationDecisions[i].char == "”");
        TracedAssertions.assertTrue(ok);
        ok = true;
        for (i in 0...r.clusters.length)
            ok = ok && r.clusters[i].glyphInlineShift == 0;
        TracedAssertions.assertTrue(ok);
    }

    @:test public static function keepsContractionApostropheLatinInsideCjkSingleQuotes():Void {
        var t = QuoteClassificationEngineTestSupport.begin("keepsContractionApostropheLatinInsideCjkSingleQuotes");
        var r = QuoteClassificationEngineTestSupport.layout("中‘that’s’中", 320);
        var a:org.tiqian.core.FontDecisionInfo = null;
        var c:org.tiqian.core.FontDecisionInfo = null;
        var b:org.tiqian.core.FontDecisionInfo = null;
        for (i in 0...r.debug.fontDecisions.length) {
            var d = r.debug.fontDecisions[i];
            if (d.range.start == 1)
                a = d;
            if (d.range.start == 2)
                c = d;
            if (d.range.start == 8)
                b = d;
        }
        TracedAssertions.assertEqualsString("CjkPunctuation", a.role);
        TracedAssertions.assertEqualsString("LatinText", c.role);
        TracedAssertions.assertEqualsString("that’s", c.sourceText);
        TracedAssertions.assertEqualsString("latin-primary", c.fontKey);
        TracedAssertions.assertEqualsString("CjkPunctuation", b.role);
        var cl:Null<Cluster> = null;
        for (i in 0...r.clusters.length) {
            var x = r.clusters[i];
            if (x.text == "that’s")
                cl = x;
        }
        TracedAssertions.assertEqualsString("latin-primary", cl.fontKey);
        var none = true;
        for (i in 0...r.debug.punctuationDecisions.length)
            none = none && r.debug.punctuationDecisions[i].range.start != 6;
        TracedAssertions.assertTrue(none);
    }

    @:test public static function keepsLatinWordInternalCurlyQuotesInLatinRunInsideMixedParagraph():Void {
        QuoteClassificationEngineTestSupport.internal("中文 Latin: le“t”ters 中文", "NonCjkWordInternalQuotePair", "LatinText");
    }

    @:test public static function supportsSupplementaryLettersInsideLatinWordInternalQuotes():Void {
        QuoteClassificationEngineTestSupport.internal("中文 a“𝐀”b 中文", "NonCjkWordInternalQuotePair", "LatinText");
    }

    @:test public static function keepsLetterBoundedWordInternalQuotesLatin():Void {
        QuoteClassificationEngineTestSupport.internal("中a“b”c文", "NonCjkWordInternalQuotePair", "LatinText");
    }

    @:test public static function keepsDigitContentInsideLetterBoundedQuotesLatin():Void {
        QuoteClassificationEngineTestSupport.internal("中a“1”c文", "NonCjkWordInternalQuotePair", "LatinText");
    }

    @:test public static function keepsDigitBoundedWordInternalQuotesCjk():Void {
        QuoteClassificationEngineTestSupport.internal("中1“1”2文", "PairedPunctuationOuterScriptContext", "CjkPunctuation");
    }

    @:test public static function keepsFullwidthLetterBoundedWordInternalQuotesCjk():Void {
        QuoteClassificationEngineTestSupport.internal("中Ａ“Ｂ”Ｃ文", "ParagraphLanguageQuoteContext", "CjkPunctuation");
    }

    @:test public static function keepsEmptyWordInternalQuotesLatin():Void {
        QuoteClassificationEngineTestSupport.internal("中文a“”b中文", "NonCjkWordInternalQuotePair", "LatinText");
    }

    @:test public static function keepsAstralLetterBoundedWordInternalQuotesLatin():Void {
        QuoteClassificationEngineTestSupport.internal("中𝐀“b”𝐁文", "NonCjkWordInternalQuotePair", "LatinText",
            "keepsAstralLetterBoundedWordInternalQuotesLatin");
    }

    @:test public static function keepsSpaceInsidePairOutOfWordInternalFastPathLatin():Void {
        QuoteClassificationEngineTestSupport.internal("中a“b c”d文", "ParagraphLanguageQuoteContext", "CjkPunctuation",
            "keepsSpaceInsidePairOutOfWordInternalFastPathLatin");
    }

    @:test public static function keepsDigitBoundedSingleQuotePairCjkViaEnclosingQuotation():Void {
        var t = QuoteClassificationEngineTestSupport.arm();
        var r = QuoteClassificationEngineTestSupport.layout("尾号是“1‘2’3”。", 320);
        var n = 0;
        var allOk = true;
        for (di in 0...r.debug.roleOverrides.length) {
            var d = r.debug.roleOverrides[di];
            if (d.sourceText == "\u2018" || d.sourceText == "\u2019") {
                n++;
                allOk = allOk && d.overriddenRole == "CjkPunctuation" && d.source == "PairedPunctuationEnclosingQuoteContext";
            }
        }
        TracedAssertions.assertEquals(2, n);
        TracedAssertions.assertTrue(allOk);
        var dAll = true;
        for (di in 0...r.debug.roleOverrides.length) {
            var d = r.debug.roleOverrides[di];
            if (d.sourceText == "\u201C" || d.sourceText == "\u201D")
                dAll = dAll && d.overriddenRole == "CjkPunctuation";
        }
        TracedAssertions.assertTrue(dAll);
    }

    @:test public static function resolvesDigitBoundUnmatchedQuotesAsPrimes():Void {
        var t = QuoteClassificationEngineTestSupport.arm();
        var r = QuoteClassificationEngineTestSupport.layout("他用时1’30”，屏幕是6.1”的。", 320);
        var n = 0;
        var allOk = true;
        for (di in 0...r.debug.roleOverrides.length) {
            var d = r.debug.roleOverrides[di];
            if (d.sourceText == "\u2019" || d.sourceText == "\u201D") {
                n++;
                allOk = allOk && d.overriddenRole == "LatinText" && d.source == "NumericPrimeUnmatchedQuote";
            }
        }
        TracedAssertions.assertEquals(3, n);
        TracedAssertions.assertTrue(allOk);
    }

    @:test public static function keepsDecadeStyleApostropheWithLetterFlankLatin():Void {
        var t = QuoteClassificationEngineTestSupport.arm();
        var r = QuoteClassificationEngineTestSupport.layout("那是90’s的音乐。", 320);
        var a:RoleOverrideInfo = null;
        for (di in 0...r.debug.roleOverrides.length) {
            var d = r.debug.roleOverrides[di];
            if (d.sourceText == "\u2019")
                a = d;
        }
        TracedAssertions.assertEqualsString("LatinText", a.overriddenRole);
        TracedAssertions.assertEqualsString("NonCjkInWordApostrophe", a.source);
    }
}
