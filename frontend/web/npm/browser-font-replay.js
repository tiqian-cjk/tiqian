import {
  FONT_BACKEND_REVISION,
  FONT_REPLAY_REVISION,
  metricReplayKey,
  shapeReplayKey,
} from "./snapshot-schema.js";

const REGISTRY_KEY = Symbol.for(`org.tiqian.web.font-replay.${FONT_REPLAY_REVISION}`);
const registry = globalThis[REGISTRY_KEY] ??= {
  sessions: new Map(),
  shapeResults: new Map(),
  metricResults: new Map(),
  nextSessionId: 1,
  nextResultId: 1,
};

function finiteNumber(value, field) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new Error(`InvalidServerShapingReplay:${field}`);
  }
  return value;
}

function replayIndex(items, kind) {
  if (!Array.isArray(items)) throw new Error(`InvalidServerShapingReplay:${kind}`);
  const index = new Map();
  for (const item of items) {
    if (!item || typeof item !== "object" || typeof item.key !== "string" || !item.key) {
      throw new Error(`InvalidServerShapingReplay:${kind}`);
    }
    if (index.has(item.key)) throw new Error(`ConflictingServerShapingReplay:${kind}`);
    index.set(item.key, item);
  }
  return index;
}

function scaledShape(item, fontSize) {
  const result = item?.result;
  if (!result || typeof result !== "object" || !Array.isArray(result.glyphs)) {
    throw new Error("InvalidServerShapingReplay:shape-result");
  }
  const scale = finiteNumber(Number(fontSize), "font-size");
  if (scale <= 0) throw new Error("InvalidServerShapingReplay:font-size");
  const glyphs = result.glyphs.map((glyph) => {
    if (!glyph || typeof glyph !== "object" || !Number.isSafeInteger(glyph.id) || glyph.id < 0) {
      throw new Error("InvalidServerShapingReplay:glyph");
    }
    const bounds = glyph.boundsEm == null
      ? null
      : glyph.boundsEm.map((value, index) => finiteNumber(value, `glyph-bound-${index}`) * scale);
    if (bounds != null && bounds.length !== 4) {
      throw new Error("InvalidServerShapingReplay:glyph-bounds");
    }
    return {
      id: glyph.id,
      advance: finiteNumber(glyph.advanceEm, "glyph-advance") * scale,
      x: finiteNumber(glyph.xEm, "glyph-x") * scale,
      y: finiteNumber(glyph.yEm, "glyph-y") * scale,
      bounds,
    };
  });
  if (!Array.isArray(result.features) || result.features.some((value) => typeof value !== "string")) {
    throw new Error("InvalidServerShapingReplay:features");
  }
  const unsafeBreakCount = Number(result.unsafeBreakCount ?? 0);
  if (!Number.isSafeInteger(unsafeBreakCount) || unsafeBreakCount < 0) {
    throw new Error("InvalidServerShapingReplay:unsafe-break-count");
  }
  return {
    faceId: String(result.faceId ?? ""),
    fontInstanceId: String(result.fontInstanceId ?? ""),
    script: String(result.script ?? ""),
    features: [...result.features],
    unsafeBreakCount,
    advance: finiteNumber(result.advanceEm, "shape-advance") * scale,
    glyphs,
  };
}

function scaledMetrics(item, fontSize) {
  if (!Array.isArray(item?.valuesEm) || item.valuesEm.length !== 5) {
    throw new Error("InvalidServerShapingReplay:metrics-result");
  }
  const scale = finiteNumber(Number(fontSize), "font-size");
  if (scale <= 0) throw new Error("InvalidServerShapingReplay:font-size");
  return item.valuesEm.map((value, index) => value == null
    ? Number.NaN
    : finiteNumber(value, `metric-${index}`) * scale);
}

