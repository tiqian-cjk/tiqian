import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";

import {
  BrowserFontSessionError,
  createBrowserFontSessionLoader,
} from "./browser-fonts.js";
import { FONT_BACKEND_REVISION } from "./precompute-fonts.js";

function digest(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function faceEvidence(sourceSha256, overrides = {}) {
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
    },
    ...overrides,
  };
}

function manifestWithFaces(facesByEntry, versions = facesByEntry.map(() => "fixture-hb")) {
  const descriptors = [];
  const descriptorIndexes = new Map();
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
    return { faceRef, coverageText: face.coverageText, probe: face.probe };
  }));
  return {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v10",
    fontSourcePolicy: "compatible-local-render-family-v2",
    renderFontFamilies: ["Fixture Sans"],
    paragraphSelector: "p[data-tq-snapshot-key]",
    valueStyles: [],
    valueStylesSha256: "fixture",
    typographies: [{ sha256: "fixture", value: {} }],
    fontEvidence: {
      backendRevision: FONT_BACKEND_REVISION,
      harfbuzzVersion: versions[0],
      faces: descriptors,
    },
    entries: facesByEntry.map((_faces, index) => ({
      key: `p-${index + 1}`,
      typographyRef: 0,
      fontFaceEvidence: fontFaceEvidence[index],
    })),
  };
}

function snapshotRoot(manifest) {
  const script = { textContent: JSON.stringify(manifest) };
  const template = {
    content: {
      querySelector(selector) {
        return selector === "[data-tq-snapshot-manifest]" ? script : null;
      },
    },
  };
  const documentObject = {
    baseURI: "https://example.test/blog/post/",
    getElementById(id) {
      return id === "tq-page" ? template : null;
    },
  };
  return {
    ownerDocument: documentObject,
    getAttribute(name) {
      return name === "snapshot-ref" ? "tq-page" : null;
    },
  };
}

function harness(manifest, options = {}) {
  const bytes = options.bytes ?? new TextEncoder().encode("fixture-font-source");
  const requests = [];
  const createCalls = [];
  const sessions = [];
  const contractCalls = [];
  let closeCount = 0;
  const fetch = async (url, init) => {
    requests.push({ url, init });
    if (options.fetchError) throw options.fetchError;
    return {
      ok: options.responseOk ?? true,
      status: options.responseStatus ?? 200,
      async arrayBuffer() {
        return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      },
    };
  };
  const createFontSession = async (specs, createOptions) => {
    createCalls.push({ specs, options: createOptions });
    if (options.createError) throw options.createError;
    const session = {
      id: `browser-session-${createCalls.length}`,
      backendRevision: options.backendRevision ?? FONT_BACKEND_REVISION,
      harfbuzzVersion: options.harfbuzzVersion ?? "fixture-hb",
      faces: specs.map((spec) => ({
        family: spec.family,
        style: spec.style,
        weight: [...spec.weight],
        unicodeRange: spec.unicodeRange,
        publicUrl: spec.publicUrl,
        sourceSha256: digest(spec.source),
        sfntSha256: "b".repeat(64),
        faceIndex: spec.faceIndex,
        sourceOrder: spec.sourceOrder,
        axisTags: ["wght"],
        localNames: ["Fixture CJK", "FixtureCJK"],
      })),
      close() {
        closeCount += 1;
      },
    };
    options.mutateSession?.(session);
    sessions.push(session);
    return session;
  };
  const loader = createBrowserFontSessionLoader({
    createFontSession,
    fetch,
    sha256: async (value) => digest(value),
    validateContract: async (root) => {
      contractCalls.push(root);
      const result = options.contractResults?.shift?.();
      return result ?? { matches: true, reason: null };
    },
  });
  return {
    loader,
    root: snapshotRoot(manifest),
    requests,
    createCalls,
    sessions,
    contractCalls,
    closeCount: () => closeCount,
  };
}

function assertCode(code) {
  return (error) => {
    assert.ok(error instanceof BrowserFontSessionError);
    assert.equal(error.code, code);
    return true;
  };
}

