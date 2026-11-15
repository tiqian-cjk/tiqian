package org.tiqian.shared.prepared_dom;

/**
 * Render-evidence lowering (ADR 0053 SinglePlanLowerer step 2), ported from
 * prepared-dom-evidence.ts: annotation spans, inline-object placeholders and
 * SVG overlays built purely from the prepared plan evidence fields.
 *
 * Attribute keys travel as AttributeEntry because data-tq-* keys contain
 * hyphens and "class" is a reserved word (D1 table-driven model). Every
 * numeric string uses the generated string-plus-value form, which is JS
 * Number::toString and therefore byte-identical to the TS oracle.
 *
 * Two oracle behaviours are spelled out here because the typed model differs
 * from the TS record: a null attribute value in TS is simply not pushed
 * (renderedElement filters null), and the emphasis-dot resolver null return is
 * normalised to the empty string by the glue, which the truthiness fallback
 * to currentColor treats the same way.
 */
class Evidence {

    public static var SPACING_EPSILON:Float = 0.01;
    public static var RUBY_ASCENT_RATIO:Float = 0.8;
    public static var BOPOMOFO_LANG:String = "zh-Hant-TW";
    public static var BOPOMOFO_TONE_TARGET_INK_WIDTH_SCALE:Float = 0.82;
    public static var BOPOMOFO_TONE_SLASH_INK_WIDTH_EM_REGULAR:Float = 0.404;
    public static var BOPOMOFO_TONE_SLASH_INK_WIDTH_EM_SEMIBOLD:Float = 0.446;
    public static var BOPOMOFO_TONE_CARON_INK_WIDTH_EM_REGULAR:Float = 0.644;
    public static var BOPOMOFO_TONE_CARON_INK_WIDTH_EM_SEMIBOLD:Float = 0.682;
    public static var LINE_THICKNESS_EM:Float = 0.08;
    public static var WAVY_HALF_WAVE_EM:Float = 0.2;
    public static var WAVY_AMPLITUDE_EM:Float = 0.06;
    public static var WAVY_ENDPOINT_EPSILON_PX:Float = 0.01;

    /**
     * Pending inline-object placeholder (prepared-dom-evidence.ts:103). The
     * trailing margin attribute exists only in the margin branch, mirroring
     * appendInlineObject spacing gate.
     */
    public static function inlineObjectPlaceholder(cell:InlineObjectPlaceholderCell, trailingGap:Float, styleClassFor:Null<StyleClassResolver>):MarkupNode {
        final carriesTrailingMargin = Math.abs(trailingGap) >= SPACING_EPSILON;
        final attributes:Array<AttributeEntry> = [];
        Markup.setAttribute(attributes, "data-tq-advance", "" + cell.naturalWidth);
        Markup.setAttribute(attributes, "data-tq-geometry", "true");
        Markup.setAttribute(attributes, "data-tq-inline-object", "pending");
        Markup.setAttribute(attributes, "data-tq-object-range", "" + cell.rangeStart + "-" + cell.rangeEnd);
        if (carriesTrailingMargin)
            Markup.setAttribute(attributes, "data-tq-object-trailing-margin", "" + trailingGap);
        Markup.setAttribute(attributes, "data-tq-x", "" + cell.drawX);
        final styles:Array<String> = [
            "display:inline-block!important",
            "box-sizing:border-box!important",
            "inline-size:" + Markup.px(cell.naturalWidth) + "!important"
        ];
        if (carriesTrailingMargin)
            styles.push("margin-right:" + Markup.px(trailingGap) + "!important");
        Markup.applyDynamicStyles(attributes, styles, styleClassFor);
        return Markup.renderedElement("span", attributes, null, false);
    }

