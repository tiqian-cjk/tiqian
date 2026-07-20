import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";

import {
  BrowserFontSessionError,
  browserFontSessionWorkerContract,
  createBrowserFontSessionLoader,
} from "./browser-fonts.js";
import {
  FONT_BACKEND_REVISION,
  FONT_REPLAY_REVISION,
} from "./snapshot-schema.js";

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

function manifestWithFaces(
  facesByEntry,
  versions = facesByEntry.map(() => "fixture-hb"),
  typography = {},
) {
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
    renderRevision: "prebroken-dom-v15",
    fontSourcePolicy: "host-compatible-stylesheet-v1",
    renderFontFamilies: ["Fixture CJK"],
    paragraphSelector: "p[data-tq-snapshot-key]",
    valueStyles: [],
    valueStylesSha256: "fixture",
    typographies: [{ sha256: "fixture", value: typography }],
    fontEvidence: {
      backendRevision: FONT_BACKEND_REVISION,
      harfbuzzVersion: versions[0],
      faces: descriptors,
    },
    fontReplay: {
      revision: FONT_REPLAY_REVISION,
      shapes: [],
      metrics: [],
    },
    entries: facesByEntry.map((_faces, index) => ({
      key: `p-${index + 1}`,
      typographyRef: 0,
      fontFaceEvidence: fontFaceEvidence[index],
    })),
  };
}

function snapshotRoot(manifest, documentOverrides = {}) {
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
    ...documentOverrides,
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
  const preparedContractCalls = [];
  const renderFaceCreates = [];
  const renderFaceAdds = [];
  const renderFaceDeletes = [];
  const renderFontSourceCreates = [];
  const renderFontSourceReleases = [];
  const fontLoads = [];
  let closeCount = 0;
  const fetch = async (url, init) => {
    requests.push({ url, init });
    const sequencedError = options.fetchErrors?.shift?.();
    if (sequencedError) throw sequencedError;
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
      faces: createOptions.faceMetadata.map((face) => ({
        ...face,
        weight: [...face.weight],
        axisTags: Object.keys(face.axes ?? {}).sort(),
        localNames: [...face.localNames],
      })),
      close() {
        closeCount += 1;
      },
    };
    options.mutateSession?.(session);
    sessions.push(session);
    return session;
  };
  const fontSet = options.documentOverrides?.fonts ?? {
    async load(descriptor, text) {
      fontLoads.push({ descriptor, text });
      return [{}];
    },
  };
  const createRenderFontFace = options.createRenderFontFace ?? ((family, source, descriptors) => {
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
  const createRenderFontSource = options.createRenderFontSource ?? ((source) => {
    renderFontSourceCreates.push(source);
    const url = `blob:fixture-font-${renderFontSourceCreates.length}`;
    let released = false;
    return {
      source: `url("${url}")`,
      release() {
        if (released) return false;
        released = true;
        renderFontSourceReleases.push(url);
        return true;
      },
    };
  });
  const loader = createBrowserFontSessionLoader({
    ...(options.useDefaultSession ? {} : { createFontSession }),
    fetch,
    sha256: async (value) => digest(value),
    createRenderFontFace,
    createRenderFontSource,
    validateContract: async (root) => {
      contractCalls.push(root);
      const result = options.contractResults?.shift?.();
      return result ?? { matches: true, reason: null };
    },
    ...(options.preparedContractResults ? {
      validatePreparedContract: async (root) => {
        preparedContractCalls.push(root);
        return options.preparedContractResults.shift() ?? { matches: true, reason: null };
      },
    } : {}),
  });
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
  assert.equal(state.requests.length, 0);
  assert.equal(state.createCalls.length, 1);
  assert.equal(state.contractCalls.length, 4);
  assert.equal(state.createCalls[0].specs.length, 1);
  assert.equal(state.createCalls[0].options.sessionPrefix, "tq-browser-font");
  assert.deepEqual(state.createCalls[0].options.baseFeatures, []);
  assert.equal(state.closeCount(), 0);

  assert.equal(state.loader.release(first), true);
  assert.equal(state.loader.release(first), false);
  assert.equal(state.closeCount(), 0);
  assert.equal(state.renderFaceDeletes.length, 0);
  assert.equal(state.loader.release(second), true);
  assert.equal(state.closeCount(), 1);
  assert.equal(state.renderFaceDeletes.length, 0);

  const next = await state.loader.prepare(state.root);
  assert.equal(next.id, "browser-session-2");
  assert.equal(state.requests.length, 0);
  assert.equal(state.createCalls.length, 2);
  assert.equal(state.loader.release(next), true);
  assert.equal(state.closeCount(), 2);
});

