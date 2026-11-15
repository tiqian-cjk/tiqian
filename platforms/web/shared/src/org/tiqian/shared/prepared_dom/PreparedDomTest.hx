package org.tiqian.shared.prepared_dom;

import org.tiqian.test.trace.TracedAssertions;

/**
 * Pins class 生成 + data-tq constants + spacing classification to the exact
 * TS oracle outputs (prepared-dom.ts snapshotValueStyleClass /
 * runtimeValueStyleClass / constants / preparedSpacing).
 */
class PreparedDomTest {

    @:test
    public static function snapshotValueStyleClassMatchesTs():Void {
        TracedAssertions.assertEqualsString("tqv-0", PreparedDom.snapshotValueStyleClass(0), "snapshot class 0");
        TracedAssertions.assertEqualsString("tqv-1", PreparedDom.snapshotValueStyleClass(1), "snapshot class 1");
        TracedAssertions.assertEqualsString("tqv-a", PreparedDom.snapshotValueStyleClass(10), "snapshot class 10");
        TracedAssertions.assertEqualsString("tqv-z", PreparedDom.snapshotValueStyleClass(35), "snapshot class 35");
        TracedAssertions.assertEqualsString("tqv-10", PreparedDom.snapshotValueStyleClass(36), "snapshot class 36");
        TracedAssertions.assertEqualsString("tqv-16", PreparedDom.snapshotValueStyleClass(42), "snapshot class 42");
        TracedAssertions.assertEqualsString("tqv-2s", PreparedDom.snapshotValueStyleClass(100), "snapshot class 100");
        TracedAssertions.assertEqualsString("tqv-zz", PreparedDom.snapshotValueStyleClass(1295), "snapshot class 1295");
        TracedAssertions.assertEqualsString("tqv-100", PreparedDom.snapshotValueStyleClass(1296), "snapshot class 1296");
    }

    @:test
    public static function runtimeValueStyleClassMatchesTs():Void {
        TracedAssertions.assertEqualsString("tqvr-", PreparedDom.runtimeValueStyleClass(""), "runtime class empty");
        TracedAssertions.assertEqualsString("tqvr-abc", PreparedDom.runtimeValueStyleClass("abc"), "runtime class abc");
        TracedAssertions.assertEqualsString("tqvr-2f0l6t6m7d", PreparedDom.runtimeValueStyleClass("2f0l6t6m7d"), "runtime class hashed");
    }

    @:test
    public static function dataTqConstantsMatchTs():Void {
        TracedAssertions.assertEqualsString("[data-tq-line-flow-width]", PreparedDom.LINE_MARKER_SELECTOR, "LINE_MARKER_SELECTOR");
        TracedAssertions.assertEqualsString("tiqian-prose, [data-tiqian-root]", PreparedDom.ROOT_SELECTOR, "ROOT_SELECTOR");
        TracedAssertions.assertEqualsString("data-tq-value-style-scope", PreparedDom.VALUE_STYLE_SCOPE_ATTRIBUTE, "VALUE_STYLE_SCOPE_ATTRIBUTE");
        TracedAssertions.assertEqualsString("data-tq-prepared-value-styles", PreparedDom.VALUE_STYLE_ELEMENT_ATTRIBUTE, "VALUE_STYLE_ELEMENT_ATTRIBUTE");
        TracedAssertions.assertEqualsString("data-tq-live-semantic-index", PreparedDom.LIVE_SEMANTIC_INDEX_ATTRIBUTE, "LIVE_SEMANTIC_INDEX_ATTRIBUTE");
        TracedAssertions.assertEqualsString("tiqian-snapshot-style-owner", PreparedDom.SNAPSHOT_STYLE_OWNER, "SNAPSHOT_STYLE_OWNER");
        TracedAssertions.assertEqualsString("zh-Hans", PreparedDom.DEFAULT_LOCALE, "DEFAULT_LOCALE");
    }

