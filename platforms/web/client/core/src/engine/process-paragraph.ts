import { globalServices } from "../services/global-services.js";
// processParagraph (TsHost runtime port, Slice 4d-1). Ports the paragraph
// processing orchestration from WebEnhancerParagraphPipeline.kt
// (processParagraph, lines 89-227, and layoutParagraph, lines 229-264).
// The module coordinates paragraph eligibility, style capture, markdown
// lowering, snapshot layout Worker queries with rich fallback detection,
// direct prepare/commit dispatch, and capability issue reporting.
//
// Stateless module: processParagraph(context, paragraph) is a named function
// that receives the EnhancedElementContext as its first parameter; runtime
// options, the browser fallback descriptor, the snapshot session view, the
// tracked-paragraph accumulation and the issue ledger all come off the
// context's part surface. The stateless worker-request,
// prepare-paragraph-layout, lifecycle, eligibility, markdown-lowering,
// prepared-metadata and commit-prepared-paragraph helpers are imported
// directly.
//
// Embedding constraint: the generator wraps this file in a Kotlin raw string,
// so the source must contain no dollar sign and no triple double-quote
// sequence. Use string concatenation, never template literals.

// Ambient global declarations pulled in via import type from owner modules.
import type { LoweredParagraph } from "./lowered-paragraph.js";
import type { CapabilityIssueRecord, EnhanceOptions, ResolvedEnhanceOptions } from "./lifecycle.js";
import {
  applyConfiguredHostFontSize,
  captureSourceInlineSize,
  conformingSnapshotFontSessionId,
  reportIssue,
  stabilizeContentSizedItemInlineSize,
} from "./lifecycle.js";
import {
  classifyRole as classifyFontRole,
  classifyRoles as classifyFontRoles,
  firstDivergentInlineShapingProperty,
  unsupportedInlineShapingProperties,
} from "./engine-access/font-role.js";
import { InlineShapingStylePolicy } from "@tiqian/engine/org/tiqian/font/InlineShapingStylePolicy";
import type { EnhancedElementContext } from "./context/enhance-context.js";
import type { DiagnosisIssueRecord } from "./context/diagnosis-manager.js";
import type { TrackedParagraph } from "./enhance/context-state.js";
import { activeSnapshotSessionDescriptor } from "./enhance/snapshot-adoption.js";
import {
  rawDomBegin,
  rawDomTake,
  rawDomCommit,
  rawDomRestoreParagraph,
} from "./raw-dom.js";
import { shouldTryParagraph } from "./eligibility.js";
import { lowerMarkdown } from "./markdown-lowering.js";
import {
  preparedCjkStrongSemanticsJson,
  preparedInlineObjectMetaJson,
  preparedSemanticReplayJson,
} from "./prepared-metadata.js";
import { workerLayoutRequest } from "./worker-request.js";
import { prepareParagraphLayout } from "./prepare-paragraph-layout.js";
import {
  commitPreparedParagraph,
  commitWorkerPreparedParagraph,
} from "./commit-prepared-paragraph.js";

