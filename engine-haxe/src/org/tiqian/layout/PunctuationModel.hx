package org.tiqian.layout;

using std.Functional;

import org.tiqian.clreq.ClreqPunctuationPolicies;
import org.tiqian.clreq.GlueSide;
import org.tiqian.clreq.PunctuationClass;
import org.tiqian.clreq.PunctuationGluePlacement;
import org.tiqian.clreq.PunctuationGluePlacements;
import org.tiqian.clreq.PunctuationWidthPolicy;
import org.tiqian.core.Rect;
import org.tiqian.core.TextRange;
import org.tiqian.core.TiqianIllegalArgumentException;
import org.tiqian.core.TextRangeError;

@:dataClass
class PunctuationAtom {
    public final range:TextRange;
    public final char:String;
    public final punctuationClass:PunctuationClass;
    public final advance:Float;
    public final inkBounds:Null<Rect>;
    public final bodyWidth:Float;
    public final haltAdvance:Null<Float>;
    public final haltValidation:Null<String>;
    public final leadingGlue:Glue;
    public final trailingGlue:Glue;
    public final anchor:PunctuationAnchor;
    public final geometrySource:String;
    public final policyBodyFloor:Float;
    public final inkWidth:Null<Float>;
    public final inkCenter:Null<Float>;
    public final inkContainmentBodyFloor:Null<Float>;
    public final inkContainmentApplied:Bool;
    public final inkBoundsFallback:Null<String>;
    public final advanceExpansion:Float;
    public final glyphInlineShift:Float;
    public final glyphPlacementReason:Null<String>;
    public final leadingGlueInitiallyConsumed:Float;
    public final trailingGlueInitiallyConsumed:Float;

    public function new(range:TextRange, char:String, punctuationClass:PunctuationClass, advance:Float, inkBounds:Null<Rect>, bodyWidth:Float,
            ?haltAdvance:Null<Float>, ?haltValidation:Null<String>, leadingGlue:Glue, trailingGlue:Glue, anchor:PunctuationAnchor, geometrySource:String,
            policyBodyFloor:Float, inkWidth:Null<Float>, inkCenter:Null<Float>, inkContainmentBodyFloor:Null<Float>, inkContainmentApplied:Bool,
            inkBoundsFallback:Null<String>, advanceExpansion:Float, glyphInlineShift:Float, glyphPlacementReason:Null<String>,
            ?leadingGlueInitiallyConsumed:Null<Float>, ?trailingGlueInitiallyConsumed:Null<Float>) {
        this.range = range;
        this.char = char;
        this.punctuationClass = punctuationClass;
        this.advance = advance;
        this.inkBounds = inkBounds;
        this.bodyWidth = bodyWidth;
        this.haltAdvance = haltAdvance;
        this.haltValidation = haltValidation;
        this.leadingGlue = leadingGlue;
        this.trailingGlue = trailingGlue;
        this.anchor = anchor;
        this.geometrySource = geometrySource;
        this.policyBodyFloor = policyBodyFloor;
        this.inkWidth = inkWidth;
        this.inkCenter = inkCenter;
        this.inkContainmentBodyFloor = inkContainmentBodyFloor;
        this.inkContainmentApplied = inkContainmentApplied;
        this.inkBoundsFallback = inkBoundsFallback;
        this.advanceExpansion = advanceExpansion;
        this.glyphInlineShift = glyphInlineShift;
        this.glyphPlacementReason = glyphPlacementReason;
        this.leadingGlueInitiallyConsumed = leadingGlueInitiallyConsumed == null ? 0 : leadingGlueInitiallyConsumed;
        this.trailingGlueInitiallyConsumed = trailingGlueInitiallyConsumed == null ? 0 : trailingGlueInitiallyConsumed;
    }
}

@:dataClass
class PunctuationInkInput {
    public final advance:Float;
    public final inkBounds:Null<Rect>;
    public final haltAdvance:Null<Float>;
    public final haltPlacementX:Null<Float>;
    public final boundsFallbackReason:Null<String>;

    public function new(advance:Float, ?inkBounds:Null<Rect>, ?haltAdvance:Null<Float>, ?haltPlacementX:Null<Float>, ?boundsFallbackReason:Null<String>) {
        this.advance = advance;
        this.inkBounds = inkBounds;
        this.haltAdvance = haltAdvance;
        this.haltPlacementX = haltPlacementX;
        this.boundsFallbackReason = boundsFallbackReason;
    }
}

enum PunctuationAnchor {
    Leading;
    Center;
    Trailing;
}

@:dataClass
class Glue {
    public final kind:GlueKind;
    public final min:Float;
    public final natural:Float;
    public final max:Float;
    public final priority:Int;
    public final penalty:Int;

