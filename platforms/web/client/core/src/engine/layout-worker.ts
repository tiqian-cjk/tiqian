import {
  workerSnapshotSubsetSourceBoundaries,
} from "../sampler/font-face-boundaries.js";
import {
  createManifestFontSession,
  createProbeBootstrapFontSession,
} from "./web-worker/session-bootstrap.js";
import type { ServerReplayFontSession } from "../measurement/browser-font-replay.js";
import type {
  WorkerRequestEnvelope,
  WorkerResponseEnvelope,
} from "./web-worker/worker-channel.js";
import { preparedParagraphPlan } from "./engine-access/prepared-paragraph.js";
import type { DecorationWire } from "./engine-access/wire-types.js";
import { prepareParagraphRequestWire } from "./wire-construction.js";
import type { WorkerLayoutRequestBody } from "./web-worker/worker-channel.js";
import { initializeGlobalServices } from "../services/global-services.js";

type WorkerMessageEventListener = (event: MessageEvent<WorkerRequestEnvelope>) => void | Promise<void>;

interface LayoutWorkerMessageScope {
  addEventListener(type: "message", listener: WorkerMessageEventListener): void;
  postMessage(message: WorkerResponseEnvelope): void;
}

const sessions: Map<string, ServerReplayFontSession> = new Map();

// Workers own a separate global scope; custom-element registration only initializes the page.
initializeGlobalServices();

function errorDetail(error: unknown): string {
  return String(error instanceof Error ? error.message : error).slice(0, 1_000);
}

(globalThis as LayoutWorkerMessageScope).addEventListener("message", async (event: MessageEvent<WorkerRequestEnvelope>) => {
  const message = event.data;
  if (!message || typeof message !== "object") return;
  const { id, type, sessionKey } = message;
  try {
    if (type === "init") {
      let session = sessions.get(sessionKey);
      if (!session) {
        session = message.probeBootstrap === true
          ? await createProbeBootstrapFontSession(sessionKey, message)
          : await createManifestFontSession(message.manifestText!, message.tablesBytes, sessionKey);
        sessions.set(sessionKey, session);
      }
      (globalThis as LayoutWorkerMessageScope).postMessage({ id, ok: true });
      return;
    }
    if (type === "release") {
      sessions.get(sessionKey)?.close?.();
      sessions.delete(sessionKey);
      (globalThis as LayoutWorkerMessageScope).postMessage({ id, ok: true });
      return;
    }
    if (type !== "layout") return;
    const session = sessions.get(sessionKey);
    if (!session) throw new Error("LayoutWorkerFontSessionMissing");
    const request: WorkerLayoutRequestBody = message.request;
    const additionalBoundaries = workerSnapshotSubsetSourceBoundaries(session.faces, request);
    const sourceBoundaries = [
      ...new Set([
        ...request.sourceBoundaries,
        ...additionalBoundaries,
      ]),
    ];
    // WorkerRenderEvidencePassthrough: the field passes through verbatim; an
    // old sender omits it, undefined reaches the nullable ffi parameter as
    // null, and the wire-derived verdict applies, so package version skew
    // keeps both directions working.
    // zeroAdvanceEpsilonPx only prefilters the diagnostics channel, which the
    // worker discards; the plan bytes do not depend on the value.
    // The worker channel sends no decorations; a typed empty array keeps the
    // field at the wire element type. The brand crossing lives in
    // wire-construction.js.
    const decorations: Array<DecorationWire> = [];
    const requestDto = prepareParagraphRequestWire({
      text: request.text,
      maxWidthPx: request.maxWidthPx,
      fontFamilies: request.fontFamilies,
      fontSizePx: request.fontSizePx,
      lineHeightPx: request.lineHeightPx,
      locale: request.locale,
      fontWeight: request.fontWeight,
      italic: request.italic,
      firstLineIndentIc: request.firstLineIndentIc,
      lineLengthGridEnabled: true,
      sourceBoundaries: sourceBoundaries,
      textSpans: request.textSpans,
      inlineBoxes: request.inlineBoxes,
      lineBreakSpans: request.lineBreakSpans,
      inlineObjects: request.inlineObjects,
      decorations: decorations,
      emphasisDotGapEm: null,
      renderEvidenceOverride: request.renderEvidence,
    });
    const plan = preparedParagraphPlan(requestDto, {
      shape: session.shape,
      resolve: session.resolve,
    });
    (globalThis as LayoutWorkerMessageScope).postMessage({ id, ok: true, plan });
  } catch (error) {
    (globalThis as LayoutWorkerMessageScope).postMessage({ id, ok: false, error: errorDetail(error) });
  }
});


