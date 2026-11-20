// prepareParagraphLayout (TsHost runtime port, Slice 4b). Ports the paragraph
// layout PREPARATION step of the web host from
// WebEnhancerParagraphPipeline.kt (prepareParagraphLayout, lines 319-498).
// The module computes the responsive measure, gates the prepared-DOM bridge,
// checks prepared-DOM eligibility, serializes the lowered paragraph onto the
// shared ffi wire, runs the snapshot-session or browser-metric layout call, and
// re-checks the plan envelope facts into three named capability verdicts.
//
// Stateless module: prepareParagraphLayout() is exported directly and reads
// the installed prepared-DOM renderer from globalThis inside the body.
//
// Corrective wave 5 (#106): the wire format is now declared DTO objects instead
// of separator-joined strings. The ffi boundary exports WorkerLayoutRequest
// and PrepareParagraphRequest interfaces generated from Kotlin @JsExport types.

// Ambient global declarations pulled in via import type from owner modules.
import type { LoweredParagraph } from "./lowered-paragraph.js";
import { LAYOUT_REVISION, SNAPSHOT_SCHEMA } from "../sampler/snapshot/snapshot-schema.js";
import {
  precomputeParagraphWithBrowserMetrics,
  precomputeParagraphWithDiagnostics,
} from "@tiqian/ffi";
import type { PrepareParagraphRequest } from "@tiqian/ffi";
import {
  decorationWires,
  inlineBoxWires,
  inlineObjectWires,
  lineBreakSpanWires,
  prepareParagraphRequestWire,
  textSpanWires,
} from "./wire-construction.js";
import { effectiveLineMeasure, sourceParagraphWidth } from "./responsive-measure.js";

interface LayoutPlanLine {
  rangeStart: number;
  rangeEnd: number;
}

interface LayoutPlan {
  lines: LayoutPlanLine[];
}

interface LayoutCapabilityIssue {
  name: string;
  reason: string;
}

interface LayoutAdvanceSuspect {
  displayText: string;
  advance: number;
  reason: string;
}

interface LayoutDiagnostics {
  capabilityIssues: LayoutCapabilityIssue[];
  advanceSuspects: LayoutAdvanceSuspect[];
}

// The prepare verdict is a discriminated union on kind. Every original
// construction site sets the fields of its own member only.
interface PrepareUnchangedResult {
  kind: "unchanged";
}

interface PrepareUnsupportedResult {
  kind: "unsupported";
  name: string;
  detail?: string;
  element?: Element;
  rawEnvelope?: string;
  reportToConsole?: boolean;
  [key: string]: unknown;
}

export interface PrepareReadyResult {
  kind: "ready";
  rawEnvelope: unknown;
  planJson: string | Record<string, unknown>;
  plan: LayoutPlan;
  diagnostics: LayoutDiagnostics;
  width: number;
  measure: number;
  snapshotFontSessionUsed: boolean;
  [key: string]: unknown;
}

export type PrepareLayoutResult =
  | PrepareUnchangedResult
  | PrepareUnsupportedResult
  | PrepareReadyResult;

type BrowserBridgeShapeJsonFn = (input: string) => string;
type BrowserBridgeMetricsJsonFn = (input: string) => string;

interface BrowserBridgeDescriptor {
  shapeJson: BrowserBridgeShapeJsonFn;
  metricsJson: BrowserBridgeMetricsJsonFn;
}

interface PrepareParagraphTarget {
  source: Element;
  lowered: LoweredParagraph;
  lastMeasure: number | null;
}

interface PrepareSnapshotSessionDescriptor {
  shapeJson: BrowserBridgeShapeJsonFn;
  metricsJson: BrowserBridgeMetricsJsonFn;
}

interface PrepareParagraphLayoutInvocation {
  paragraph: PrepareParagraphTarget;
  options: Record<string, unknown>;
  snapshotSession: PrepareSnapshotSessionDescriptor | null;
  browserFallback: Record<string, unknown> | null;
  widthOverride?: number | null;
  ignoreUnchangedMeasure?: boolean;
}