function installReplayBackend() {
  if (globalThis.__TiqianFontBackend) {
    if (globalThis.__TiqianFontBackendReplayRegistry === registry) return;
    throw new Error("FontBackendGlobalCollision");
  }
  globalThis.__TiqianFontBackendRevision = FONT_BACKEND_REVISION;
  globalThis.__TiqianFontBackendReplayRegistry = registry;
  globalThis.__TiqianFontBackend = {
    shape(
      sessionId,
      displayText,
      serializedFamilies,
      fontSize,
      fontWeight,
      italic,
      locale,
      role,
      sourceText = displayText,
    ) {
      const session = registry.sessions.get(sessionId);
      if (!session) throw new Error(`UnknownFontSession:${sessionId}`);
      const key = shapeReplayKey(
        displayText,
        serializedFamilies,
        fontWeight,
        italic,
        locale,
        role,
        sourceText,
      );
      const item = session.shapes.get(key);
      if (!item) throw new Error(`MissingServerShapingReplay:shape:${key}`);
      const handle = registry.nextResultId++;
      registry.shapeResults.set(handle, scaledShape(item, fontSize));
      return handle;
    },
    shapeGlyphCount: (handle) => registry.shapeResults.get(handle)?.glyphs.length ?? 0,
    shapeGlyphId: (handle, index) => registry.shapeResults.get(handle)?.glyphs[index]?.id ?? 0,
    shapeGlyphAdvance: (handle, index) =>
      registry.shapeResults.get(handle)?.glyphs[index]?.advance ?? 0,
    shapeGlyphX: (handle, index) => registry.shapeResults.get(handle)?.glyphs[index]?.x ?? 0,
    shapeGlyphY: (handle, index) => registry.shapeResults.get(handle)?.glyphs[index]?.y ?? 0,
    shapeGlyphBound(handle, index, edge) {
      return registry.shapeResults.get(handle)?.glyphs[index]?.bounds?.[edge] ?? Number.NaN;
    },
    shapeAdvance: (handle) => registry.shapeResults.get(handle)?.advance ?? 0,
    shapeFaceId: (handle) => registry.shapeResults.get(handle)?.faceId ?? "",
    shapeFontInstanceId: (handle) => registry.shapeResults.get(handle)?.fontInstanceId ?? "",
    shapeScript: (handle) => registry.shapeResults.get(handle)?.script ?? "",
    shapeFeatureCount: (handle) => registry.shapeResults.get(handle)?.features.length ?? 0,
    shapeFeature: (handle, index) => registry.shapeResults.get(handle)?.features[index] ?? "",
    shapeUnsafeBreakCount: (handle) => registry.shapeResults.get(handle)?.unsafeBreakCount ?? 0,
    releaseShape: (handle) => registry.shapeResults.delete(handle),
    metrics(sessionId, serializedFamilies, fontSize, fontWeight, italic, role, faceSelectionText) {
      const session = registry.sessions.get(sessionId);
      if (!session) throw new Error(`UnknownFontSession:${sessionId}`);
      const key = metricReplayKey(
        serializedFamilies,
        fontWeight,
        italic,
        role,
        faceSelectionText,
      );
      const item = session.metrics.get(key);
      if (!item) throw new Error(`MissingServerShapingReplay:metrics:${key}`);
      const handle = registry.nextResultId++;
      registry.metricResults.set(handle, scaledMetrics(item, fontSize));
      return handle;
    },
    metricValue: (handle, index) => registry.metricResults.get(handle)?.[index] ?? Number.NaN,
    releaseMetrics: (handle) => registry.metricResults.delete(handle),
  };
}

export async function createServerReplayFontSession(faceSpecs, options = {}) {
  const replay = options.replay;
  if (!replay || replay.revision !== FONT_REPLAY_REVISION) {
    throw new Error("ServerShapingReplayRevisionMismatch");
  }
  const shapes = replayIndex(replay.shapes, "shapes");
  const metrics = replayIndex(replay.metrics, "metrics");
  if (shapes.size === 0 || metrics.size === 0) {
    throw new Error("ServerShapingReplayEmpty");
  }
  const faceMetadata = options.faceMetadata;
  if (!Array.isArray(faceSpecs) || !Array.isArray(faceMetadata) ||
      faceSpecs.length !== faceMetadata.length) {
    throw new Error("ServerShapingReplayFaceMismatch");
  }
  installReplayBackend();
  const prefix = String(options.sessionPrefix ?? "tq-browser-replay").trim() || "tq-browser-replay";
  const sessionId = `${prefix}-${registry.nextSessionId++}`;
  registry.sessions.set(sessionId, { shapes, metrics });
  let closed = false;
  return Object.freeze({
    id: sessionId,
    backendRevision: FONT_BACKEND_REVISION,
    harfbuzzVersion: String(options.harfbuzzVersion ?? ""),
    faces: faceMetadata.map((face) => Object.freeze({
      ...face,
      weight: Object.freeze([...face.weight]),
      axisTags: Object.freeze(Object.keys(face.axes ?? {}).sort()),
      localNames: Object.freeze([...face.localNames]),
    })),
    close() {
      if (closed) return;
      closed = true;
      registry.sessions.delete(sessionId);
    },
  });
}
