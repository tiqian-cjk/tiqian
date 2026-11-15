package org.tiqian.shared.prepared_dom;

import org.tiqian.test.trace.TracedAssertions;

/**
 * Pins the render-evidence lowering to the exact TS oracle outputs of
 * prepared-dom-evidence.ts (inline-object placeholder, ruby span, bopomofo
 * annotation, interlinear/dot overlays and the overlay-geometry failure).
 * Every expected string was produced by running the hand-written TS
 * implementation over the same inputs; html and JSON.stringify(artifact)
 * are compared byte for byte.
 */
class EvidenceTest {

    @:test
    public static function inlineObjectPlaceholderNoMarginMatchesTs():Void {
        final cell:InlineObjectPlaceholderCell = { naturalWidth: 12.5, rangeStart: 3, rangeEnd: 5, drawX: 40 };
        final node = Evidence.inlineObjectPlaceholder(cell, 0, null);
        TracedAssertions.assertEqualsString("<span data-tq-advance=\"12.5\" data-tq-geometry=\"true\" data-tq-inline-object=\"pending\" data-tq-object-range=\"3-5\" data-tq-x=\"40\" style=\"display:inline-block!important;box-sizing:border-box!important;inline-size:12.5px!important\"></span>", node.html, "inline placeholder no margin html");
        TracedAssertions.assertEqualsString("[\"span\",[[\"data-tq-advance\",\"12.5\"],[\"data-tq-geometry\",\"true\"],[\"data-tq-inline-object\",\"pending\"],[\"data-tq-object-range\",\"3-5\"],[\"data-tq-x\",\"40\"],[\"style\",\"display:inline-block!important;box-sizing:border-box!important;inline-size:12.5px!important\"]],[]]", PreparedDomTestSupport.artifactToJson(node.artifact), "inline placeholder no margin artifact");
    }

    @:test
    public static function inlineObjectPlaceholderTrailingMarginMatchesTs():Void {
        final cell:InlineObjectPlaceholderCell = { naturalWidth: 8, rangeStart: 3, rangeEnd: 5, drawX: 40 };
        final node = Evidence.inlineObjectPlaceholder(cell, 1.5, new DeclarationLengthStyleClass());
        TracedAssertions.assertEqualsString("<span class=\"tqc-117\" data-tq-advance=\"8\" data-tq-geometry=\"true\" data-tq-inline-object=\"pending\" data-tq-object-range=\"3-5\" data-tq-object-trailing-margin=\"1.5\" data-tq-x=\"40\"></span>", node.html, "inline placeholder margin html");
        TracedAssertions.assertEqualsString("[\"span\",[[\"class\",\"tqc-117\"],[\"data-tq-advance\",\"8\"],[\"data-tq-geometry\",\"true\"],[\"data-tq-inline-object\",\"pending\"],[\"data-tq-object-range\",\"3-5\"],[\"data-tq-object-trailing-margin\",\"1.5\"],[\"data-tq-x\",\"40\"]],[]]", PreparedDomTestSupport.artifactToJson(node.artifact), "inline placeholder margin artifact");
    }

    @:test
    public static function rubyAnnotationSpanMatchesTs():Void {
        final ruby:RubyAnnotation = { fontSize: 9, ascent: 8.2, fontFamilies: ["Noto Serif CJK SC", "serif"], text: "注", fontWeight: 600, centerX: 30.25, baselineY: 100 };
        final node = Evidence.rubyAnnotationSpan(ruby, 80, null);
        TracedAssertions.assertEqualsString("<span data-tq-geometry=\"true\" data-tq-src=\"（注）\" style=\"color:currentColor!important;font-family:&quot;Noto Serif CJK SC&quot;,&quot;serif&quot;!important;font-size:9px!important;font-weight:600!important;left:30.25px!important;line-height:1!important;position:absolute!important;top:11.8px!important;transform:translateX(-50%)!important;white-space:pre!important\">注</span>", node.html, "ruby span html");
        TracedAssertions.assertEqualsString("[\"span\",[[\"data-tq-geometry\",\"true\"],[\"data-tq-src\",\"（注）\"],[\"style\",\"color:currentColor!important;font-family:\\\"Noto Serif CJK SC\\\",\\\"serif\\\"!important;font-size:9px!important;font-weight:600!important;left:30.25px!important;line-height:1!important;position:absolute!important;top:11.8px!important;transform:translateX(-50%)!important;white-space:pre!important\"]],[[\"#\",\"注\"]]]", PreparedDomTestSupport.artifactToJson(node.artifact), "ruby span artifact");
    }

