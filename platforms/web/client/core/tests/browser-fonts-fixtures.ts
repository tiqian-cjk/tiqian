// Shared browser-font-session fixtures: manifest and face-evidence builders,
// a stub snapshot root, and a loader harness. Extracted verbatim from
// browser-fonts.test.mjs so the timing-golden suite can prepare real session
// handles for the worker message-order journeys.

import { createHash } from "node:crypto";

import { createBrowserFontSessionLoader } from "../src/measurement/browser-fonts.js";
import type {
  BrowserFontSessionCreateOptions,
  BrowserFontSessionLoader,
  BrowserFontSessionLoaderOptions,
  FontSessionCreator,
  ManifestFaceSpec,
  SnapshotFontContractResult,
} from "../src/measurement/browser-fonts.js";
import type {
  ServerReplayFontSession,
} from "../src/measurement/browser-font-replay.js";
import {
  FONT_BACKEND_REVISION,
  FONT_REPLAY_REVISION,
} from "../src/sampler/snapshot/snapshot-schema.js";
import type { SnapshotProbe } from "../src/sampler/snapshot/snapshot-table-binary.js";
import { writeBinaryTable } from "../src/sampler/snapshot/table-binary-encode.js";
import { FakeElement } from "./snapshot-dom-fixtures.js";

function probe<T>(value: unknown): T {
  return value as T;
}

export function digest(bytes: Uint8Array | ArrayBuffer | string): string {
  return createHash("sha256").update(probe<Uint8Array>(bytes)).digest("hex");
}

export interface LoadedTable {
  url: string;
  bytes: Uint8Array;
  sha256: string;
}

/**
 * Snapshot tables of the manifests the fixtures build. Each manifest pins its
 * own table; the global fetch stub serves the bytes by URL so the transport
 * walks the same path a host page uses.
 */
let tableCounter = 0;
let currentTable: LoadedTable | null = null;
const tableBytesByUrl = new Map<string, Uint8Array>();
const chainFetch = globalThis.fetch;
globalThis.fetch = async (url: string | URL | Request, init?: RequestInit) => {
  const bytes = tableBytesByUrl.get(String(url));
  if (bytes != null) return probe<Response>({ ok: true, arrayBuffer: async () => bytes.buffer });
  return chainFetch(url, init);
};

export function getCurrentTable(): LoadedTable | null {
  return currentTable;
}

export interface ProbeOverride {
  text?: string;
  advancePx?: number;
  fontSizePx?: number;
  fontWeight?: number;
  italic?: boolean;
  script?: string;
  language?: string;
}

export interface FaceEvidenceOverrides {
  weight?: [number, number];
  fontWeight?: number;
  family?: string;
  style?: string;
  unicodeRange?: string;
  publicUrl?: string;
  sourceSha256?: string;
  sfntSha256?: string;
  faceIndex?: number;
  sourceOrder?: number;
  axes?: Record<string, number>;
  localNames?: string[];
  coverageText?: string;
  probe?: ProbeOverride;
  [key: string]: unknown;
}

export interface FaceEvidenceProbe {
  text: string;
  advancePx: number;
  fontSizePx: number;
  fontWeight: number;
  italic: boolean;
  script: string;
  language: string;
}

export interface FaceEvidence {
  family: string;
  style: string;
  weight: [number, number];
  unicodeRange: string;
  publicUrl: string;
  sourceSha256: string;
  sfntSha256: string;
  faceIndex: number;
  sourceOrder: number;
  axes: Record<string, number>;
  localNames: string[];
  coverageText: string;
  probe: FaceEvidenceProbe;
  [key: string]: unknown;
}

export function faceEvidence(sourceSha256: string, overrides: FaceEvidenceOverrides = {}): FaceEvidence {
  const weight = overrides.weight ?? [100, 900];
  const fontWeight = overrides.fontWeight ?? 400;
  const probeOverride = overrides.probe ?? {};
  return {
    family: "Fixture CJK",
    style: "normal",
    weight,
    unicodeRange: "U+0000-9FFF",
    publicUrl: "/assets/fixture-deadbeef.woff2",
    sourceSha256,
    sfntSha256: "b".repeat(64),
    faceIndex: 0,
    sourceOrder: 0,
    axes: { wght: fontWeight },
    localNames: ["Fixture CJK", "FixtureCJK"],
    coverageText: "中国",
    ...overrides,
    probe: {
      text: probeOverride.text ?? "中国",
      advancePx: probeOverride.advancePx ?? 36,
      fontSizePx: probeOverride.fontSizePx ?? 18,
      fontWeight: probeOverride.fontWeight ?? fontWeight,
      italic: probeOverride.italic ?? false,
      script: probeOverride.script ?? "Hani",
      language: probeOverride.language ?? "zh-Hans",
    },
  };
}

