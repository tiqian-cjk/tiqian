import { createServerReplayFontSession } from "./browser-font-replay.js";
import { loadBrowserFontFaces } from "./font-face-loader.js";
import type {
  ReplayFontSessionFace,
  ServerReplayFontReplay,
  ServerReplayFontSession,
  ServerReplayFontSessionOptions,
} from "./browser-font-replay.js";
import {
  FONT_BACKEND_REVISION,
  FONT_REPLAY_REVISION,
  FONT_SOURCE_POLICY,
  LAYOUT_REVISION,
  RENDER_REVISION,
  readableSnapshotSchema,
} from "../sampler/snapshot/snapshot-schema.js";
import { expandSnapshotManifest } from "../sampler/snapshot/snapshot-manifest.js";
import type { ExpandedSnapshotManifest, SnapshotManifestWire } from "../sampler/snapshot/snapshot-manifest.js";
import { snapshotTablesForRoot } from "../sampler/snapshot/snapshot-tables.js";
import type { LoadedSnapshotTable } from "../sampler/snapshot/snapshot-tables.js";
import {
  validatePrecomputedSnapshotFontReplayContract,
  validatePrecomputedSnapshotFontReplayLiveContract,
} from "../sampler/snapshot/precomputed.js";
// Ambient global declarations pulled in via import type from owner modules.
import type { TiqianLayoutWorkerInstance } from "../engine/coordination/coordination-service.js";
import { globalServices } from "../services/global-services.js";

const HASH_PATTERN = /^[a-f0-9]{64}$/u;
const HANDLE_STATE = Symbol("tiqian.browserFontSession");
const PARSER_PENDING_CONTRACT_REASONS = new Set<string | null | undefined>([
  "SnapshotTemplateMissing",
  "SnapshotCandidateSetMismatch",
  "SnapshotCandidateKeyInvalid",
  "SnapshotEntryMissing",
  "SnapshotSourceMismatch",
  "SnapshotSourceSemanticsMismatch",
]);

export class BrowserFontSessionError extends Error {
  declare code: string;
  declare detail: string | undefined;

  constructor(code: string, detail?: string, options?: ErrorOptions) {
    super(detail ? `${code}:${detail}` : code, options);
    this.name = "BrowserFontSessionError";
    this.code = code;
    this.detail = detail;
  }
}

export interface SnapshotFontContractDetail {
  kind?: string;
  expectedFaces?: unknown;
  actualFaces?: unknown;
  firstField?: unknown;
}

export interface SnapshotFontContractResult {
  matches: boolean;
  reason?: string | null;
  detail?: SnapshotFontContractDetail | null;
  paragraphSelector?: string;
  compatibleLocalDeclared?: boolean;
}

export type SnapshotFontContractValidator = (root: HTMLElement) => Promise<SnapshotFontContractResult> | SnapshotFontContractResult;

function formatContractMismatchDetail(result: SnapshotFontContractResult | null | undefined): string {
  const reason = result?.reason ?? "unknown";
  if (!result?.detail) return reason;
  const { kind, expectedFaces, actualFaces, firstField } = result.detail;
  if (kind === "EmptyCandidateSet") {
    return `${reason}|EmptyCandidateSet`;
  }
  if (kind === "FieldMismatch") {
    return `${reason}|FieldMismatch|expectedFaces=${expectedFaces}|actualFaces=${actualFaces}|firstField=${firstField}`;
  }
  return reason;
}

function fail(code: string, detail?: string, cause?: unknown): never {
  throw new BrowserFontSessionError(code, detail, cause == null ? undefined : { cause });
}

function stringValue(value: unknown, code: string, field: string): string {
  if (typeof value !== "string" || value.trim() === "") fail(code, field);
  return value;
}

function textValue(value: unknown, code: string, field: string): string {
  if (typeof value !== "string" || value.length === 0) fail(code, field);
  return value;
}

function digestValue(value: unknown, field: string): string {
  if (typeof value !== "string" || !HASH_PATTERN.test(value)) {
    fail("SnapshotFontEvidenceInvalid", field);
  }
  return value;
}

function weightValue(value: unknown): [number, number] {
  if (
    !Array.isArray(value) || value.length !== 2 ||
    !value.every((item) => typeof item === "number" && Number.isFinite(item))
  ) fail("SnapshotFontEvidenceInvalid", "weight");
  const weight: [number, number] = [value[0], value[1]];
  if (weight[0] <= 0 || weight[1] < weight[0]) {
    fail("SnapshotFontEvidenceInvalid", "weight");
  }
  return weight;
}

