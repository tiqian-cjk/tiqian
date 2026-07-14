import {
  createFontSession,
  sha256,
} from "./precompute-fonts.js";
import {
  FONT_BACKEND_REVISION,
  FONT_SOURCE_POLICY,
  LAYOUT_REVISION,
  RENDER_REVISION,
  SNAPSHOT_SCHEMA,
} from "./snapshot-schema.js";
import { parseSnapshotManifest } from "./snapshot-manifest.js";
import { validatePrecomputedSnapshotExactFontContract } from "./precomputed.js";

const HASH_PATTERN = /^[a-f0-9]{64}$/u;
const CONTENT_ADDRESS_PATTERN = /(?:^|[._/-])[a-f0-9]{8,}(?=[._/-]|$)/iu;
const HANDLE_STATE = Symbol("tiqian.browserFontSession");

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
  const versions = new Set();
  const backendRevisions = new Set();
  const groups = new Map();
  for (const entry of manifest.entries) {
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
      const key = faceDescriptorKey(face);
      const existing = groups.get(key);
      const axisTags = Object.keys(face.axes).sort();
      if (!existing) {
        groups.set(key, { ...face, axisTags });
        continue;
      }
      if (
        existing.sourceSha256 !== face.sourceSha256 ||
        existing.sfntSha256 !== face.sfntSha256 ||
        existing.sourceOrder !== face.sourceOrder ||
        !sameValue(existing.localNames, face.localNames) ||
        !sameValue(existing.axisTags, axisTags)
      ) fail("SnapshotFontEvidenceConflict", face.publicUrl);
    }
  }
  if (versions.size !== 1) fail("SnapshotHarfBuzzVersionConflict");
  if (backendRevisions.size !== 1) fail("SnapshotBackendRevisionConflict");
  const backendRevision = backendRevisions.values().next().value;
  if (backendRevision !== FONT_BACKEND_REVISION) {
    fail("FontBackendRevisionMismatch", `${backendRevision}:${FONT_BACKEND_REVISION}`);
  }
  const faces = Array.from(groups.values()).sort((left, right) =>
    left.sourceOrder - right.sourceOrder);
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
    template,
    manifestText: script.textContent,
    baseUrl: documentObject?.baseURI ?? globalThis.location?.href,
    ...collected,
  };
}

function resolvedFontUrl(publicUrl, baseUrl) {
  let resolved;
  try {
    resolved = new URL(publicUrl, baseUrl);
  } catch (error) {
    fail("SnapshotFontUrlInvalid", publicUrl, error);
  }
  if (!CONTENT_ADDRESS_PATTERN.test(resolved.pathname)) {
    fail("SnapshotFontUrlNotContentAddressed", publicUrl);
  }
  return resolved.href;
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
  const createSession = options.createFontSession ?? createFontSession;
  const digest = options.sha256 ?? sha256;
  const fetchImplementation = options.fetch ?? ((...args) => globalThis.fetch(...args));
  const validateContract = options.validateContract ?? validatePrecomputedSnapshotExactFontContract;
  const cache = new WeakMap();

  async function requireExactContract(root) {
    let result;
    try {
      result = await validateContract(root);
    } catch (error) {
      fail("SnapshotExactFontContractValidationFailed", undefined, error);
    }
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
      state.session?.close();
    }
  }

  async function load(context) {
    const bytesByUrl = new Map();
    const faceSpecs = [];
    for (const face of context.faces) {
      const url = resolvedFontUrl(face.publicUrl, context.baseUrl);
      let bytesPromise = bytesByUrl.get(url);
      if (!bytesPromise) {
        bytesPromise = (async () => {
          let response;
          try {
            response = await fetchImplementation(url, { credentials: "same-origin" });
          } catch (error) {
            fail("FontFetchFailed", url, error);
          }
          if (!response?.ok || typeof response.arrayBuffer !== "function") {
            fail("FontFetchFailed", `${url}:${response?.status ?? "invalid-response"}`);
          }
          try {
            return new Uint8Array(await response.arrayBuffer());
          } catch (error) {
            fail("FontFetchFailed", url, error);
          }
        })();
        bytesByUrl.set(url, bytesPromise);
      }
      const bytes = await bytesPromise;
      const actualSourceSha256 = await digest(bytes);
      if (actualSourceSha256 !== face.sourceSha256) {
        fail("FontSourceDigestMismatch", face.publicUrl);
      }
      faceSpecs.push({
        family: face.family,
        style: face.style,
        weight: [...face.weight],
        unicodeRange: face.unicodeRange,
        publicUrl: face.publicUrl,
        faceIndex: face.faceIndex,
        sourceOrder: face.sourceOrder,
        source: bytes.slice(),
      });
    }

    let session;
    try {
      session = await createSession(faceSpecs, { sessionPrefix: "tq-browser-font" });
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
    await requireExactContract(root);
    const context = snapshotContext(root);
    const cacheKey = `${context.baseUrl ?? ""}\u0000${context.manifestText}`;
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
        session: null,
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
      await requireExactContract(root);
      const current = snapshotContext(root);
      if (
        current.template !== context.template || current.manifestText !== context.manifestText ||
        current.baseUrl !== context.baseUrl
      ) fail("SnapshotManifestChangedDuringFontPreparation");
    } catch (error) {
      releaseStateReference(state);
      throw error;
    }
    const token = { state, released: false };
    return Object.freeze({
      id: session.id,
      paragraphSelector: context.paragraphSelector,
      renderFontFamilies: Object.freeze([...context.renderFontFamilies]),
      [HANDLE_STATE]: token,
    });
  }

  async function revalidate(root, handle) {
    const token = handle?.[HANDLE_STATE];
    if (!token || token.released || !token.state.session) {
      fail("BrowserFontSessionHandleInvalid");
    }
    // ExistingSessionLiveContractRevalidation: the loaded HarfBuzz session and
    // verified source bytes are immutable, but the host source, cascade and
    // declared font contract remain live. The contract validator already
    // rechecks those inputs after its asynchronous font probes, so one pass is
    // sufficient when no font fetch/session creation occurs between checks.
    await requireExactContract(root);
    const context = snapshotContext(root);
    const cacheKey = `${context.baseUrl ?? ""}\u0000${context.manifestText}`;
    const { state } = token;
    if (cacheKey !== state.cacheKey || state.versions.get(cacheKey) !== state) {
      fail("SnapshotManifestChangedDuringFontPreparation");
    }
    return handle;
  }

  function release(handle) {
    const token = handle?.[HANDLE_STATE];
    if (!token || token.released) return false;
    token.released = true;
    const { state } = token;
    releaseStateReference(state);
    return true;
  }

  return Object.freeze({ prepare, revalidate, release });
}

const defaultLoader = createBrowserFontSessionLoader();

export const prepareBrowserFontSession = defaultLoader.prepare;
export const revalidateBrowserFontSession = defaultLoader.revalidate;
export const releaseBrowserFontSession = defaultLoader.release;
