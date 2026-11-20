// Shared browser-font-session fixtures: manifest and face-evidence builders,
// a stub snapshot root, and a loader harness. Extracted verbatim from
// browser-fonts.test.mjs so the timing-golden suite can prepare real session
// handles for the worker message-order journeys.

import { createHash } from "node:crypto";

import {
  createBrowserFontSessionLoader,
  type BrowserFontSessionLoaderOptions,
  type FontSessionCreator,
  type BrowserFontSessionCreateOptions,
} from "@tiqian/core/src/measurement/browser-fonts.js";
import type { ServerReplayFontSession } from "@tiqian/core/src/measurement/browser-font-replay.js";
import {
  FONT_BACKEND_REVISION,
  FONT_REPLAY_REVISION,
} from "@tiqian/core/snapshot-schema.js";
import { writeBinaryTable } from "@tiqian/core/table-binary-encode";
import { probe } from "./runtime-host.js";

type FetchFn = (url: string | URL, init?: RequestInit) => Promise<Response>;
type AsyncSha256Fn = (value: string | Uint8Array) => Promise<string>;
type CreateRenderFontFaceFn = (family: string, source: string, descriptors: Record<string, unknown>) => Promise<Record<string, unknown>>;
type FontSourceReleaseFn = () => boolean;

interface RenderFontSource {
  source: string;
  release: FontSourceReleaseFn;
}

type CreateRenderFontSourceFn = (source: string) => RenderFontSource;

interface FixtureBrowserFontSessionLoaderOptions extends BrowserFontSessionLoaderOptions {
  fetch: FetchFn;
  sha256: AsyncSha256Fn;
  createRenderFontFace: CreateRenderFontFaceFn;
  createRenderFontSource: CreateRenderFontSourceFn;
}

export function digest(bytes: Uint8Array | string): string {
  return createHash("sha256").update(bytes).digest("hex");
}

export interface CurrentTableInfo {
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
let currentTable: CurrentTableInfo | null = null;
const tableBytesByUrl = new Map<string, Uint8Array>();
const chainFetch = globalThis.fetch;
globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
  const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
  const bytes = tableBytesByUrl.get(url);
  if (bytes != null) {
    const arrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
    return new Response(new Blob([new Uint8Array(arrayBuffer)]), { status: 200, statusText: "OK" });
  }
  return chainFetch(input, init);
}) as typeof fetch;

export function getCurrentTable(): CurrentTableInfo | null {
  return currentTable;
}

interface FaceEvidenceOverrides {
  weight?: number[];
  fontWeight?: number;
  [key: string]: unknown;
}

export function faceEvidence(sourceSha256: string, overrides: FaceEvidenceOverrides = {}): Record<string, unknown> {
  const weight = overrides.weight ?? [100, 900];
  const fontWeight = overrides.fontWeight ?? 400;
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
    probe: {
      text: "中国",
      advancePx: 36,
      fontSizePx: 18,
      fontWeight,
      italic: false,
      script: "Hani",
      language: "zh-Hans",
      features: [],
    },
    ...overrides,
  };
}

interface ReplayShapeEntry {
  key: string;
  result: Record<string, unknown>;
}

interface ReplayMetricEntry {
  key: string;
  valuesEm: Record<string, unknown>;
}

interface ManifestExtras {
  replayShapes?: ReplayShapeEntry[];
  replayMetrics?: ReplayMetricEntry[];
  backendRevision?: string;
}

interface ManifestWithFacesOptions {
  versions?: string[];
  typography?: Record<string, unknown>;
  extras?: ManifestExtras;
}

interface ProbeEntry {
  text: string;
  advancePx: number;
  fontSizePx: number;
  fontWeight: number;
  italic: boolean;
  script: string;
  language: string;
  features: string[];
}