export interface ReplayGlyphItem {
  id: number;
  advanceEm: number;
  xEm: number;
  yEm: number;
  boundsEm?: [number | null, number | null, number | null, number | null];
}

export interface ReplayShapeResult {
  glyphs: ReplayGlyphItem[];
  faceId: string;
  fontInstanceId: string;
  script: string;
  features: string[];
  unsafeBreakCount: number;
  advanceEm: number;
}

export interface ReplayShapeEntry {
  key: string;
  result: ReplayShapeResult;
}

export interface ReplayMetricEntry {
  key: string;
  valuesEm: number[];
}

export interface ManifestExtras {
  replayShapes?: ReplayShapeEntry[];
  replayMetrics?: ReplayMetricEntry[];
  backendRevision?: string;
}

export interface ManifestEntryDescriptor {
  [key: string]: unknown;
}

export interface ManifestEntry {
  key: string;
  typographyRef: number;
  fontFaceEvidence: unknown;
}

export interface ManifestFontReplay {
  revision: string;
  encoding: string;
  shapes: unknown[][];
}

export interface ManifestSnapshotTables {
  snapshot: string;
}

export interface BuiltManifest {
  schema: number;
  tables: ManifestSnapshotTables;
  layoutRevision: string;
  renderRevision: string;
  fontSourcePolicy: string;
  renderFontFamilies: string[];
  paragraphSelector: string;
  fontReplay: ManifestFontReplay;
  entries: ManifestEntry[];
  fontContractEntries?: unknown[];
  [key: string]: unknown;
}

export function manifestWithFaces(
  facesByEntry: FaceEvidence[][],
  versions: string[] = facesByEntry.map(() => "fixture-hb"),
  typography: Record<string, unknown> = {},
  extras: ManifestExtras = {},
): BuiltManifest {
  const descriptors: ManifestEntryDescriptor[] = [];
  const descriptorIndexes = new Map<string, number>();
  const probes: SnapshotProbe[] = [];
  const fontFaceEvidence = facesByEntry.map((faces) => faces.map((face) => {
    const descriptor = Object.fromEntries(Object.entries(face).filter(([key]) =>
      key !== "coverageText" && key !== "probe"));
    const signature = JSON.stringify(descriptor);
    let faceRef = descriptorIndexes.get(signature);
    if (faceRef == null) {
      faceRef = descriptors.length;
      descriptors.push(descriptor);
      descriptorIndexes.set(signature, faceRef);
    }
    const probe: SnapshotProbe = { features: [], ...face.probe };
    const probeSignature = JSON.stringify(probe);
    let probeRef = probes.findIndex((existing) => JSON.stringify(existing) === probeSignature);
    if (probeRef < 0) {
      probeRef = probes.length;
      probes.push(probe);
    }
    return { faceRef, coverageText: face.coverageText, probeRef };
  }));
  // Replay and metric strings intern at the head of the table strings, the
  // order the encoder writes; probe strings follow through the writer.
  const replayStrings: string[] = [];
  const replayStringRef = (text: string): number => {
    const existing = replayStrings.indexOf(text);
    if (existing >= 0) return existing;
    replayStrings.push(text);
    return replayStrings.length - 1;
  };
  const shapeRows = (extras.replayShapes ?? []).map((shape) => {
    const [displayText, serializedFamilies, fontWeight, italic, locale, role, sourceText] =
      JSON.parse(shape.key) as [string, string, number, boolean, string, string, string];
    return [
      replayStringRef(displayText),
      replayStringRef(serializedFamilies),
      fontWeight,
      italic ? 1 : 0,
      replayStringRef(locale),
      replayStringRef(role),
      replayStringRef(sourceText),
      replayStringRef(shape.result.faceId),
      replayStringRef(shape.result.fontInstanceId),
      replayStringRef(shape.result.script),
      shape.result.features.map(replayStringRef),
      shape.result.unsafeBreakCount,
      shape.result.advanceEm,
      shape.result.glyphs.flatMap((glyph) => [
        glyph.id, glyph.advanceEm, glyph.xEm, glyph.yEm,
        ...(glyph.boundsEm ?? [null, null, null, null]),
      ]),
    ];
  });
  const metricRows = (extras.replayMetrics ?? []).map((metric) => {
    const [serializedFamilies, fontWeight, italic, role, faceSelectionText] =
      JSON.parse(metric.key) as [string, number, boolean, string, string];
    return {
      serializedFamilies,
      fontWeight,
      italic,
      role,
      faceSelectionText,
      valuesEm: metric.valuesEm,
    };
  });
  for (const row of metricRows) {
    replayStringRef(row.serializedFamilies);
    replayStringRef(row.role);
    replayStringRef(row.faceSelectionText);
  }
  const tableBytes = writeBinaryTable({
    replayStrings,
    metrics: metricRows,
    probes,
    typographies: [{ sha256: "fixture", value: typography }],
    faces: descriptors,
    valueStyles: [],
    fontPreloads: [],
    revisions: {
      backendRevision: extras.backendRevision ?? FONT_BACKEND_REVISION,
      harfbuzzVersion: versions[0],
    },
  });
  const url = `https://tables.test/fixture-${tableCounter += 1}.tiqtbl`;
  tableBytesByUrl.set(url, tableBytes);
  currentTable = { url, bytes: tableBytes, sha256: digest(tableBytes) };
  return {
    schema: 2,
    tables: { snapshot: currentTable.sha256 },
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v17",
    fontSourcePolicy: "host-compatible-stylesheet-v1",
    renderFontFamilies: ["Fixture CJK"],
    paragraphSelector: "p[data-tq-snapshot-key]",
    fontReplay: {
      revision: FONT_REPLAY_REVISION,
      encoding: "shared-strings-v1",
      shapes: shapeRows,
    },
    entries: facesByEntry.map((_faces, index) => ({
      key: `p-${index + 1}`,
      typographyRef: 0,
      fontFaceEvidence: fontFaceEvidence[index],
    })),
  };
}

