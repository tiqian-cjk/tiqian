// Worker layout request serialization (TsHost runtime port, Slices 3b and 4b).
// Ports workerLayoutRequestJson from WebEnhancerSupport.kt and both
// workerLayoutRequest overloads from WebEnhancerParagraphPipeline.kt into one
// module: the lowered-paragraph overload in Slice 3b, and the root+paragraph
// overload (4b) that feeds Kotlin-core classifier hooks through the markdown
// lowering bridge.
//
// Stateless module: the three serializers are exported directly. The module
// reads the stateless lifecycle, eligibility, responsive-measure and
// markdown-lowering helpers inside function bodies.
//
// Corrective wave 5 (#106): the wire format is now declared DTO objects instead
// of separator-joined strings. The ffi boundary exports WorkerLayoutRequest
// and PrepareParagraphRequest interfaces generated from Kotlin @JsExport types.

// Ambient global declarations pulled in via import type from owner modules.
import type { LoweredParagraph } from "./lowered-paragraph.js";
import type { EnhanceOptions } from "./lifecycle.js";
import { allowsSnapshotLayout, conformingSnapshotFontSessionId, withRootDefaults } from "./lifecycle.js";
import {
  classifyRole as classifyFontRole,
  classifyRoles as classifyFontRoles,
  firstDivergentInlineShapingProperty,
  unsupportedInlineShapingProperties,
} from "./font-role.js";
import type { WorkerLayoutRequest } from "./wire-types.js";
import {
  inlineBoxWires,
  inlineObjectWires,
  lineBreakSpanWires,
  renderInlineBoxWires,
  semanticSpanWires,
  textSpanWires,
  workerLayoutRequestWire,
} from "./wire-construction.js";
import { shouldTryParagraph } from "./eligibility.js";
import { effectiveLineMeasure, sourceParagraphWidth } from "./responsive-measure.js";
import { lowerMarkdown } from "./markdown-lowering.js";

interface WorkerInlineShapingDecisionResult {
  name: string;
  detail: string;
}

// WebEnhancerSupport.kt INLINE_EDGE_EPSILON: a clone box whose edges stay
// below this epsilon remains eligible for Worker preparation.
const INLINE_EDGE_EPSILON = 0.01;
// WebEnhancer.kt ROOT_SELECTOR: the selector that identifies a Tiqian prose
// root, matched against a paragraph's closest ancestor scope.
const ROOT_SELECTOR = 'tiqian-prose, [data-tiqian-root]';

/**
 * Escape a string into the Worker JSON string format.
 *
 * @param {string} value
 * @returns {string}
 */
function escapeJson(value: string): string {
  let result = '"';
  for (let i = 0; i < value.length; i += 1) {
    const ch = value.charAt(i);
    const code = value.charCodeAt(i);
    switch (ch) {
      case '"':
        result += '\\"';
        break;
      case '\\':
        result += '\\\\';
        break;
      case '\b':
        result += '\\b';
        break;
      case '\f':
        result += '\\f';
        break;
      case '\n':
        result += '\\n';
        break;
      case '\r':
        result += '\\r';
        break;
      case '\t':
        result += '\\t';
        break;
      default:
        if (code < 0x20) {
          result += '\\u' + code.toString(16).padStart(4, '0');
        } else {
          result += ch;
        }
        break;
    }
  }
  result += '"';
  return result;
}

// elementAttributesJson in WebEnhancerSupport.kt is a @JsFun around
// JSON.stringify of the [name, value] pairs; the result is already JSON and
// is appended verbatim, never re-escaped.
function elementAttributesJson(element: Element): string {
  return JSON.stringify(Array.from(element.attributes || [], function (attribute) {
    return [attribute.name, attribute.value];
  }));
}

// CanonicalPlainParagraphEvidence: twin of isCanonicalPlainParagraph in
// lowered-paragraph.js (six collections). sourceSpans and domInlineObjects
// never travel the layout wire, so the request carries the full-model verdict
// for the worker to pass as the render-evidence override.
function hasRenderEvidence(lowered: LoweredParagraph): boolean {
  return lowered.spans.length > 0 ||
    lowered.decorations.length > 0 ||
    lowered.inlineBoxes.length > 0 ||
    lowered.inlineObjects.length > 0 ||
    lowered.domInlineObjects.length > 0 ||
    lowered.sourceSpans.length > 0;
}

/**
 * Serialize a lowered paragraph into the Worker layout request DTO, matching
 * the Kotlin builder field for field.
 *
 * @param {Element} paragraph
 * @param {LoweredParagraph} lowered
 * @param {number} width
 * @param {number} firstLineIndentIc
 * @returns {WorkerLayoutRequest}
 */
