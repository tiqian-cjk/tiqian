package org.tiqian.shared.prepared_dom;

/**
 * Shared prepared-dom lowering (web/TS-only, research 5.4/5.5).
 *
 * data-tq attribute constants + class 生成 (snapshot tqv-N / runtime tqvr-key)
 * + spacing classification (preparedSpacing) + run signature lowering
 * (preparedFeatureSignature / preparedRenderFontSignature).
 * Byte-critical where noted: the artifact renderer replays these strings into
 * data-tq attributes, so each must match the TS oracle exactly.
 */
class PreparedDom {

    /** Root selector constant (prepared-dom.ts:312). */
    public static var ROOT_SELECTOR:String = "tiqian-prose, [data-tiqian-root]";
    /** Line-marker selector constant (prepared-dom.ts:311). */
    public static var LINE_MARKER_SELECTOR:String = "[data-tq-line-flow-width]";
    /** data-tq value-style scope attribute name (prepared-dom.ts:313). TODO(sh-1-handoff): sh-1 owns SnapshotValueStyle.VALUE_STYLE_SCOPE_ATTRIBUTE (arch/s2-sh-1 @ 7550d77c); switch to cross-package import and delete this local when sh-1 lands in this branch. */
    public static var VALUE_STYLE_SCOPE_ATTRIBUTE:String = "data-tq-value-style-scope";
    /** data-tq prepared-value-styles attribute name (prepared-dom.ts:314). TODO(sh-1-handoff): sh-1 owns SnapshotValueStyle.VALUE_STYLE_ELEMENT_ATTRIBUTE (arch/s2-sh-1 @ 7550d77c); switch to cross-package import and delete this local when sh-1 lands in this branch. */
    public static var VALUE_STYLE_ELEMENT_ATTRIBUTE:String = "data-tq-prepared-value-styles";
    /** data-tq live-semantic-index attribute name (prepared-dom.ts:315). */
    public static var LIVE_SEMANTIC_INDEX_ATTRIBUTE:String = "data-tq-live-semantic-index";
    /** Snapshot style owner sentinel (prepared-dom.ts:318). TODO(sh-1-handoff): sh-1 owns SnapshotValueStyle.SNAPSHOT_STYLE_OWNER (arch/s2-sh-1 @ 7550d77c); switch to cross-package import and delete this local when sh-1 lands in this branch. */
    public static var SNAPSHOT_STYLE_OWNER:String = "tiqian-snapshot-style-owner";
    /** Default locale fallback (prepared-dom.ts:310). */
    public static var DEFAULT_LOCALE:String = "zh-Hans";

    /** Merge tolerance / carrier visibility gate (prepared-dom.ts:303). */
    public static var SPACING_EPSILON:Float = 0.01;
    /** Arithmetic-dust zeroing threshold (prepared-dom.ts:308). */
    public static var SPACING_DUST_EPSILON:Float = 1e-6;
    /** Render flow epsilon (prepared-dom.ts:309). */
    public static var RENDER_FLOW_EPSILON_PX:Float = 0.01;

    /** 'tqv-' + base36(index) — snapshot value-style class (byte-critical). */
    public static function snapshotValueStyleClass(index:Int):String {
        return "tqv-" + base36(index);
    }

    /** 'tqvr-' + key — runtime value-style class. */
    public static function runtimeValueStyleClass(key:String):String {
        return "tqvr-" + key;
    }

    /**
     * Classify trailing gap into a spacing result (prepared-dom.ts:478).
     * Byte-critical: the kind string drives data-tq-advance / margin-right
     * lowering in renderRun, and px feeds the px() serializer.
     */
    public static function preparedSpacing(display:String, naturalWidth:Float, trailingGap:Float):PreparedSpacingResult {
        if (Math.abs(trailingGap) < SPACING_DUST_EPSILON) return { kind: "none", px: 0.0 };
        if (display.length == 1 && naturalWidth + trailingGap >= 0) {
            return { kind: "letter", px: trailingGap };
        }
        if (trailingGap < 0) return { kind: "overlap", px: trailingGap };
        return { kind: "trailing-letter", px: trailingGap };
    }

    /**
     * Feature-set replay signature (prepared-dom.ts:502). Null/absent folds to
     * the empty signature, mirroring Array.from(openTypeFeatures ?? [], String)
     * .join(","). Byte-critical: renderRun validates this against the open-type
     * feature set and writes data-tq-open-type-features.
     */
    public static function preparedFeatureSignature(openTypeFeatures:Null<Array<String>>):String {
        if (openTypeFeatures == null) return "";
        return openTypeFeatures.join(",");
    }