function sourceOrderValue(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) < 0) {
    fail("SnapshotFontEvidenceInvalid", "sourceOrder");
  }
  return value as number;
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string" && item.trim() !== "");
}

function stringSet(value: unknown, field: string, code: string = "SnapshotFontEvidenceInvalid"): string[] {
  if (!isStringArray(value)) {
    fail(code, field);
  }
  return Array.from(new Set(value)).sort();
}

export interface RawProbeLike {
  fontWeight?: unknown;
  text?: unknown;
}

export interface RawEvidenceLike {
  axes?: unknown;
  probe?: RawProbeLike | null;
  harfbuzzVersion?: unknown;
  backendRevision?: unknown;
  faces?: unknown;
}

export interface RawEvidenceFace {
  family?: unknown;
  style?: unknown;
  weight?: unknown;
  unicodeRange?: unknown;
  publicUrl?: unknown;
  faceIndex?: unknown;
  sourceSha256?: unknown;
  sfntSha256?: unknown;
  sourceOrder?: unknown;
  localNames?: unknown;
  axes?: unknown;
  probe?: RawProbeLike | null;
  coverageText?: unknown;
}

export interface RawFontEvidenceLike {
  harfbuzzVersion?: unknown;
  backendRevision?: unknown;
  faces?: unknown;
}

export interface RawManifestTypographyLike {
  fontVariantNumeric?: unknown;
}

export interface RawManifestEntryLike {
  typography?: RawManifestTypographyLike;
  fontEvidence?: RawFontEvidenceLike;
}

export interface RawFontReplayLike {
  revision?: unknown;
  shapes?: unknown;
  metrics?: unknown;
}

export interface RawManifestLike {
  schema?: unknown;
  layoutRevision?: unknown;
  renderRevision?: unknown;
  fontSourcePolicy?: unknown;
  entries?: unknown;
  fontReplay?: ServerReplayFontReplay | RawFontReplayLike;
  fontContractEntries?: unknown;
  renderFontFamilies?: unknown;
  paragraphSelector?: unknown;
}

function axesValue(evidence: RawEvidenceLike, weight: [number, number]): Record<string, number> {
  const axes = evidence.axes;
  if (!axes || typeof axes !== "object" || Array.isArray(axes)) {
    fail("SnapshotFontEvidenceInvalid", "axes");
  }
  const result: Record<string, number> = {};
  for (const [tag, rawValue] of Object.entries(axes as Record<string, unknown>)) {
    if (
      !/^[\x20-\x7e]{4}$/u.test(tag) ||
      typeof rawValue !== "number" || !Number.isFinite(rawValue)
    ) {
      fail("SnapshotFontEvidenceInvalid", `axes.${tag}`);
    }
    result[tag] = rawValue;
  }
  if (Object.hasOwn(result, "wght")) {
    const probeWeight = evidence.probe?.fontWeight;
    if (
      typeof probeWeight !== "number" || !Number.isFinite(probeWeight) ||
      result.wght !== probeWeight ||
      result.wght < weight[0] || result.wght > weight[1]
    ) fail("SnapshotFontEvidenceInvalid", "axes.wght");
  }
  return result;
}

export interface EvidenceFaceDescriptor {
  family: string;
  style: string;
  weight: readonly number[];
  unicodeRange: string;
  publicUrl: string;
  faceIndex: number;
}

function faceDescriptorKey(face: EvidenceFaceDescriptor): string {
  return JSON.stringify([
    face.family,
    face.style,
    face.weight,
    face.unicodeRange,
    face.publicUrl,
    face.faceIndex,
  ]);
}

function sameValue(left: unknown, right: unknown): boolean {
  return JSON.stringify(left) === JSON.stringify(right);
}

export interface EvidenceFace {
  family: string;
  style: string;
  weight: [number, number];
  unicodeRange: string;
  publicUrl: string;
  sourceSha256: string;
  sfntSha256: string;
  faceIndex: number;
  sourceOrder: number;
  localNames: string[];
  axes: Record<string, number>;
}

