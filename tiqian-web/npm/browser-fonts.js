import { createServerReplayFontSession } from "./browser-font-replay.js";
import {
  FONT_BACKEND_REVISION,
  FONT_REPLAY_REVISION,
  FONT_SOURCE_POLICY,
  LAYOUT_REVISION,
  RENDER_REVISION,
  SNAPSHOT_SCHEMA,
} from "./snapshot-schema.js";
import { parseSnapshotManifest } from "./snapshot-manifest.js";
import {
  validatePrecomputedExactFontReplayContract,
  validatePrecomputedExactFontReplayLiveContract,
} from "./precomputed.js";

const HASH_PATTERN = /^[a-f0-9]{64}$/u;
const HANDLE_STATE = Symbol("tiqian.browserFontSession");
const PARSER_PENDING_CONTRACT_REASONS = new Set([
  "SnapshotTemplateMissing",
  "SnapshotCandidateSetMismatch",
  "SnapshotCandidateKeyInvalid",
  "SnapshotEntryMissing",
  "SnapshotSourceMismatch",
  "SnapshotSourceSemanticsMismatch",
]);

export class BrowserFontSessionError extends Error {
  constructor(code, detail, options) {
    super(detail ? `${code}:${detail}` : code, options);
    this.name = "BrowserFontSessionError";
    this.code = code;
  }
}

function fail(code, detail, cause) {
  throw new BrowserFontSessionError(code, detail, cause == null ? undefined : { cause });
}

function stringValue(value, code, field) {
  if (typeof value !== "string" || value.trim() === "") fail(code, field);
  return value;
}

function textValue(value, code, field) {
  if (typeof value !== "string" || value.length === 0) fail(code, field);
  return value;
}

function digestValue(value, field) {
  if (typeof value !== "string" || !HASH_PATTERN.test(value)) {
    fail("SnapshotFontEvidenceInvalid", field);
  }
  return value;
}

function weightValue(value) {
  if (
    !Array.isArray(value) || value.length !== 2 ||
    !value.every((item) => typeof item === "number" && Number.isFinite(item))
  ) fail("SnapshotFontEvidenceInvalid", "weight");
  const weight = [...value];
  if (weight[0] <= 0 || weight[1] < weight[0]) {
    fail("SnapshotFontEvidenceInvalid", "weight");
  }
  return weight;
}

function sourceOrderValue(value) {
  if (!Number.isSafeInteger(value) || value < 0) {
    fail("SnapshotFontEvidenceInvalid", "sourceOrder");
  }
  return value;
}

function stringSet(value, field, code = "SnapshotFontEvidenceInvalid") {
  if (!Array.isArray(value) || value.some((item) => typeof item !== "string" || item.trim() === "")) {
    fail(code, field);
  }
  return Array.from(new Set(value)).sort();
}

