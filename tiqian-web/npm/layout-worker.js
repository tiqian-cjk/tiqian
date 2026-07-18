import { createServerReplayFontSession } from "./browser-font-replay.js";
import {
  mergeSerializedSourceBoundaries,
  workerExactSubsetSourceBoundaries,
} from "./font-face-boundaries.js";
import { parseSnapshotManifest } from "./snapshot-manifest.js";
import { precomputeParagraph } from "./precompute-runtime/Tiqian-tiqian-web-precompute.mjs";

const sessions = new Map();

function manifestSession(manifestText, sessionKey) {
  const manifest = parseSnapshotManifest(manifestText);
  const entries = [...(manifest.entries ?? []), ...(manifest.fontContractEntries ?? [])];
  const evidence = entries.flatMap((entry) => entry?.fontEvidence?.faces ?? []);
  if (evidence.length === 0 || !manifest.fontReplay) {
    throw new Error("LayoutWorkerFontContractInvalid");
  }
  const faces = [];
  const seen = new Set();
  for (const face of evidence) {
    const key = JSON.stringify([
      face.sfntSha256,
      face.faceIndex,
      face.sourceOrder,
      face.family,
      face.style,
      face.weight,
      face.unicodeRange,
      face.publicUrl,
    ]);
    if (seen.has(key)) continue;
    seen.add(key);
    faces.push(face);
  }
  faces.sort((left, right) => Number(left.sourceOrder) - Number(right.sourceOrder));
  const first = entries.find((entry) => entry?.fontEvidence)?.fontEvidence;
  return createServerReplayFontSession(
    faces.map(() => ({})),
    {
      sessionPrefix: `tq-worker-${sessionKey}`,
      replay: manifest.fontReplay,
      faceMetadata: faces,
      harfbuzzVersion: first?.harfbuzzVersion ?? "",
    },
  );
}

function errorDetail(error) {
  return String(error instanceof Error ? error.message : error).slice(0, 1_000);
}

globalThis.addEventListener("message", async (event) => {
  const message = event.data;
  if (!message || typeof message !== "object") return;
  const { id, type, sessionKey } = message;
  try {
    if (type === "init") {
      let session = sessions.get(sessionKey);
      if (!session) {
        session = await manifestSession(message.manifestText, sessionKey);
        sessions.set(sessionKey, session);
      }
      globalThis.postMessage({ id, ok: true });
      return;
    }
    if (type === "release") {
      sessions.get(sessionKey)?.close?.();
      sessions.delete(sessionKey);
      globalThis.postMessage({ id, ok: true });
      return;
    }
    if (type !== "layout") return;
    const session = sessions.get(sessionKey);
    if (!session) throw new Error("LayoutWorkerFontSessionMissing");
    const request = message.request;
    const sourceBoundaries = mergeSerializedSourceBoundaries(
      request.sourceBoundaries,
      workerExactSubsetSourceBoundaries(session.faces, request),
    );
    const plan = precomputeParagraph(
      session.id,
      request.text,
      request.maxWidthPx,
      request.fontFamilies,
      request.fontSizePx,
      request.lineHeightPx,
      request.locale,
      request.fontWeight,
      request.italic,
      request.firstLineIndentIc,
      true,
      sourceBoundaries,
      request.textSpans,
      request.inlineBoxes,
    );
    globalThis.postMessage({ id, ok: true, plan });
  } catch (error) {
    globalThis.postMessage({ id, ok: false, error: errorDetail(error) });
  }
});