    @:test
    public static function rubyAnnotationSpanAscentFallbackMatchesTs():Void {
        final ruby:RubyAnnotation = { fontSize: 9, ascent: Math.NaN, fontFamilies: [], text: "注", fontWeight: 600, centerX: 0, baselineY: 100 };
        final node = Evidence.rubyAnnotationSpan(ruby, 80, new DeclarationLengthStyleClass());
        TracedAssertions.assertEqualsString("<span class=\"tqc-233\" data-tq-geometry=\"true\" data-tq-src=\"（注）\">注</span>", node.html, "ruby fallback html");
        TracedAssertions.assertEqualsString("[\"span\",[[\"class\",\"tqc-233\"],[\"data-tq-geometry\",\"true\"],[\"data-tq-src\",\"（注）\"]],[[\"#\",\"注\"]]]", PreparedDomTestSupport.artifactToJson(node.artifact), "ruby fallback artifact");
    }

    @:test
    public static function bopomofoAnnotationSpanMatchesTs():Void {
        final zone = EvidenceTestSupport.bopomofoZone();
        final node = Evidence.bopomofoAnnotationSpan(zone, 9.5, 20, 13.5, null);
        TracedAssertions.assertEqualsString("<span data-tq-geometry=\"true\" data-tq-src=\"（ㄅㄚ）\" lang=\"zh-Hant-TW\" style=\"box-sizing:border-box!important;display:inline-block!important;height:13.5px!important;line-height:13.5px!important;overflow:visible!important;position:relative!important;user-select:all!important;vertical-align:top!important;-webkit-user-select:all!important;white-space:pre!important;width:9.5px!important\"><span data-tq-geometry=\"true\" lang=\"zh-Hant-TW\" style=\"color:currentColor!important;font-family:&quot;Bopomofo Font&quot;!important;font-feature-settings:'vert' 1, 'vrt2' 1!important;font-size:9px!important;font-style:normal!important;font-weight:700!important;left:1px!important;line-height:9px!important;overflow:visible!important;pointer-events:none!important;position:absolute!important;top:0px!important;white-space:pre!important;display:inline-block!important;text-orientation:upright!important;writing-mode:vertical-rl!important\">ㄅ</span><span data-tq-geometry=\"true\" lang=\"zh-Hant-TW\" style=\"color:currentColor!important;font-family:&quot;Bopomofo Font&quot;!important;font-feature-settings:'vert' 1, 'vrt2' 1!important;font-size:10.82111px!important;font-style:normal!important;font-weight:700!important;left:3.5px!important;line-height:9px!important;overflow:visible!important;pointer-events:none!important;position:absolute!important;top:10.33944px!important;white-space:pre!important;display:inline-block!important;text-orientation:upright!important;writing-mode:vertical-rl!important\">ˇ</span><span data-tq-geometry=\"true\" lang=\"zh-Hant-TW\" style=\"color:currentColor!important;font-family:&quot;Bopomofo Font&quot;!important;font-feature-settings:'vert' 1, 'vrt2' 1!important;font-size:9px!important;font-style:normal!important;font-weight:700!important;left:1px!important;line-height:9px!important;overflow:visible!important;pointer-events:none!important;position:absolute!important;top:22.5px!important;white-space:pre!important;display:inline-block!important;text-orientation:upright!important;writing-mode:vertical-rl!important\">ㄚ</span></span>", node.html, "bopomofo zone html");
        TracedAssertions.assertEqualsString("[\"span\",[[\"data-tq-geometry\",\"true\"],[\"data-tq-src\",\"（ㄅㄚ）\"],[\"lang\",\"zh-Hant-TW\"],[\"style\",\"box-sizing:border-box!important;display:inline-block!important;height:13.5px!important;line-height:13.5px!important;overflow:visible!important;position:relative!important;user-select:all!important;vertical-align:top!important;-webkit-user-select:all!important;white-space:pre!important;width:9.5px!important\"]],[[\"span\",[[\"data-tq-geometry\",\"true\"],[\"lang\",\"zh-Hant-TW\"],[\"style\",\"color:currentColor!important;font-family:\\\"Bopomofo Font\\\"!important;font-feature-settings:'vert' 1, 'vrt2' 1!important;font-size:9px!important;font-style:normal!important;font-weight:700!important;left:1px!important;line-height:9px!important;overflow:visible!important;pointer-events:none!important;position:absolute!important;top:0px!important;white-space:pre!important;display:inline-block!important;text-orientation:upright!important;writing-mode:vertical-rl!important\"]],[[\"#\",\"ㄅ\"]]],[\"span\",[[\"data-tq-geometry\",\"true\"],[\"lang\",\"zh-Hant-TW\"],[\"style\",\"color:currentColor!important;font-family:\\\"Bopomofo Font\\\"!important;font-feature-settings:'vert' 1, 'vrt2' 1!important;font-size:10.82111px!important;font-style:normal!important;font-weight:700!important;left:3.5px!important;line-height:9px!important;overflow:visible!important;pointer-events:none!important;position:absolute!important;top:10.33944px!important;white-space:pre!important;display:inline-block!important;text-orientation:upright!important;writing-mode:vertical-rl!important\"]],[[\"#\",\"ˇ\"]]],[\"span\",[[\"data-tq-geometry\",\"true\"],[\"lang\",\"zh-Hant-TW\"],[\"style\",\"color:currentColor!important;font-family:\\\"Bopomofo Font\\\"!important;font-feature-settings:'vert' 1, 'vrt2' 1!important;font-size:9px!important;font-style:normal!important;font-weight:700!important;left:1px!important;line-height:9px!important;overflow:visible!important;pointer-events:none!important;position:absolute!important;top:22.5px!important;white-space:pre!important;display:inline-block!important;text-orientation:upright!important;writing-mode:vertical-rl!important\"]],[[\"#\",\"ㄚ\"]]]]]", PreparedDomTestSupport.artifactToJson(node.artifact), "bopomofo zone artifact");
    }

