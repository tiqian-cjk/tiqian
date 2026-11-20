// commitPreparedParagraph (TsHost runtime port, Slice 4c). Ports the two
// paragraph layout COMMIT functions of the web host from
// WebEnhancerParagraphPipeline.kt (commitWorkerPreparedParagraph, lines 266-313,
// and commitPreparedParagraph, lines 500-583). The module mounts the rendered
// prepared DOM, sets canonical-source and canonical-plain attributes, and
// manages rawDom engine write suspensions.
//
// Stateless module: commitWorkerPreparedParagraph(rawDom, argument) and
// commitPreparedParagraph(rawDom, argument) are named functions that receive
// the raw-DOM collaborator as an explicit first parameter. Consumers import
// the functions directly; tests call the functions with a fake rawDom.
//
// Embedding constraint: the generator wraps this file in a Kotlin raw string,
// so the source must contain no dollar sign and no triple double-quote
// sequence. Use string concatenation, never template literals.

// Ambient global declarations pulled in via import type from owner modules.
import type { LoweredParagraph } from "./lowered-paragraph.js";
import type { PrepareReadyResult } from "./prepare-paragraph-layout.js";
import type { WorkerPreparedParagraph } from "./web-worker/worker-channel.js";
import { renderPreparedParagraphInto } from "../sampler/snapshot/prepared-dom.js";
import { PlanSchema } from "@tiqian/protocol/org/tiqian/protocol/PlanSchema";
import type { EnhancedElementContext } from "./context/enhance-context.js";
import {
  rawDomStampRendered,
  rawDomSuspendEngineWrites,
} from "./raw-dom.js";
import { effectiveLineMeasure, sourceParagraphWidth } from "./responsive-measure.js";
import { prepareParagraphLayout } from "./prepare-paragraph-layout.js";

// PreparedPlanWireShape: the engine emits a plan in two forms. The JSON
// entries serialize it through PlanJson.encode, whose first two keys are the
// producer constants PLAN_SCHEMA and PLAN_LAYOUT_REVISION
// (engine-haxe/src/org/tiqian/protocol/PlanJson.hx:20-23). The structured
// entries (toPlanWithDiagnostics for main-thread layout and
// PlanLowering.toPlan for the layout Worker) return the Plan struct, which
// carries geometry only. The lowered-DOM gate rejects a plan whose
// schema/layoutRevision do not match this build
// (sampler/snapshot/prepared-dom.ts:713), so the structured form is stamped
// here, immediately before it crosses that gate, with the same two
// constants. Nothing else stamps: the snapshot loader and the server build
// hand stored plan JSON straight to the renderer, so a stored plan that lost
// the fields still fails the gate exactly as before.
const PLAN_WIRE_SCHEMA = PlanSchema.PLAN_SCHEMA;
const PLAN_WIRE_LAYOUT_REVISION = PlanSchema.PLAN_LAYOUT_REVISION;

function wirePlan(planOrJson: Parameters<typeof renderPreparedParagraphInto>[1]): Parameters<typeof renderPreparedParagraphInto>[1] {
  if (typeof planOrJson === "string" || planOrJson == null) return planOrJson;
  const plan = planOrJson as unknown as Record<string, unknown>;
  const schema = plan.schema == null ? PLAN_WIRE_SCHEMA : plan.schema;
  const layoutRevision = plan.layoutRevision == null ? PLAN_WIRE_LAYOUT_REVISION : plan.layoutRevision;
  return { ...plan, schema: schema, layoutRevision: layoutRevision } as Parameters<typeof renderPreparedParagraphInto>[1];
}

// The commit verdict is a discriminated union on kind. Every original
// construction site sets the fields of its own member only.
interface CommitSuccessResult {
  kind: "success";
  measure: number;
  [key: string]: unknown;
}

interface CommitUnsupportedResult {
  kind: "unsupported";
  name: string;
  detail?: string;
  element?: Element;
  [key: string]: unknown;
}

export type CommitResult = CommitSuccessResult | CommitUnsupportedResult;

interface CommitParagraphTarget {
  source: Element;
  lowered: LoweredParagraph;
  lastMeasure: number | null;
}

interface CommitWorkerPreparedParagraphArgument {
  paragraph: CommitParagraphTarget;
  workerPlan: string | WorkerPreparedParagraph;
  inlineObjectMetaJson: string;
  cjkStrongSemanticsJson: string;
}

