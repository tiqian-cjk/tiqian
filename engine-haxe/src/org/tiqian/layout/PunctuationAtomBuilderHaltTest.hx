package org.tiqian.layout;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import org.tiqian.clreq.PunctuationGluePlacement;
import org.tiqian.clreq.PunctuationWidthPolicy;
import org.tiqian.clreq.InteriorPunctuationStyle;
import org.tiqian.core.Rect;
import org.tiqian.core.TextRange;
import org.tiqian.layout.PunctuationModel.PunctuationAtomBuilder;
import org.tiqian.layout.PunctuationModel.PunctuationInkInput;
import org.tiqian.layout.PunctuationModel.PunctuationAtom;
import org.tiqian.layout.PunctuationModel.PunctuationAnchor;

class PunctuationAtomBuilderHaltTest {
    @:test public static function haltAdvanceWithoutPlacementUsesNamedProfileFallback():Void {
        PunctuationAtomBuilderHaltSupport.s("haltAdvanceWithoutPlacementUsesNamedProfileFallback");
        final a = PunctuationAtomBuilderHaltSupport.atom("。", new PunctuationInkInput(16, null, 7.5));
        PunctuationAtomBuilderHaltSupport.f(7.5, a.bodyWidth);
        PunctuationAtomBuilderHaltSupport.f(7.5, a.haltAdvance);
        PunctuationAtomBuilderHaltSupport.f(0, a.leadingGlue.natural);
        PunctuationAtomBuilderHaltSupport.f(8.5, a.trailingGlue.natural);
        PunctuationAtomBuilderHaltSupport.q("FontHaltAdvanceWithProfileFallback", a.geometrySource);
    }

    @:test public static function haltPlacementDirectlyDefinesBothCompressionSides():Void {
        PunctuationAtomBuilderHaltSupport.s("haltPlacementDirectlyDefinesBothCompressionSides");
        final a = PunctuationAtomBuilderHaltSupport.atom("（", new PunctuationInkInput(16, new Rect(5, -12, 11, 2), 8, -4));
        PunctuationAtomBuilderHaltSupport.f(4, a.leadingGlue.natural);
        PunctuationAtomBuilderHaltSupport.f(4, a.trailingGlue.natural);
        PunctuationAtomBuilderHaltSupport.f(8, a.bodyWidth);
        PunctuationAtomBuilderHaltSupport.r(Std.string(PunctuationAnchor.Center), Std.string(a.anchor));
        PunctuationAtomBuilderHaltSupport.q("FontHaltFittedBodyCompression", a.geometrySource);
        PunctuationAtomBuilderHaltSupport.nul(a.haltValidation);
    }

    @:test public static function haltPlacementOverridesRegionalProfileDirection():Void {
        PunctuationAtomBuilderHaltSupport.s("haltPlacementOverridesRegionalProfileDirection");
        final b = new PunctuationAtomBuilder(Traditional);
        final a = b.build("。", new TextRange(0, 1), PunctuationAtomBuilderHaltSupport.em, new PunctuationInkInput(16, new Rect(1, -4, 7, 1), 8, 0));
        PunctuationAtomBuilderHaltSupport.f(0, a.leadingGlue.natural);
        PunctuationAtomBuilderHaltSupport.f(8, a.trailingGlue.natural);
        PunctuationAtomBuilderHaltSupport.nul(a.haltValidation);
    }

    @:test public static function defaultInkCapsAHaltTrimThatWouldCutIntoThePaintedGlyph():Void {
        PunctuationAtomBuilderHaltSupport.s("defaultInkCapsAHaltTrimThatWouldCutIntoThePaintedGlyph");
        final a = PunctuationAtomBuilderHaltSupport.atom("（", new PunctuationInkInput(16, new Rect(2, -12, 15, 2), 8, -8));
        PunctuationAtomBuilderHaltSupport.f(2, a.leadingGlue.natural);
        PunctuationAtomBuilderHaltSupport.f(0, a.trailingGlue.natural);
        PunctuationAtomBuilderHaltSupport.f(14, a.bodyWidth);
        PunctuationAtomBuilderHaltSupport.q("halt-trim-limited-by-default-ink-bounds", a.haltValidation);
        TracedAssertions.assertTrue(a.inkContainmentApplied);
    }