    @:test
    public static function bopomofoAnnotationSpanClassModeMatchesTs():Void {
        final zone = EvidenceTestSupport.bopomofoZone();
        final node = Evidence.bopomofoAnnotationSpan(zone, 9.5, 20, 13.5, new DeclarationLengthStyleClass());
        TracedAssertions.assertEqualsString("<span class=\"tqc-307\" data-tq-geometry=\"true\" data-tq-src=\"（ㄅㄚ）\" lang=\"zh-Hant-TW\"><span class=\"tqc-470\" data-tq-geometry=\"true\" lang=\"zh-Hant-TW\">ㄅ</span><span class=\"tqc-486\" data-tq-geometry=\"true\" lang=\"zh-Hant-TW\">ˇ</span><span class=\"tqc-473\" data-tq-geometry=\"true\" lang=\"zh-Hant-TW\">ㄚ</span></span>", node.html, "bopomofo class html");
        TracedAssertions.assertEqualsString("[\"span\",[[\"class\",\"tqc-307\"],[\"data-tq-geometry\",\"true\"],[\"data-tq-src\",\"（ㄅㄚ）\"],[\"lang\",\"zh-Hant-TW\"]],[[\"span\",[[\"class\",\"tqc-470\"],[\"data-tq-geometry\",\"true\"],[\"lang\",\"zh-Hant-TW\"]],[[\"#\",\"ㄅ\"]]],[\"span\",[[\"class\",\"tqc-486\"],[\"data-tq-geometry\",\"true\"],[\"lang\",\"zh-Hant-TW\"]],[[\"#\",\"ˇ\"]]],[\"span\",[[\"class\",\"tqc-473\"],[\"data-tq-geometry\",\"true\"],[\"lang\",\"zh-Hant-TW\"]],[[\"#\",\"ㄚ\"]]]]]", PreparedDomTestSupport.artifactToJson(node.artifact), "bopomofo class artifact");
    }