export function buildWorkerLayoutRequest(paragraph: Element, lowered: LoweredParagraph, width: number, firstLineIndentIc: number): WorkerLayoutRequest {
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
  // spacing. The Kotlin decode (MarkdownParagraphLowering.kt
  // decodeInlineBoxes) constructs InlineBoxSpan with the constructor default
  // InlineBoxOuterSpacing.Narrow (core TextModel.kt), so every inlineBoxes
  // join field and renderInlineBoxes entry emits the string Narrow.
  const inlineBoxes = inlineBoxWires(lowered.inlineBoxes.map(function (box) {
    return {
      start: box.start,
      end: box.end,
      inlineStart: box.inlineStart,
      inlineEnd: box.inlineEnd,
      outerSpacing: 'Narrow',
    };
  }));

  // LineBreakPolicy decode: the Kotlin decode maps every wire policy string
  // to the same member, so the join always emits ProgressiveTechnical
  // regardless of the source span's policy value.
  const lineBreakSpans = lineBreakSpanWires(lowered.lineBreakSpans.map(function (span) {
    return {
      start: span.start,
      end: span.end,
      policy: 'ProgressiveTechnical',
    };
  }));

  // WorkerInlineObjectWire: the same measured geometry the runtime lowering
  // feeds its engine (advance, ascent, descent) so the Worker lays the
  // replacement character out identically; the live element stays on the
  // main thread and enters at commit time.
  const inlineObjects = inlineObjectWires(lowered.inlineObjects.map(function (span) {
    return {
      start: span.start,
      end: span.end,
      advance: span.advance,
      ascent: span.ascent,
      descent: span.descent,
    };
  }));

  // SourceBoundary wire: the Kotlin decode builds a deduped Set, then the
  // builder emits it sorted ascending joined by ",". Array.from(new Set(...))
  // dedupes; the numeric sort keeps the ascending order.
  const sourceBoundaries: number[] = Array.from(new Set(lowered.sourceBoundaries))
    .sort(function (a, b) { return a - b; });

  // WorkerSemanticHierarchyOrder: sourceSpans are collected after their
  // children, so the list index identifies the live element but cannot also
  // describe outer-to-inner replay order.
  const semantics = semanticSpanWires(lowered.sourceSpans.map(function (sourceSpan, i) {
    return {
      start: sourceSpan.start,
      end: sourceSpan.end,
      tagName: sourceSpan.element.tagName.toLowerCase(),
      attributes: Array.from(sourceSpan.element.attributes || [], function (attribute) {
        return [attribute.name, attribute.value];
      }),
      sourceIndex: i,
      order: sourceSpan.depth,
    };
  }));

  const renderInlineBoxes = renderInlineBoxWires(lowered.inlineBoxes.map(function (inlineBox) {
    return {
      start: inlineBox.start,
      end: inlineBox.end,
      inlineStartPx: inlineBox.inlineStart,
      inlineEndPx: inlineBox.inlineEnd,
      outerSpacing: 'Narrow',
    };
  }));

  return workerLayoutRequestWire({
    text: lowered.text,
    maxWidthPx: width,
    fontFamilies: lowered.textStyle.fontFamilies,
    fontSizePx: lowered.textStyle.fontSize,
    lineHeightPx: lowered.lineHeight,
    locale: lowered.textStyle.locale,
    fontWeight: lowered.textStyle.fontWeight,
    italic: lowered.textStyle.italic,
    firstLineIndentIc: firstLineIndentIc,
    lineLengthGridEnabled: true,
    sourceBoundaries: sourceBoundaries,
    textSpans: textSpans,
    inlineBoxes: inlineBoxes,
    lineBreakSpans: lineBreakSpans,
    inlineObjects: inlineObjects,
    renderEvidence: hasRenderEvidence(lowered),
    semantics: semantics,
    renderInlineBoxes: renderInlineBoxes,
    sourceTag: paragraph.tagName.toLowerCase(),
  });
}

/**
 * Lower a live paragraph through the markdown bridge, then serialize it as a
 * Worker layout request. Ports the root+paragraph workerLayoutRequest
 * overload from WebEnhancerParagraphPipeline.kt (lines 28-44).
 *
 * ffi carries the injected 3c export surface: classifyFontRole,
 * unsupportedInlineShapingProperties, firstDivergentInlineShapingProperty.
 *
 * The root overload discards the lowering issue: ok !== true returns null
 * without reading result.issue. Only processParagraph reports lowering
 * issues, so the Worker path stays silent on failure.
 *
 * @param {Element} root
 * @param {Element} paragraph
 * @param {Record<string, unknown>} options
 * @returns {WorkerLayoutRequest|null}
 */