    @:test
    public static function preparedSpacingMatchesTs():Void {
        var r = PreparedDom.preparedSpacing("字", 14, 0);
        TracedAssertions.assertEqualsString("none", r.kind, "spacing 字/14/0" + " kind");
        TracedAssertions.assertEqualsString("0px", Markup.px(r.px), "spacing 字/14/0" + " px");
        var r = PreparedDom.preparedSpacing("字", 14, 5e-7);
        TracedAssertions.assertEqualsString("none", r.kind, "spacing 字/14/5e-7" + " kind");
        TracedAssertions.assertEqualsString("0px", Markup.px(r.px), "spacing 字/14/5e-7" + " px");
        var r = PreparedDom.preparedSpacing("字", 14, 0.000001);
        TracedAssertions.assertEqualsString("letter", r.kind, "spacing 字/14/0.000001" + " kind");
        TracedAssertions.assertEqualsString("0px", Markup.px(r.px), "spacing 字/14/0.000001" + " px");
        var r = PreparedDom.preparedSpacing("字", 14, 0.5);
        TracedAssertions.assertEqualsString("letter", r.kind, "spacing 字/14/0.5" + " kind");
        TracedAssertions.assertEqualsString("0.5px", Markup.px(r.px), "spacing 字/14/0.5" + " px");
        var r = PreparedDom.preparedSpacing("字", 14, -0.5);
        TracedAssertions.assertEqualsString("letter", r.kind, "spacing 字/14/-0.5" + " kind");
        TracedAssertions.assertEqualsString("-0.5px", Markup.px(r.px), "spacing 字/14/-0.5" + " px");
        var r = PreparedDom.preparedSpacing("字", 14, -20);
        TracedAssertions.assertEqualsString("overlap", r.kind, "spacing 字/14/-20" + " kind");
        TracedAssertions.assertEqualsString("-20px", Markup.px(r.px), "spacing 字/14/-20" + " px");
        var r = PreparedDom.preparedSpacing("字", 14, 2);
        TracedAssertions.assertEqualsString("letter", r.kind, "spacing 字/14/2" + " kind");
        TracedAssertions.assertEqualsString("2px", Markup.px(r.px), "spacing 字/14/2" + " px");
        var r = PreparedDom.preparedSpacing("ab", 14, 0.5);
        TracedAssertions.assertEqualsString("trailing-letter", r.kind, "spacing ab/14/0.5" + " kind");
        TracedAssertions.assertEqualsString("0.5px", Markup.px(r.px), "spacing ab/14/0.5" + " px");
        var r = PreparedDom.preparedSpacing("ab", 14, -0.5);
        TracedAssertions.assertEqualsString("overlap", r.kind, "spacing ab/14/-0.5" + " kind");
        TracedAssertions.assertEqualsString("-0.5px", Markup.px(r.px), "spacing ab/14/-0.5" + " px");
        var r = PreparedDom.preparedSpacing("ab", 14, -20);
        TracedAssertions.assertEqualsString("overlap", r.kind, "spacing ab/14/-20" + " kind");
        TracedAssertions.assertEqualsString("-20px", Markup.px(r.px), "spacing ab/14/-20" + " px");
        var r = PreparedDom.preparedSpacing("", 14, 0.5);
        TracedAssertions.assertEqualsString("trailing-letter", r.kind, "spacing /14/0.5" + " kind");
        TracedAssertions.assertEqualsString("0.5px", Markup.px(r.px), "spacing /14/0.5" + " px");
        var r = PreparedDom.preparedSpacing("字", -14, 14);
        TracedAssertions.assertEqualsString("letter", r.kind, "spacing 字/-14/14" + " kind");
        TracedAssertions.assertEqualsString("14px", Markup.px(r.px), "spacing 字/-14/14" + " px");
        var r = PreparedDom.preparedSpacing("字", -14, 14.0000001);
        TracedAssertions.assertEqualsString("letter", r.kind, "spacing 字/-14/14.0000001" + " kind");
        TracedAssertions.assertEqualsString("14px", Markup.px(r.px), "spacing 字/-14/14.0000001" + " px");
        var r = PreparedDom.preparedSpacing("字", -14, 13.9999999);
        TracedAssertions.assertEqualsString("trailing-letter", r.kind, "spacing 字/-14/13.9999999" + " kind");
        TracedAssertions.assertEqualsString("14px", Markup.px(r.px), "spacing 字/-14/13.9999999" + " px");
        var r = PreparedDom.preparedSpacing("abc", 0, 0);
        TracedAssertions.assertEqualsString("none", r.kind, "spacing abc/0/0" + " kind");
        TracedAssertions.assertEqualsString("0px", Markup.px(r.px), "spacing abc/0/0" + " px");
        var r = PreparedDom.preparedSpacing("a", 0, 0.000001);
        TracedAssertions.assertEqualsString("letter", r.kind, "spacing a/0/0.000001" + " kind");
        TracedAssertions.assertEqualsString("0px", Markup.px(r.px), "spacing a/0/0.000001" + " px");
    }
    @:test
    public static function preparedFeatureSignatureMatchesTs():Void {
        TracedAssertions.assertEqualsString("", PreparedDom.preparedFeatureSignature(null), "feature null");
        TracedAssertions.assertEqualsString("", PreparedDom.preparedFeatureSignature([]), "feature empty");
        TracedAssertions.assertEqualsString("pwid,palt", PreparedDom.preparedFeatureSignature(["pwid,palt"]), "feature single");
        TracedAssertions.assertEqualsString("pwid,palt,fwid", PreparedDom.preparedFeatureSignature(["pwid,palt", "fwid"]), "feature pair");
        TracedAssertions.assertEqualsString("kern,liga", PreparedDom.preparedFeatureSignature(["kern", "liga"]), "feature kern+liga");
    }