function evidenceFace(value: RawEvidenceFace | null | undefined): EvidenceFace {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail("SnapshotFontEvidenceInvalid", "face");
  }
  const family = stringValue(value.family, "SnapshotFontEvidenceInvalid", "family");
  const style = stringValue(value.style, "SnapshotFontEvidenceInvalid", "style");
  if (style !== "normal" && style !== "italic") {
    fail("SnapshotFontEvidenceInvalid", "style");
  }
  const weight = weightValue(value.weight);
  if (typeof value.unicodeRange !== "string") {
    fail("SnapshotFontEvidenceInvalid", "unicodeRange");
  }
  const publicUrl = stringValue(value.publicUrl, "SnapshotFontEvidenceInvalid", "publicUrl");
  const faceIndex = value.faceIndex;
  if (typeof faceIndex !== "number" || !Number.isSafeInteger(faceIndex) || faceIndex < 0) {
    fail("SnapshotFontEvidenceInvalid", "faceIndex");
  }
  const face = {
    family,
    style,
    weight,
    unicodeRange: value.unicodeRange as string,
    publicUrl,
    sourceSha256: digestValue(value.sourceSha256, "sourceSha256"),
    sfntSha256: digestValue(value.sfntSha256, "sfntSha256"),
    faceIndex,
    sourceOrder: sourceOrderValue(value.sourceOrder),
    localNames: stringSet(value.localNames, "localNames"),
  };
  return { ...face, axes: axesValue(value as RawEvidenceLike, weight) };
}

interface FaceGroupEntry extends EvidenceFace {
  axisTags: string[];
  coverage: Set<string>;
}

export interface CollectedManifestFace extends EvidenceFace {
  coverageText: string;
  loadWeight: number;
  axisTags?: string[];
}

export interface CollectedManifestFaces {
  paragraphSelector: string;
  renderFontFamilies: string[];
  backendRevision: string;
  harfbuzzVersion: string;
  faces: CollectedManifestFace[];
  replay: ServerReplayFontReplay;
  baseFeatures: string[];
}

function collectManifestFaces(manifest: RawManifestLike | null | undefined): CollectedManifestFaces {
  if (
    !manifest || typeof manifest !== "object" || Array.isArray(manifest) ||
    !readableSnapshotSchema(manifest.schema as number) || manifest.layoutRevision !== LAYOUT_REVISION ||
    manifest.renderRevision !== RENDER_REVISION || manifest.fontSourcePolicy !== FONT_SOURCE_POLICY
  ) fail("SnapshotRevisionMismatch");
  if (!Array.isArray(manifest.entries) || manifest.entries.length === 0) {
    fail("SnapshotManifestInvalid", "entries");
  }
  if (
    manifest.fontReplay?.revision !== FONT_REPLAY_REVISION ||
    !Array.isArray(manifest.fontReplay.shapes) ||
    !Array.isArray(manifest.fontReplay.metrics)
  ) {
    fail("SnapshotFontReplayInvalid");
  }
  if (manifest.fontContractEntries != null && !Array.isArray(manifest.fontContractEntries)) {
    fail("SnapshotManifestInvalid", "fontContractEntries");
  }
  const families = manifest.renderFontFamilies;
  if (!isStringArray(families) || families.length === 0 ||
      new Set(families.map((family) => family.trim().toLowerCase())).size !== families.length) {
    fail("SnapshotManifestInvalid", "renderFontFamilies");
  }
  const renderFontFamilies = [...families];
  const paragraphSelector = stringValue(
    manifest.paragraphSelector,
    "SnapshotManifestInvalid",
    "paragraphSelector",
  );
  const numericVariants = new Set(
    [...(manifest.entries as RawManifestEntryLike[]), ...((manifest.fontContractEntries ?? []) as RawManifestEntryLike[])].map(
      (entry) => String(entry?.typography?.fontVariantNumeric ?? "normal"),
    ),
  );
  if (
    numericVariants.size !== 1 ||
    ![...numericVariants].every((value) => value === "normal" || value === "lining-nums")
  ) {
    fail("SnapshotTypographyConflict", "fontVariantNumeric");
  }
  const fontVariantNumeric = numericVariants.values().next().value;
  const versions = new Set<string>();
  const backendRevisions = new Set<string>();
  const groups = new Map<string, FaceGroupEntry>();
  for (const entry of [...(manifest.entries as RawManifestEntryLike[]), ...((manifest.fontContractEntries ?? []) as RawManifestEntryLike[])]) {
    const fontEvidence = entry?.fontEvidence;
    if (!fontEvidence || typeof fontEvidence !== "object" || Array.isArray(fontEvidence)) {
      fail("SnapshotFontEvidenceInvalid", "fontEvidence");
    }
    versions.add(stringValue(
      fontEvidence.harfbuzzVersion,
      "SnapshotFontEvidenceInvalid",
      "harfbuzzVersion",
    ));
    backendRevisions.add(stringValue(
      fontEvidence.backendRevision,
      "SnapshotFontEvidenceInvalid",
      "backendRevision",
    ));
    if (!Array.isArray(fontEvidence.faces) || fontEvidence.faces.length === 0) {
      fail("SnapshotFontEvidenceInvalid", "faces");
    }
    for (const rawFace of fontEvidence.faces as RawEvidenceFace[]) {
      const face = evidenceFace(rawFace);
      // WhitespaceGlyphEvidenceIsText: a dedicated Latin/space face can
      // legitimately contribute only U+0020. Descriptor identifiers still use
      // trim-aware validation, but glyph coverage must preserve every source
      // code point and reject only the actually empty string.
      const coverageText = textValue(
        rawFace.coverageText ?? rawFace.probe?.text,
        "SnapshotFontEvidenceInvalid",
        "coverageText",
      );
      const key = faceDescriptorKey(face);
      const existing = groups.get(key);
      const axisTags = Object.keys(face.axes).sort();
      if (!existing) {
        groups.set(key, { ...face, axisTags, coverage: new Set(coverageText) });
        continue;
      }
      if (
        existing.sourceSha256 !== face.sourceSha256 ||
        existing.sfntSha256 !== face.sfntSha256 ||
        existing.sourceOrder !== face.sourceOrder ||
        !sameValue(existing.localNames, face.localNames) ||
        !sameValue(existing.axisTags, axisTags)
      ) fail("SnapshotFontEvidenceConflict", face.publicUrl);
      for (const point of coverageText) existing.coverage.add(point);
    }
  }
  if (versions.size !== 1) fail("SnapshotHarfBuzzVersionConflict");
  if (backendRevisions.size !== 1) fail("SnapshotBackendRevisionConflict");
  const backendRevision = backendRevisions.values().next().value!;
  if (backendRevision !== FONT_BACKEND_REVISION) {
    fail("FontBackendRevisionMismatch", `${backendRevision}:${FONT_BACKEND_REVISION}`);
  }
  const faces: CollectedManifestFace[] = Array.from(groups.values(), ({ coverage, ...face }) => ({
    ...face,
    coverageText: Array.from(coverage).join(""),
    loadWeight: face.axes.wght ?? face.weight[0],
  })).sort((left, right) => left.sourceOrder - right.sourceOrder);
  const sourceOrders = new Set<number>();
  for (const face of faces) {
    if (sourceOrders.has(face.sourceOrder)) {
      fail("SnapshotFontEvidenceConflict", `sourceOrder=${face.sourceOrder}`);
    }
    sourceOrders.add(face.sourceOrder);
  }
  return {
    paragraphSelector,
    renderFontFamilies,
    backendRevision,
    harfbuzzVersion: versions.values().next().value!,
    faces,
    replay: manifest.fontReplay as ServerReplayFontReplay,
    baseFeatures: fontVariantNumeric === "lining-nums" ? ["lnum"] : [],
  };
}