test("browser font sessions reuse a live adoption proof before probing again", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const sourceSha256 = digest(bytes);
  const state = harness(manifestWithFaces([[faceEvidence(sourceSha256)]]), {
    bytes,
    preparedContractResults: [
      { matches: true, reason: null },
      { matches: true, reason: null },
      { matches: true, reason: null },
    ],
  });

  const handle = await state.loader.prepare(state.root);
  assert.equal(state.contractCalls.length, 0);
  assert.equal(state.preparedContractCalls.length, 2);

  assert.strictEqual(await state.loader.revalidate(state.root, handle), handle);
  assert.equal(state.contractCalls.length, 0);
  assert.equal(state.preparedContractCalls.length, 3);
  assert.equal(state.loader.release(handle), true);
});

test("browser font sessions expose only replay identity to the layout Worker", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const manifest = manifestWithFaces([[faceEvidence(digest(bytes))]]);
  const state = harness(manifest, { bytes });

  const handle = await state.loader.prepare(state.root);
  const contract = browserFontSessionWorkerContract(handle);

  assert.deepEqual(contract, {
    sessionKey: handle.id,
    manifestText: JSON.stringify(manifest),
  });
  assert.equal(state.loader.release(handle), true);
  assert.throws(() => browserFontSessionWorkerContract(handle), assertCode("BrowserFontSessionHandleInvalid"));
});