    @:test
    public static function appendEvidenceOverlaysMatchesTs():Void {
        final nodes:Array<MarkupNode> = [Markup.renderedText("x")];
        final options:EvidenceOverlayOptions = { emphasisDotColor: new ClusterThreeDotColor() };
        Evidence.appendEvidenceOverlays(nodes, EvidenceTestSupport.overlayPlan(), options);
        TracedAssertions.assertEqualsInt(3, nodes.length, "overlay node count");
        TracedAssertions.assertEqualsString("<svg aria-hidden=\"true\" data-tq-copy-ignore=\"true\" data-tq-geometry=\"true\" style=\"--tq-overlay-width:200px;--tq-overlay-height:20px\"><line data-tq-decoration-line=\"true\" stroke=\"currentColor\" stroke-linecap=\"butt\" stroke-width=\"1.28\" style=\"--tq-decoration-color:currentColor;--tq-decoration-stroke-width:1.28px\" x1=\"1\" x2=\"40\" y1=\"18.5\" y2=\"18.5\"></line><path d=\"M 50 18.5 Q 51.6 16.58 53.2 18.5 Q 54.800000000000004 20.42 56.400000000000006 18.5 Q 58.00000000000001 16.58 59.60000000000001 18.5 Q 61.20000000000001 20.42 62.80000000000001 18.5 Q 64.4 16.58 66.00000000000001 18.5 Q 67.60000000000002 20.42 69.20000000000002 18.5 Q 70.80000000000001 16.58 72.40000000000002 18.5 Q 74.00000000000003 20.42 75.60000000000002 18.5 Q 77.20000000000002 16.58 78.80000000000003 18.5 Q 80.40000000000003 20.42 82.00000000000003 18.5 Q 83.60000000000002 16.58 85.20000000000003 18.5 Q 86.80000000000004 20.42 88.40000000000003 18.5 Q 90.00000000000003 16.58 91.60000000000004 18.5 Q 93.20000000000005 20.42 94.80000000000004 18.5 Q 96.40000000000003 16.58 98.00000000000004 18.5 Q 99.60000000000005 20.42 101.20000000000005 18.5 Q 102.80000000000004 16.58 104.40000000000005 18.5 Q 106.00000000000006 20.42 107.60000000000005 18.5 Q 109.20000000000005 16.58 110.80000000000005 18.5 Q 112.40000000000006 20.42 114.00000000000006 18.5 Q 115.60000000000005 16.58 117.20000000000006 18.5 Q 118.72500000000002 20.42 120.25 18.5\" data-tq-decoration-wave=\"true\" fill=\"none\" stroke=\"currentColor\" stroke-linecap=\"butt\" stroke-linejoin=\"round\" stroke-width=\"1.28\" style=\"--tq-decoration-color:currentColor;--tq-decoration-stroke-width:1.28px\"></path></svg>", nodes[1].html, "decoration overlay html");
        TracedAssertions.assertEqualsString("[\"svg\",[[\"aria-hidden\",\"true\"],[\"data-tq-copy-ignore\",\"true\"],[\"data-tq-geometry\",\"true\"],[\"style\",\"--tq-overlay-width:200px;--tq-overlay-height:20px\"]],[[\"line\",[[\"data-tq-decoration-line\",\"true\"],[\"stroke\",\"currentColor\"],[\"stroke-linecap\",\"butt\"],[\"stroke-width\",\"1.28\"],[\"style\",\"--tq-decoration-color:currentColor;--tq-decoration-stroke-width:1.28px\"],[\"x1\",\"1\"],[\"x2\",\"40\"],[\"y1\",\"18.5\"],[\"y2\",\"18.5\"]],[]],[\"path\",[[\"d\",\"M 50 18.5 Q 51.6 16.58 53.2 18.5 Q 54.800000000000004 20.42 56.400000000000006 18.5 Q 58.00000000000001 16.58 59.60000000000001 18.5 Q 61.20000000000001 20.42 62.80000000000001 18.5 Q 64.4 16.58 66.00000000000001 18.5 Q 67.60000000000002 20.42 69.20000000000002 18.5 Q 70.80000000000001 16.58 72.40000000000002 18.5 Q 74.00000000000003 20.42 75.60000000000002 18.5 Q 77.20000000000002 16.58 78.80000000000003 18.5 Q 80.40000000000003 20.42 82.00000000000003 18.5 Q 83.60000000000002 16.58 85.20000000000003 18.5 Q 86.80000000000004 20.42 88.40000000000003 18.5 Q 90.00000000000003 16.58 91.60000000000004 18.5 Q 93.20000000000005 20.42 94.80000000000004 18.5 Q 96.40000000000003 16.58 98.00000000000004 18.5 Q 99.60000000000005 20.42 101.20000000000005 18.5 Q 102.80000000000004 16.58 104.40000000000005 18.5 Q 106.00000000000006 20.42 107.60000000000005 18.5 Q 109.20000000000005 16.58 110.80000000000005 18.5 Q 112.40000000000006 20.42 114.00000000000006 18.5 Q 115.60000000000005 16.58 117.20000000000006 18.5 Q 118.72500000000002 20.42 120.25 18.5\"],[\"data-tq-decoration-wave\",\"true\"],[\"fill\",\"none\"],[\"stroke\",\"currentColor\"],[\"stroke-linecap\",\"butt\"],[\"stroke-linejoin\",\"round\"],[\"stroke-width\",\"1.28\"],[\"style\",\"--tq-decoration-color:currentColor;--tq-decoration-stroke-width:1.28px\"]],[]]]]", PreparedDomTestSupport.artifactToJson(nodes[1].artifact), "decoration overlay artifact");
        TracedAssertions.assertEqualsString("<svg aria-hidden=\"true\" data-tq-copy-ignore=\"true\" data-tq-geometry=\"true\" style=\"--tq-overlay-width:200px;--tq-overlay-height:20px\"><circle cx=\"12.5\" cy=\"21\" data-tq-decoration-dot=\"true\" fill=\"rgb(17, 34, 51)\" r=\"1.5\" style=\"--tq-decoration-color:rgb(17, 34, 51)\"></circle><circle cx=\"30\" cy=\"21\" data-tq-decoration-dot=\"true\" fill=\"currentColor\" r=\"1.25\" style=\"--tq-decoration-color:currentColor\"></circle></svg>", nodes[2].html, "emphasis dot overlay html");
        TracedAssertions.assertEqualsString("[\"svg\",[[\"aria-hidden\",\"true\"],[\"data-tq-copy-ignore\",\"true\"],[\"data-tq-geometry\",\"true\"],[\"style\",\"--tq-overlay-width:200px;--tq-overlay-height:20px\"]],[[\"circle\",[[\"cx\",\"12.5\"],[\"cy\",\"21\"],[\"data-tq-decoration-dot\",\"true\"],[\"fill\",\"rgb(17, 34, 51)\"],[\"r\",\"1.5\"],[\"style\",\"--tq-decoration-color:rgb(17, 34, 51)\"]],[]],[\"circle\",[[\"cx\",\"30\"],[\"cy\",\"21\"],[\"data-tq-decoration-dot\",\"true\"],[\"fill\",\"currentColor\"],[\"r\",\"1.25\"],[\"style\",\"--tq-decoration-color:currentColor\"]],[]]]]", PreparedDomTestSupport.artifactToJson(nodes[2].artifact), "emphasis dot overlay artifact");
    }