    public function new(kind:GlueKind, min:Float, natural:Float, max:Float, priority:Int, penalty:Int) {
        if (min > natural)
            throw new TiqianIllegalArgumentException(Message("Glue min must not exceed natural."));
        if (natural > max)
            throw new TiqianIllegalArgumentException(Message("Glue natural must not exceed max."));
        this.kind = kind;
        this.min = min;
        this.natural = natural;
        this.max = max;
        this.priority = priority;
        this.penalty = penalty;
    }
}

enum GlueKind {
    PunctuationLeading;
    PunctuationTrailing;
    CjkLatinSpace;
    WordSpace;
    CjkInterChar;
    ProgressiveTechnical;
    EmergencyGraphemeTracking;
    InlineObjectPunctuationTrailing;
    InlineObjectRelation;
    InlineObjectBinaryOperator;
    InlineObjectBoundary;
}

@:dataClass class AdjustmentOpportunity {
    public final range:TextRange;
    public final glue:Glue;

    public function new(range:TextRange, glue:Glue) {
        this.range = range;
        this.glue = glue;
    }
}

@:dataClass class PunctuationSpacingAdjustment {
    public final range:TextRange;
    public final reductionTargetRange:TextRange;
    public final leftChar:String;
    public final rightChar:String;
    public final naturalInnerGlue:Float;
    public final adjustedInnerGlue:Float;
    public final reduction:Float;
    public final reason:String;

    public function new(range:TextRange, reductionTargetRange:TextRange, leftChar:String, rightChar:String, naturalInnerGlue:Float, adjustedInnerGlue:Float,
            reduction:Float, reason:String) {
        this.range = range;
        this.reductionTargetRange = reductionTargetRange;
        this.leftChar = leftChar;
        this.rightChar = rightChar;
        this.naturalInnerGlue = naturalInnerGlue;
        this.adjustedInnerGlue = adjustedInnerGlue;
        this.reduction = reduction;
        this.reason = reason;
    }
}

@:dataClass class PunctuationSpacingCompressionResult {
    public final adjustments:Array<PunctuationSpacingAdjustment>;

    public function new(adjustments:Array<PunctuationSpacingAdjustment>) {
        this.adjustments = adjustments;
    }

    public var totalReduction(get, never):Float;

    public function get_totalReduction():Float {
        return adjustments.sumOfFloat(adjustment -> adjustment.reduction);
    }
}

class PunctuationSpacingCompressor {
    public function new() {}

    public function compress(atoms:Array<PunctuationAtom>, em:Float):PunctuationSpacingCompressionResult {
        if (atoms.length < 2)
            return new PunctuationSpacingCompressionResult([]);
        final half = em / 2;
        final out:Array<PunctuationSpacingAdjustment> = [];
        var i = 0;
        while (i < atoms.length - 1) {
            final left = atoms[i];
            final right = atoms[i + 1];
            if (left.range.end == right.range.start) {
                final lt = Math.max(0, left.trailingGlue.natural - left.trailingGlueInitiallyConsumed);
                final rl = Math.max(0, right.leadingGlue.natural - right.leadingGlueInitiallyConsumed);
                final natural = lt + rl;
                if (natural > 0) {
                    final adjusted = Math.max(0, natural - half);
                    final reduction = natural - adjusted;
                    if (reduction > 0)
                        out.push(new PunctuationSpacingAdjustment(new TextRange(left.range.start, right.range.end), lt >= rl ? left.range : right.range,
                            left.char, right.char, natural, adjusted, reduction, "collapse-adjacent-punctuation-inner-glue"));
                }
            }
            i++;
        }
        return new PunctuationSpacingCompressionResult(out);
    }

    public function compressCjkClosingBeforeAsciiPointMark(atoms:Array<PunctuationAtom>, text:String, em:Float):PunctuationSpacingCompressionResult {
        final out:Array<PunctuationSpacingAdjustment> = [];
        var half = em / 2;
        var li = 0;
        while (li < atoms.length) {
            final left = atoms[li];
            li++;
            if (left.punctuationClass != PunctuationClass.Closing || left.range.end >= text.length)
                continue;
            final r = text.charAt(left.range.end);
            if (!ClreqPunctuationPolicies.isAsciiPointMark(r))
                continue;
            final natural = Math.max(0, left.trailingGlue.natural - left.trailingGlueInitiallyConsumed);
            if (natural <= 0)
                continue;
            final adjusted = Math.max(0, natural - half);
            if (natural - adjusted > 0)
                out.push(new PunctuationSpacingAdjustment(new TextRange(left.range.start, left.range.end + 1), left.range, left.char, r, natural, adjusted,
                    natural - adjusted, "collapse-cjk-closing-before-ascii-point-mark"));
        }
        return new PunctuationSpacingCompressionResult(out);
    }
}