export function manifestWithFaces(
  facesByEntry: Record<string, unknown>[][],
  options: ManifestWithFacesOptions = {}
): Record<string, unknown> {
  const { versions, typography = {}, extras = {} } = options;
  const descriptorIndexes = new Map<string, number>();
  const descriptors: Record<string, unknown>[] = [];
  const probes: ProbeEntry[] = [];
  const defaultFeatures: string[] = [];
  const fontFaceEvidence = facesByEntry.map((faces) =>
    faces.map((face) => {
      const descriptor = Object.fromEntries(
        Object.entries(face).filter(([key]) => key !== "coverageText" && key !== "probe")
      );
      const signature = JSON.stringify(descriptor);
      let faceRef = descriptorIndexes.get(signature);
      if (faceRef == null) {
        faceRef = descriptors.length;
        descriptors.push(descriptor);
        descriptorIndexes.set(signature, faceRef);
      }
      const rawProbe = face.probe as Record<string, unknown>;
      const probeEntry: ProbeEntry = probe<ProbeEntry>({
        features: defaultFeatures,
        ...rawProbe,
      });
      const probeSignature = JSON.stringify(probeEntry);
      let probeRef = probes.findIndex((existing) => JSON.stringify(existing) === probeSignature);
      if (probeRef < 0) {
        probeRef = probes.length;
        probes.push(probeEntry);
      }
      return { faceRef, coverageText: face.coverageText, probeRef };
    })
  );

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
    const [
      displayText,
      serializedFamilies,
      fontWeight,
      italic,
      locale,
      role,
      sourceText,
    ] = JSON.parse(shape.key) as [string, string, number, number, string, string, string];
    return [
      replayStringRef(displayText),
      replayStringRef(serializedFamilies),
      fontWeight,
      italic ? 1 : 0,
      replayStringRef(locale),
      replayStringRef(role),
      replayStringRef(sourceText),
      replayStringRef(shape.result.faceId as string),
      replayStringRef(shape.result.fontInstanceId as string),
      replayStringRef(shape.result.script as string),
      (shape.result.features as string[]).map(replayStringRef),
      shape.result.unsafeBreakCount as number,
      shape.result.advanceEm as number,
      (shape.result.glyphs as Array<Record<string, unknown>>).flatMap((glyph) => [
        glyph.id,
        glyph.advanceEm,
        glyph.xEm,
        glyph.yEm,
        ...(glyph.boundsEm as [unknown, unknown, unknown, unknown] ?? [null, null, null, null]),
      ]),
    ];
  });

  const metricRows = (extras.replayMetrics ?? []).map((metric) => {
    const [
      serializedFamilies,
      fontWeight,
      italic,
      role,
      faceSelectionText,
    ] = JSON.parse(metric.key) as [string, number, number, string, string];
    const rawValues: unknown[] = Array.isArray(metric.valuesEm) ? metric.valuesEm : Object.values(metric.valuesEm);
    const valuesEm: (number | null)[] = rawValues.map((v) => (typeof v === "number" || v === null ? v : null));
    return {
      serializedFamilies,
      fontWeight,
      italic: italic !== 0,
      role,
      faceSelectionText,
      valuesEm,
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
      harfbuzzVersion: versions?.[0] ?? "fixture-hb",
    },
  });

  const url = `https://tables.test/fixture-${(tableCounter += 1)}.tiqtbl`;
  tableBytesByUrl.set(url, tableBytes);
  currentTable = { url, bytes: tableBytes, sha256: digest(tableBytes) };

  return {
    schema: 2,
    tables: { snapshot: currentTable.sha256 },
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v16",
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

export interface FontsOverride {
  load(descriptor: unknown, text: string): Promise<unknown[]>;
}

export interface SnapshotRootDocumentOverrides extends Record<string, unknown> {
  fonts?: FontsOverride;
}

export interface SnapshotRootOptions {
  documentOverrides?: SnapshotRootDocumentOverrides;
  fonts?: FontsOverride;
  [key: string]: unknown;
}

export interface ScriptElement {
  textContent: string;
}

export interface TemplateContent {
  querySelector(selector: string): ScriptElement | null;
}

export interface TemplateElement {
  content: TemplateContent;
}

export interface SnapshotOwnerDocument {
  baseURI: string;
  getElementById(id: string): TemplateElement | null;
  [key: string]: unknown;
}

export interface SnapshotRoot {
  ownerDocument: SnapshotOwnerDocument;
  getAttribute(name: string): string | null;
}

export function snapshotRoot(
  manifest: Record<string, unknown>,
  options: SnapshotRootOptions = {}
): SnapshotRoot {
  const { documentOverrides = {} } = options;
  const script: ScriptElement = { textContent: JSON.stringify(manifest) };
  const template: TemplateElement = {
    content: {
      querySelector(selector: string) {
        return selector === "[data-tq-snapshot-manifest]" ? script : null;
      },
    },
  };
  const documentObject: SnapshotOwnerDocument = {
    baseURI: "https://example.test/blog/post/",
    getElementById(id: string) {
      return id === "tq-page" ? template : null;
    },
    ...documentOverrides,
  };
  return {
    ownerDocument: documentObject,
    getAttribute(name: string) {
      if (name === "snapshot-ref") return "tq-page";
      if (name === "tq-tables" && currentTable) return currentTable.url;
      return null;
    },
  };
}

export type MutateSessionFn = (session: Record<string, unknown>) => void;

export interface ContractResult {
  matches: boolean;
  reason: string | null;
}

interface ExtendedBrowserFontSessionLoaderOptions extends BrowserFontSessionLoaderOptions {
  fetch: FetchFn;
  sha256: AsyncSha256Fn;
  createRenderFontFace: CreateRenderFontFaceFn;
  createRenderFontSource: CreateRenderFontSourceFn;
}

export interface HarnessOptions {
  bytes?: Uint8Array;
  fetchError?: Error;
  fetchErrors?: Error[];
  responseOk?: boolean;
  responseStatus?: number;
  createError?: Error;
  mutateSession?: MutateSessionFn;
  documentOverrides?: SnapshotRootDocumentOverrides;
  renderFaceCreateError?: Error;
  renderFaceLoadError?: Error;
  createRenderFontFace?: CreateRenderFontFaceFn;
  createRenderFontSource?: CreateRenderFontSourceFn;
  contractResults?: ContractResult[];
  preparedContractResults?: ContractResult[];
  useDefaultSession?: boolean;
  backendRevision?: string;
  harfbuzzVersion?: string;
}

export interface HarnessRequest {
  url: string | URL;
  init?: RequestInit;
}

export interface HarnessCreateCall {
  specs: unknown;
  options: unknown;
}

export interface HarnessFontLoad {
  descriptor: unknown;
  text: string;
}

export type CloseCountFn = () => number;

export interface HarnessResult {
  loader: ReturnType<typeof createBrowserFontSessionLoader>;
  root: SnapshotRoot;
  requests: HarnessRequest[];
  createCalls: HarnessCreateCall[];
  sessions: Record<string, unknown>[];
  contractCalls: unknown[];
  preparedContractCalls: unknown[];
  renderFaceCreates: Record<string, unknown>[];
  renderFaceAdds: unknown[];
  renderFaceDeletes: unknown[];
  renderFontSourceCreates: string[];
  renderFontSourceReleases: string[];
  fontLoads: HarnessFontLoad[];
  closeCount: CloseCountFn;
}

export function harness(
  manifest: Record<string, unknown>,
  options: HarnessOptions = {}
): HarnessResult {
  const bytes = options.bytes ?? new TextEncoder().encode("fixture-font-source");
  const requests: HarnessRequest[] = [];
  const createCalls: HarnessCreateCall[] = [];
  const sessions: Record<string, unknown>[] = [];
  const contractCalls: unknown[] = [];
  const preparedContractCalls: unknown[] = [];
  const renderFaceCreates: Record<string, unknown>[] = [];
  const renderFaceAdds: unknown[] = [];
  const renderFaceDeletes: unknown[] = [];
  const renderFontSourceCreates: string[] = [];
  const renderFontSourceReleases: string[] = [];
  const fontLoads: HarnessFontLoad[] = [];
  let closeCount = 0;

  const fetch: FetchFn = async (url: string | URL, init?: RequestInit) => {
    requests.push({ url, init });
    const sequencedError = options.fetchErrors?.shift?.();
    if (sequencedError) throw sequencedError;
    if (options.fetchError) throw options.fetchError;
    const status = options.responseStatus ?? (options.responseOk === false ? 500 : 200);
    const arrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
    return new Response(new Blob([new Uint8Array(arrayBuffer)]), {
      status,
      statusText: status === 200 ? "OK" : "Error",
    });
  };

  const createFontSession = async (specs: unknown, createOptions: BrowserFontSessionCreateOptions): Promise<ServerReplayFontSession> => {
    createCalls.push({ specs, options: createOptions });
    if (options.createError) throw options.createError;
    const session = {
      id: `browser-session-${createCalls.length}`,
      backendRevision: options.backendRevision ?? FONT_BACKEND_REVISION,
      harfbuzzVersion: options.harfbuzzVersion ?? "fixture-hb",
      faces: probe<Array<Record<string, unknown>>>(createOptions.faceMetadata || []).map((face) => ({
        ...face,
        weight: [...((face.weight || []) as number[])],
        axisTags: Object.keys(face.axes ?? {}).sort(),
        localNames: [...((face.localNames || []) as string[])],
      })),
      close() {
        closeCount += 1;
      },
    };
    options.mutateSession?.(session);
    sessions.push(session);
    return probe<ServerReplayFontSession>(session);
  };

  const fontSet: FontsOverride = options.documentOverrides?.fonts ?? {
    async load(descriptor: unknown, text: string) {
      fontLoads.push({ descriptor, text });
      return [{}];
    },
  };

  const createRenderFontFace: CreateRenderFontFaceFn = options.createRenderFontFace ?? (async (family: string, source: string, descriptors: Record<string, unknown>) => {
    if (options.renderFaceCreateError) throw options.renderFaceCreateError;
    const face = {
      family,
      source,
      descriptors,
      status: "unloaded",
      async load() {
        if (options.renderFaceLoadError) throw options.renderFaceLoadError;
        face.status = "loaded";
        return face;
      },
    };
    renderFaceCreates.push(face);
    return face;
  });

  const createRenderFontSource: CreateRenderFontSourceFn = options.createRenderFontSource ?? ((source: string) => {
    renderFontSourceCreates.push(source);
    const url = `blob:fixture-font-${renderFontSourceCreates.length}`;
    let released = false;
    const fontSource: RenderFontSource = {
      source: `url("${url}")`,
      release() {
        if (released) return false;
        released = true;
        renderFontSourceReleases.push(url);
        return true;
      },
    };
    return fontSource;
  });

  const rawLoaderOptions: ExtendedBrowserFontSessionLoaderOptions = {
    ...(options.useDefaultSession ? {} : { createFontSession }),
    fetch,
    sha256: async (value: string | Uint8Array) => digest(value),
    createRenderFontFace,
    createRenderFontSource,
    validateContract: async (root: unknown) => {
      contractCalls.push(root);
      const result = options.contractResults?.shift?.();
      return result ?? { matches: true, reason: null };
    },
    ...(options.preparedContractResults
      ? {
          validatePreparedContract: async (root: unknown) => {
            preparedContractCalls.push(root);
            return options.preparedContractResults!.shift() ?? { matches: true, reason: null };
          },
        }
      : {}),
  };
  const loader = createBrowserFontSessionLoader(rawLoaderOptions);

  const rootOptions: SnapshotRootOptions = {
    ...options.documentOverrides,
    fonts: fontSet,
  };

  return {
    loader,
    root: snapshotRoot(manifest, rootOptions),
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