    @:test
    public static function appendEvidenceOverlaysPlainDotsMatchesTs():Void {
        final nodes:Array<MarkupNode> = [Markup.renderedText("x")];
        final options:EvidenceOverlayOptions = { emphasisDotColor: null };
        Evidence.appendEvidenceOverlays(nodes, EvidenceTestSupport.plainDotPlan(), options);
        TracedAssertions.assertEqualsInt(2, nodes.length, "plain dot node count");
        TracedAssertions.assertEqualsString("<svg aria-hidden=\"true\" data-tq-copy-ignore=\"true\" data-tq-geometry=\"true\" style=\"--tq-overlay-width:100px;--tq-overlay-height:20px\"><circle cx=\"4\" cy=\"9\" data-tq-decoration-dot=\"true\" fill=\"currentColor\" r=\"1.5\" style=\"--tq-decoration-color:currentColor\"></circle></svg>", nodes[1].html, "plain dot html");
        TracedAssertions.assertEqualsString("[\"svg\",[[\"aria-hidden\",\"true\"],[\"data-tq-copy-ignore\",\"true\"],[\"data-tq-geometry\",\"true\"],[\"style\",\"--tq-overlay-width:100px;--tq-overlay-height:20px\"]],[[\"circle\",[[\"cx\",\"4\"],[\"cy\",\"9\"],[\"data-tq-decoration-dot\",\"true\"],[\"fill\",\"currentColor\"],[\"r\",\"1.5\"],[\"style\",\"--tq-decoration-color:currentColor\"]],[]]]]", PreparedDomTestSupport.artifactToJson(nodes[1].artifact), "plain dot artifact");
    }

    @:test
    public static function appendEvidenceOverlaysEmptyPlanAppendsNothing():Void {
        final nodes:Array<MarkupNode> = [Markup.renderedText("x")];
        final options:EvidenceOverlayOptions = { emphasisDotColor: null };
        Evidence.appendEvidenceOverlays(nodes, EvidenceTestSupport.emptyPlan(), options);
        TracedAssertions.assertEqualsInt(1, nodes.length, "empty overlay node count");
    }

    @:test
    public static function appendEvidenceOverlaysInvalidGeometryThrows():Void {
        final nodes:Array<MarkupNode> = [Markup.renderedText("x")];
        final options:EvidenceOverlayOptions = { emphasisDotColor: null };
        var caught:PreparedDomException = null;
        try {
            Evidence.appendEvidenceOverlays(nodes, EvidenceTestSupport.invalidGeometryPlan(), options);
        } catch (e:PreparedDomException) {
            caught = e;
        }
        TracedAssertions.assertTrue(caught != null, "invalid overlay geometry throws");
        if (caught != null)
            TracedAssertions.assertEqualsString("InvalidPreparedOverlayGeometry", caught.message, "invalid overlay geometry message");
    }
}