function axesValue(evidence, weight) {
  const axes = evidence.axes;
  if (!axes || typeof axes !== "object" || Array.isArray(axes)) {
    fail("SnapshotFontEvidenceInvalid", "axes");
  }
  const result = {};
  for (const [tag, rawValue] of Object.entries(axes)) {
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

function faceDescriptorKey(face) {
  return JSON.stringify([
    face.family,
    face.style,
    face.weight,
    face.unicodeRange,
    face.publicUrl,
    face.faceIndex,
  ]);
}

function sameValue(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function evidenceFace(value) {
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
    unicodeRange: value.unicodeRange,
    publicUrl,
    sourceSha256: digestValue(value.sourceSha256, "sourceSha256"),
    sfntSha256: digestValue(value.sfntSha256, "sfntSha256"),
    faceIndex,
    sourceOrder: sourceOrderValue(value.sourceOrder),
    localNames: stringSet(value.localNames, "localNames"),
  };
  return { ...face, axes: axesValue(value, weight) };
}

function collectManifestFaces(manifest) {
  if (
    !manifest || typeof manifest !== "object" || Array.isArray(manifest) ||
    manifest.schema !== SNAPSHOT_SCHEMA || manifest.layoutRevision !== LAYOUT_REVISION ||
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
  if (!Array.isArray(manifest.renderFontFamilies) || manifest.renderFontFamilies.length === 0 ||
      manifest.renderFontFamilies.some((family) => typeof family !== "string" || !family.trim()) ||
      new Set(manifest.renderFontFamilies.map((family) => family.trim().toLowerCase())).size !==
        manifest.renderFontFamilies.length) {
    fail("SnapshotManifestInvalid", "renderFontFamilies");
  }
  const renderFontFamilies = [...manifest.renderFontFamilies];
  const paragraphSelector = stringValue(
    manifest.paragraphSelector,
    "SnapshotManifestInvalid",
    "paragraphSelector",
  );
  const numericVariants = new Set(
    [...manifest.entries, ...(manifest.fontContractEntries ?? [])].map(
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
  const versions = new Set();
  const backendRevisions = new Set();
  const groups = new Map();
  for (const entry of [...manifest.entries, ...(manifest.fontContractEntries ?? [])]) {
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
    for (const rawFace of fontEvidence.faces) {
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
  const backendRevision = backendRevisions.values().next().value;
  if (backendRevision !== FONT_BACKEND_REVISION) {
    fail("FontBackendRevisionMismatch", `${backendRevision}:${FONT_BACKEND_REVISION}`);
  }
  const faces = Array.from(groups.values(), ({ coverage, ...face }) => ({
    ...face,
    coverageText: Array.from(coverage).join(""),
    loadWeight: face.axes.wght ?? face.weight[0],
  })).sort((left, right) => left.sourceOrder - right.sourceOrder);
  const sourceOrders = new Set();
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
    harfbuzzVersion: versions.values().next().value,
    faces,
    replay: manifest.fontReplay,
    baseFeatures: fontVariantNumeric === "lining-nums" ? ["lnum"] : [],
  };
}

function snapshotContext(root) {
  if (!root || typeof root.getAttribute !== "function") fail("SnapshotRootInvalid");
  const reference = root.getAttribute("snapshot-ref");
  if (!reference) fail("SnapshotReferenceMissing");
  const documentObject = root.ownerDocument ?? globalThis.document;
  const template = documentObject?.getElementById?.(reference);
  if (!template?.content) fail("SnapshotTemplateMissing", reference);
  const script = template.content.querySelector?.("[data-tq-snapshot-manifest]");
  if (typeof script?.textContent !== "string" || script.textContent.trim() === "") {
    fail("SnapshotManifestMissing", reference);
  }
  let manifest;
  try {
    manifest = parseSnapshotManifest(script.textContent);
  } catch (error) {
    fail("SnapshotManifestInvalid", reference, error);
  }
  const collected = collectManifestFaces(manifest);
  return {
    documentObject,
    template,
    manifestText: script.textContent,
    ...collected,
  };
}

function actualFaceKey(face) {
  return faceDescriptorKey(face);
}

function validateSession(session, expected) {
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
  const actualByKey = new Map();
  for (const actual of session.faces) {
    if (!actual || typeof actual !== "object" || Array.isArray(actual)) {
      fail("FontSessionFaceMetadataMismatch", "face");
    }
    const key = actualFaceKey(actual);
    if (actualByKey.has(key)) fail("FontSessionFaceMetadataMismatch", "duplicate");
    actualByKey.set(key, actual);
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

export function createBrowserFontSessionLoader(options = {}) {
  const createSession = options.createFontSession ?? createServerReplayFontSession;
  const preferPreparedContract = options.validateContract == null ||
    options.validatePreparedContract != null;
  const validateContract = options.validateContract ??
    validatePrecomputedExactFontReplayContract;
  const validatePreparedContract = options.validatePreparedContract ?? (
    options.validateContract
      ? validateContract
      : validatePrecomputedExactFontReplayLiveContract
  );
  const cache = new WeakMap();

  async function validateExactContract(root) {
    let result;
    try {
      result = await validateContract(root);
    } catch (error) {
      fail("SnapshotExactFontContractValidationFailed", undefined, error);
    }
    return result;
  }

  async function validateExactPreparedContract(root) {
    let result;
    try {
      result = await validatePreparedContract(root);
    } catch (error) {
      fail("SnapshotExactFontContractValidationFailed", undefined, error);
    }
    if (!result?.matches) {
      fail("SnapshotExactFontContractMismatch", result?.reason ?? "unknown");
    }
    return result;
  }

  async function requirePreparedOrExactContract(root) {
    if (preferPreparedContract) {
      let prepared;
      try {
        prepared = await validatePreparedContract(root);
      } catch (error) {
        fail("SnapshotExactFontContractValidationFailed", undefined, error);
      }
      if (prepared?.matches) return prepared;
    }
    return requireExactContract(root);
  }

  async function waitForParserContract(root, initialResult) {
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
      const finish = (result) => {
        if (settled) return;
        settled = true;
        observer.disconnect();
        documentObject.removeEventListener?.("DOMContentLoaded", onParserComplete);
        resolve(result);
      };
      const failValidation = (error) => {
        if (settled) return;
        settled = true;
        observer.disconnect();
        documentObject.removeEventListener?.("DOMContentLoaded", onParserComplete);
        reject(error);
      };
      const revalidate = async ({ parserComplete = false } = {}) => {
        if (settled) return;
        if (validating) {
          queued = true;
          return;
        }
        validating = true;
        let result;
        try {
          result = await validateExactContract(root);
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

  async function requireExactContract(root) {
    const result = await waitForParserContract(root, await validateExactContract(root));
    if (!result?.matches) {
      fail("SnapshotExactFontContractMismatch", result?.reason ?? "unknown");
    }
    return result;
  }

  function releaseStateReference(state) {
    state.references -= 1;
    if (state.references < 0) fail("BrowserFontSessionReferenceUnderflow");
    if (state.references === 0) {
      if (state.versions.get(state.cacheKey) === state) {
        state.versions.delete(state.cacheKey);
      }
      globalThis.__TiqianLayoutWorker?.release?.(state.session?.id);
      state.session?.close();
    }
  }

  async function load(context) {
    // ServerReplayNeedsNoBrowserFontBytes: glyph ids, advances and metrics are
    // already embedded in the manifest. Browser paint remains owned by the
    // host @font-face/local() cascade and is proven before this session starts.
    const faceSpecs = context.faces.map((face) => ({
      family: face.family,
      style: face.style,
      weight: [...face.weight],
      unicodeRange: face.unicodeRange,
      publicUrl: face.publicUrl,
      faceIndex: face.faceIndex,
      sourceOrder: face.sourceOrder,
    }));

    let session;
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

  async function prepare(root) {
    // HostCompatibleReplayContract: both snapshots and runtime replay paint
    // through the host family, so the same live CSS/probe proof gates both.
    await requirePreparedOrExactContract(root);
    const context = snapshotContext(root);
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
        state.session = session;
        return session;
      }).catch((error) => {
        if (versions.get(cacheKey) === state) versions.delete(cacheKey);
        throw error;
      });
      versions.set(cacheKey, state);
    }
    state.references += 1;
    let session;
    try {
      session = await state.promise;
      await validateExactPreparedContract(root);
      const current = snapshotContext(root);
      if (
        current.template !== context.template || current.manifestText !== context.manifestText
      ) fail("SnapshotManifestChangedDuringFontPreparation");
    } catch (error) {
      releaseStateReference(state);
      throw error;
    }
    const token = { state, released: false };
    return Object.freeze({
      id: session.id,
      paragraphSelector: context.paragraphSelector,
      renderFontFamilies: Object.freeze([...state.renderFontFamilies]),
      [HANDLE_STATE]: token,
    });
  }

  async function revalidate(root, handle) {
    const token = handle?.[HANDLE_STATE];
    if (!token || token.released || !token.state.session) {
      fail("BrowserFontSessionHandleInvalid");
    }
    // ExistingSessionLiveContractRevalidation: replay data is immutable, but
    // the host font cascade remains a live rendering dependency.
    await requirePreparedOrExactContract(root);
    const context = snapshotContext(root);
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

  async function prepareRenderFonts(root, handle) {
    const token = handle?.[HANDLE_STATE];
    if (!token || token.released || !token.state.session) {
      fail("BrowserFontSessionHandleInvalid");
    }
    const { state } = token;
    const fontSet = root?.ownerDocument?.fonts;
    if (typeof fontSet?.load !== "function") fail("RenderFontFaceSetUnavailable");
    state.renderFontsPromise ??= Promise.all(state.renderFontFaces.map((face) => fontSet.load(
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

  function release(handle) {
    const token = handle?.[HANDLE_STATE];
    if (!token || token.released) return false;
    token.released = true;
    const { state } = token;
    releaseStateReference(state);
    return true;
  }

  return Object.freeze({ prepare, revalidate, prepareRenderFonts, release });
}

/** Internal handoff used by the module Worker without exposing font bytes. */
export function browserFontSessionWorkerContract(handle) {
  const token = handle?.[HANDLE_STATE];
  if (!token || token.released || !token.state.session) {
    fail("BrowserFontSessionHandleInvalid");
  }
  return Object.freeze({
    sessionKey: token.state.session.id,
    manifestText: snapshotContextFromState(token.state),
  });
}

function snapshotContextFromState(state) {
  if (typeof state.manifestText !== "string" || state.manifestText.length === 0) {
    fail("BrowserFontSessionWorkerContractUnavailable");
  }
  return state.manifestText;
}

const defaultLoader = createBrowserFontSessionLoader();

export const prepareBrowserFontSession = defaultLoader.prepare;
export const revalidateBrowserFontSession = defaultLoader.revalidate;
export const prepareBrowserRenderFonts = defaultLoader.prepareRenderFonts;
export const releaseBrowserFontSession = defaultLoader.release;