    @:test public static function equalHaltAdvanceFallsThroughToInkBounds():Void {
        PunctuationAtomBuilderHaltSupport.s("equalHaltAdvanceFallsThroughToInkBounds");
        final a = PunctuationAtomBuilderHaltSupport.atom("，", new PunctuationInkInput(16, new Rect(6, -4, 10, 1), 16));
        PunctuationAtomBuilderHaltSupport.nul(a.haltAdvance);
        PunctuationAtomBuilderHaltSupport.f(4, a.leadingGlue.natural);
        PunctuationAtomBuilderHaltSupport.f(4, a.trailingGlue.natural);
        PunctuationAtomBuilderHaltSupport.q("InkBoundsFittedBodyCompression", a.geometrySource);
    }

    @:test public static function microsoftYaheiCentredCommaCompressesFromBothSides():Void {
        PunctuationAtomBuilderHaltSupport.s("microsoftYaheiCentredCommaCompressesFromBothSides");
        final a = PunctuationAtomBuilderHaltSupport.unit("，", 2048, 821, 1130);
        TracedAssertions.assertEqualsFloatTolerance(8, a.bodyWidth, .001);
        TracedAssertions.assertEqualsFloatTolerance(4, a.leadingGlue.natural, .01);
        TracedAssertions.assertEqualsFloatTolerance(4, a.trailingGlue.natural, .01);
        PunctuationAtomBuilderHaltSupport.r(Std.string(PunctuationAnchor.Center), Std.string(a.anchor));
        PunctuationAtomBuilderHaltSupport.f(0, a.glyphInlineShift);
    }

    @:test public static function microsoftYaheiBottomLeftStopKeepsItsLeadingSafetyMargin():Void {
        PunctuationAtomBuilderHaltSupport.s("microsoftYaheiBottomLeftStopKeepsItsLeadingSafetyMargin");
        final a = PunctuationAtomBuilderHaltSupport.unit("。", 2048, 131, 632);
        PunctuationAtomBuilderHaltSupport.f(8, a.bodyWidth);
        PunctuationAtomBuilderHaltSupport.f(0, a.leadingGlue.natural);
        PunctuationAtomBuilderHaltSupport.f(8, a.trailingGlue.natural);
        PunctuationAtomBuilderHaltSupport.r(Std.string(PunctuationAnchor.Leading), Std.string(a.anchor));
        PunctuationAtomBuilderHaltSupport.f(0, a.glyphInlineShift);
    }

    @:test public static function founderHeitiCentredParenthesesStayMirrorImages():Void {
        PunctuationAtomBuilderHaltSupport.s("founderHeitiCentredParenthesesStayMirrorImages");
        final o = PunctuationAtomBuilderHaltSupport.unit("（", 1000, 456, 647), c = PunctuationAtomBuilderHaltSupport.unit("）", 1000, 353, 544);
        TracedAssertions.assertEqualsFloatTolerance(o.leadingGlue.natural, c.trailingGlue.natural, .001);
        TracedAssertions.assertEqualsFloatTolerance(o.trailingGlue.natural, c.leadingGlue.natural, .001);
        TracedAssertions.assertTrue(o.leadingGlue.natural > 0 && o.trailingGlue.natural > 0);
        PunctuationAtomBuilderHaltSupport.f(0, o.glyphInlineShift);
        PunctuationAtomBuilderHaltSupport.f(0, c.glyphInlineShift);
    }

