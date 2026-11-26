import {
  FONT_BACKEND_REVISION,
  FONT_REPLAY_REVISION,
  metricReplayKey,
  shapeReplayKey,
} from "../sampler/snapshot/snapshot-schema.js";
import {
  scaleMetricReplayItem,
  scaleShapeReplayItem,
} from "./replay-entry-codec.js";
import type {
  ReplayMetricItem,
  ReplayShapeItem,
  ScaledShapeResult,
} from "./replay-entry-codec.js";
import {
  probeMetricReplayValues,
  probeShapeReplayResult,
} from "./replay-probe.js";
import type { ProbeMeasure } from "./replay-probe.js";
import type { SnapshotManifestFace } from "../sampler/snapshot/snapshot-manifest.js";
import type { SnapshotProbe } from "../sampler/snapshot/snapshot-table-binary.js";
import { globalServices } from "../services/global-services.js";
import { toEngineFontMetrics, toEngineShapingResult } from "../engine/engine-access/host-result.js";
import type { ShapingInput, ShapingResult } from "@tiqian/engine/org/tiqian/shaping/TextShaper";
import type { FontMetricsRequest } from "@tiqian/engine/org/tiqian/font/FontMetrics";
import type { RawFontMetrics } from "@tiqian/engine/org/tiqian/font/RawFontMetrics";

export interface ReplayProbe {
  measure: ProbeMeasure;
}

export interface ServerReplayFontReplay {
  revision: string;
  shapes: ReplayShapeItem[];
  metrics: ReplayMetricItem[];
}

export interface ServerReplayFontSessionOptions {
  replay?: ServerReplayFontReplay;
  probe?: ReplayProbe | null;
  faceMetadata?: SnapshotManifestFace[];
  sessionPrefix?: string;
  harfbuzzVersion?: string;
}

export interface ReplayFontSessionFace {
  family: string;
  style: string;
  weight: readonly number[];
  unicodeRange: string;
  publicUrl: string;
  sourceSha256: string;
  sfntSha256: string;
  faceIndex: number;
  sourceOrder: number;
  axes: Record<string, unknown>;
  localNames: readonly string[];
  coverageText?: string;
  probe?: SnapshotProbe | undefined;
}

// The engine's two host callbacks, as typed adapters. Every descriptor that
// carries the pair references these names instead of repeating an inline
// function type.
export type ShapeFn = (input: ShapingInput) => ShapingResult;
export type MetricsFn = (request: FontMetricsRequest) => RawFontMetrics;

export interface SnapshotSessionCallbacks {
  shape: ShapeFn;
  resolve: MetricsFn;
}

export interface ServerReplayFontSession {
  id: string;
  backendRevision: string;
  harfbuzzVersion: string;
  faces: ReplayFontSessionFace[];
  close: SessionCloser;
  shape: ShapeFn;
  resolve: MetricsFn;
}

interface ReplaySession {
  shapes: Map<string, ReplayShapeItem>;
  metrics: Map<string, ReplayMetricItem>;
  probe: ReplayProbe | null;
}

export interface ReplayRegistry {
  sessions: Map<string, ReplaySession>;
  shapeResults: Map<number, ScaledShapeResult>;
  metricResults: Map<number, number[]>;
  nextSessionId: number;
  nextResultId: number;
}

type ReplayHandleNumberQuery = (handle: number) => number;
type ReplayHandleStringQuery = (handle: number) => string;
type ReplaySlotNumberQuery = (handle: number, index: number) => number;
type ReplaySlotStringQuery = (handle: number, index: number) => string;
type ReplayEdgeNumberQuery = (handle: number, index: number, edge: number) => number;
type ReplayHandleRelease = (handle: number) => void;
type SessionCloser = () => void;