test("browser font sessions aggregate manifest evidence and close after the final release", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const sourceSha256 = digest(bytes);
  const manifest = manifestWithFaces([
    [faceEvidence(sourceSha256)],
    [faceEvidence(sourceSha256, { fontWeight: 500, axes: { wght: 500 } })],
  ]);
  const state = harness(manifest, { bytes });

  const [first, second] = await Promise.all([
    state.loader.prepare(state.root),
    state.loader.prepare(state.root),
  ]);

  assert.equal(first.id, "browser-session-1");
  assert.equal(second.id, first.id);
  assert.equal(first.paragraphSelector, "p[data-tq-snapshot-key]");
  assert.equal(state.requests.length, 1);
  assert.equal(state.requests[0].url, "https://example.test/assets/fixture-deadbeef.woff2");
  assert.deepEqual(state.requests[0].init, { credentials: "same-origin" });
  assert.equal(state.createCalls.length, 1);
  assert.equal(state.contractCalls.length, 4);
  assert.equal(state.createCalls[0].specs.length, 1);
  assert.equal(state.createCalls[0].options.sessionPrefix, "tq-browser-font");
  assert.equal(state.closeCount(), 0);

  assert.equal(state.loader.release(first), true);
  assert.equal(state.loader.release(first), false);
  assert.equal(state.closeCount(), 0);
  assert.equal(state.loader.release(second), true);
  assert.equal(state.closeCount(), 1);

  const next = await state.loader.prepare(state.root);
  assert.equal(next.id, "browser-session-2");
  assert.equal(state.requests.length, 2);
  assert.equal(state.createCalls.length, 2);
  assert.equal(state.loader.release(next), true);
  assert.equal(state.closeCount(), 2);
});

test("live snapshot font contract is required before fetching exact font bytes", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const manifest = manifestWithFaces([[faceEvidence(digest(bytes))]]);
  const state = harness(manifest, {
    bytes,
    contractResults: [{ matches: false, reason: "SnapshotSourceMismatch" }],
  });

  await assert.rejects(
    state.loader.prepare(state.root),
    (error) => {
      assertCode("SnapshotExactFontContractMismatch")(error);
      assert.match(error.message, /SnapshotSourceMismatch/u);
      return true;
    },
  );
  assert.equal(state.requests.length, 0);
  assert.equal(state.createCalls.length, 0);
});

test("live snapshot font contract is revalidated after asynchronous font preparation", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const manifest = manifestWithFaces([[faceEvidence(digest(bytes))]]);
  const state = harness(manifest, {
    bytes,
    contractResults: [
      { matches: true, reason: null },
      { matches: false, reason: "FontFaceContractMismatch" },
    ],
  });

  await assert.rejects(
    state.loader.prepare(state.root),
    assertCode("SnapshotExactFontContractMismatch"),
  );
  assert.equal(state.requests.length, 1);
  assert.equal(state.createCalls.length, 1);
  assert.equal(state.closeCount(), 1);
});

test("an existing font session revalidates live inputs without loading bytes again", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const manifest = manifestWithFaces([[faceEvidence(digest(bytes))]]);
  const state = harness(manifest, { bytes });
  const handle = await state.loader.prepare(state.root);

  assert.strictEqual(await state.loader.revalidate(state.root, handle), handle);
  assert.equal(state.contractCalls.length, 3);
  assert.equal(state.requests.length, 1);
  assert.equal(state.createCalls.length, 1);
  assert.equal(state.closeCount(), 0);

  assert.equal(state.loader.release(handle), true);
  await assert.rejects(
    state.loader.revalidate(state.root, handle),
    assertCode("BrowserFontSessionHandleInvalid"),
  );
});

test("source bytes are checked before a HarfBuzz session is created and failed loads are evicted", async () => {
  const manifest = manifestWithFaces([[faceEvidence("0".repeat(64))]]);
  const state = harness(manifest);

  await assert.rejects(state.loader.prepare(state.root), assertCode("FontSourceDigestMismatch"));
  await assert.rejects(state.loader.prepare(state.root), assertCode("FontSourceDigestMismatch"));

  assert.equal(state.requests.length, 2);
  assert.equal(state.createCalls.length, 0);
  assert.equal(state.closeCount(), 0);
});