    @:test
    public static function preparedRenderFontSignatureMatchesTs():Void {
        TracedAssertions.assertEqualsString("", PreparedDom.preparedRenderFontSignature([]), "font empty");
        TracedAssertions.assertEqualsString("Noto Sans CJK SC", PreparedDom.preparedRenderFontSignature(["Noto Sans CJK SC"]), "font single");
        TracedAssertions.assertEqualsString("A\u001FB\u001FC", PreparedDom.preparedRenderFontSignature(["A", "B", "C"]), "font trio");
    }

    @:test
    public static function openTypeFeatureSetMatchesTs():Void {
        TracedAssertions.assertEqualsString("true", PreparedDom.isPreparedOpenTypeFeatureSignature("pwid,palt") ? "true" : "false", "member pwid,palt");
        TracedAssertions.assertEqualsString("true", PreparedDom.isPreparedOpenTypeFeatureSignature("fwid") ? "true" : "false", "member fwid");
        TracedAssertions.assertEqualsString("false", PreparedDom.isPreparedOpenTypeFeatureSignature("kern") ? "true" : "false", "nonmember kern");
        TracedAssertions.assertEqualsString("false", PreparedDom.isPreparedOpenTypeFeatureSignature("") ? "true" : "false", "nonmember empty");
    }