/** Named shape for the class-based glue split that Kotlin models as Pair<Float, Float>. */
private typedef ClassGluePair = {leading:Float, trailing:Float};

class PunctuationAtomBuilder {
    private final defaultGluePlacement:PunctuationGluePlacement;
    private final defaultWidthPolicy:PunctuationWidthPolicy;

    public function new(?gluePlacement:Null<PunctuationGluePlacement>, ?widthPolicy:Null<PunctuationWidthPolicy>) {
        this.defaultGluePlacement = gluePlacement == null ? PunctuationGluePlacement.MainlandSimplified : gluePlacement;
        this.defaultWidthPolicy = widthPolicy == null ? new PunctuationWidthPolicy() : widthPolicy;
    }

    /** Kotlin declares this overload as build(text, index, em); Haxe cannot give two methods one name with different bodies, so the text+index form is buildAtIndex. */
    public function buildAtIndex(text:String, index:Int, em:Float):Null<PunctuationAtom> {
        if (index < 0 || index >= text.length)
            return null;
        return build(text.charAt(index), new TextRange(index, index + 1), em, null, null, null);
    }

    public function build(char:String, range:TextRange, em:Float, ?inkInput:Null<PunctuationInkInput>, ?gluePlacement:Null<PunctuationGluePlacement>,
            ?widthPolicy:Null<PunctuationWidthPolicy>):Null<PunctuationAtom> {
        final placement = gluePlacement == null ? defaultGluePlacement : gluePlacement;
        final wp = widthPolicy == null ? defaultWidthPolicy : widthPolicy;
        final policy = ClreqPunctuationPolicies.policyFor(char);
        if (policy.punctuationClass == PunctuationClass.Other)
            return null;
        final policyAdvance = policy.defaultAdvanceEm * em;
        final shaped = inkInput == null ? null : (inkInput.advance > 0 ? inkInput.advance : null);
        final raw = shaped == null ? policyAdvance : shaped;
        final expansion = Math.max(0, policyAdvance - raw);
        final glueSide = PunctuationGluePlacements.glueSideFor(placement, policy.punctuationClass);
        final shift = shaped != null && expansion > 0 ? switch (glueSide) {
            case LeadingOnly: expansion;
            case BothSides: expansion / 2;
            case TrailingOnly: 0;
        } : 0;
        final ink = inkInput == null || inkInput.inkBounds == null ? null : shiftRect(inkInput.inkBounds, shift);
        final inkWidth = ink == null ? null : Math.max(0, ink.width);
        final center = ink == null ? null : (ink.left + ink.right) / 2;
        final advance = Math.max(Math.max(raw, policyAdvance), ink == null ? 0 : ink.right);
        final policyFloor = policy.defaultBodyEm * em;
        final halt = inkInput == null ? null : (expansion <= PLACEMENT_EPSILON
            && inkInput.haltAdvance != null
            && inkInput.haltAdvance > 0
            && inkInput.haltAdvance < advance ? inkInput.haltAdvance : null);
        final forced = ClreqPunctuationPolicies.forcedHalfWidth(char, wp);
        final forcedFloor = forced ? Math.min(policyFloor, .5 * em) : policyFloor;
        final target = halt == null ? forcedFloor : halt;
        final geo = compressionGeometry(advance, raw, target, ink, halt, inkInput == null ? null : inkInput.haltPlacementX, policy.punctuationClass, placement);
        return new PunctuationAtom(range, char, policy.punctuationClass, advance, ink, geo.bodyWidth, halt, geo.haltValidation,
            new Glue(PunctuationLeading, 0, geo.leadingTrim, geo.leadingTrim, 0, 0),
            new Glue(PunctuationTrailing, 0, geo.trailingTrim, geo.trailingTrim, 0, 0), geo.anchor, (forced ? geo.source + "FixedHalfWidth" : geo.source),
            policyFloor, inkWidth, center, geo.inkBodyFloor, geo.inkContainmentApplied, ink == null && inkInput != null ? inkInput.boundsFallbackReason : null,
            Math.max(0, advance
                - raw), shift,
            shift != 0 ? "UnderwidthPunctuationFullWidthBoxPlacement" : null, forced ? geo.leadingTrim : 0, forced ? geo.trailingTrim : 0);
    }

    private function shiftRect(r:Rect, a:Float):Rect {
        return a == 0 ? r : new Rect(r.left + a, r.top, r.right + a, r.bottom);
    }