export interface ServerReplayFontBackend {
  shape(
    sessionId: string,
    displayText: string,
    serializedFamilies: string,
    fontSize: number,
    fontWeight: number,
    italic: boolean,
    locale: string,
    role: string,
    sourceText?: string,
  ): number;
  shapeGlyphCount: ReplayHandleNumberQuery;
  shapeGlyphId: ReplaySlotNumberQuery;
  shapeGlyphAdvance: ReplaySlotNumberQuery;
  shapeGlyphX: ReplaySlotNumberQuery;
  shapeGlyphY: ReplaySlotNumberQuery;
  shapeGlyphBound: ReplayEdgeNumberQuery;
  shapeAdvance: ReplayHandleNumberQuery;
  shapeFaceId: ReplayHandleStringQuery;
  shapeFontInstanceId: ReplayHandleStringQuery;
  shapeScript: ReplayHandleStringQuery;
  shapeFeatureCount: ReplayHandleNumberQuery;
  shapeFeature: ReplaySlotStringQuery;
  shapeUnsafeBreakCount: ReplayHandleNumberQuery;
  releaseShape: ReplayHandleRelease;
  metrics(
    sessionId: string,
    serializedFamilies: string,
    fontSize: number,
    fontWeight: number,
    italic: boolean,
    role: string,
    faceSelectionText: string,
  ): number;
  metricValue: ReplaySlotNumberQuery;
  releaseMetrics: ReplayHandleRelease;
}

function replayRegistry(): ReplayRegistry {
  return globalServices().coordination.fonts.replayRegistry;
}

function replayIndex<T extends { key: string }>(items: T[], kind: string): Map<string, T> {
  if (!Array.isArray(items)) throw new Error(`InvalidServerShapingReplay:${kind}`);
  const index = new Map<string, T>();
  for (const item of items) {
    if (!item || typeof item !== "object" || typeof item.key !== "string" || !item.key) {
      throw new Error(`InvalidServerShapingReplay:${kind}`);
    }
    if (index.has(item.key)) throw new Error(`ConflictingServerShapingReplay:${kind}`);
    index.set(item.key, item);
  }
  return index;
}

function createShapeCallback(registry: ReplayRegistry, sessionId: string): ShapeFn {
  return (input: ShapingInput): ShapingResult => {
    const session = registry.sessions.get(sessionId);
    if (!session) throw new Error(`UnknownFontSession:${sessionId}`);

    // Match the server's key for display substitutions by using the source range.
    const sourceText = input.text.substring(input.range.start, input.range.end);
    const displayText = input.displayText;
    const serializedFamilies = input.style.fontFamilies.join("\u001f");
    const fontSize = input.style.fontSize;
    const fontWeight = input.style.fontWeight;
    const italic = input.style.italic;
    const locale = input.style.locale;
    const role = input.fontDecision.role.kind;

    const key = shapeReplayKey(
      displayText,
      serializedFamilies,
      fontWeight,
      italic,
      locale,
      role,
      sourceText,
    );
    let item = session.shapes.get(key);
    if (!item && session.probe) {
      const probedResult = probeShapeReplayResult(
        { displayText, serializedFamilies, fontSize, fontWeight, italic },
        session.probe.measure,
      );
      if (probedResult) {
        item = { key, result: probedResult };
        session.shapes.set(key, item);
      }
    }
    if (!item) throw new Error(`MissingServerShapingReplay:shape:${key}`);
    const handle = registry.nextResultId++;
    registry.shapeResults.set(handle, scaleShapeReplayItem(item, fontSize));
    const glyphs = registry.shapeResults.get(handle)!;

    const range = { start: input.range.start, end: input.range.end };
    const fontKey = input.fontDecision.candidate.key;
    return toEngineShapingResult({
      clusters: [{
        range,
        text: sourceText,
        displayText,
        fontKey,
        advance: glyphs.advance,
      }],
      glyphRuns: [{
        range,
        fontKey,
        glyphs: glyphs.glyphs.map((g) => ({
          id: g.id,
          clusterRange: range,
          advance: g.advance,
          x: g.x,
          y: g.y,
        })),
        advance: glyphs.advance,
        openTypeFeatures: glyphs.features,
      }],
      decisions: [{
        range,
        sourceText,
        displayText,
        fontKey,
        glyphCount: glyphs.glyphs.length,
        advance: glyphs.advance,
        source: "HarfBuzz",
        reason: `SharedHarfBuzzSession:face=${glyphs.faceId}; instance=${glyphs.fontInstanceId}; current-segment-context; features=${glyphs.features.join(",").replace(/^$/, "default")}; unsafeToBreakGlyphs=${glyphs.unsafeBreakCount}`,
        glyphsWithoutInkBounds: glyphs.glyphs.filter((g) => g.bounds === null).length,
        missingGlyphs: glyphs.glyphs.filter((g) => g.id === 0).length,
        resolvedFace: glyphs.faceId,
        script: glyphs.script,
        language: input.style.locale,
        featureEvidence: glyphs.features.length > 0 ? glyphs.features.join(",") : null,
      }],
    });
  };
}