export interface SnapshotContext extends CollectedManifestFaces {
  documentObject: Document;
  template: HTMLTemplateElement;
  manifestText: string;
  tablesBytes: Uint8Array | null;
}

async function snapshotContext(root: HTMLElement): Promise<SnapshotContext> {
  if (!root || typeof root.getAttribute !== "function") fail("SnapshotRootInvalid");
  const reference = root.getAttribute("snapshot-ref");
  if (!reference) fail("SnapshotReferenceMissing");
  const documentObject = root.ownerDocument ?? globalThis.document;
  const template = documentObject?.getElementById?.(reference) as HTMLTemplateElement | null;
  if (!template?.content) fail("SnapshotTemplateMissing", reference);
  const script = template.content.querySelector?.("[data-tq-snapshot-manifest]");
  if (typeof script?.textContent !== "string" || script.textContent.trim() === "") {
    fail("SnapshotManifestMissing", reference);
  }
  let parsed: SnapshotManifestWire | undefined;
  try {
    parsed = JSON.parse(script.textContent) as SnapshotManifestWire;
  } catch (error) {
    fail("SnapshotManifestInvalid", reference, error);
  }
  // The snapshot table resolves through the root attribute; the loaded bytes
  // verify against the sha the manifest pins before any row is read.
  let tables: LoadedSnapshotTable | null = null;
  if (parsed?.tables != null) {
    const expected = typeof (parsed.tables as { snapshot?: unknown })?.snapshot === "string"
      ? (parsed.tables as { snapshot: string }).snapshot
      : null;
    tables = await snapshotTablesForRoot(root, expected);
    if (tables == null) fail("SnapshotTablesMissing", reference);
  }
  let manifest: ExpandedSnapshotManifest | undefined;
  try {
    manifest = expandSnapshotManifest(parsed, tables?.view ?? null);
  } catch (error) {
    fail("SnapshotManifestInvalid", reference, error);
  }
  const collected = collectManifestFaces(manifest as RawManifestLike);
  return {
    documentObject,
    template,
    manifestText: script.textContent,
    tablesBytes: tables?.bytes ?? null,
    ...collected,
  };
}