export function workerLayoutRequestForRoot(root: Element, paragraph: Element, options: EnhanceOptions): WorkerLayoutRequest | null {
  // RootScopeGate: a paragraph belongs when it has no owner, owns the root,
  // or lives outside the root. A nested owner under the root is not in this
  // paragraph's scope, so it returns null before anything else runs.
  const owner = paragraph.closest(ROOT_SELECTOR);
  if (owner && owner !== root && root.contains(owner)) {
    return null;
  }
  if (!shouldTryParagraph(paragraph)) return null;
  if (!allowsSnapshotLayout(options)) return null;
  const resolved = withRootDefaults(options, root);
  let lowered: LoweredParagraph | null = null;
  try {
    // The options bag mirrors loweringOptionsJs in MarkdownParagraphLowering.kt:
    // fontSize and lineHeight are nullable, strongAsEmphasisMarks is a boolean,
    // and locale is fixed to LOWERING_DEFAULT_LOCALE ("zh-Hans").
    const result = lowerMarkdown(paragraph, {
      fontSize: resolved.fontSize as number | undefined,
      lineHeight: resolved.lineHeight as number | undefined,
      strongAsEmphasisMarks: resolved.strongAsEmphasisMarks as boolean | undefined,
      locale: 'zh-Hans',
    }, {
      // Singular and batch role classifiers are the ffi exports verbatim.
      classifyRole: classifyFontRole,
      classifyRoles: classifyFontRoles,
      // The inlineShapingDecision wrapper reproduces the Kotlin closure in
      // MarkdownParagraphLowering.kt: a null divergence property returns null,
      // otherwise the inlineShapingDecisionResultJs shape is built.
      inlineShapingDecision: function (tag: string, elementValues: string[], paragraphValues: string[]): WorkerInlineShapingDecisionResult | null {
        const property = firstDivergentInlineShapingProperty(elementValues, paragraphValues);
        return property == null ? null : { name: 'UnsupportedInlineShapingStyle', detail: tag + ':' + property };
      },
      inlineShapingProperties: unsupportedInlineShapingProperties(),
    });
    if (result && result.ok === true) lowered = result.lowered;
  } catch (error) { lowered = null; }
  if (lowered == null) return null;
  return workerLayoutRequest(paragraph, lowered, resolved);
}

/**
 * Gate the lowered paragraph against Worker preparation eligibility, compute
 * the responsive line measure, and serialize the request. Returns null when
 * ineligible.
 *
 * @param {Element} paragraph
 * @param {LoweredParagraph} lowered
 * @param {Record<string, unknown>} options
 * @returns {WorkerLayoutRequest|null}
 */
export function workerLayoutRequest(paragraph: Element, lowered: LoweredParagraph, options: EnhanceOptions): WorkerLayoutRequest | null {
  if (conformingSnapshotFontSessionId(options) == null) return null;
  // WorkerRequestMatchesRuntimeEligibility: inline objects no longer exclude
  // a paragraph from Worker preparation; their measured geometry travels on
  // the request wire and the live elements enter at commit time, the same
  // split the runtime exact path uses. Decorated paragraphs stay excluded
  // because the request wire carries no decoration input; they lower on the
  // main thread, whose LayoutInput carries the decorations, and commit
  // through the same prepared bridge. Every other exclusion mirrors
  // isRuntimeSnapshotPreparedDomEligible so both exact paths adopt one shape.
  if (lowered.decorations.length > 0 ||
      lowered.sourceSpans.some(function (span) {
        return span.inlineBoxStyle.boxDecorationBreak === 'clone' &&
          (Math.abs(span.inlineBoxStyle.inlineStart) >= INLINE_EDGE_EPSILON ||
            Math.abs(span.inlineBoxStyle.inlineEnd) >= INLINE_EDGE_EPSILON);
      }) ||
      lowered.spans.some(function (span) {
        return span.style.locale !== lowered.textStyle.locale;
      })) {
    return null;
  }
  const rawWidth = sourceParagraphWidth(paragraph);
  if (!Number.isFinite(rawWidth) || rawWidth <= 0) return null;
  // WorkerLineMeasureMatchesResponsiveGrid: the responsive coordinator
  // intentionally treats widths within the same floor(width / fontSize) cell
  // count as one layout input. Serialize that effective measure, not the
  // transient CSS width observed while a window is being dragged, so
  // preparation and commit use the same Worker plan inside the grid.
  const measure = effectiveLineMeasure(
    rawWidth,
    lowered.textStyle.fontSize,
  );
  const firstLineIndentIc = paragraph.tagName.toUpperCase() === 'LI'
    ? 0
    : (options.firstLineIndentIc as number);
  return buildWorkerLayoutRequest(paragraph, lowered, measure, firstLineIndentIc);
}