export type FontsLoadFn = (descriptor: string, text?: string) => Promise<unknown[]>;
export type DocumentGetElementByIdFn = (id: string) => unknown;

export interface SnapshotRootFonts {
  load: FontsLoadFn;
}

export interface SnapshotRootDocumentOverrides {
  fonts?: SnapshotRootFonts;
  baseURI?: string;
  getElementById?: DocumentGetElementByIdFn;
  [key: string]: unknown;
}

export interface SnapshotManifestScriptElement {
  textContent: string;
}

export function snapshotRoot(manifest: unknown, documentOverrides: SnapshotRootDocumentOverrides = {}): HTMLElement {
  const script: SnapshotManifestScriptElement = { textContent: JSON.stringify(manifest) };
  const template = {
    content: {
      querySelector(selector: string): SnapshotManifestScriptElement | null {
        return selector === "[data-tq-snapshot-manifest]" ? script : null;
      },
    },
  };
  const documentObject = {
    baseURI: "https://example.test/blog/post/",
    getElementById(id: string): unknown {
      return id === "tq-page" ? template : null;
    },
    ...documentOverrides,
  };
  const root = new FakeElement("tiqian-prose");
  root.ownerDocument = probe<Document>(documentObject);
  root.setAttribute("snapshot-ref", "tq-page");
  // Override getAttribute to handle special cases
  const originalGetAttribute = root.getAttribute.bind(root);
  root.getAttribute = function (name: string): string | null {
    if (name === "tq-tables" && currentTable) return currentTable.url;
    return originalGetAttribute(name);
  };
  return probe<HTMLElement>(root);
}

export type MutateSessionCallback = (session: Record<string, unknown>) => void;
export type CreateRenderFontFaceFn = (family: string, source: unknown, descriptors: unknown) => unknown;
export type FontReleaseFn = () => boolean;

export interface RenderFontSourceHandle {
  source: string;
  release: FontReleaseFn;
}

export type CreateRenderFontSourceFn = (source: unknown) => RenderFontSourceHandle;
export type CloseCountGetter = () => number;

export interface HarnessOptions {
  bytes?: Uint8Array;
  fetchErrors?: Error[];
  fetchError?: Error;
  responseOk?: boolean;
  responseStatus?: number;
  createError?: Error;
  backendRevision?: string;
  harfbuzzVersion?: string;
  mutateSession?: MutateSessionCallback;
  documentOverrides?: SnapshotRootDocumentOverrides;
  renderFaceCreateError?: Error;
  renderFaceLoadError?: Error;
  contractResults?: SnapshotFontContractResult[];
  preparedContractResults?: SnapshotFontContractResult[];
  useDefaultSession?: boolean;
  createRenderFontFace?: CreateRenderFontFaceFn;
  createRenderFontSource?: CreateRenderFontSourceFn;
}

export interface HarnessCreateCall {
  specs: readonly ManifestFaceSpec[];
  options: BrowserFontSessionCreateOptions;
}

export interface HarnessRequest {
  url: string;
  init?: RequestInit;
}

export interface HarnessFontLoad {
  descriptor: string;
  text?: string;
}

export interface HarnessResult {
  loader: BrowserFontSessionLoader;
  root: HTMLElement;
  requests: HarnessRequest[];
  createCalls: HarnessCreateCall[];
  sessions: unknown[];
  contractCalls: HTMLElement[];
  preparedContractCalls: HTMLElement[];
  renderFaceCreates: unknown[];
  renderFaceAdds: unknown[];
  renderFaceDeletes: unknown[];
  renderFontSourceCreates: unknown[];
  renderFontSourceReleases: string[];
  fontLoads: HarnessFontLoad[];
  closeCount: CloseCountGetter;
}