function actualFaceKey(face: ReplayFontSessionFace): string {
  return faceDescriptorKey(face);
}

export interface ActualReplayFace extends ReplayFontSessionFace {
  axisTags?: string[];
}

function validateSession(session: ServerReplayFontSession, expected: CollectedManifestFaces): void {
  if (
    !session || typeof session.id !== "string" || session.id === "" ||
    typeof session.close !== "function" || !Array.isArray(session.faces)
  ) fail("BrowserFontSessionInvalid");
  if (session.backendRevision !== expected.backendRevision) {
    fail("FontBackendRevisionMismatch", `${expected.backendRevision}:${session.backendRevision}`);
  }
  if (session.harfbuzzVersion !== expected.harfbuzzVersion) {
    fail("HarfBuzzVersionMismatch", `${expected.harfbuzzVersion}:${session.harfbuzzVersion}`);
  }
  if (session.faces.length !== expected.faces.length) {
    fail("FontSessionFaceCountMismatch");
  }
  const actualByKey = new Map<string, ActualReplayFace>();
  for (const actual of session.faces) {
    if (!actual || typeof actual !== "object" || Array.isArray(actual)) {
      fail("FontSessionFaceMetadataMismatch", "face");
    }
    const key = actualFaceKey(actual);
    if (actualByKey.has(key)) fail("FontSessionFaceMetadataMismatch", "duplicate");
    actualByKey.set(key, actual as ActualReplayFace);
  }
  for (const face of expected.faces) {
    const actual = actualByKey.get(faceDescriptorKey(face));
    if (!actual) fail("FontSessionFaceMetadataMismatch", face.publicUrl);
    if (
      actual.sourceSha256 !== face.sourceSha256 || actual.sfntSha256 !== face.sfntSha256 ||
      actual.faceIndex !== face.faceIndex || actual.sourceOrder !== face.sourceOrder ||
      !sameValue(stringSet(
        actual.localNames,
        "localNames",
        "FontSessionFaceMetadataMismatch",
      ), face.localNames) ||
      !sameValue(stringSet(
        actual.axisTags,
        "axisTags",
        "FontSessionFaceMetadataMismatch",
      ), face.axisTags)
    ) fail("FontSessionFaceMetadataMismatch", face.publicUrl);
  }
}

export interface ManifestFaceSpec {
  family: string;
  style: string;
  weight: number[];
  unicodeRange: string;
  publicUrl: string;
  faceIndex: number;
  sourceOrder: number;
}

export interface BrowserFontSessionCreateOptions extends ServerReplayFontSessionOptions {
  baseFeatures?: string[];
}

export type FontSessionCreator = (
  faces: readonly ManifestFaceSpec[],
  options: BrowserFontSessionCreateOptions,
) => Promise<ServerReplayFontSession>;

export interface BrowserFontSessionLoaderOptions {
  createFontSession?: FontSessionCreator;
  validateContract?: SnapshotFontContractValidator;
  validatePreparedContract?: SnapshotFontContractValidator;
}

interface RenderFontFaceSpec {
  family: string;
  style: string;
  weight: number;
  text: string;
}

interface BrowserFontSessionState {
  references: number;
  versions: Map<string, BrowserFontSessionState>;
  cacheKey: string;
  manifestText: string;
  tablesBytes: Uint8Array | null;
  session: ServerReplayFontSession | null;
  renderFontFaces: RenderFontFaceSpec[];
  renderFontFamilies: string[];
  renderFontsPromise: Promise<boolean> | null;
  promise?: Promise<ServerReplayFontSession>;
}

interface BrowserFontSessionToken {
  state: BrowserFontSessionState;
  released: boolean;
}

export interface BrowserFontSessionHandle {
  readonly id: string;
  readonly paragraphSelector: string;
  readonly renderFontFamilies: readonly string[];
  readonly [HANDLE_STATE]?: BrowserFontSessionToken;
}

export type BrowserFontSessionPreparer = (root: HTMLElement) => Promise<BrowserFontSessionHandle>;
export type BrowserFontSessionRevalidator = (root: HTMLElement, handle: BrowserFontSessionHandle) => Promise<BrowserFontSessionHandle>;
export type BrowserRenderFontPreparer = (root: HTMLElement, handle: BrowserFontSessionHandle) => Promise<boolean>;
export type BrowserFontSessionReleaser = (handle: BrowserFontSessionHandle) => boolean;