    @:test
    public static function canMergePreparedRunMatchesTs():Void {
        var a:PreparedRunSignature = {
            rangeStart: 0, rangeEnd: 5, source: "ab", display: "ab",
            naturalWidth: 20.0, trailingGap: 0.0, shapingBoundary: false,
            openTypeFeatures: null, renderFontFamilies: [], spacing: { kind: "none", px: 0.0 },
            italicEffect: false, dashStrategy: null, evidenceRenderFontFamily: null,
            styleSignature: "s0", punctuationSignature: "p0", semanticSignature: null
        };
        var b:PreparedRunSignature = {
            rangeStart: 5, rangeEnd: 9, source: "cd", display: "cd",
            naturalWidth: 20.0, trailingGap: 0.0, shapingBoundary: false,
            openTypeFeatures: null, renderFontFamilies: [], spacing: { kind: "none", px: 0.0 },
            italicEffect: false, dashStrategy: null, evidenceRenderFontFamily: null,
            styleSignature: "s0", punctuationSignature: "p0", semanticSignature: null
        };
        TracedAssertions.assertEqualsString("true", PreparedDom.canMergePreparedRun(a, b) ? "true" : "false", "contiguous none merge");
        b.rangeStart = 6;
        TracedAssertions.assertEqualsString("false", PreparedDom.canMergePreparedRun(a, b) ? "true" : "false", "gap rangeEnd != rangeStart");
        b.rangeStart = 5;
        a.semanticSignature = "x";
        TracedAssertions.assertEqualsString("false", PreparedDom.canMergePreparedRun(a, b) ? "true" : "false", "semanticSignature differs");
        a.semanticSignature = null;
        a.shapingBoundary = true;
        TracedAssertions.assertEqualsString("false", PreparedDom.canMergePreparedRun(a, b) ? "true" : "false", "shapingBoundary left");
        a.shapingBoundary = false;
        a.openTypeFeatures = ["pwid,palt"];
        TracedAssertions.assertEqualsString("false", PreparedDom.canMergePreparedRun(a, b) ? "true" : "false", "feature signature differs");
        a.openTypeFeatures = null;
        b.renderFontFamilies = ["X"];
        TracedAssertions.assertEqualsString("false", PreparedDom.canMergePreparedRun(a, b) ? "true" : "false", "render font signature differs");
        b.renderFontFamilies = [];
        b.dashStrategy = "dash";
        TracedAssertions.assertEqualsString("false", PreparedDom.canMergePreparedRun(a, b) ? "true" : "false", "dashStrategy not null");
        b.dashStrategy = null;
        b.styleSignature = "s1";
        TracedAssertions.assertEqualsString("false", PreparedDom.canMergePreparedRun(a, b) ? "true" : "false", "styleSignature differs");
        b.styleSignature = "s0";
        b.punctuationSignature = "p1";
        TracedAssertions.assertEqualsString("false", PreparedDom.canMergePreparedRun(a, b) ? "true" : "false", "punctuationSignature differs");
        b.punctuationSignature = "p0";
        b.italicEffect = true;
        TracedAssertions.assertEqualsString("false", PreparedDom.canMergePreparedRun(a, b) ? "true" : "false", "italicEffect differs");
        b.italicEffect = false;
        b.evidenceRenderFontFamily = "e";
        TracedAssertions.assertEqualsString("false", PreparedDom.canMergePreparedRun(a, b) ? "true" : "false", "evidenceRenderFontFamily differs");
        b.evidenceRenderFontFamily = null;
        a.spacing = { kind: "letter", px: 0.5 };
        b.spacing = { kind: "letter", px: 0.5 };
        TracedAssertions.assertEqualsString("true", PreparedDom.canMergePreparedRun(a, b) ? "true" : "false", "letter equal px merge");
        b.spacing = { kind: "letter", px: 0.51 };
        TracedAssertions.assertEqualsString("false", PreparedDom.canMergePreparedRun(a, b) ? "true" : "false", "letter px diff >= epsilon");
        a.spacing = { kind: "none", px: 0.0 };
        TracedAssertions.assertEqualsString("false", PreparedDom.canMergePreparedRun(a, b) ? "true" : "false", "none + letter");
        b.spacing = { kind: "overlap", px: -0.5 };
        TracedAssertions.assertEqualsString("false", PreparedDom.canMergePreparedRun(a, b) ? "true" : "false", "none + overlap");
        a.spacing = { kind: "overlap", px: -0.5 };
        TracedAssertions.assertEqualsString("false", PreparedDom.canMergePreparedRun(a, b) ? "true" : "false", "overlap + overlap");
    }