test("layout Worker plans survive duplicate module instances and reach the runtime bridge", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const state = harness(manifestWithFaces([[faceEvidence(digest(bytes))]]), { bytes });
  const handle = await state.loader.prepare(state.root);
  const originalWorker = globalThis.Worker;
  const originalInnerHeight = globalThis.innerHeight;
  const originalApi = globalThis.TiqianWeb;
  const originalBridge = globalThis.__TiqianLayoutWorker;
  const coordinatorKey = Symbol.for("@tiqian/prose.layout-worker-coordinator.v1");
  const originalCoordinator = globalThis[coordinatorKey];
  const element = {
    closest: () => state.root,
    getBoundingClientRect: () => ({ top: 0, bottom: 24 }),
  };
  const selectors = [];
  state.root.querySelectorAll = (selector) => {
    selectors.push(selector);
    return [element];
  };
  let requestText = "first";
  const completionSelector = ":is(p, li):not([data-tq-snapshot-key])";

  class FixtureWorker {
    listeners = new Map();

    addEventListener(type, listener) {
      this.listeners.set(type, listener);
    }

    postMessage(message) {
      queueMicrotask(() => this.listeners.get("message")?.({
        data: message.type === "layout"
          ? message.request.text === "failure"
            ? { id: message.id, ok: false, error: "fixture replay miss" }
            : { id: message.id, ok: true, plan: { fixture: message.request.text } }
          : { id: message.id, ok: true },
      }));
    }

    terminate() {}
  }

  try {
    delete globalThis[coordinatorKey];
    delete globalThis.__TiqianLayoutWorker;
    globalThis.Worker = FixtureWorker;
    globalThis.innerHeight = 800;
    globalThis.TiqianWeb = {
      workerLayoutRequest: () => JSON.stringify({
        text: requestText,
        maxWidthPx: 320,
        semantics: [],
        renderInlineBoxes: [],
      }),
    };

    const firstModule = await import(`./worker-layout.js?fixture=first-${Date.now()}`);
    assert.equal(await firstModule.prepareWorkerLayouts(state.root, handle, {
      paragraphSelector: completionSelector,
    }), 1);
    const firstRequest = globalThis.TiqianWeb.workerLayoutRequest();
    assert.equal(
      JSON.parse(globalThis.__TiqianLayoutWorker.take(element, handle.id, firstRequest)).plan.fixture,
      "first",
    );
    const semanticOnlyChange = JSON.stringify({
      ...JSON.parse(firstRequest),
      semantics: [{ start: 0, end: 5, tagName: "a", attributes: [["href", "/latest"]] }],
      renderInlineBoxes: [{ start: 0, end: 5, inlineStart: 1, inlineEnd: 2 }],
    });
    const semanticRecord = JSON.parse(
      globalThis.__TiqianLayoutWorker.take(element, handle.id, semanticOnlyChange),
    );
    assert.equal(semanticRecord.plan.fixture, "first");
    assert.deepEqual(semanticRecord.semantics, [{
      start: 0,
      end: 5,
      tagName: "a",
      attributes: [["href", "/latest"]],
    }]);
    assert.deepEqual(semanticRecord.inlineBoxes, [
      { start: 0, end: 5, inlineStart: 1, inlineEnd: 2 },
    ]);
    const changedMeasure = JSON.stringify({
      ...JSON.parse(firstRequest),
      maxWidthPx: 319,
    });
    assert.equal(
      globalThis.__TiqianLayoutWorker.take(element, handle.id, changedMeasure),
      null,
    );

    requestText = "second";
    const secondModule = await import(`./worker-layout.js?fixture=second-${Date.now()}`);
    assert.equal(await secondModule.prepareWorkerLayouts(state.root, handle, {
      paragraphSelector: completionSelector,
    }), 1);
    const secondRequest = globalThis.TiqianWeb.workerLayoutRequest();
    assert.equal(
      JSON.parse(globalThis.__TiqianLayoutWorker.take(element, handle.id, secondRequest)).plan.fixture,
      "second",
    );
    assert.equal(globalThis.__TiqianLayoutWorker.issue(element, handle.id, secondRequest), null);

    requestText = "failure";
    assert.equal(await secondModule.prepareWorkerLayouts(state.root, handle, {
      paragraphSelector: completionSelector,
    }), 0);
    const failedRequest = globalThis.TiqianWeb.workerLayoutRequest();
    assert.equal(globalThis.__TiqianLayoutWorker.take(element, handle.id, failedRequest), null);
    assert.equal(
      globalThis.__TiqianLayoutWorker.issue(element, handle.id, failedRequest),
      "fixture replay miss",
    );

    requestText = "default-runtime-set";
    assert.equal(await secondModule.prepareWorkerLayouts(state.root, handle, {}), 1);
    const defaultRequest = globalThis.TiqianWeb.workerLayoutRequest();
    assert.equal(
      JSON.parse(globalThis.__TiqianLayoutWorker.take(element, handle.id, defaultRequest)).plan.fixture,
      "default-runtime-set",
    );

    assert.equal(state.loader.release(handle), true);
    assert.equal(globalThis.__TiqianLayoutWorker.take(element, handle.id, firstRequest), null);
    assert.equal(globalThis.__TiqianLayoutWorker.take(element, handle.id, secondRequest), null);
    assert.equal(globalThis.__TiqianLayoutWorker.issue(element, handle.id, failedRequest), null);
    assert.deepEqual(selectors, [
      completionSelector,
      completionSelector,
      completionSelector,
      "p, li",
    ]);
  } finally {
    globalThis[coordinatorKey]?.worker?.terminate?.();
    if (originalCoordinator === undefined) delete globalThis[coordinatorKey];
    else globalThis[coordinatorKey] = originalCoordinator;
    if (originalBridge === undefined) delete globalThis.__TiqianLayoutWorker;
    else globalThis.__TiqianLayoutWorker = originalBridge;
    if (originalWorker === undefined) delete globalThis.Worker;
    else globalThis.Worker = originalWorker;
    if (originalInnerHeight === undefined) delete globalThis.innerHeight;
    else globalThis.innerHeight = originalInnerHeight;
    if (originalApi === undefined) delete globalThis.TiqianWeb;
    else globalThis.TiqianWeb = originalApi;
    state.loader.release(handle);
  }
});

test("browser font sessions retain whitespace-only glyph evidence", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const sourceSha256 = digest(bytes);
  const manifest = manifestWithFaces([[
    faceEvidence(sourceSha256, {
      unicodeRange: "U+0020",
      coverageText: " ",
      probe: {
        ...faceEvidence(sourceSha256).probe,
        text: " ",
        advancePx: 4,
        script: "Latn",
      },
    }),
  ]]);
  const state = harness(manifest, { bytes });

  const handle = await state.loader.prepare(state.root);

  assert.equal(state.createCalls.length, 1);
  assert.equal(state.loader.release(handle), true);
});

test("browser font sessions never fetch font bytes for server replay", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const manifest = manifestWithFaces([[faceEvidence(digest(bytes))]]);
  const state = harness(manifest, {
    bytes,
    fetchErrors: [new TypeError("conditional cache race")],
  });

  const handle = await state.loader.prepare(state.root);

  assert.equal(state.requests.length, 0);
  assert.equal(state.loader.release(handle), true);
});