    @:test public static function underwidthOpeningQuoteCompletesTheLeadingSideOfItsFullWidthCell():Void {
        PunctuationAtomBuilderHaltSupport.s("underwidthOpeningQuoteCompletesTheLeadingSideOfItsFullWidthCell");
        final a = PunctuationAtomBuilderHaltSupport.atom("“", new PunctuationInkInput(6, new Rect(1, -10, 5, 0)));
        PunctuationAtomBuilderHaltSupport.f(16, a.advance);
        PunctuationAtomBuilderHaltSupport.f(10, a.advanceExpansion);
        TracedAssertions.assertEqualsFloatTolerance(8, a.bodyWidth, .001);
        PunctuationAtomBuilderHaltSupport.f(8, a.leadingGlue.natural);
        PunctuationAtomBuilderHaltSupport.f(0, a.trailingGlue.natural);
        PunctuationAtomBuilderHaltSupport.f(10, a.glyphInlineShift);
        PunctuationAtomBuilderHaltSupport.q("UnderwidthPunctuationFullWidthBoxPlacement", a.glyphPlacementReason);
    }

    @:test public static function fixedHalfConsumesMeasuredSidebearingsInsteadOfApplyingAProfileShift():Void {
        PunctuationAtomBuilderHaltSupport.s("fixedHalfConsumesMeasuredSidebearingsInsteadOfApplyingAProfileShift");
        final a = PunctuationAtomBuilderHaltSupport.builder.build("《", new TextRange(0, 1), PunctuationAtomBuilderHaltSupport.em,
            new PunctuationInkInput(16, new Rect(6.5, -12, 15.5, 2)), null, new PunctuationWidthPolicy(Kaiming));
        PunctuationAtomBuilderHaltSupport.f(16, a.advance);
        PunctuationAtomBuilderHaltSupport.f(9.5, a.bodyWidth);
        PunctuationAtomBuilderHaltSupport.f(6.5, a.leadingGlueInitiallyConsumed);
        PunctuationAtomBuilderHaltSupport.f(0, a.trailingGlueInitiallyConsumed);
        PunctuationAtomBuilderHaltSupport.f(0, a.glyphInlineShift);
        PunctuationAtomBuilderHaltSupport.q("InkBoundsFittedBodyCompressionFixedHalfWidth", a.geometrySource);
    }

    @:test public static function overhangReducesCompressionCapacityWithoutMovingInk():Void {
        PunctuationAtomBuilderHaltSupport.s("overhangReducesCompressionCapacityWithoutMovingInk");
        final a = PunctuationAtomBuilderHaltSupport.atom("《", new PunctuationInkInput(16, new Rect(6.5, -12, 17, 2)));
        PunctuationAtomBuilderHaltSupport.f(17, a.advance);
        PunctuationAtomBuilderHaltSupport.f(10.5, a.bodyWidth);
        PunctuationAtomBuilderHaltSupport.f(6.5, a.leadingGlue.natural);
        PunctuationAtomBuilderHaltSupport.f(0, a.trailingGlue.natural);
        PunctuationAtomBuilderHaltSupport.f(0, a.glyphInlineShift);
        TracedAssertions.assertTrue(a.inkContainmentApplied);
    }
}

/** Shared fixtures and traced-assertion helpers for PunctuationAtomBuilderHaltTest; the Kotlin test-class lowering admits test functions only. */
class PunctuationAtomBuilderHaltSupport {
    public static final builder = new PunctuationAtomBuilder();
    public static final em:Float = 16;

    public static function s(n:String):Void
        new TestTraceRecorder("PunctuationAtomBuilderHaltTest").section(n);

    public static function f(e:Float, a:Float):Void
        TracedAssertions.assertEqualsFloat(e, a);

    public static function q(e:String, a:String):Void
        TracedAssertions.assertEqualsString(e, a);

    public static function r(e:String, a:String):Void
        TracedAssertions.assertEqualsRendered(e, a);

    public static function nul<T>(v:Null<T>):Void
        TracedAssertions.assertNullRendered(v == null, "-");

    public static function atom(c:String, ?input:Null<PunctuationInkInput>):Null<PunctuationAtom>
        return builder.build(c, new TextRange(0, 1), em, input);

    public static function unit(c:String, u:Float, l:Float, rr:Float):Null<PunctuationAtom>
        return atom(c, new PunctuationInkInput(em, new Rect(l / u * em, -12, rr / u * em, 2)));
}