interface ProcessInlineShapingDecisionResult {
  name: string;
  detail: string;
}

  // Constants named after the Kotlin constants in WebEnhancerSupport.kt:
  // lines 470-475 and 483-489.
  const CANONICAL_SOURCE_ATTRIBUTE = 'data-tq-canonical-source';
  const SNAPSHOT_PREPARED_DOM_ATTRIBUTE = 'data-tq-snapshot-prepared-dom';
  const RUNTIME_RENDER_FONT_ATTRIBUTE = 'data-tq-runtime-render-font';
  const HOST_INLINE_SIZE_ATTRIBUTE = 'data-tq-host-inline-size';
  const SNAPSHOT_FONT_SESSION_CAPABILITY_FAILURES = [
    'NoSnapshotFontFace',
    'MissingGlyph',
    'MissingServerShapingReplay',
    'NoSnapshotMetricFace',
    'NonUniformUnicodeRangeMetrics',
  ];

  // CanonicalPlainParagraph: inline twin of isCanonicalPlainParagraph in
  // lowered-paragraph.js (line 110). True when all six styled collections
  // are empty.
  function isCanonicalPlain(lowered: LoweredParagraph): boolean {
    return lowered.spans.length === 0 &&
      lowered.decorations.length === 0 &&
      lowered.inlineBoxes.length === 0 &&
      lowered.inlineObjects.length === 0 &&
      lowered.domInlineObjects.length === 0 &&
      lowered.sourceSpans.length === 0;
  }

  // CapabilityFailureDetail: inline twin of
  // isSnapshotFontSessionCapabilityFailureDetail in WebEnhancerSupport.kt
  // (line 140). Returns false when detail is null.
  function isCapabilityFailureDetail(detail: unknown): boolean {
    if (detail == null) return false;
    const str = String(detail);
    for (let i = 0; i < SNAPSHOT_FONT_SESSION_CAPABILITY_FAILURES.length; i += 1) {
      if (str.indexOf(SNAPSHOT_FONT_SESSION_CAPABILITY_FAILURES[i]) !== -1) {
        return true;
      }
    }
    return false;
  }

  // LoweringHelpers: inline twin of the helpers builder in worker-request.js
  // (lines 258-269).
  function loweringHelpers(): Record<string, unknown> {
    return {
      classifyRole: classifyFontRole,
      classifyRoles: classifyFontRoles,
      inlineShapingDecision: function (tag: string, elementValues: string[], paragraphValues: string[]): ProcessInlineShapingDecisionResult | null {
        const property = InlineShapingStylePolicy.firstDivergentProperty(elementValues, paragraphValues);
        return property == null ? null : { name: 'UnsupportedInlineShapingStyle', detail: tag + ':' + property };
      },
      inlineShapingProperties: InlineShapingStylePolicy.unsupportedInlineShapingProperties.slice(),
    };
  }

  /**
   * Process a single paragraph element through markdown lowering, rawDom
   * takeover, layout preparation, and commit.
   *
   * @param {Object} context
   * @param {Element} paragraph
   */
  export function processParagraph(context: EnhancedElementContext, paragraph: Element): void {
    if (!shouldTryParagraph(paragraph)) return;

    const options = context.contextState.runtimeOptions as ResolvedEnhanceOptions;

    // Capture host-owned inline typography before any computed-style probe.
    // CSSStyleDeclaration can leave an empty style attribute after a
    // temporary property is removed even when the source had no attribute.
    const originalStyleAttribute = paragraph.getAttribute('style');

    let lowered: LoweredParagraph | null = null;
    try {
      const loweringResult = lowerMarkdown(
        paragraph,
        options,
        loweringHelpers()
      );
      if (loweringResult && loweringResult.ok === true) {
        lowered = loweringResult.lowered;
      } else {
        const issue = (loweringResult && loweringResult.issue) || {
          name: 'UnsupportedParagraph',
          detail: 'paragraph could not be lowered',
          element: paragraph,
          reportToConsole: true,
        };
        if (issue.element == null) issue.element = paragraph;
        if (issue.reportToConsole == null) issue.reportToConsole = true;
        reportIssue(issue);
        context.diagnosis.issues.push(issue as DiagnosisIssueRecord);
        return;
      }
    } catch (error) {
      const loweringIssue: CapabilityIssueRecord = {
        name: 'DomLoweringFailure',
        detail: ((error && (error as { message?: string }).message) as string) || 'unexpected DOM lowering failure',
        element: paragraph,
        reportToConsole: true,
      };
      reportIssue(loweringIssue);
      context.diagnosis.issues.push(loweringIssue as DiagnosisIssueRecord);
      return;
    }

    const paragraphStyle = (paragraph as HTMLElement).style;
    rawDomBegin(
      context,
      paragraph,
      paragraph.getAttribute('data-tq-rendered'),
      paragraph.getAttribute('data-tq-canonical-plain'),
      paragraph.getAttribute(CANONICAL_SOURCE_ATTRIBUTE),
      paragraph.getAttribute(SNAPSHOT_PREPARED_DOM_ATTRIBUTE),
      paragraph.getAttribute('lang'),
      originalStyleAttribute,
      paragraphStyle ? paragraphStyle.getPropertyValue('position') : '',
      paragraphStyle ? paragraphStyle.getPropertyPriority('position') : '',
      paragraphStyle ? paragraphStyle.getPropertyValue('inline-size') : '',
      paragraphStyle ? paragraphStyle.getPropertyPriority('inline-size') : '',
      paragraphStyle ? paragraphStyle.getPropertyValue('font-size') : '',
      paragraphStyle ? paragraphStyle.getPropertyPriority('font-size') : '',
      paragraph.getAttribute(HOST_INLINE_SIZE_ATTRIBUTE)
    );

    const hostFontSizeApplied = applyConfiguredHostFontSize(
      paragraph as HTMLElement,
      options ? (options.fontSize as number | undefined) : undefined
    );
    const sourceInlineSize = captureSourceInlineSize(paragraph);

    // PreparedDomLane: the prepared-DOM flag dissolved from root-state.ts
    // never had a write path in the shipped runtime, so the active options
    // are the runtime options unchanged (the former withoutSnapshotFontSession
    // branch is unreachable).
    const activeOptions: EnhanceOptions = options;

    const workerRequest = workerLayoutRequest(
      paragraph,
      lowered,
      activeOptions
    );
    const sessionKey = conformingSnapshotFontSessionId(activeOptions);
    // The layout Worker channel is installed by the host page bundle and by
    // test worlds per test; an absent channel reads as no reusable plan, the
    // same tolerance the former Kotlin shims applied.
    const layoutWorker = globalServices().coordination.layoutWorker;

    // Older host bundles expose only the string form of the Worker bridge.
    let workerPlan;
    let workerIssue;
    if (workerRequest != null && sessionKey != null && layoutWorker != null) {
      if (layoutWorker.lookup) {
        const result = layoutWorker.lookup(sessionKey, workerRequest);
        workerPlan = result?.prepared;
        workerIssue = result?.issue;
      } else {
        const requestText = JSON.stringify(workerRequest);
        workerPlan = layoutWorker.take(paragraph, sessionKey, requestText);
        if (workerPlan == null) workerIssue = layoutWorker.issue(paragraph, sessionKey, requestText);
      }
    }

    // WorkerIneligibleRichRunBrowserFallback: SSR and the exact Worker
    // still fail closed when a semantic run has no replayable font
    // evidence. In the live browser, a rich paragraph can shape just that
    // unsupported run through its resolved host font while covered runs
    // remain on the snapshot session. The progressive scheduler bounds this
    // main-thread fallback to the individual paragraph slice.
    const canUseRichBrowserFallback = !isCanonicalPlain(lowered) && isCapabilityFailureDetail(workerIssue);

    if (
      activeOptions &&
      activeOptions.requireSnapshotLayoutWorker &&
      workerRequest != null &&
      workerPlan == null &&
      !canUseRichBrowserFallback
    ) {
      if (originalStyleAttribute == null) {
        paragraph.removeAttribute('style');
      } else {
        paragraph.setAttribute('style', originalStyleAttribute);
      }
      const snapshotWorkerIssue = {
        name: 'SnapshotLayoutWorkerPlanUnavailable',
        detail: workerIssue || 'the snapshot layout Worker produced no reusable plan',
        element: paragraph,
        reportToConsole: true,
      };
      reportIssue(snapshotWorkerIssue);
      context.diagnosis.issues.push(snapshotWorkerIssue as DiagnosisIssueRecord);
      return;
    }

    rawDomTake(context, paragraph, hostFontSizeApplied);
    const hostInlineSizeApplied = stabilizeContentSizedItemInlineSize(
      paragraph as HTMLElement,
      sourceInlineSize
    );

    paragraph.setAttribute('data-tq-rendered', 'true');
    paragraph.setAttribute(RUNTIME_RENDER_FONT_ATTRIBUTE, 'true');

    const item: TrackedParagraph = {
      source: paragraph,
      lowered: lowered,
      lastMeasure: null,
    };

    rawDomCommit(context, paragraph, hostInlineSizeApplied);

    let layoutIssue = null;
    try {
      if (workerPlan != null) {
        layoutIssue = commitWorkerPreparedParagraph(
          context,
          {
            paragraph: item,
            workerPlan: workerPlan,
            inlineObjectMetaJson: preparedInlineObjectMetaJson(lowered),
            cjkStrongSemanticsJson: preparedCjkStrongSemanticsJson(lowered),
          }
        );
      } else {
        const preparation = prepareParagraphLayout(
          {
            paragraph: item,
            options: activeOptions,
            snapshotSession: activeSnapshotSessionDescriptor(activeOptions),
            browserFallback: context.typography.browserFallback,
          }
        );
        if (preparation.kind === 'unchanged') {
          layoutIssue = null;
        } else if (preparation.kind === 'unsupported') {
          layoutIssue = preparation;
        } else if (preparation.kind === 'ready') {
          const commitResult = commitPreparedParagraph(
            context,
            {
              paragraph: item,
              preparation: preparation,
              options: activeOptions,
              browserFallback: context.typography.browserFallback,
                semanticReplayJson: preparedSemanticReplayJson(lowered),
              inlineObjectMetaJson: preparedInlineObjectMetaJson(lowered),
              cjkStrongSemanticsJson: preparedCjkStrongSemanticsJson(lowered),
            }
          );
          if (commitResult.kind === 'success') {
            item.lastMeasure = commitResult.measure;
            layoutIssue = null;
          } else {
            layoutIssue = commitResult;
          }
        }
      }
    } catch (error) {
      layoutIssue = {
        name: 'WebEnhancementFailure',
        detail: (error && (error as { message?: string }).message) || 'unexpected layout or DOM rendering failure',
        element: paragraph,
        reportToConsole: true,
      };
    }

    if (layoutIssue == null) {
      context.contextState.pushParagraph(item);
    } else {
      rawDomRestoreParagraph(context, paragraph);
      if (layoutIssue.element == null) {
        layoutIssue.element = paragraph;
      }
      if (layoutIssue.reportToConsole == null) {
        layoutIssue.reportToConsole = true;
      }
      reportIssue(layoutIssue as CapabilityIssueRecord);
      context.diagnosis.issues.push(layoutIssue as DiagnosisIssueRecord);
    }
  }