interface CommitPreparedParagraphArgument {
  paragraph: CommitParagraphTarget;
  preparation: PrepareReadyResult;
  options: Record<string, unknown>;
  browserFallback: Record<string, unknown> | null;
  semanticReplayJson: string;
  inlineObjectMetaJson: string;
  cjkStrongSemanticsJson: string;
}

// Both commit functions receive the raw-DOM collaborator as an explicit first
// parameter. Consumers import the functions directly; the engine bootstrap
// passes the single shared raw-DOM instance.

const CANONICAL_SOURCE_ATTRIBUTE = 'data-tq-canonical-source';
const SNAPSHOT_PREPARED_DOM_ATTRIBUTE = 'data-tq-snapshot-prepared-dom';

// CanonicalPlainParagraph: inline twin of isCanonicalPlainParagraph in
// lowered-paragraph.js (line 110). True when all six styled collections are
// empty. The module cannot import the ESM function, so it carries an inline
// copy.
function isCanonicalPlain(lowered: LoweredParagraph): boolean {
  return lowered.spans.length === 0 &&
    lowered.decorations.length === 0 &&
    lowered.inlineBoxes.length === 0 &&
    lowered.inlineObjects.length === 0 &&
    lowered.domInlineObjects.length === 0 &&
    lowered.sourceSpans.length === 0;
}

// RenderPreparedWorkerParagraphDom: direct port of the
// renderPreparedWorkerParagraphDom @JsFun body in WebEnhancerSupport.kt.
function renderWorkerPrepared(
  rawDomContext: EnhancedElementContext,
  host: Element,
  workerPlan: string | WorkerPreparedParagraph,
  locale: string,
  sourceText: string,
  semanticElements: Element[],
  inlineObjectElements: Element[],
  inlineObjectMetaJson: string,
  cjkStrongSemanticsJson: string
): unknown {
  const record: WorkerPreparedParagraph = typeof workerPlan === "string" ? JSON.parse(workerPlan) : workerPlan;
  const inlineObjects = Array.from(inlineObjectElements || []);
  const meta = JSON.parse(inlineObjectMetaJson || '[]');
  const inlineObjectsMetaPaired = meta.map(function (entry: Record<string, unknown>, index: number) {
    return {
      start: entry.start,
      end: entry.end,
      marginRight: entry.marginRight,
      element: inlineObjects[index],
    };
  });
  return rawDomSuspendEngineWrites(rawDomContext, host, function () {
    return renderPreparedParagraphInto(
      host,
      wirePlan(record.plan as Parameters<typeof renderPreparedParagraphInto>[1]),
      locale,
      {
        sourceText: sourceText,
        semanticReplay: record.semanticReplay || 'snapshot-safe',
        semantics: record.semantics,
        inlineBoxes: record.inlineBoxes || [],
        liveSemanticElements: Array.from(semanticElements || []),
        inlineObjects: inlineObjectsMetaPaired,
        cjkStrongSemantics: JSON.parse(cjkStrongSemanticsJson || '[]'),
      },
      rawDomContext
    );
  });
}

// RenderPreparedParagraphDom: direct port of the renderPreparedParagraphDom
// @JsFun body in WebEnhancerSupport.kt.
function renderPrepared(
  rawDomContext: EnhancedElementContext,
  host: Element,
  planJson: Parameters<typeof renderPreparedParagraphInto>[1],
  locale: string,
  sourceText: string,
  semanticElements: Element[],
  semanticsJson: string,
  inlineObjectElements: Element[],
  inlineObjectMetaJson: string,
  cjkStrongSemanticsJson: string
): unknown {
  const semantics = Array.from(semanticElements || []);
  const inlineObjects = Array.from(inlineObjectElements || []);
  const hasLiveSources = semantics.length > 0 || inlineObjects.length > 0;
  return rawDomSuspendEngineWrites(rawDomContext, host, function () {
    const meta = JSON.parse(inlineObjectMetaJson || '[]');
    const inlineObjectsMetaPaired = meta.map(function (entry: Record<string, unknown>, index: number) {
      return {
        start: entry.start,
        end: entry.end,
        marginRight: entry.marginRight,
        element: inlineObjects[index],
      };
    });
    const options = hasLiveSources ? {
      sourceText: sourceText,
      semanticReplay: 'live-source',
      semantics: JSON.parse(semanticsJson || '[]'),
      liveSemanticElements: semantics,
      inlineObjects: inlineObjectsMetaPaired,
      cjkStrongSemantics: JSON.parse(cjkStrongSemanticsJson || '[]'),
    } : undefined;
    return renderPreparedParagraphInto(
      host,
      wirePlan(planJson),
      locale,
      options,
      rawDomContext
    );
  });
}