    @:test
    public static function mergePreparedRunMatchesTs():Void {
        var a:PreparedRunSignature = {
            rangeStart: 0, rangeEnd: 5, source: "ab", display: "ab",
            naturalWidth: 20.0, trailingGap: 0.5, shapingBoundary: false,
            openTypeFeatures: null, renderFontFamilies: [], spacing: { kind: "none", px: 0.0 },
            italicEffect: false, dashStrategy: null, evidenceRenderFontFamily: null,
            styleSignature: "s0", punctuationSignature: "p0", semanticSignature: null
        };
        var b:PreparedRunSignature = {
            rangeStart: 5, rangeEnd: 9, source: "cd", display: "cd",
            naturalWidth: 18.0, trailingGap: -0.5, shapingBoundary: false,
            openTypeFeatures: null, renderFontFamilies: [], spacing: { kind: "none", px: 0.0 },
            italicEffect: false, dashStrategy: null, evidenceRenderFontFamily: null,
            styleSignature: "s0", punctuationSignature: "p0", semanticSignature: null
        };
        PreparedDom.mergePreparedRun(a, b);
        TracedAssertions.assertEqualsString("9", Std.string(a.rangeEnd), "rangeEnd");
        TracedAssertions.assertEqualsString("abcd", a.source, "source concat");
        TracedAssertions.assertEqualsString("abcd", a.display, "display concat");
        TracedAssertions.assertEqualsString("38", Std.string(a.naturalWidth), "naturalWidth sum");
        TracedAssertions.assertEqualsString("0", Std.string(a.trailingGap), "trailingGap sum");
    }

    @:test
    public static function renderRunTextOnlyMatchesTs():Void {
        final run = PreparedDomTestSupport.input("字", "字", 0.0, 14.0, false, null, [], 0.0,
            { kind: "none", px: 0.0 }, null, false, null, null, null, null, null,
            null, null, null);
        final node = PreparedDom.renderRun(run, null);
        TracedAssertions.assertEqualsString("字", node.html, "renderRunTextOnlyMatchesTs html");
        TracedAssertions.assertEqualsString("[\"#\",\"字\"]", PreparedDomTestSupport.artifactToJson(node.artifact), "renderRunTextOnlyMatchesTs artifact");
    }

    @:test
    public static function renderRunElementMatchesTs():Void {
        final run = PreparedDomTestSupport.input("语", "a", 10.5, 12.0, true, ["pwid", "palt"],
            ["Noto Serif CJK SC", "serif"], 0.5, { kind: "letter", px: 1.25 },
            { fontSize: 16.0, fontWeight: 700.0, italic: false }, false,
            "spread", "zh-Hans", "face-1", "1,2,3", "ev", 2.0, 3.5, null);
        final node = PreparedDom.renderRun(run, null);
        TracedAssertions.assertEqualsString("<span data-tq-advance=\"12.5\" data-tq-dash-advance=\"12\" data-tq-dash-evidence=\"ev\" data-tq-dash-face=\"face-1\" data-tq-dash-glyph-ids=\"1,2,3\" data-tq-dash-strategy=\"spread\" data-tq-geometry=\"true\" data-tq-open-type-features=\"pwid,palt\" data-tq-punctuation-body-width=\"3.5\" data-tq-punctuation-ink-floor=\"2\" data-tq-render-font-projection=\"true\" data-tq-shaping-boundary data-tq-src=\"语\" data-tq-x=\"10.5\" lang=\"zh-Hans\" style=\"font-family:&quot;Noto Serif CJK SC&quot;,&quot;serif&quot;!important;font-size:16px!important;font-weight:700!important;font-style:normal!important;letter-spacing:1.25px!important\">a</span>", node.html, "renderRunElementMatchesTs html");
        TracedAssertions.assertEqualsString("[\"span\",[[\"data-tq-advance\",\"12.5\"],[\"data-tq-dash-advance\",\"12\"],[\"data-tq-dash-evidence\",\"ev\"],[\"data-tq-dash-face\",\"face-1\"],[\"data-tq-dash-glyph-ids\",\"1,2,3\"],[\"data-tq-dash-strategy\",\"spread\"],[\"data-tq-geometry\",\"true\"],[\"data-tq-open-type-features\",\"pwid,palt\"],[\"data-tq-punctuation-body-width\",\"3.5\"],[\"data-tq-punctuation-ink-floor\",\"2\"],[\"data-tq-render-font-projection\",\"true\"],[\"data-tq-shaping-boundary\",\"\"],[\"data-tq-src\",\"语\"],[\"data-tq-x\",\"10.5\"],[\"lang\",\"zh-Hans\"],[\"style\",\"font-family:\\\"Noto Serif CJK SC\\\",\\\"serif\\\"!important;font-size:16px!important;font-weight:700!important;font-style:normal!important;letter-spacing:1.25px!important\"]],[[\"#\",\"a\"]]]", PreparedDomTestSupport.artifactToJson(node.artifact), "renderRunElementMatchesTs artifact");
    }