for (const [name, expectedCode, options] of [
  [
    "decompressed sfnt digest",
    "FontSessionFaceMetadataMismatch",
    { mutateSession: (session) => { session.faces[0].sfntSha256 = "c".repeat(64); } },
  ],
  [
    "face family metadata",
    "FontSessionFaceMetadataMismatch",
    { mutateSession: (session) => { session.faces[0].family = "Wrong Family"; } },
  ],
  [
    "variable axes",
    "FontSessionFaceMetadataMismatch",
    { mutateSession: (session) => { session.faces[0].axisTags = []; } },
  ],
  [
    "OpenType local names",
    "FontSessionFaceMetadataMismatch",
    { mutateSession: (session) => { session.faces[0].localNames = ["Wrong Name"]; } },
  ],
  [
    "backend revision",
    "FontBackendRevisionMismatch",
    { backendRevision: "other-backend" },
  ],
  [
    "HarfBuzz version",
    "HarfBuzzVersionMismatch",
    { harfbuzzVersion: "other-hb" },
  ],
]) {
  test(`browser font session rejects mismatched ${name} and closes it`, async () => {
    const bytes = new TextEncoder().encode("fixture-font-source");
    const manifest = manifestWithFaces([[faceEvidence(digest(bytes))]]);
    const state = harness(manifest, { bytes, ...options });

    await assert.rejects(state.loader.prepare(state.root), assertCode(expectedCode));

    assert.equal(state.createCalls.length, 1);
    assert.equal(state.closeCount(), 1);
  });
}

test("conflicting duplicate face evidence misses before fetching font bytes", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const sourceSha256 = digest(bytes);
  const conflicting = faceEvidence(sourceSha256, { sfntSha256: "c".repeat(64) });
  const manifest = manifestWithFaces([
    [faceEvidence(sourceSha256)],
    [conflicting],
  ]);
  const state = harness(manifest, { bytes });

  await assert.rejects(state.loader.prepare(state.root), assertCode("SnapshotFontEvidenceConflict"));

  assert.equal(state.requests.length, 0);
  assert.equal(state.createCalls.length, 0);
});

test("the shared manifest HarfBuzz version must match the loaded session", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const evidence = faceEvidence(digest(bytes));
  const manifest = manifestWithFaces([[evidence], [evidence]], ["hb-one", "hb-two"]);
  const state = harness(manifest, { bytes });

  await assert.rejects(state.loader.prepare(state.root), assertCode("HarfBuzzVersionMismatch"));
  assert.equal(state.requests.length, 1);
});

test("sourceOrder restores the build face priority before creating the browser session", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const sourceSha256 = digest(bytes);
  const later = faceEvidence(sourceSha256, {
    publicUrl: "/assets/later-deadbeef.woff2",
    sourceOrder: 9,
  });
  const earlier = faceEvidence(sourceSha256, {
    publicUrl: "/assets/earlier-deadbeef.woff2",
    sourceOrder: 2,
  });
  const state = harness(manifestWithFaces([[later], [earlier]]), { bytes });

  const handle = await state.loader.prepare(state.root);

  assert.deepEqual(
    state.createCalls[0].specs.map((face) => [face.publicUrl, face.sourceOrder]),
    [
      ["/assets/earlier-deadbeef.woff2", 2],
      ["/assets/later-deadbeef.woff2", 9],
    ],
  );
  assert.equal(state.loader.release(handle), true);
});

test("duplicate sourceOrder across distinct faces misses before fetching", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const sourceSha256 = digest(bytes);
  const first = faceEvidence(sourceSha256, {
    publicUrl: "/assets/first-deadbeef.woff2",
    sourceOrder: 3,
  });
  const second = faceEvidence(sourceSha256, {
    publicUrl: "/assets/second-deadbeef.woff2",
    sourceOrder: 3,
  });
  const state = harness(manifestWithFaces([[first], [second]]), { bytes });

  await assert.rejects(
    state.loader.prepare(state.root),
    assertCode("SnapshotFontEvidenceConflict"),
  );
  assert.equal(state.requests.length, 0);
});

test("manifest backend revisions must agree with the browser backend", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const sourceSha256 = digest(bytes);
  const manifest = manifestWithFaces([[faceEvidence(sourceSha256)]]);
  manifest.fontEvidence.backendRevision = "stale-backend";
  const state = harness(manifest, { bytes });

  await assert.rejects(
    state.loader.prepare(state.root),
    assertCode("FontBackendRevisionMismatch"),
  );
  assert.equal(state.requests.length, 0);
});