// WebEnhancerSupport.kt INLINE_EDGE_EPSILON: a clone box whose edges stay
// below this epsilon remains eligible for prepared-DOM preparation.
const INLINE_EDGE_EPSILON = 0.01;
// WebEnhancerSupport.kt ZERO_ADVANCE_EPSILON: the host threshold passed to
// the ffi diagnostics export, which pre-filters advance suspects.
const ZERO_ADVANCE_EPSILON = 0.01;
// WebEnhancerSupport.kt SNAPSHOT_FONT_SESSION_CAPABILITY_FAILURES: substrings
// that mark an snapshot-session layout failure as a font capability issue,
// after which the whole paragraph retries through the browser bridge.
const SNAPSHOT_FONT_SESSION_CAPABILITY_FAILURES = [
  'NoSnapshotFontFace',
  'MissingGlyph',
  'MissingServerShapingReplay',
  'NoSnapshotMetricFace',
  'NonUniformUnicodeRangeMetrics',
];

// Serialize the lowered paragraph onto the shared ffi wire as a DTO.
// Twins of the worker-request.js serializer functions, copied locally so
// both files stay embeddable and import-free.
export function wireArguments(lowered: LoweredParagraph): PrepareParagraphRequest {
  const textSpans = textSpanWires(lowered.spans.map(function (span) {
    return {
      start: span.start,
      end: span.end,
      fontFamilies: span.style.fontFamilies,
      fontSize: span.style.fontSize,
      fontWeight: span.style.fontWeight,
      italic: span.style.italic,
      baselineShift: span.style.baselineShift,
    };
  }));

  // InlineBoxOuterSpacing default chain: the wire never carries outer
  // spacing, so every inlineBoxes join field emits the string Narrow.
  const inlineBoxes = inlineBoxWires(lowered.inlineBoxes.map(function (box) {
    return {
      start: box.start,
      end: box.end,
      inlineStart: box.inlineStart,
      inlineEnd: box.inlineEnd,
      outerSpacing: 'Narrow',
    };
  }));

  // LineBreakPolicy decode maps every wire policy string to the same
  // member, so the join always emits ProgressiveTechnical.
  const lineBreakSpans = lineBreakSpanWires(lowered.lineBreakSpans.map(function (span) {
    return {
      start: span.start,
      end: span.end,
      policy: 'ProgressiveTechnical',
    };
  }));

  const inlineObjects = inlineObjectWires(lowered.inlineObjects.map(function (span) {
    return {
      start: span.start,
      end: span.end,
      advance: span.advance,
      ascent: span.ascent,
      descent: span.descent,
    };
  }));

  // Decorations (mirrors the Kotlin parseDecorations landed in 33c5106):
  // each entry carries start, end, and the member-name kind string.
  const decorations = decorationWires(lowered.decorations.map(function (decoration) {
    return {
      start: decoration.start,
      end: decoration.end,
      kind: decoration.kind,
    };
  }));

  // SourceBoundary wire: dedupe into a Set, sort ascending, join by comma.
  const sourceBoundaries: number[] = Array.from(new Set(lowered.sourceBoundaries))
    .sort(function (a, b) { return a - b; });

  return prepareParagraphRequestWire({
    text: lowered.text,
    maxWidthPx: 0, // Will be set by caller
    fontFamilies: lowered.textStyle.fontFamilies,
    fontSizePx: lowered.textStyle.fontSize,
    lineHeightPx: lowered.lineHeight,
    locale: lowered.textStyle.locale,
    fontWeight: lowered.textStyle.fontWeight,
    italic: lowered.textStyle.italic,
    firstLineIndentIc: 0, // Will be set by caller
    lineLengthGridEnabled: true,
    sourceBoundaries: sourceBoundaries,
    textSpans: textSpans,
    inlineBoxes: inlineBoxes,
    lineBreakSpans: lineBreakSpans,
    inlineObjects: inlineObjects,
    decorations: decorations,
    emphasisDotGapEm: null, // Will be set by caller
    renderEvidenceOverride: null, // Will be set by caller
  });
}

  // RuntimeSnapshotPreparedDomScope: inline the lowered-paragraph.js predicate
  // isRuntimeSnapshotPreparedDomEligible, which requires every span to share the
  // paragraph locale. The plan wire carries one paragraph locale.
  function isPreparedDomEligible(lowered: LoweredParagraph): boolean {
    return lowered.spans.every(function (span) {
      return span.style.locale === lowered.textStyle.locale;
    });
  }

  // CanonicalPlainParagraphEvidence: twin of isCanonicalPlainParagraph in
  // lowered-paragraph.js (six collections). The wire predicate inside the
  // layout module cannot see sourceSpans or domInlineObjects because they
  // never travel the wire, so the host passes this full-model verdict as the
  // render-evidence override on both layout calls.
  function hasRenderEvidence(lowered: LoweredParagraph): boolean {
    return lowered.spans.length > 0 ||
      lowered.decorations.length > 0 ||
      lowered.inlineBoxes.length > 0 ||
      lowered.inlineObjects.length > 0 ||
      lowered.domInlineObjects.length > 0 ||
      lowered.sourceSpans.length > 0;
  }

  // PreparedDomUnifiedEligibility: the prepared-dom module is imported
  // statically, and the plan revision the renderer must report now comes
  // from the same single source as the snapshot revision (boring cutover
  // Stage1-P4), so the revision comparison reduces to the schema gate on
  // the imported constant.
  function isPreparedDomBridgeAvailable(): boolean {
    return SNAPSHOT_SCHEMA === 1;
  }

  function isSnapshotSessionCapabilityFailure(error: unknown): boolean {
    const message = String(error && (error as { message?: string }).message);
    for (let i = 0; i < SNAPSHOT_FONT_SESSION_CAPABILITY_FAILURES.length; i += 1) {
      if (message.indexOf(SNAPSHOT_FONT_SESSION_CAPABILITY_FAILURES[i]) !== -1) {
        return true;
      }
    }
    return false;
  }

  /**
   * Prepare a paragraph for layout. See the slice header for the verdict
   * shapes and the Kotlin order this follows.
   *
   * @param {Object} argument
   * @returns {Object}
   */
  export function prepareParagraphLayout(argument: PrepareParagraphLayoutInvocation): PrepareLayoutResult {
    const paragraph = argument.paragraph;
    const options = argument.options;
    const snapshotSession = argument.snapshotSession;
    const browserFallback = argument.browserFallback;
    const widthOverride = argument.widthOverride;
    const ignoreUnchangedMeasure = argument.ignoreUnchangedMeasure;
    const lowered = paragraph.lowered;
    const element = paragraph.source;

    const width = widthOverride != null
      ? widthOverride
      : sourceParagraphWidth(paragraph.source);
    const fontSize = lowered.textStyle.fontSize;
    const measure = effectiveLineMeasure(width, fontSize);

    if (!ignoreUnchangedMeasure && paragraph.lastMeasure === measure) {
      return { kind: 'unchanged' };
    }

    if (!isPreparedDomBridgeAvailable()) {
      return {
        kind: 'unsupported',
        name: 'PreparedDomBridgeUnavailable',
        detail: 'expectedLayoutRevision=' + LAYOUT_REVISION,
        element: element,
      };
    }

    if (!isPreparedDomEligible(lowered)) {
      let firstMismatch = null;
      for (let i = 0; i < lowered.spans.length; i += 1) {
        if (lowered.spans[i].style.locale !== lowered.textStyle.locale) {
          firstMismatch = lowered.spans[i];
          break;
        }
      }
      return {
        kind: 'unsupported',
        name: 'SpanLocaleMismatchUnsupported',
        detail: 'spanRange=' + (firstMismatch ? firstMismatch.start : 0) +
          '..' + (firstMismatch ? firstMismatch.end : 0) +
          '; spanLocale=' + (firstMismatch ? firstMismatch.style.locale : 'unknown') +
          '; paragraphLocale=' + lowered.textStyle.locale,
        element: element,
      };
    }

    let wire = wireArguments(lowered);
    const firstLineIndentIc = element.tagName.toUpperCase() === 'LI'
      ? 0
      : (options.firstLineIndentIc as number);
    // The Kotlin direct path builds ParagraphStyle without lineLengthGrid,
    // whose data-class default is LineLengthGrid(enabled = true).
    const lineLengthGridEnabled = true;
    const emphasisDotGapEm: number | null = options.emphasisDotGapEm == null
      ? null
      : (options.emphasisDotGapEm as number);
    const renderEvidenceOverride = hasRenderEvidence(lowered);

    // Update the DTO with the computed values
    wire = {
      ...wire,
      maxWidthPx: measure,
      firstLineIndentIc: firstLineIndentIc,
      lineLengthGridEnabled: lineLengthGridEnabled,
      emphasisDotGapEm: emphasisDotGapEm,
      renderEvidenceOverride: renderEvidenceOverride,
    };

    let snapshotFontSessionUsed = browserFallback != null;

    let rawEnvelope;
    if (snapshotSession != null) {
      try {
        // SnapshotSessionSemanticLayout: one font session serves the canonical
        // plain paragraph and the semantic DOM, so no engine pair exists.
        rawEnvelope = precomputeParagraphWithDiagnostics(
          wire,
          ZERO_ADVANCE_EPSILON,
          snapshotSession.shapeJson,
          snapshotSession.metricsJson,
        );
      } catch (error) {
        if (!isSnapshotSessionCapabilityFailure(error)) throw error;
        // PreparedDomAfterSessionFailure: a capability failure retries the
        // whole paragraph through the browser bridge. The per-run
        // SnapshotSessionBrowserFallback* wrappers are deliberately not ported
        // (Slice 4a note); the whole paragraph re-runs instead.
        snapshotFontSessionUsed = false;
        rawEnvelope = precomputeParagraphWithBrowserMetrics(
          wire,
          ZERO_ADVANCE_EPSILON,
          browserFallback!.bridge as BrowserBridgeDescriptor,
        );
      }
    } else {
      if (browserFallback == null) {
        throw new Error('missing browserFallback descriptor for browser-metric layout');
      }
      snapshotFontSessionUsed = false;
      rawEnvelope = precomputeParagraphWithBrowserMetrics(
        wire,
        ZERO_ADVANCE_EPSILON,
        browserFallback.bridge as BrowserBridgeDescriptor,
      );
    }

    const envelope = typeof rawEnvelope === "string" ? JSON.parse(rawEnvelope) : rawEnvelope;
    const planJson = envelope.plan as string | Record<string, unknown>;
    const plan = (typeof planJson === "string" ? JSON.parse(planJson) : planJson) as LayoutPlan;
    const diagnostics = envelope.diagnostics as LayoutDiagnostics;

    // Verdict, not diagnostics: capabilityIssues and advanceSuspects are the
    // render gates below (the first hit returns unsupported); the full arrays
    // have no other consumer. Keep the names and semantics as published.
    const capabilityIssue = diagnostics.capabilityIssues[0];
    if (capabilityIssue != null) {
      return {
        kind: 'unsupported',
        name: capabilityIssue.name,
        detail: capabilityIssue.reason,
        element: element,
      };
    }

    let invalidShaping = null;
    for (let s = 0; s < diagnostics.advanceSuspects.length; s += 1) {
      const suspect = diagnostics.advanceSuspects[s];
      if (suspect.displayText.length > 0 &&
          suspect.displayText.indexOf('\n') === -1 &&
          suspect.displayText.indexOf('\r') === -1) {
        invalidShaping = suspect;
        break;
      }
    }
    if (invalidShaping != null) {
      return {
        kind: 'unsupported',
        name: 'InvalidWebShapingAdvance',
        detail: 'text=' + invalidShaping.displayText +
          '; advance=' + invalidShaping.advance +
          '; ' + invalidShaping.reason,
        element: element,
      };
    }

    let clonedDecoration = null;
    for (let d = 0; d < lowered.sourceSpans.length; d += 1) {
      const sourceSpan = lowered.sourceSpans[d];
      let crossing = 0;
      for (let l = 0; l < plan.lines.length; l += 1) {
        const line = plan.lines[l];
        if (line.rangeStart < sourceSpan.end && line.rangeEnd > sourceSpan.start) {
          crossing += 1;
        }
      }
      if (sourceSpan.inlineBoxStyle.boxDecorationBreak === 'clone' &&
          (Math.abs(sourceSpan.inlineBoxStyle.inlineStart) >= INLINE_EDGE_EPSILON ||
            Math.abs(sourceSpan.inlineBoxStyle.inlineEnd) >= INLINE_EDGE_EPSILON) &&
          crossing > 1) {
        clonedDecoration = sourceSpan;
        break;
      }
    }
    if (clonedDecoration != null) {
      return {
        kind: 'unsupported',
        name: 'InlineCloneDecorationBreakUnsupported',
        detail: clonedDecoration.element.tagName.toLowerCase(),
        element: element,
      };
    }

    return {
      kind: 'ready',
      rawEnvelope: rawEnvelope,
      planJson: planJson,
      plan: plan,
      diagnostics: diagnostics,
      width: width,
      measure: measure,
      snapshotFontSessionUsed: snapshotFontSessionUsed,
    };
  }