    /**
     * Render-font replay signature (prepared-dom.ts:506). Unit separator joins
     * the font families, mirroring Array.from(renderFontFamilies ?? [], String)
     * .join(""). Byte-critical: renderRun writes the projected families.
     */
    public static function preparedRenderFontSignature(renderFontFamilies:Array<String>):String {
        return renderFontFamilies.join("");
    }

    /**
     * Enum dispatch over the open-type feature signatures that carry a CSS
     * replay rule (prepared-dom.ts:500 Set). Table-driven per D1: any other
     * signature has no replay rule and must not be silently painted.
     */
    public static function isPreparedOpenTypeFeatureSignature(signature:String):Bool {
        return signature == "pwid,palt" || signature == "fwid";
    }

    /**
     * Merge eligibility (prepared-dom.ts:510). Byte-critical: the decision
     * changes the number of data-tq spans the artifact renderer emits.
     */
    public static function canMergePreparedRun(left:PreparedRunSignature, right:PreparedRunSignature):Bool {
        if (left.rangeEnd != right.rangeStart ||
            left.semanticSignature != right.semanticSignature ||
            left.shapingBoundary || right.shapingBoundary ||
            preparedFeatureSignature(left.openTypeFeatures) != preparedFeatureSignature(right.openTypeFeatures) ||
            preparedRenderFontSignature(left.renderFontFamilies) != preparedRenderFontSignature(right.renderFontFamilies) ||
            left.dashStrategy != null || right.dashStrategy != null ||
            left.styleSignature != right.styleSignature ||
            left.punctuationSignature != right.punctuationSignature ||
            left.italicEffect != right.italicEffect ||
            left.evidenceRenderFontFamily != right.evidenceRenderFontFamily) {
            return false;
        }
        if (left.spacing.kind == "none" && right.spacing.kind == "none") return true;
        return left.spacing.kind == "letter" && right.spacing.kind == "letter" &&
            Math.abs(left.spacing.px - right.spacing.px) < SPACING_EPSILON;
    }

    /**
     * Fold right into left in place (prepared-dom.ts:528). Byte-critical: the
     * concatenated source/display and summed geometry feed the single merged
     * span the renderer emits.
     */
    public static function mergePreparedRun(left:PreparedRunSignature, right:PreparedRunSignature):Void {
        left.rangeEnd = right.rangeEnd;
        left.source += right.source;
        left.display += right.display;
        left.naturalWidth += right.naturalWidth;
        left.trailingGap += right.trailingGap;
    }