test("lining numeric snapshots preserve the server lnum replay contract", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const manifest = manifestWithFaces(
    [[faceEvidence(digest(bytes), { probe: {
      ...faceEvidence(digest(bytes)).probe,
      features: ["lnum"],
    } })]],
    undefined,
    { fontVariantNumeric: "lining-nums" },
  );
  const state = harness(manifest, { bytes });

  const handle = await state.loader.prepare(state.root);

  assert.deepEqual(state.createCalls[0].options.baseFeatures, ["lnum"]);
  assert.equal(state.loader.release(handle), true);
});

test("browser font sessions include runtime-only semantic contract entries", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const sourceSha256 = digest(bytes);
  const manifest = manifestWithFaces([
    [faceEvidence(sourceSha256)],
    [faceEvidence(sourceSha256, {
      publicUrl: "/assets/semantic-deadbeef.woff2",
      sourceOrder: 1,
      unicodeRange: "U+6E32",
      coverageText: "渲",
      probe: {
        ...faceEvidence(sourceSha256).probe,
        text: "渲",
      },
    })],
  ]);
  manifest.fontContractEntries = [manifest.entries.pop()];
  const state = harness(manifest, { bytes });

  const handle = await state.loader.prepare(state.root);

  assert.equal(state.createCalls[0].specs.length, 2);
  assert.equal(state.requests.length, 0);
  assert.equal(state.loader.release(handle), true);
});

test("runtime replay loads and preserves the host render family", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const manifest = manifestWithFaces([[faceEvidence(digest(bytes))]]);
  const state = harness(manifest, { bytes });
  const handle = await state.loader.prepare(state.root);

  assert.deepEqual(handle.renderFontFamilies, ["Fixture CJK"]);
  assert.equal(state.renderFaceCreates.length, 0);
  assert.equal(state.renderFaceAdds.length, 0);
  assert.equal(await state.loader.prepareRenderFonts(state.root, handle), true);
  assert.deepEqual(state.fontLoads, [{
    descriptor: 'normal 400 16px "Fixture CJK"',
    text: "中国",
  }]);
  assert.equal(state.loader.release(handle), true);
  assert.equal(state.renderFaceDeletes.length, 0);
});

test("live snapshot font contract is required before creating replay state", async () => {
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

test("parser-time source mismatch retries as soon as the snapshot source becomes complete", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const manifest = manifestWithFaces([[faceEvidence(digest(bytes))]]);
  let mutationCallback;
  class FixtureMutationObserver {
    constructor(callback) {
      mutationCallback = callback;
    }
    observe() {}
    disconnect() {}
  }
  const state = harness(manifest, {
    bytes,
    contractResults: [
      { matches: false, reason: "SnapshotSourceMismatch" },
      { matches: false, reason: "SnapshotSourceMismatch" },
      { matches: true, reason: null },
      { matches: true, reason: null },
    ],
    documentOverrides: {
      readyState: "loading",
      defaultView: { MutationObserver: FixtureMutationObserver },
      addEventListener() {},
      removeEventListener() {},
    },
  });

  const pending = state.loader.prepare(state.root);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(state.requests.length, 0);
  mutationCallback();
  const handle = await pending;

  assert.equal(state.requests.length, 0);
  assert.equal(state.createCalls.length, 1);
  assert.equal(state.loader.release(handle), true);
});

test("parser completion makes an unresolved source mismatch fail closed", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const manifest = manifestWithFaces([[faceEvidence(digest(bytes))]]);
  let parserComplete;
  class FixtureMutationObserver {
    observe() {}
    disconnect() {}
  }
  const state = harness(manifest, {
    bytes,
    contractResults: [
      { matches: false, reason: "SnapshotSourceMismatch" },
      { matches: false, reason: "SnapshotSourceMismatch" },
      { matches: false, reason: "SnapshotSourceMismatch" },
    ],
    documentOverrides: {
      readyState: "loading",
      defaultView: { MutationObserver: FixtureMutationObserver },
      addEventListener(name, listener) {
        if (name === "DOMContentLoaded") parserComplete = listener;
      },
      removeEventListener() {},
    },
  });

  const pending = state.loader.prepare(state.root);
  await new Promise((resolve) => setImmediate(resolve));
  parserComplete();

  await assert.rejects(pending, (error) => {
    assertCode("SnapshotExactFontContractMismatch")(error);
    assert.match(error.message, /SnapshotSourceMismatch/u);
    return true;
  });
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
  assert.equal(state.requests.length, 0);
  assert.equal(state.createCalls.length, 1);
  assert.equal(state.closeCount(), 1);
});