    /**
     * Ruby annotation span (prepared-dom-evidence.ts:128). RubyPlanAscent: the
     * plan carries the declared ascent of the annotation face;
     * RubyAscentRatioFallback keeps the earlier behaviour for plans built
     * before that field existed.
     */
    public static function rubyAnnotationSpan(ruby:RubyAnnotation, lineTop:Float, styleClassFor:Null<StyleClassResolver>):MarkupNode {
        final fontSize = ruby.fontSize;
        final planAscent = ruby.ascent;
        final ascent = Math.isFinite(planAscent) ? planAscent : fontSize * RUBY_ASCENT_RATIO;
        final families = ruby.fontFamilies;
        final attributes:Array<AttributeEntry> = [];
        Markup.setAttribute(attributes, "data-tq-geometry", "true");
        Markup.setAttribute(attributes, "data-tq-src", "（" + ruby.text + "）");
        final styles:Array<String> = ["color:currentColor!important"];
        if (families.length > 0)
            styles.push("font-family:" + Markup.cssFamilyList(families) + "!important");
        styles.push("font-size:" + Markup.px(fontSize) + "!important");
        styles.push("font-weight:" + ruby.fontWeight + "!important");
        styles.push("left:" + Markup.px(ruby.centerX) + "!important");
        styles.push("line-height:1!important");
        styles.push("position:absolute!important");
        styles.push("top:" + Markup.px(ruby.baselineY - lineTop - ascent) + "!important");
        styles.push("transform:translateX(-50%)!important");
        styles.push("white-space:pre!important");
        Markup.applyDynamicStyles(attributes, styles, styleClassFor);
        return Markup.renderedElement("span", attributes, ruby.text, false);
    }

    /**
     * Bopomofo annotation zone (prepared-dom-evidence.ts:215): one container
     * per zone with one absolutely positioned span per placement.
     */
    public static function bopomofoAnnotationSpan(zone:BopomofoZone, width:Float, lineTop:Float, lineHeight:Float, styleClassFor:Null<StyleClassResolver>):RenderedMarkupContainer {
        final fontWeight = zone.fontWeight;
        final families = zone.fontFamilies;
        final placements = zone.placements;
        final attributes:Array<AttributeEntry> = [];
        Markup.setAttribute(attributes, "data-tq-geometry", "true");
        Markup.setAttribute(attributes, "data-tq-src", "（" + zone.text + "）");
        Markup.setAttribute(attributes, "lang", BOPOMOFO_LANG);
        final styles:Array<String> = [
            "box-sizing:border-box!important",
            "display:inline-block!important",
            "height:" + Markup.px(lineHeight) + "!important",
            "line-height:" + Markup.px(lineHeight) + "!important",
            "overflow:visible!important",
            "position:relative!important",
            "user-select:all!important",
            "vertical-align:top!important",
            "-webkit-user-select:all!important",
            "white-space:pre!important",
            "width:" + Markup.px(width) + "!important"
        ];
        Markup.applyDynamicStyles(attributes, styles, styleClassFor);
        final container = Markup.renderedContainer("span", attributes);
        final zoneLeft = bopomofoZoneLeft(placements);
        var i = 0;
        while (i < placements.length) {
            final placement = placements[i];
            final text = placement.text;
            final css = bopomofoCssPlacement(text, placement.role, fontWeight, placement.left, placement.top, placement.width, placement.height);
            final glyphAttributes:Array<AttributeEntry> = [];
            Markup.setAttribute(glyphAttributes, "data-tq-geometry", "true");
            Markup.setAttribute(glyphAttributes, "lang", BOPOMOFO_LANG);
            final glyphStyles:Array<String> = ["color:currentColor!important"];
            if (families.length > 0)
                glyphStyles.push("font-family:" + Markup.cssFamilyList(families) + "!important");
            glyphStyles.push("font-feature-settings:'vert' 1, 'vrt2' 1!important");
            glyphStyles.push("font-size:" + Markup.px(css.fontSize) + "!important");
            glyphStyles.push("font-style:normal!important");
            glyphStyles.push("font-weight:" + fontWeight + "!important");
            glyphStyles.push("left:" + Markup.px(css.left - zoneLeft) + "!important");
            glyphStyles.push("line-height:" + Markup.px(css.lineHeight) + "!important");
            glyphStyles.push("overflow:visible!important");
            glyphStyles.push("pointer-events:none!important");
            glyphStyles.push("position:absolute!important");
            glyphStyles.push("top:" + Markup.px(css.top - lineTop) + "!important");
            glyphStyles.push("white-space:pre!important");
            glyphStyles.push("display:inline-block!important");
            glyphStyles.push("text-orientation:upright!important");
            glyphStyles.push("writing-mode:vertical-rl!important");
            Markup.applyDynamicStyles(glyphAttributes, glyphStyles, styleClassFor);
            container.children.push(Markup.renderedElement("span", glyphAttributes, text, false));
            i += 1;
        }
        return container;
    }