    /**
     * Lower one prepared run to a render node (prepared-dom.ts:536). Builds the
     * attribute list with setAttribute (record collapse), applies dynamic style
     * classes, then constructs the markup node (renderedText / renderedElement /
     * renderedContainer). Returns a MarkupNode whose html and artifact match the
     * TS oracle byte-for-byte.
     */
    public static function renderRun(input:PreparedRunRenderInput, styleClassFor:Null<StyleClassResolver>):MarkupNode {
        final featureSignature = preparedFeatureSignature(input.openTypeFeatures);
        final renderFontFamilies = input.renderFontFamilies;
        final needsElement = input.shapingBoundary || featureSignature != ""
            || renderFontFamilies.length > 0 || input.source != input.display || input.spacing.kind != "none"
            || input.styleDelta != null || input.italicEffect || input.evidenceRenderFontFamily != null
            || input.dashStrategy != null || input.punctuationInkFloor != null;
        if (!needsElement) return Markup.renderedText(input.display);

        final attributes:Array<AttributeEntry> = [];
        final advance = input.spacing.kind == "letter" || input.spacing.kind == "trailing-letter"
            ? input.naturalWidth + input.trailingGap : input.naturalWidth;
        Markup.setAttribute(attributes, "data-tq-advance", "" + advance);
        Markup.setAttribute(attributes, "data-tq-geometry", "true");
        Markup.setAttribute(attributes, "data-tq-x", "" + input.drawX);
        if (input.shapingBoundary || featureSignature != "") {
            Markup.setAttribute(attributes, "data-tq-shaping-boundary", "");
        }
        if (featureSignature != "") {
            if (!isPreparedOpenTypeFeatureSignature(featureSignature)) {
                throw new PreparedDomException(UnsupportedOpenTypeFeatures(featureSignature));
            }
            Markup.setAttribute(attributes, "data-tq-open-type-features", featureSignature);
        }
        if (input.source != input.display) {
            Markup.setAttribute(attributes, "data-tq-src", input.source);
        }
        if (input.dashStrategy != null) {
            final dashStrategy:String = input.dashStrategy;
            Markup.setAttribute(attributes, "data-tq-dash-strategy", dashStrategy);
            Markup.setAttribute(attributes, "data-tq-dash-advance", "" + input.naturalWidth);
            if (input.evidenceRenderFontFamily != null) {
                final evidenceRenderFontFamily:String = input.evidenceRenderFontFamily;
                Markup.setAttribute(attributes, "data-tq-dash-font-family", evidenceRenderFontFamily);
            }
            if (input.resolvedFace != null) {
                final resolvedFace:String = input.resolvedFace;
                Markup.setAttribute(attributes, "data-tq-dash-face", resolvedFace);
            }
            if (input.glyphIds != null) {
                final glyphIds:String = input.glyphIds;
                Markup.setAttribute(attributes, "data-tq-dash-glyph-ids", glyphIds);
            }
            if (input.shapingEvidence != null) {
                final shapingEvidence:String = input.shapingEvidence;
                Markup.setAttribute(attributes, "data-tq-dash-evidence", shapingEvidence);
            }
            if (input.shapingLanguage != null) {
                final shapingLanguage:String = input.shapingLanguage;
                Markup.setAttribute(attributes, "lang", shapingLanguage);
            }
        }
        if (input.punctuationInkFloor != null) {
            final punctuationInkFloor:Float = input.punctuationInkFloor;
            Markup.setAttribute(attributes, "data-tq-punctuation-ink-floor", "" + punctuationInkFloor);
            if (input.punctuationBodyWidth != null) {
                final punctuationBodyWidth:Float = input.punctuationBodyWidth;
                Markup.setAttribute(attributes, "data-tq-punctuation-body-width", "" + punctuationBodyWidth);
            }
        }
        final styles:Array<String> = [];
        if (renderFontFamilies.length > 0) {
            Markup.setAttribute(attributes, "data-tq-render-font-projection", "true");
            styles.push("font-family:" + Markup.cssFamilyList(renderFontFamilies) + "!important");
        }
        if (input.evidenceRenderFontFamily != null) {
            Markup.setAttribute(attributes, "data-tq-render-font-projection", "true");
            final evidenceRenderFontFamily:String = input.evidenceRenderFontFamily;
            styles.push("font-family:" + Markup.cssString(evidenceRenderFontFamily) + "!important");
        }
        if (input.italicEffect && (input.styleDelta == null || input.styleDelta.italic != true)) {
            styles.push("font-style:italic!important");
        }
        if (input.styleDelta != null) {
            final styleDelta:StyleDelta = input.styleDelta;
            if (styleDelta.fontSize != null) {
                final fontSize:Float = styleDelta.fontSize;
                styles.push("font-size:" + Markup.px(fontSize) + "!important");
            }
            if (styleDelta.fontWeight != null) {
                final fontWeight:Float = styleDelta.fontWeight;
                styles.push("font-weight:" + fontWeight + "!important");
            }
            if (styleDelta.italic == true) {
                styles.push("font-style:italic!important");
            } else if (styleDelta.italic == false) {
                styles.push("font-style:normal!important");
            }
        }
        if (input.spacing.kind == "letter") {
            styles.push("letter-spacing:" + Markup.px(input.spacing.px) + "!important");
        } else if (input.spacing.kind == "overlap") {
            styles.push("margin-right:" + Markup.px(input.spacing.px) + "!important");
        }
        Markup.applyDynamicStyles(attributes, styles, styleClassFor);
        if (input.spacing.kind == "trailing-letter") {
            final container = Markup.renderedContainer("span", attributes);
            container.children.push(Markup.renderedText(input.display));
            final carrierEntries:Array<AttributeEntry> = [
                { name: "aria-hidden", value: "true" },
                { name: "data-tq-copy-ignore", value: "true" },
                { name: "data-tq-geometry", value: "true" },
                { name: "data-tq-spacing-carrier", value: "true" },
            ];
            final carrierStyles:Array<String> = [
                "display:inline-block!important",
                "inline-size:" + Markup.px(input.spacing.px) + "!important",
                "height:0!important",
                "line-height:0!important",
                "letter-spacing:" + Markup.px(input.spacing.px) + "!important",
                "overflow:hidden!important",
                "vertical-align:baseline!important",
                "white-space:pre!important",
            ];
            Markup.applyDynamicStyles(carrierEntries, carrierStyles, styleClassFor);
            container.children.push(Markup.renderedElement("span", carrierEntries, String.fromCharCode(160), false));
            return container;
        }
        return Markup.renderedElement("span", attributes, input.display, false);
    }

    /** Non-negative base-36 encoding matching JS Number.prototype.toString(36). */
    private static function base36(value:Int):String {
        if (value == 0) return "0";
        var s:String = "";
        var n:Int = value;
        while (n > 0) {
            var d:Int = n % 36;
            s = BASE36.charAt(d) + s;
            n = Std.int(n / 36);
        }
        return s;
    }

    private static var BASE36:String = "0123456789abcdefghijklmnopqrstuvwxyz";
}