/**
 * Commit a worker-prepared paragraph to the DOM.
 *
 * @param {Object} rawDomContext
 * @param {Object} argument
 * @returns {Object|null}
 */
export function commitWorkerPreparedParagraph(rawDomContext: EnhancedElementContext, argument: CommitWorkerPreparedParagraphArgument): CommitResult | null {
  const paragraph = argument.paragraph;
  const source = paragraph.source;
  const lowered = paragraph.lowered;
  const width = sourceParagraphWidth(source);

  source.setAttribute(SNAPSHOT_PREPARED_DOM_ATTRIBUTE, 'true');
  source.setAttribute(CANONICAL_SOURCE_ATTRIBUTE, 'true');

  // CanonicalPlainMatchesRuntimeScope: the re-lowering treats a paragraph as
  // a prepared plain host only when the paragraph shape really is plain.
  // Inline-object paragraphs carry replacement characters the re-lowering
  // must re-measure, so sourceSpans alone must not mark them plain.
  if (isCanonicalPlain(lowered)) {
    source.setAttribute('data-tq-canonical-plain', 'true');
  } else {
    source.removeAttribute('data-tq-canonical-plain');
  }

  source.setAttribute('lang', lowered.textStyle.locale);

  const sourceSpansElements = lowered.sourceSpans.map(function (s) {
    return s.element;
  });
  const domInlineObjectsElements = lowered.domInlineObjects.map(function (s) {
    return s.element;
  });

  renderWorkerPrepared(
    rawDomContext,
    source,
    argument.workerPlan,
    lowered.textStyle.locale,
    lowered.text,
    sourceSpansElements,
    domInlineObjectsElements,
    argument.inlineObjectMetaJson,
    argument.cjkStrongSemanticsJson
  );

  // WorkerCommitRecordsMeasure: cache the effective line measure computed from
  // the measured width and the paragraph font size.
  paragraph.lastMeasure = effectiveLineMeasure(
    width,
    lowered.textStyle.fontSize
  );
  rawDomStampRendered(rawDomContext, source);
  return null;
}

/**
 * Commit a direct prepared paragraph layout result to the DOM.
 *
 * @param {Object} rawDomContext
 * @param {Object} argument
 * @returns {Object}
 */
export function commitPreparedParagraph(rawDomContext: EnhancedElementContext, argument: CommitPreparedParagraphArgument): CommitResult {
  const paragraph = argument.paragraph;
  const preparation = argument.preparation;
  const source = paragraph.source;
  const lowered = paragraph.lowered;

  // PreparedPlainHostPromise: canonical-plain promises the re-lowerer a
  // prepared plain host, so a rich prepared paragraph only carries
  // canonical-source and re-lowers through its live clones.
  if (isCanonicalPlain(lowered)) {
    source.setAttribute('data-tq-canonical-plain', 'true');
  }
  source.setAttribute(CANONICAL_SOURCE_ATTRIBUTE, 'true');
  source.setAttribute('lang', lowered.textStyle.locale);

  const sourceSpansElements = lowered.sourceSpans.map(function (s) {
    return s.element;
  });
  const domInlineObjectsElements = lowered.domInlineObjects.map(function (s) {
    return s.element;
  });

  // Kotlin re-serializes its LayoutResult via toPreparedParagraphJson with
  // renderEvidence = !isCanonicalPlainParagraph(); the TS prepare step passes
  // the same six-collection verdict as the render-evidence override, so
  // preparation.planJson is already the byte-equivalent wire form and is used
  // directly.
  renderPrepared(
    rawDomContext,
    source,
    preparation.planJson as Parameters<typeof renderPreparedParagraphInto>[1],
    lowered.textStyle.locale,
    lowered.text,
    sourceSpansElements,
    argument.semanticReplayJson,
    domInlineObjectsElements,
    argument.inlineObjectMetaJson,
    argument.cjkStrongSemanticsJson
  );

  rawDomStampRendered(rawDomContext, source);
  return {
    kind: 'success',
    measure: preparation.measure,
  };
}