export interface BrowserFontSessionLoader {
  prepare: BrowserFontSessionPreparer;
  revalidate: BrowserFontSessionRevalidator;
  prepareRenderFonts: BrowserRenderFontPreparer;
  release: BrowserFontSessionReleaser;
}

interface RevalidateOptions {
  parserComplete?: boolean;
}

export function createBrowserFontSessionLoader(options: BrowserFontSessionLoaderOptions = {}): BrowserFontSessionLoader {
  const createSession = options.createFontSession ?? createServerReplayFontSession;
  const preferPreparedContract = options.validateContract == null ||
    options.validatePreparedContract != null;
  const validateContract: SnapshotFontContractValidator = options.validateContract ??
    validatePrecomputedSnapshotFontReplayContract;
  const validatePreparedContract: SnapshotFontContractValidator = options.validatePreparedContract ?? (
    options.validateContract
      ? validateContract
      : validatePrecomputedSnapshotFontReplayLiveContract
  );
  const cache = new WeakMap<HTMLTemplateElement, Map<string, BrowserFontSessionState>>();

  async function validateSnapshotContract(root: HTMLElement): Promise<SnapshotFontContractResult> {
    let result: SnapshotFontContractResult;
    try {
      result = await validateContract(root);
    } catch (error) {
      fail("SnapshotFontContractValidationFailed", undefined, error);
    }
    return result;
  }

  async function validateSnapshotPreparedContract(root: HTMLElement): Promise<SnapshotFontContractResult> {
    let result: SnapshotFontContractResult;
    try {
      result = await validatePreparedContract(root);
    } catch (error) {
      fail("SnapshotFontContractValidationFailed", undefined, error);
    }
    if (!result?.matches) {
      fail("SnapshotFontContractMismatch", formatContractMismatchDetail(result));
    }
    return result;
  }

  async function requirePreparedOrSnapshotContract(root: HTMLElement): Promise<SnapshotFontContractResult> {
    if (preferPreparedContract) {
      let prepared: SnapshotFontContractResult | undefined;
      try {
        prepared = await validatePreparedContract(root);
      } catch (error) {
        fail("SnapshotFontContractValidationFailed", undefined, error);
      }
      if (prepared?.matches) return prepared;
    }
    return requireSnapshotContract(root);
  }

  async function waitForParserContract(root: HTMLElement, initialResult: SnapshotFontContractResult): Promise<SnapshotFontContractResult> {
    const documentObject = root?.ownerDocument;
    const MutationObserverConstructor = documentObject?.defaultView?.MutationObserver ??
      globalThis.MutationObserver;
    if (
      initialResult?.matches || documentObject?.readyState !== "loading" ||
      !PARSER_PENDING_CONTRACT_REASONS.has(initialResult?.reason) ||
      typeof MutationObserverConstructor !== "function" ||
      typeof documentObject.addEventListener !== "function"
    ) return initialResult;

    return new Promise((resolve, reject) => {
      let validating = false;
      let queued = false;
      let settled = false;
      const finish = (result: SnapshotFontContractResult) => {
        if (settled) return;
        settled = true;
        observer.disconnect();
        documentObject.removeEventListener?.("DOMContentLoaded", onParserComplete);
        resolve(result);
      };
      const failValidation = (error: unknown) => {
        if (settled) return;
        settled = true;
        observer.disconnect();
        documentObject.removeEventListener?.("DOMContentLoaded", onParserComplete);
        reject(error);
      };
      const revalidate = async ({ parserComplete = false }: RevalidateOptions = {}) => {
        if (settled) return;
        if (validating) {
          queued = true;
          return;
        }
        validating = true;
        let result: SnapshotFontContractResult;
        try {
          result = await validateSnapshotContract(root);
        } catch (error) {
          failValidation(error);
          return;
        } finally {
          validating = false;
        }
        if (result?.matches || parserComplete || documentObject.readyState !== "loading" ||
            !PARSER_PENDING_CONTRACT_REASONS.has(result?.reason)) {
          finish(result);
          return;
        }
        if (queued) {
          queued = false;
          void revalidate();
        }
      };
      const onParserComplete = () => void revalidate({ parserComplete: true });
      const observer = new MutationObserverConstructor(() => void revalidate());
      observer.observe(root, { attributes: true, childList: true, characterData: true, subtree: true });
      const documentRoot = documentObject.documentElement;
      if (documentRoot && documentRoot !== root) {
        observer.observe(documentRoot, { childList: true, subtree: true });
      }
      documentObject.addEventListener("DOMContentLoaded", onParserComplete, { once: true });
      // Close the gap between the first validation and installing observers.
      void revalidate();
    });
  }

  async function requireSnapshotContract(root: HTMLElement): Promise<SnapshotFontContractResult> {
    const result = await waitForParserContract(root, await validateSnapshotContract(root));
    if (!result?.matches) {
      fail("SnapshotFontContractMismatch", formatContractMismatchDetail(result));
    }
    return result;
  }

  function releaseStateReference(state: BrowserFontSessionState): void {
    state.references -= 1;
    if (state.references < 0) fail("BrowserFontSessionReferenceUnderflow");
    if (state.references === 0) {
      if (state.versions.get(state.cacheKey) === state) {
        state.versions.delete(state.cacheKey);
      }
      globalServices().coordination.layoutWorker?.release?.(state.session?.id);
      state.session?.close();
    }
  }

  async function load(context: CollectedManifestFaces): Promise<ServerReplayFontSession> {
    // ServerReplayNeedsNoBrowserFontBytes: glyph ids, advances and metrics are
    // already embedded in the manifest. Browser paint remains owned by the
    // host @font-face/local() cascade and is proven before this session starts.
    const faceSpecs: ManifestFaceSpec[] = context.faces.map((face) => ({
      family: face.family,
      style: face.style,
      weight: [...face.weight],
      unicodeRange: face.unicodeRange,
      publicUrl: face.publicUrl,
      faceIndex: face.faceIndex,
      sourceOrder: face.sourceOrder,
    }));

    let session: ServerReplayFontSession | undefined;
    try {
      session = await createSession(faceSpecs, {
        sessionPrefix: "tq-browser-font",
        baseFeatures: context.baseFeatures,
        replay: context.replay,
        faceMetadata: context.faces,
        harfbuzzVersion: context.harfbuzzVersion,
      });
      validateSession(session, context);
      return session;
    } catch (error) {
      try {
        session?.close?.();
      } catch {
        // The validation failure remains the primary fail-closed reason.
      }
      if (error instanceof BrowserFontSessionError) throw error;
      fail("FontSessionCreationFailed", undefined, error);
    }
  }

  async function prepare(root: HTMLElement): Promise<BrowserFontSessionHandle> {
    // HostCompatibleReplayContract: both snapshots and runtime replay paint
    // through the host family, so the same live CSS/probe proof gates both.
    await requirePreparedOrSnapshotContract(root);
    const context = await snapshotContext(root);
    const cacheKey = context.manifestText;
    let versions = cache.get(context.template);
    if (!versions) {
      versions = new Map();
      cache.set(context.template, versions);
    }
    let state = versions.get(cacheKey);
    if (!state) {
      state = {
        references: 0,
        versions,
        cacheKey,
        manifestText: context.manifestText,
        tablesBytes: context.tablesBytes,
        session: null,
        renderFontFaces: context.faces.map((face) => ({
          family: face.family,
          style: face.style,
          weight: face.loadWeight,
          text: face.coverageText,
        })),
        renderFontFamilies: context.renderFontFamilies,
        renderFontsPromise: null,
      };
      state.promise = load(context).then((session) => {
        state!.session = session;
        return session;
      }).catch((error) => {
        if (versions!.get(cacheKey) === state) versions!.delete(cacheKey);
        throw error;
      });
      versions.set(cacheKey, state);
    }
    state.references += 1;
    let session: ServerReplayFontSession;
    try {
      session = await state.promise!;
      await validateSnapshotPreparedContract(root);
      const current = await snapshotContext(root);
      if (
        current.template !== context.template || current.manifestText !== context.manifestText
      ) fail("SnapshotManifestChangedDuringFontPreparation");
    } catch (error) {
      releaseStateReference(state);
      throw error;
    }
    const token: BrowserFontSessionToken = { state, released: false };
    return Object.freeze({
      id: session.id,
      paragraphSelector: context.paragraphSelector,
      renderFontFamilies: Object.freeze([...state.renderFontFamilies]),
      [HANDLE_STATE]: token,
    });
  }

  async function revalidate(root: HTMLElement, handle: BrowserFontSessionHandle): Promise<BrowserFontSessionHandle> {
    const token = handle?.[HANDLE_STATE];
    if (!token || token.released || !token.state.session) {
      fail("BrowserFontSessionHandleInvalid");
    }
    // ExistingSessionLiveContractRevalidation: replay data is immutable, but
    // the host font cascade remains a live rendering dependency.
    await requirePreparedOrSnapshotContract(root);
    const context = await snapshotContext(root);
    const cacheKey = context.manifestText;
    const { state } = token;
    if (cacheKey !== state.cacheKey) {
      fail("SnapshotManifestChangedDuringFontPreparation", "cache-key");
    }
    if (state.versions.get(cacheKey) !== state) {
      fail("SnapshotManifestChangedDuringFontPreparation", "session-evicted");
    }
    return handle;
  }

  async function prepareRenderFonts(root: HTMLElement, handle: BrowserFontSessionHandle): Promise<boolean> {
    const token = handle?.[HANDLE_STATE];
    if (!token || token.released || !token.state.session) {
      fail("BrowserFontSessionHandleInvalid");
    }
    const { state } = token;
    const fontSet = root?.ownerDocument?.fonts;
    if (typeof fontSet?.load !== "function") fail("RenderFontFaceSetUnavailable");
    state.renderFontsPromise ??= Promise.all(state.renderFontFaces.map((face) => loadBrowserFontFaces(fontSet,
      `${face.style} ${face.weight} 16px ${JSON.stringify(face.family)}`,
      face.text,
    ))).then((results) => {
      const missing = results.findIndex((faces) => !faces || faces.length === 0);
      if (missing >= 0) {
        fail("RenderFontFaceLoadFailed", state.renderFontFaces[missing].family);
      }
      return true;
    }).catch((error) => {
      if (error instanceof BrowserFontSessionError) throw error;
      fail("RenderFontFaceLoadFailed", undefined, error);
    });
    return state.renderFontsPromise;
  }

  function release(handle: BrowserFontSessionHandle): boolean {
    const token = handle?.[HANDLE_STATE];
    if (!token || token.released) return false;
    token.released = true;
    const { state } = token;
    releaseStateReference(state);
    return true;
  }

  return Object.freeze({ prepare, revalidate, prepareRenderFonts, release });
}