    /**
     * Appends the engine-owned interlinear and emphasis overlays after the flow
     * content (prepared-dom-evidence.ts:313). Mutates nodes in place, matching
     * the TS oracle.
     */
    public static function appendEvidenceOverlays(nodes:Array<MarkupNode>, plan:EvidenceOverlayPlan, options:EvidenceOverlayOptions):Void {
        final segments:Array<EvidenceDecorationSegment> = plan.decorationSegments == null ? [] : plan.decorationSegments;
        final dots:Array<EvidenceEmphasisDot> = plan.emphasisDots == null ? [] : plan.emphasisDots;
        final emphasisDotColor = options.emphasisDotColor;
        if (segments.length > 0) {
            final fontSize = plan.fontSize;
            final width = plan.overlayWidth;
            final height = plan.height;
            if (!Math.isFinite(fontSize) || !Math.isFinite(width) || !Math.isFinite(height))
                throw new PreparedDomException(InvalidPreparedOverlayGeometry);
            final strokeWidth = fontSize * LINE_THICKNESS_EM;
            final svg = Markup.renderedContainer("svg", overlayAttributes(width, height));
            var i = 0;
            while (i < segments.length) {
                final segment = segments[i];
                final left = segment.left;
                final top = segment.top;
                final right = segment.right;
                final style = "--tq-decoration-color:currentColor;--tq-decoration-stroke-width:" + Markup.px(strokeWidth);
                switch (segment.kind) {
                    case ProperNoun:
                        svg.children.push(decorationLine(left, top, right, strokeWidth, style));
                    case BookTitle:
                        svg.children.push(decorationWave(left, top, right, fontSize, strokeWidth, style));
                }
                i += 1;
            }
            nodes.push(svg);
        }
        if (dots.length > 0) {
            final width = plan.overlayWidth;
            final height = plan.height;
            if (!Math.isFinite(width) || !Math.isFinite(height))
                throw new PreparedDomException(InvalidPreparedOverlayGeometry);
            final svg = Markup.renderedContainer("svg", overlayAttributes(width, height));
            var j = 0;
            while (j < dots.length) {
                final dot = dots[j];
                final color = emphasisDotColor == null ? "" : emphasisDotColor.resolve(dot.clusterRangeStart);
                final dotColor = color.length == 0 ? "currentColor" : color;
                final circleEntries:Array<AttributeEntry> = [];
                Markup.setAttribute(circleEntries, "cx", "" + dot.anchorX);
                Markup.setAttribute(circleEntries, "cy", "" + dot.anchorY);
                Markup.setAttribute(circleEntries, "data-tq-decoration-dot", "true");
                Markup.setAttribute(circleEntries, "fill", dotColor);
                Markup.setAttribute(circleEntries, "r", "" + (dot.dotDiameter / 2));
                Markup.setAttribute(circleEntries, "style", "--tq-decoration-color:" + dotColor);
                svg.children.push(Markup.renderedElement("circle", circleEntries, null, false));
                j += 1;
            }
            nodes.push(svg);
        }
    }

    /** Straight interlinear line under a proper noun (prepared-dom-evidence.ts:336). */
    private static function decorationLine(left:Float, top:Float, right:Float, strokeWidth:Float, style:String):MarkupNode {
        final entries:Array<AttributeEntry> = [];
        Markup.setAttribute(entries, "data-tq-decoration-line", "true");
        Markup.setAttribute(entries, "stroke", "currentColor");
        Markup.setAttribute(entries, "style", style);
        Markup.setAttribute(entries, "stroke-linecap", "butt");
        Markup.setAttribute(entries, "stroke-width", "" + strokeWidth);
        Markup.setAttribute(entries, "x1", "" + left);
        Markup.setAttribute(entries, "x2", "" + right);
        Markup.setAttribute(entries, "y1", "" + top);
        Markup.setAttribute(entries, "y2", "" + top);
        return Markup.renderedElement("line", entries, null, false);
    }

    /** Wavy interlinear line under a book title (prepared-dom-evidence.ts:347). */
    private static function decorationWave(left:Float, top:Float, right:Float, fontSize:Float, strokeWidth:Float, style:String):MarkupNode {
        final entries:Array<AttributeEntry> = [];
        Markup.setAttribute(entries, "data-tq-decoration-wave", "true");
        Markup.setAttribute(entries, "d", wavyLinePath(left, right, top, fontSize));
        Markup.setAttribute(entries, "fill", "none");
        Markup.setAttribute(entries, "stroke", "currentColor");
        Markup.setAttribute(entries, "style", style);
        Markup.setAttribute(entries, "stroke-linecap", "butt");
        Markup.setAttribute(entries, "stroke-linejoin", "round");
        Markup.setAttribute(entries, "stroke-width", "" + strokeWidth);
        return Markup.renderedElement("path", entries, null, false);
    }