    private function compressionGeometry(advance:Float, raw:Float, target:Float, ink:Null<Rect>, halt:Null<Float>, placementX:Null<Float>,
            cls:PunctuationClass, placement:PunctuationGluePlacement):CompressionGeometry {
        final requested = Math.max(0, advance - target);
        if (halt != null && placementX != null && Math.isFinite(placementX)) {
            final rawReduction = Math.max(0, raw - halt);
            final reqLead = Math.max(0, Math.min(rawReduction, -placementX));
            final reqTrail = Math.max(0, requested - reqLead);
            final lead = ink == null ? reqLead : Math.min(reqLead, Math.max(0, ink.left));
            final trail = ink == null ? reqTrail : Math.min(reqTrail, Math.max(0, advance - ink.right));
            final limited = lead + PLACEMENT_EPSILON < reqLead || trail + PLACEMENT_EPSILON < reqTrail;
            return new CompressionGeometry(lead, trail, advance - lead - trail, anchorFor(lead, trail), "FontHaltFittedBodyCompression",
                ink == null ? null : advance - lead - trail, limited, limited ? "halt-trim-limited-by-default-ink-bounds" : null);
        }
        if (ink != null) {
            final frame = fittedBodyFrame(advance, Math.max(0, Math.min(target, advance)), ink);
            return new CompressionGeometry(frame.start, Math.max(0, advance - frame.start - frame.width), frame.width, frame.anchor,
                halt != null ? "FontHaltAdvanceWithInkBoundsFittedPlacement" : "InkBoundsFittedBodyCompression", frame.width,
                frame.width > target + PLACEMENT_EPSILON, null);
        }
        final pair = classBasedGlue(cls, requested, placement);
        return new CompressionGeometry(pair.leading, pair.trailing, advance - pair.leading - pair.trailing, anchorFor(pair.leading, pair.trailing),
            halt != null ? "FontHaltAdvanceWithProfileFallback" : "ProfileGlueFallbackWithoutFontGeometry", null, false, null);
    }

    private function fittedBodyFrame(advance:Float, target:Float, ink:Rect):BodyFrame {
        final lw = Math.max(target, Math.min(ink.right, advance));
        final tw = Math.max(target, Math.min(advance - ink.left, advance));
        final cw = Math.max(target, Math.min(Math.max(advance - 2 * ink.left, 2 * ink.right - advance), advance));
        final a = [
            new BodyFrame(Leading, 0, lw),
            new BodyFrame(Center, (advance - cw) / 2, cw),
            new BodyFrame(Trailing, advance - tw, tw)
        ];
        final ic = (ink.left + ink.right) / 2;
        var best = a[0];
        for (i in 1...a.length)
            if (a[i].width < best.width
                || a[i].width == best.width
                && Math.abs(a[i].start + a[i].width / 2 - ic) < Math.abs(best.start + best.width / 2 - ic))
                best = a[i];
        return best;
    }

    private function anchorFor(l:Float, t:Float):PunctuationAnchor {
        return l > PLACEMENT_EPSILON
            && t > PLACEMENT_EPSILON ? Center : l > PLACEMENT_EPSILON ? Trailing : t > PLACEMENT_EPSILON ? Leading : Center;
    }

    private function classBasedGlue(cls:PunctuationClass, total:Float, placement:PunctuationGluePlacement):ClassGluePair {
        final side = PunctuationGluePlacements.glueSideFor(placement, cls);
        return switch (side) {
            case LeadingOnly: {leading: total, trailing: 0};
            case TrailingOnly: {leading: 0, trailing: total};
            case BothSides: {leading: total / 2, trailing: total / 2};
        };
    }

    private static final PLACEMENT_EPSILON:Float = .001;
}

@:dataClass class BodyFrame {
    public final anchor:PunctuationAnchor;
    public final start:Float;
    public final width:Float;

    public function new(anchor:PunctuationAnchor, start:Float, width:Float) {
        this.anchor = anchor;
        this.start = start;
        this.width = width;
    }
}

@:dataClass class CompressionGeometry {
    public final leadingTrim:Float;
    public final trailingTrim:Float;
    public final bodyWidth:Float;
    public final anchor:PunctuationAnchor;
    public final source:String;
    public final inkBodyFloor:Null<Float>;
    public final inkContainmentApplied:Bool;
    public final haltValidation:Null<String>;

    public function new(leadingTrim:Float, trailingTrim:Float, bodyWidth:Float, anchor:PunctuationAnchor, source:String, inkBodyFloor:Null<Float>,
            inkContainmentApplied:Bool, haltValidation:Null<String>) {
        this.leadingTrim = leadingTrim;
        this.trailingTrim = trailingTrim;
        this.bodyWidth = bodyWidth;
        this.anchor = anchor;
        this.source = source;
        this.inkBodyFloor = inkBodyFloor;
        this.inkContainmentApplied = inkContainmentApplied;
        this.haltValidation = haltValidation;
    }
}