export interface BrowserFontSessionWorkerContract {
  readonly sessionKey: string;
  readonly manifestText: string;
  readonly tablesBytes: Uint8Array | null;
}

/** Internal handoff used by the module Worker without exposing font bytes. */
export function browserFontSessionWorkerContract(handle: BrowserFontSessionHandle): BrowserFontSessionWorkerContract {
  const token = handle?.[HANDLE_STATE];
  if (!token || token.released || !token.state.session) {
    fail("BrowserFontSessionHandleInvalid");
  }
  return Object.freeze({
    sessionKey: token.state.session.id,
    manifestText: snapshotContextFromState(token.state),
    // The snapshot-table bytes the manifest pins; null for schema-1 manifests
    // whose replay rows are already self-contained.
    tablesBytes: token.state.tablesBytes ?? null,
  });
}

function snapshotContextFromState(state: BrowserFontSessionState): string {
  if (typeof state.manifestText !== "string" || state.manifestText.length === 0) {
    fail("BrowserFontSessionWorkerContractUnavailable");
  }
  return state.manifestText;
}

// The page-wide default loader instance is owned by the service-owned
// FontCoordinationState (one per document, see fonts.ts). These four exported
// bindings keep their names and delegate to that loader. The state record
// starts with browserFontLoader undefined and the loader is constructed here
// on first use: building it inside the coordination-service module would
// statically import this module's graph — which reaches precomputed.ts and
// prepared-dom.ts, whose module body installs the read-only prepared
// renderer bridge — ahead of test fixtures that pre-seed that slot.
function defaultFontSessionLoader(): BrowserFontSessionLoader {
  const fonts = globalServices().coordination.fonts;
  fonts.browserFontLoader ??= createBrowserFontSessionLoader();
  return fonts.browserFontLoader;
}

export function prepareBrowserFontSession(root: HTMLElement): Promise<BrowserFontSessionHandle> {
  return defaultFontSessionLoader().prepare(root);
}

export function revalidateBrowserFontSession(
  root: HTMLElement,
  handle: BrowserFontSessionHandle,
): Promise<BrowserFontSessionHandle> {
  return defaultFontSessionLoader().revalidate(root, handle);
}

export function prepareBrowserRenderFonts(root: HTMLElement, handle: BrowserFontSessionHandle): Promise<boolean> {
  return defaultFontSessionLoader().prepareRenderFonts(root, handle);
}

export function releaseBrowserFontSession(handle: BrowserFontSessionHandle): boolean {
  return defaultFontSessionLoader().release(handle);
}