export function harness(manifest: unknown, options: HarnessOptions = {}): HarnessResult {
  const bytes = options.bytes ?? new TextEncoder().encode("fixture-font-source");
  const requests: HarnessRequest[] = [];
  const createCalls: HarnessCreateCall[] = [];
  const sessions: unknown[] = [];
  const contractCalls: HTMLElement[] = [];
  const preparedContractCalls: HTMLElement[] = [];
  const renderFaceCreates: unknown[] = [];
  const renderFaceAdds: unknown[] = [];
  const renderFaceDeletes: unknown[] = [];
  const renderFontSourceCreates: unknown[] = [];
  const renderFontSourceReleases: string[] = [];
  const fontLoads: HarnessFontLoad[] = [];
  let closeCount = 0;
  const fetch = async (url: string | URL | Request, init?: RequestInit): Promise<Response> => {
    requests.push({ url: String(url), init });
    const sequencedError = options.fetchErrors?.shift?.();
    if (sequencedError) throw sequencedError;
    if (options.fetchError) throw options.fetchError;
    return probe<Response>({
      ok: options.responseOk ?? true,
      status: options.responseStatus ?? 200,
      async arrayBuffer() {
        return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      },
    });
  };
  const createFontSession = async (specs: readonly ManifestFaceSpec[], createOptions: BrowserFontSessionCreateOptions): Promise<ServerReplayFontSession> => {
    createCalls.push({ specs, options: createOptions });
    if (options.createError) throw options.createError;
    const session = {
      id: `browser-session-${createCalls.length}`,
      backendRevision: options.backendRevision ?? FONT_BACKEND_REVISION,
      harfbuzzVersion: options.harfbuzzVersion ?? "fixture-hb",
      faces: (createOptions.faceMetadata ?? []).map((face) => ({
        ...face,
        weight: [...face.weight],
        axisTags: Object.keys(face.axes ?? {}).sort(),
        localNames: [...face.localNames],
      })),
      close() {
        closeCount += 1;
      },
    };
    options.mutateSession?.(probe<Record<string, unknown>>(session));
    sessions.push(session);
    return probe<ServerReplayFontSession>(session);
  };
  const fontSet: SnapshotRootFonts = options.documentOverrides?.fonts ?? {
    async load(descriptor: string, text?: string) {
      fontLoads.push({ descriptor, text });
      return [{}];
    },
  };
  const createRenderFontFace: CreateRenderFontFaceFn = options.createRenderFontFace ?? ((family: string, source: unknown, descriptors: unknown) => {
    if (options.renderFaceCreateError) throw options.renderFaceCreateError;
    const face = {
      family,
      source,
      descriptors,
      status: "unloaded",
      async load() {
        if (options.renderFaceLoadError) throw options.renderFaceLoadError;
        this.status = "loaded";
        return this;
      },
    };
    renderFaceCreates.push(face);
    return face;
  });
  const createRenderFontSource: CreateRenderFontSourceFn = options.createRenderFontSource ?? ((source: unknown) => {
    renderFontSourceCreates.push(source);
    const url = `blob:fixture-font-${renderFontSourceCreates.length}`;
    let released = false;
    const handle: RenderFontSourceHandle = {
      source: `url("${url}")`,
      release() {
        if (released) return false;
        released = true;
        renderFontSourceReleases.push(url);
        return true;
      },
    };
    return handle;
  });
  const loaderOptions: BrowserFontSessionLoaderOptions = {
    ...(options.useDefaultSession ? {} : { createFontSession: probe<FontSessionCreator>(createFontSession) }),
    validateContract: async (root: HTMLElement): Promise<SnapshotFontContractResult> => {
      contractCalls.push(root);
      const result = options.contractResults?.shift?.();
      return result ?? { matches: true, reason: null };
    },
    ...(options.preparedContractResults ? {
      validatePreparedContract: async (root: HTMLElement): Promise<SnapshotFontContractResult> => {
        preparedContractCalls.push(root);
        return options.preparedContractResults?.shift?.() ?? { matches: true, reason: null };
      },
    } : {}),
  };
  const loader = createBrowserFontSessionLoader(loaderOptions);
  return {
    loader,
    root: snapshotRoot(manifest, { ...options.documentOverrides, fonts: fontSet }),
    requests,
    createCalls,
    sessions,
    contractCalls,
    preparedContractCalls,
    renderFaceCreates,
    renderFaceAdds,
    renderFaceDeletes,
    renderFontSourceCreates,
    renderFontSourceReleases,
    fontLoads,
    closeCount: () => closeCount,
  };
}