    @:test
    public static function renderRunTrailingLetterMatchesTs():Void {
        final run = PreparedDomTestSupport.input("a", "a", 0.0, 5.0, false, null, [], 0.0,
            { kind: "trailing-letter", px: 2.5 }, null, false, null, null, null,
            null, null, null, null, null);
        final node = PreparedDom.renderRun(run, null);
        TracedAssertions.assertEqualsString("<span data-tq-advance=\"5\" data-tq-geometry=\"true\" data-tq-x=\"0\">a<span aria-hidden=\"true\" data-tq-copy-ignore=\"true\" data-tq-geometry=\"true\" data-tq-spacing-carrier=\"true\" style=\"display:inline-block!important;inline-size:2.5px!important;height:0!important;line-height:0!important;letter-spacing:2.5px!important;overflow:hidden!important;vertical-align:baseline!important;white-space:pre!important\">\u00A0</span></span>", node.html, "renderRunTrailingLetterMatchesTs html");
        TracedAssertions.assertEqualsString("[\"span\",[[\"data-tq-advance\",\"5\"],[\"data-tq-geometry\",\"true\"],[\"data-tq-x\",\"0\"]],[[\"#\",\"a\"],[\"span\",[[\"aria-hidden\",\"true\"],[\"data-tq-copy-ignore\",\"true\"],[\"data-tq-geometry\",\"true\"],[\"data-tq-spacing-carrier\",\"true\"],[\"style\",\"display:inline-block!important;inline-size:2.5px!important;height:0!important;line-height:0!important;letter-spacing:2.5px!important;overflow:hidden!important;vertical-align:baseline!important;white-space:pre!important\"]],[[\"#\",\"\u00A0\"]]]]]", PreparedDomTestSupport.artifactToJson(node.artifact), "renderRunTrailingLetterMatchesTs artifact");
    }

    @:test
    public static function renderRunUnsupportedOpenTypeFeaturesThrows():Void {
        final run = PreparedDomTestSupport.input("a", "a", 0.0, 5.0, false, ["pwid", "palt", "bogus"], [], 0.0,
            { kind: "none", px: 0.0 }, null, false, null, null, null, null, null,
            null, null, null);
        var caught:PreparedDomException = null;
        try {
            PreparedDom.renderRun(run, null);
        } catch (e:PreparedDomException) {
            caught = e;
        }
        TracedAssertions.assertTrue(caught != null, "renderRun unsupported open-type features throws");
        if (caught != null) {
            TracedAssertions.assertEqualsString(
                "UnsupportedPreparedOpenTypeFeatures: pwid,palt,bogus",
                caught.message, "renderRun unsupported open-type features message");
        }
    }
}