function createMetricsCallback(registry: ReplayRegistry, sessionId: string): MetricsFn {
  return (request: FontMetricsRequest): RawFontMetrics => {
    const session = registry.sessions.get(sessionId);
    if (!session) throw new Error(`UnknownFontSession:${sessionId}`);

    const serializedFamilies = request.fontFamilies.join("\u001f");
    const fontSize = request.fontSize;
    const fontWeight = request.fontWeight;
    const italic = request.italic;
    const role = request.role.kind;
    const faceSelectionText = request.faceSelectionText;

    const key = metricReplayKey(
      serializedFamilies,
      fontWeight,
      italic,
      role,
      faceSelectionText,
    );
    let item = session.metrics.get(key);
    if (!item && session.probe) {
      const valuesEm = probeMetricReplayValues(
        { serializedFamilies, fontSize, fontWeight, italic, role },
        session.probe.measure,
      );
      if (valuesEm) {
        item = { key, valuesEm };
        session.metrics.set(key, item);
      }
    }
    if (!item) throw new Error(`MissingServerShapingReplay:metrics:${key}`);
    const handle = registry.nextResultId++;
    registry.metricResults.set(handle, scaleMetricReplayItem(item, fontSize));

    const metrics = registry.metricResults.get(handle)!;
    return toEngineFontMetrics({
      ascent: metrics[0],
      descent: metrics[1],
      leading: metrics[2],
      source: "RawTables",
      typoAscent: Number.isNaN(metrics[3]) ? null : metrics[3],
      typoDescent: Number.isNaN(metrics[4]) ? null : metrics[4],
    });
  };
}

/**
 * Callback pair for an already-registered session id. The main-thread exact
 * layout path resolves its shaping supply through the coordination registry
 * the session was created in, so a conforming sessionId is sufficient; the
 * closures report an unknown id only if the session was released meanwhile.
 */
export function snapshotSessionCallbacks(sessionId: string): SnapshotSessionCallbacks {
  const registry = replayRegistry();
  return {
    shape: createShapeCallback(registry, sessionId),
    resolve: createMetricsCallback(registry, sessionId),
  };
}

export async function createServerReplayFontSession(
  faceSpecs: unknown[],
  options: ServerReplayFontSessionOptions = {},
): Promise<ServerReplayFontSession> {
  const registry = replayRegistry();
  const replay = options.replay;
  if (!replay || replay.revision !== FONT_REPLAY_REVISION) {
    throw new Error("ServerShapingReplayRevisionMismatch");
  }
  const shapes = replayIndex(replay.shapes, "shapes");
  const metrics = replayIndex(replay.metrics, "metrics");
  const probe = options.probe ?? null;
  if (probe !== null && (typeof probe !== "object" || typeof probe.measure !== "function")) {
    throw new Error("ServerShapingReplayProbeInvalid");
  }
  // ProbeBootstrapEmptyTableAllowance (ADR 0053 A5c): a probe-equipped session
  // may start from empty tables because the probe backfill is the only entry
  // source. Without a probe, empty tables stay a hard failure.
  if ((shapes.size === 0 || metrics.size === 0) && !probe) {
    throw new Error("ServerShapingReplayEmpty");
  }
  const faceMetadata = options.faceMetadata;
  if (!Array.isArray(faceSpecs) || !Array.isArray(faceMetadata) ||
      faceSpecs.length !== faceMetadata.length) {
    throw new Error("ServerShapingReplayFaceMismatch");
  }
  const prefix = String(options.sessionPrefix ?? "tq-browser-replay").trim() || "tq-browser-replay";
  const sessionId = `${prefix}-${registry.nextSessionId++}`;
  registry.sessions.set(sessionId, { shapes, metrics, probe });
  let closed = false;
  const shape = createShapeCallback(registry, sessionId);
  const resolve = createMetricsCallback(registry, sessionId);
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
    shape,
    resolve,
  });
}