    /** Tone-glyph ink width interpolation (prepared-dom-evidence.ts:163). */
    private static function bopomofoToneInkWidthEm(text:String, fontWeight:Float):Float {
        final caron = text == "ˇ";
        final regular = caron ? BOPOMOFO_TONE_CARON_INK_WIDTH_EM_REGULAR : BOPOMOFO_TONE_SLASH_INK_WIDTH_EM_REGULAR;
        final semibold = caron ? BOPOMOFO_TONE_CARON_INK_WIDTH_EM_SEMIBOLD : BOPOMOFO_TONE_SLASH_INK_WIDTH_EM_SEMIBOLD;
        final t = Math.min(Math.max((fontWeight - 400) / 300, 0), 1);
        return regular + (semibold - regular) * t;
    }

    /** Placement box to CSS values (prepared-dom-evidence.ts:174). */
    private static function bopomofoCssPlacement(text:String, role:String, fontWeight:Float, boxLeft:Float, boxTop:Float, boxWidth:Float, boxHeight:Float):BopomofoPlacementCss {
        if (role == "Symbol")
            return { left: boxLeft, top: boxTop, fontSize: boxHeight, lineHeight: boxWidth };
        if (role == "Neutral") {
            final neutralFontSize = boxWidth;
            return {
                left: boxLeft,
                top: boxTop + (boxHeight - neutralFontSize) / 2,
                fontSize: neutralFontSize,
                lineHeight: boxWidth
            };
        }
        final inkWidthEm = Math.max(bopomofoToneInkWidthEm(text, fontWeight), 0.1);
        final toneFontSize = boxWidth * BOPOMOFO_TONE_TARGET_INK_WIDTH_SCALE / inkWidthEm;
        return {
            left: boxLeft,
            top: boxTop + (boxHeight - toneFontSize) / 2,
            fontSize: toneFontSize,
            lineHeight: boxWidth
        };
    }

    /** Zone origin of the glyph spans (prepared-dom-evidence.ts:208). */
    private static function bopomofoZoneLeft(placements:Array<BopomofoPlacement>):Float {
        var i = 0;
        while (i < placements.length) {
            if (placements[i].role == "Symbol")
                return placements[i].left - placements[i].width / 9;
            i += 1;
        }
        if (placements.length == 0)
            return 0;
        var min = placements[0].left;
        var j = 1;
        while (j < placements.length) {
            if (placements[j].left < min)
                min = placements[j].left;
            j += 1;
        }
        return min;
    }

    /** Book-title wavy path (prepared-dom-evidence.ts:285). */
    private static function wavyLinePath(left:Float, right:Float, y:Float, fontSize:Float):String {
        final halfWave = Math.max(fontSize * WAVY_HALF_WAVE_EM, 1);
        final amplitude = fontSize * WAVY_AMPLITUDE_EM;
        var out = "M " + left + " " + y;
        var x = left;
        var up = true;
        while (x < right - WAVY_ENDPOINT_EPSILON_PX) {
            final rawNextX = x + halfWave;
            final nextX = rawNextX >= right - WAVY_ENDPOINT_EPSILON_PX ? right : rawNextX;
            final controlY = up ? y - amplitude * 2 : y + amplitude * 2;
            out += " Q " + ((x + nextX) / 2) + " " + controlY + " " + nextX + " " + y;
            x = nextX;
            up = !up;
        }
        return out;
    }

    /** Overlay svg attributes (prepared-dom-evidence.ts:302). */
    private static function overlayAttributes(width:Float, height:Float):Array<AttributeEntry> {
        final attributes:Array<AttributeEntry> = [];
        Markup.setAttribute(attributes, "aria-hidden", "true");
        Markup.setAttribute(attributes, "data-tq-copy-ignore", "true");
        Markup.setAttribute(attributes, "data-tq-geometry", "true");
        Markup.setAttribute(attributes, "style", "--tq-overlay-width:" + Markup.px(width) + ";--tq-overlay-height:" + Markup.px(height));
        return attributes;
    }
}