test("same-document navigation keeps a root-relative font session valid", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const manifest = manifestWithFaces([[faceEvidence(digest(bytes))]]);
  let state;
  state = harness(manifest, {
    bytes,
    mutateSession() {
      state.root.ownerDocument.baseURI = "https://example.test/another/article/";
    },
  });

  const handle = await state.loader.prepare(state.root);

  assert.equal(state.requests.length, 0);
  assert.equal(state.loader.release(handle), true);
});

test("an existing font session revalidates live inputs without loading bytes again", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const manifest = manifestWithFaces([[faceEvidence(digest(bytes))]]);
  const state = harness(manifest, { bytes });
  const handle = await state.loader.prepare(state.root);

  assert.strictEqual(await state.loader.revalidate(state.root, handle), handle);
  assert.equal(state.contractCalls.length, 3);
  assert.equal(state.requests.length, 0);
  assert.equal(state.createCalls.length, 1);
  assert.equal(state.closeCount(), 0);

  assert.equal(state.loader.release(handle), true);
  await assert.rejects(
    state.loader.revalidate(state.root, handle),
    assertCode("BrowserFontSessionHandleInvalid"),
  );
});

test("runtime replay trusts captured manifest digests without refetching font bytes", async () => {
  const manifest = manifestWithFaces([[faceEvidence("0".repeat(64))]]);
  const state = harness(manifest);

  const handle = await state.loader.prepare(state.root);
  assert.equal(state.requests.length, 0);
  assert.equal(state.createCalls.length, 1);
  assert.equal(state.loader.release(handle), true);
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
  assert.equal(state.requests.length, 0);
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

test("the default browser session scales server shaping evidence without loading HarfBuzz", async () => {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const manifest = manifestWithFaces([[faceEvidence(digest(bytes))]]);
  const families = "Fixture CJK";
  const shapeKey = JSON.stringify([
    "正文",
    families,
    400,
    false,
    "zh-Hans",
    "CjkText",
    "正文",
  ]);
  const metricKey = JSON.stringify([
    families,
    400,
    false,
    "CjkText",
    "正文",
  ]);
  manifest.fontReplay.shapes = [{
    key: shapeKey,
    result: {
      faceId: "fixture-face",
      fontInstanceId: "fixture-instance",
      script: "Hani",
      features: [],
      unsafeBreakCount: 0,
      advanceEm: 2,
      glyphs: [{
        id: 42,
        advanceEm: 2,
        xEm: 0,
        yEm: 0,
        boundsEm: [0, -0.8, 2, 0.2],
      }],
    },
  }];
  manifest.fontReplay.metrics = [{
    key: metricKey,
    valuesEm: [0.8, 0.2, 0, 0.8, 0.2],
  }];
  const state = harness(manifest, { bytes, useDefaultSession: true });

  const handle = await state.loader.prepare(state.root);
  const shape = globalThis.__TiqianFontBackend.shape(
    handle.id,
    "正文",
    families,
    20,
    400,
    false,
    "zh-Hans",
    "CjkText",
    "正文",
  );
  assert.equal(globalThis.__TiqianFontBackend.shapeAdvance(shape), 40);
  assert.equal(globalThis.__TiqianFontBackend.shapeGlyphAdvance(shape, 0), 40);
  assert.equal(globalThis.__TiqianFontBackend.shapeGlyphBound(shape, 0, 1), -16);
  globalThis.__TiqianFontBackend.releaseShape(shape);
  const metrics = globalThis.__TiqianFontBackend.metrics(
    handle.id,
    families,
    20,
    400,
    false,
    "CjkText",
    "正文",
  );
  assert.deepEqual(
    Array.from({ length: 5 }, (_, index) =>
      globalThis.__TiqianFontBackend.metricValue(metrics, index)),
    [16, 4, 0, 16, 4],
  );
  globalThis.__TiqianFontBackend.releaseMetrics(metrics);
  assert.equal(state.createCalls.length, 0);
  assert.equal(state.loader.release(handle), true);
});
