import assert from "node:assert/strict";
import test from "node:test";

import {
  FakeElement,
  FakeFragment,
  FakeText,
  FakeNode,
  asFakeElement,
  asGetComputedStyle,
  asDocument,
  canonicalFixtureNode,
  fixtureComputedStyle,
  sha256,
  styleDeclaration,
  type FixtureComputedStyleOverrides,
} from "./snapshot-dom-fixtures.js";
import {
  adoptedPrecomputedSnapshotLiveIssue,
  cssFaceContract,
  detachPrecomputedSnapshot,
  isPrecomputedSnapshotAdopted,
  precomputedSnapshotMaximumMeasureMatches,
  renderedPreparedParagraphIssue,
  restorePrecomputedSnapshot,
  tryAdoptPrecomputedSnapshot,
  validatePrecomputedSnapshotFontReplayContract,
  validatePrecomputedSnapshotFontReplayLiveContract,
  validatePrecomputedSnapshotFontContract,
} from "../src/sampler/snapshot/precomputed.js";
import { FONT_REPLAY_REVISION, stableStringify } from "../src/sampler/snapshot/snapshot-schema.js";
import { snapshotTablesForRoot } from "../src/sampler/snapshot/snapshot-tables.js";
import { writeBinaryTable } from "../src/sampler/snapshot/table-binary-encode.js";
import { createEnhanceContext, type EnhancedElementContext } from "../src/engine/context/enhance-context.js";
import { initializeGlobalServices } from "../src/services/global-services.js";
import type {
  SnapshotManifestFace,
  SnapshotManifestWire,
  SnapshotManifestWireEntry,
} from "../src/sampler/snapshot/snapshot-manifest.js";
import type { SnapshotProbe } from "../src/sampler/snapshot/snapshot-table-binary.js";

initializeGlobalServices();

type FakeElementAsHTMLElement = FakeElement & HTMLElement;
type FakeElementAsElement = FakeElement & Element;

/**
 * The adoption/restore/detach entry points take an EnhancedElementContext as
 * their second argument. One context per fake root, cached so adopt and the
 * later restore/detach in the same test share the same context value.
 */
const enhanceContexts = new WeakMap<FakeElement, EnhancedElementContext>();
function contextFor(root: FakeElement): EnhancedElementContext {
  let context = enhanceContexts.get(root);
  if (!context) {
    context = createEnhanceContext(root as FakeElementAsElement);
    enhanceContexts.set(root, context);
  }
  return context;
}

interface Typography {
  fontFamilies: string[];
  fontSizePx: number;
  lineHeightPx: number;
  locale: string;
  fontWeight: number;
  italic: boolean;
  firstLineIndentIc: number;
  lineLengthGridEnabled: boolean;
  letterSpacingPx: number;
  fontFeatureSettings: string;
  fontVariationSettings: string;
  fontVariantNumeric: string;
}

interface Probe {
  text: string;
  advancePx: number;
  fontSizePx: number;
  fontWeight: number;
  italic: boolean;
  script: string;
  language: string;
  features?: string[];
}

interface FaceEvidence {
  family: string;
  style: string;
  weight: [number, number];
  unicodeRange: string;
  publicUrl: string;
  sourceSha256: string;
  sfntSha256: string;
  faceIndex: number;
  sourceOrder: number;
  axes: Record<string, never>;
  localNames: string[];
  coverageText: string;
  probe: Probe;
}

interface FixtureStyleSheetReference {
  href: string;
}

interface FixtureCssRule {
  type: number;
  style: CSSStyleDeclaration;
  parentStyleSheet: FixtureStyleSheetReference;
}

interface FixtureStyleSheet {
  href: string;
  cssRules: FixtureCssRule[];
}

interface FixtureFontFaceSet {
  load(descriptor: string): Promise<Record<string, never>[]>;
}

interface FixtureRangeRect {
  width: number;
}

interface FixtureRange {
  selectNodeContents(node: FakeElement): void;
  getBoundingClientRect(): FixtureRangeRect;
}

interface FixtureDocument {
  baseURI: string;
  elements: Map<string, FakeElement>;
  styleSheets: FixtureStyleSheet[];
  fonts: FixtureFontFaceSet;
  createDocumentFragment(): FakeFragment;
  createElement(tagName: string): FakeElement;
  createRange(): FixtureRange;
  getElementById(id: string): FakeElement | null;
  body: FakeElement;
}

/**
 * The fixture document crosses the fake/DOM seam twice: elements created by
 * the fixture remember it as their ownerDocument, and two tests install it as
 * globalThis.document. The intersection keeps the fixture's own member types
 * while the Document half satisfies the DOM side, so one single assertion
 * carries it across.
 */
type FixtureDocumentAsDocument = Document & FixtureDocument;

interface FixtureElementRect {
  width: number;
  left: number;
  right: number;
  top: number;
  bottom: number;
  height: number;
}

interface FixtureOptions {
  localSource?: boolean;
  localName?: string;
  unsafeSibling?: boolean;
  typographyDigest?: string | null;
  probeWidth?: number;
  segmentWidth?: number;
  segmentLeft?: number;
  lineEnd?: number;
  lineTop?: number;
  lineBottom?: number;
  lineBaseline?: number;
  sentinelTop?: number;
  paragraphHeight?: number;
  probeFeatures?: string[] | undefined;
  fontVariantNumeric?: string;
  boundaryFeatureSignature?: string | null;
  shapingBoundary?: boolean;
  semanticGeometry?: boolean;
  renderFontProjection?: boolean;
  nativeText?: boolean;
  fontDisplay?: string;
  entrySource?: string | undefined;
  snapshotTablesSha?: string | null;
  entryCount?: number;
  paragraphTag?: string;
  paragraphSelector?: string;
  paragraphWidth?: number;
  maximumWidth?: number;
}

interface FixtureResult {
  documentObject: FixtureDocument;
  root: FakeElement;
  paragraph: FakeElement;
  originalText: FakeText;
  entry: FakeElement;
  measuredProbeStyles: string[];
}

/**
 * Snapshot tables of the fixtures. Each fixture registers its own bytes under
 * a unique URL; the fetch stub serves them so the transport loads through
 * the path a host page uses.
 */
/**
 * The fixture's table transport answers through globalThis.fetch. The stub's
 * own response only carries the two members the transport reads; naming the
 * view keeps the literal out of any assertion.
 */
interface TableTransportResponseView {
  ok: boolean;
  arrayBuffer(): Promise<Uint8Array>;
}

type TableFetchResult = TableTransportResponseView | Response;

type HostGetComputedStyle = typeof globalThis.getComputedStyle;

/**
 * fixtureComputedStyle serves the fixture's computed styles where the product
 * reads the host's getComputedStyle. The intersection keeps the fixture
 * function's own type, so one single assertion carries it across the seam
 * without wrapping the value.
 */
type FixtureComputedStyleAsHost = HostGetComputedStyle & typeof fixtureComputedStyle;

let tableCounter = 0;
const tableBytesByUrl = new Map<string, Uint8Array>();
const chainFetch = globalThis.fetch;
const tableFetchStub = async (url: RequestInfo | URL, init?: RequestInit): Promise<TableFetchResult> => {
  const urlStr = String(url);
  const bytes = tableBytesByUrl.get(urlStr);
  if (bytes != null) return { ok: true, arrayBuffer: async (): Promise<Uint8Array> => bytes };
  return chainFetch(url, init);
};
(globalThis as Record<string, unknown>).fetch = tableFetchStub;

function fixture(options: FixtureOptions = {}): FixtureResult {
  const {
    localSource = false,
    localName = "Fixture CJK",
    unsafeSibling = false,
    typographyDigest = null,
    probeWidth = 36,
    segmentWidth = 36,
    segmentLeft = 0,
    lineEnd = segmentWidth,
    lineTop = 0,
    lineBottom = 27,
    lineBaseline = 20,
    sentinelTop = lineBaseline,
    paragraphHeight = lineBottom,
    probeFeatures = undefined,
    fontVariantNumeric = "normal",
    boundaryFeatureSignature = null,
    shapingBoundary = true,
    semanticGeometry = false,
    renderFontProjection = false,
    nativeText = false,
    fontDisplay = "block",
    entrySource = undefined,
    snapshotTablesSha = null,
    entryCount = 1,
    paragraphTag = "p",
    paragraphSelector = "p[data-tq-snapshot-key]",
    paragraphWidth = 360,
    maximumWidth = 360,
  } = options;

  const measuredProbeStyles: string[] = [];
  const documentObject: Partial<FixtureDocument> = {
    baseURI: "https://example.test/post/",
    elements: new Map(),
    styleSheets: [],
    fonts: { load: async (): Promise<Record<string, never>[]> => [{}] },
    createDocumentFragment: (): FakeFragment => new FakeFragment(),
    createElement(tagName: string): FakeElement {
      const element = new FakeElement(tagName);
      element.ownerDocument = documentObject as FixtureDocumentAsDocument;
      element._fixtureProbeWidth = probeWidth;
      element._onFixtureProbeMeasure = (style: string): void => { measuredProbeStyles.push(style); };
      return element;
    },
    createRange() {
      let selectedNode: FakeElement | null = null;
      return {
        selectNodeContents(node: FakeElement): void {
          selectedNode = node;
        },
        getBoundingClientRect(): FixtureRangeRect {
          const element = selectedNode;
          if (element?.style?.cssText) measuredProbeStyles.push(element.style.cssText);
          return { width: probeWidth };
        },
      };
    },
    getElementById(id: string): FakeElement | null {
      return documentObject.elements?.get(id) ?? null;
    },
  };
  documentObject.body = documentObject.createElement!("body");

  const root = documentObject.createElement!("tiqian-prose");
  root.setAttribute("snapshot-ref", "tq-page");
  const paragraph = documentObject.createElement!(paragraphTag);
  paragraph.setAttribute("data-tq-snapshot-key", "p-1");
  paragraph.width = paragraphWidth;
  paragraph.height = paragraphHeight;
  paragraph.innerText = "中国";
  const originalText = new FakeText("中国");
  paragraph.appendChild(originalText);
  root.appendChild(paragraph);

  const typography: Typography = {
    fontFamilies: ["Fixture CJK"],
    fontSizePx: 18,
    lineHeightPx: 27,
    locale: "zh-Hans",
    fontWeight: 400,
    italic: false,
    firstLineIndentIc: 0,
    lineLengthGridEnabled: true,
    letterSpacingPx: 0,
    fontFeatureSettings: "normal",
    fontVariationSettings: "normal",
    fontVariantNumeric,
  };
  const evidence: FaceEvidence = {
    family: "Fixture CJK",
    style: "normal",
    weight: [400, 400],
    unicodeRange: "U+4E00-9FFF",
    publicUrl: "/assets/fixture-deadbeef.woff2",
    sourceSha256: "a".repeat(64),
    sfntSha256: "b".repeat(64),
    faceIndex: 0,
    sourceOrder: 0,
    axes: {},
    localNames: ["Fixture CJK", "FixtureCJK"],
    coverageText: "中国",
    probe: {
      text: "中国",
      advancePx: 36,
      fontSizePx: 18,
      fontWeight: 400,
      italic: false,
      script: "Hani",
      language: "zh-Hans",
      ...(probeFeatures === undefined ? {} : { features: probeFeatures }),
    },
  };
  const template = documentObject.createElement!("template");
  template.content = new FakeFragment();
  const entry = documentObject.createElement!("div");
  entry.setAttribute("data-tq-entry", "p-1");
  const marker = documentObject.createElement!("span");
  marker.setAttribute("data-tq-geometry", "true");
  marker.setAttribute("data-tq-line-flow-width", "36");
  marker.setAttribute("data-tq-line-width", "36");
  marker.setAttribute("data-tq-line-top", String(lineTop));
  marker.setAttribute("data-tq-line-bottom", String(lineBottom));
  marker.setAttribute("data-tq-line-baseline", String(lineBaseline));
  marker.setAttribute("data-tq-paragraph-height", String(lineBottom));
  marker.left = 0;
  marker.top = lineTop;
  marker.height = lineBottom - lineTop;
  const rendered = nativeText ? new FakeText("中国") : documentObject.createElement!("span");
  if (!nativeText) {
    const renderedElement = rendered as FakeElement;
    renderedElement.setAttribute("data-tq-advance", "36");
    renderedElement.setAttribute("data-tq-geometry", "true");
    if (renderFontProjection) renderedElement.setAttribute("data-tq-render-font-projection", "true");
    if (shapingBoundary) renderedElement.setAttribute("data-tq-shaping-boundary", "current-segment");
    if (boundaryFeatureSignature != null) {
      renderedElement.setAttribute("data-tq-open-type-features", boundaryFeatureSignature);
    }
    renderedElement.setAttribute("data-tq-x", "0");
    renderedElement.width = segmentWidth;
    renderedElement.left = segmentLeft;
    renderedElement.textContent = "中国";
  }
  const sentinel = documentObject.createElement!("span");
  sentinel.setAttribute("data-tq-geometry", "true");
  sentinel.setAttribute("data-tq-line-end-sentinel", "0");
  sentinel.left = lineEnd;
  sentinel.top = sentinelTop;
  const renderedParent = semanticGeometry
    ? documentObject.createElement!("strong")
    : null;
  if (renderedParent) {
    renderedParent.setAttribute("data-tq-source-semantic", "true");
    renderedParent.appendChild(rendered);
  }
  entry.append(marker, renderedParent ?? rendered, sentinel);
  // The shared rows live in one binary snapshot table; the manifest pins its
  // digest and the root references it by URL. The global fetch stub of this
  // file serves the bytes, so every fixture walks the transport a host page
  // uses. Beyond the first entry, per-entry probes cover distinct text so
  // article-sized evidence loads exercise every row.
  const probes: Probe[] = [];
  const manifestEntries: SnapshotManifestWireEntry[] = [];
  for (let index = 0; index < entryCount; index += 1) {
    const coverageText = index === 0
      ? evidence.coverageText
      : `中国${String.fromCodePoint(0x4e00 + index)}`;
    manifestEntries.push({
      key: `p-${index + 1}`,
      sourceSha256: sha256("中国"),
      typographyRef: 0,
      maxWidthPx: maximumWidth,
      fontFaceEvidence: [{
        faceRef: 0,
        coverageText,
        probeRef: probes.push({ features: [], ...evidence.probe,
          ...(index === 0 ? {} : { text: coverageText }) }) - 1,
      }],
      renderArtifactSha256: sha256(stableStringify(entry.childNodes.map(canonicalFixtureNode))),
    });
  }
  const tableBytes = writeBinaryTable({
    replayStrings: [],
    metrics: [],
    probes: probes as SnapshotProbe[],
    typographies: [{
      sha256: typographyDigest ?? sha256(stableStringify(typography)),
      value: typography,
    }],
    faces: [{
      ...Object.fromEntries(Object.entries(evidence).filter(([key]) =>
        key !== "coverageText" && key !== "probe")),
    }],
    valueStyles: [],
    fontPreloads: ["/assets/fixture-deadbeef.woff2"],
    revisions: {
      backendRevision: "tiqian-shared-harfbuzz-v5",
      harfbuzzVersion: "fixture",
    },
  });
  const tableUrl = `https://tables.test/precomputed-${tableCounter += 1}.tiqtbl`;
  tableBytesByUrl.set(tableUrl, tableBytes);
  root.setAttribute("tq-tables", tableUrl);
  const manifest: SnapshotManifestWire = {
    schema: 2,
    tables: { snapshot: snapshotTablesSha ?? sha256(tableBytes) },
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v17",
    fontSourcePolicy: "host-compatible-stylesheet-v1",
    ...(entrySource === undefined ? {} : { entrySource }),
    renderFontFamilies: ["Fixture CJK"],
    paragraphSelector,
    fontReplay: { revision: FONT_REPLAY_REVISION, encoding: "shared-strings-v1", shapes: [] },
    entries: manifestEntries,
  };
  const script = documentObject.createElement!("script");
  script.setAttribute("data-tq-snapshot-manifest", "");
  script.textContent = JSON.stringify(manifest);
  template.content.append(script, entry);
  documentObject.elements!.set("tq-page", template);

  const source = `${localSource ? `local("${localName}"),` : ""}url("/assets/fixture-deadbeef.woff2")`;
  const fontFaceStyle = styleDeclaration({
    "font-family": "\"Fixture CJK\"",
    "font-style": "normal",
    "font-weight": "400",
    "font-display": fontDisplay,
    "unicode-range": "U+4E00-9FFF",
    src: source,
  });
  const sheet = { href: "https://example.test/fonts.css" };
  const cssRules = [{ type: 5, style: fontFaceStyle, parentStyleSheet: sheet }];
  if (unsafeSibling) {
    cssRules.push({
      type: 5,
      style: styleDeclaration({
        "font-family": "\"Fixture CJK\"",
        "font-style": "normal",
        "font-weight": "400",
        "unicode-range": "U+4E00-9FFF",
        src: 'local("Fixture CJK"),url("/assets/other-feedface.woff2")',
      }),
      parentStyleSheet: sheet,
    });
  }
  documentObject.styleSheets!.push({
    href: sheet.href,
    cssRules,
  });

  return { documentObject: documentObject as FixtureDocument, root, paragraph, originalText, entry, measuredProbeStyles };
}

function attachServerSource(documentObject: FixtureDocument, text: string = "中国"): void {
  const template = documentObject.createElement("template");
  template.content = new FakeFragment();
  const source = documentObject.createElement("div");
  source.setAttribute("data-tq-source-entry", "p-1");
  source.appendChild(new FakeText(text));
  template.content.appendChild(source);
  documentObject.elements.set("tq-page-source", template);
}

test("exact runtime fallback accepts a width miss only while every live input still matches", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { documentObject, root, paragraph } = fixture();
    paragraph.width = 240;

    assert.deepEqual(await validatePrecomputedSnapshotFontContract(root as FakeElementAsHTMLElement), {
      matches: true,
      reason: null,
      paragraphSelector: "p[data-tq-snapshot-key]",
      compatibleLocalDeclared: false,
    });

    paragraph.innerText = "中国—";
    assert.deepEqual(await validatePrecomputedSnapshotFontContract(root as FakeElementAsHTMLElement), {
      matches: false,
      reason: "SnapshotSourceMismatch",
    });
    assert.deepEqual(await validatePrecomputedSnapshotFontReplayContract(root as FakeElementAsHTMLElement), {
      matches: true,
      reason: null,
      paragraphSelector: "p[data-tq-snapshot-key]",
      compatibleLocalDeclared: false,
    });
    assert.deepEqual(validatePrecomputedSnapshotFontReplayLiveContract(root as FakeElementAsHTMLElement), {
      matches: true,
      reason: null,
      paragraphSelector: "p[data-tq-snapshot-key]",
      compatibleLocalDeclared: false,
    });
    documentObject.styleSheets[0].cssRules[0].style = styleDeclaration({
      "font-family": "\"Fixture CJK\"",
      "font-style": "normal",
      "font-weight": "400",
      "font-display": "block",
      "unicode-range": "U+4E00-9FFF",
      src: 'url("/assets/changed-feedface.woff2")',
    });
    assert.deepEqual(validatePrecomputedSnapshotFontReplayLiveContract(root as FakeElementAsHTMLElement), {
      matches: false,
      reason: "FontFaceContractChangedDuringFontPreparation",
    });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("runtime font replay validates the same host CSS contract as snapshots", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root } = fixture();
    assert.deepEqual(await validatePrecomputedSnapshotFontReplayContract(root as FakeElementAsHTMLElement), {
      matches: true,
      reason: null,
      paragraphSelector: "p[data-tq-snapshot-key]",
      compatibleLocalDeclared: false,
    });
    assert.deepEqual(validatePrecomputedSnapshotFontReplayLiveContract(root as FakeElementAsHTMLElement), {
      matches: true,
      reason: null,
      paragraphSelector: "p[data-tq-snapshot-key]",
      compatibleLocalDeclared: false,
    });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("snapshot list items preserve their native marker display contract", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph } = fixture({
      paragraphTag: "li",
      paragraphSelector: ":is(p, li)[data-tq-snapshot-key]",
    });

    assert.deepEqual(await validatePrecomputedSnapshotFontContract(root as FakeElementAsHTMLElement), {
      matches: true,
      reason: null,
      paragraphSelector: ":is(p, li)[data-tq-snapshot-key]",
      compatibleLocalDeclared: false,
    });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), {
      adopted: true,
      count: 1,
    });
    assert.equal(paragraph.getAttribute("data-tq-rendered"), "true");
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("exact runtime font evidence remains valid across responsive size and line-height", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  try {
    const { root, paragraph, originalText } = fixture();
    globalThis.getComputedStyle = (element: Element | null, pseudo?: string | null): CSSStyleDeclaration => {
      const fakeElement = element as FakeElementAsElement | null;
      return fixtureComputedStyle(
        fakeElement,
        pseudo,
        fakeElement === paragraph ? { fontSize: "15.75px", lineHeight: "28px" } : {},
      );
    };

    assert.deepEqual(await validatePrecomputedSnapshotFontContract(root as FakeElementAsHTMLElement), {
      matches: true,
      reason: null,
      paragraphSelector: "p[data-tq-snapshot-key]",
      compatibleLocalDeclared: false,
    });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), {
      adopted: false,
      reason: "SnapshotTypographyMismatch",
    });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("exact font validation rechecks live source after asynchronous font probes", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { documentObject, root, paragraph } = fixture();
    documentObject.fonts.load = async (): Promise<Record<string, never>[]> => {
      paragraph.innerText = "异步改写";
      return [{}];
    };

    assert.deepEqual(await validatePrecomputedSnapshotFontContract(root as FakeElementAsHTMLElement), {
      matches: false,
      reason: "SnapshotSourceChangedDuringValidation",
    });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("proportional quote evidence and prepared boundaries replay the same feature contract", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, measuredProbeStyles } = fixture({
      probeFeatures: ["pwid", "palt"],
      boundaryFeatureSignature: "pwid,palt",
    });

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), {
      adopted: true,
      count: 1,
    });
    assert.ok(measuredProbeStyles.some((style) =>
      style.includes("font-variant-east-asian:proportional-width!important")));
    assert.ok(measuredProbeStyles.some((style) =>
      style.includes('font-feature-settings:"halt" 0, "chws" 0, "palt" 1!important')));
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("unknown font probe features fail before snapshot adoption", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph, originalText } = fixture({ probeFeatures: ["calt"] });

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), {
      adopted: false,
      reason: "FontProbeFeaturesUnsupported",
    });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("an unreadable stylesheet makes the exact font source contract unverifiable", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { documentObject, root } = fixture();
    const unreadableSheet: FixtureStyleSheet = {
      href: "https://cross-origin.example/fonts.css",
      get cssRules(): FixtureCssRule[] {
        throw new DOMException("Blocked", "SecurityError");
      },
    };
    documentObject.styleSheets.push(unreadableSheet);

    assert.deepEqual(await validatePrecomputedSnapshotFontContract(root as FakeElementAsHTMLElement), {
      matches: false,
      reason: "FontFaceCssomUnverifiable",
    });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("a compact client font contract enables the exact runtime without claiming snapshot layout", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { documentObject, root } = fixture();
    const template = documentObject.elements.get("tq-page")!;
    const manifestScript = template.content!.querySelector("[data-tq-snapshot-manifest]");
    const manifest = JSON.parse(manifestScript!.textContent!);
    manifest.entrySource = "font-contract-v1";
    manifestScript!.textContent = JSON.stringify(manifest);

    assert.deepEqual(await validatePrecomputedSnapshotFontContract(root as FakeElementAsHTMLElement), {
      matches: true,
      reason: null,
      paragraphSelector: "p[data-tq-snapshot-key]",
      compatibleLocalDeclared: false,
    });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), {
      adopted: false,
      reason: "SnapshotLayoutArtifactUnavailable",
    });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("article-sized exact font evidence loads by face and shares one layout snapshot", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { documentObject, root, measuredProbeStyles } = fixture({
      entrySource: "font-contract-v1",
      paragraphSelector: "p",
      entryCount: 40,
    });

    let fontLoads = 0;
    documentObject.fonts.load = async (): Promise<Record<string, never>[]> => {
      fontLoads += 1;
      return [{}];
    };
    let maximumAttachedProbes = 0;
    const createElement = documentObject.createElement;
    documentObject.createElement = (tagName: string): FakeElement => {
      const element = createElement(tagName);
      const getBoundingClientRect = element.getBoundingClientRect.bind(element);
      element.getBoundingClientRect = (): FixtureElementRect => {
        maximumAttachedProbes = Math.max(
          maximumAttachedProbes,
          documentObject.body.childNodes.length,
        );
        return getBoundingClientRect();
      };
      return element;
    };

    assert.deepEqual(await validatePrecomputedSnapshotFontContract(root as FakeElementAsHTMLElement), {
      matches: true,
      reason: null,
      paragraphSelector: "p",
      compatibleLocalDeclared: false,
    });
    assert.equal(fontLoads, 1);
    assert.equal(maximumAttachedProbes, 40);
    assert.equal(measuredProbeStyles.length, 40);
    assert.equal(documentObject.body.childNodes.length, 0);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("one host typography variant cannot poison a sibling runtime font replay", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  try {
    const { documentObject, root } = fixture({
      entrySource: "font-contract-v1",
      paragraphSelector: "p",
    });
    const halfWidthParagraph = documentObject.createElement("p");
    halfWidthParagraph.textContent = "使用半宽字形的宿主段落";
    root.appendChild(halfWidthParagraph);
    globalThis.getComputedStyle = (element: Element | null, pseudo?: string | null): CSSStyleDeclaration => {
      const fakeElement = element as FakeElementAsElement | null;
      return fixtureComputedStyle(
        fakeElement,
        pseudo,
        fakeElement === halfWidthParagraph
          ? {
              fontFeatureSettings: '"hwid" 1',
              fontVariantEastAsian: "proportional-width",
            }
          : {},
      );
    };

    assert.deepEqual(await validatePrecomputedSnapshotFontContract(root as FakeElementAsHTMLElement), {
      matches: true,
      reason: null,
      paragraphSelector: "p",
      compatibleLocalDeclared: false,
    });
    assert.equal(root.getAttribute("data-tiqian-snapshot-typography-issue"), null);
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), {
      adopted: false,
      reason: "SnapshotLayoutArtifactUnavailable",
    });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("shared prepared DOM validator reports the same vertical gate used for SSR adoption", () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { paragraph, entry } = fixture({ sentinelTop: 20.1 });
    while (paragraph.firstChild) paragraph.removeChild(paragraph.firstChild);
    for (const child of entry.childNodes) paragraph.appendChild(child.cloneNode(true));
    paragraph.setAttribute("data-tq-canonical-plain", "true");
    assert.equal(
      renderedPreparedParagraphIssue(paragraph as FakeElementAsElement, 360),
      "RenderedPreparedParagraphLineVerticalMismatch:0",
    );
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("shared prepared DOM validator accepts the isolated engine hyphen contract", () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { paragraph, entry } = fixture();
    const rendered = entry.querySelector("[data-tq-advance]");
    rendered!.setAttribute("data-tq-advance", "18");
    rendered!.width = 18;
    const sentinel = entry.querySelector("[data-tq-line-end-sentinel]");
    entry.removeChild(sentinel!);
    const hyphen = asFakeElement(paragraph.ownerDocument!.createElement("span"));
    hyphen.setAttribute("data-tq-advance", "18");
    hyphen.setAttribute("data-tq-geometry", "true");
    hyphen.setAttribute("data-tq-engine-hyphen", "true");
    hyphen.setAttribute("data-tq-x", "18");
    hyphen.textContent = "-";
    hyphen.left = 18;
    hyphen.top = 8;
    hyphen.width = 18;
    entry.append(hyphen, sentinel!);
    while (paragraph.firstChild) paragraph.removeChild(paragraph.firstChild);
    for (const child of entry.childNodes) paragraph.appendChild(child.cloneNode(true));
    paragraph.setAttribute("data-tq-canonical-plain", "true");
    assert.equal(renderedPreparedParagraphIssue(paragraph as FakeElementAsElement, 360), null);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("shared prepared DOM validator verifies dash-face font family against computed style", () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = (element: Element | null, pseudo?: string | null): CSSStyleDeclaration => {
    const fakeElement = element as FakeElementAsElement | null;
    const base = fixtureComputedStyle(fakeElement, pseudo);
    if (fakeElement?.hasAttribute("data-tq-dash-strategy")) {
      const dashFaceStyle: CSSStyleDeclaration = {
        ...base,
        fontFamily: "'fixture cjk', sans-serif",
      };
      return dashFaceStyle;
    }
    return base;
  };
  try {
    const { paragraph, entry } = fixture({ renderFontProjection: true });
    const rendered = entry.querySelector("[data-tq-advance]");
    rendered!.setAttribute("data-tq-dash-strategy", "Compose");
    rendered!.setAttribute("data-tq-dash-font-family", "Fixture CJK");
    while (paragraph.firstChild) paragraph.removeChild(paragraph.firstChild);
    for (const child of entry.childNodes) paragraph.appendChild(child.cloneNode(true));
    paragraph.setAttribute("data-tq-canonical-plain", "true");
    assert.equal(renderedPreparedParagraphIssue(paragraph as FakeElementAsElement, 360), null);

    const dashElement = paragraph.querySelector("[data-tq-dash-font-family]");
    dashElement!.setAttribute("data-tq-dash-font-family", "Other CJK");
    const issue = renderedPreparedParagraphIssue(paragraph as FakeElementAsElement, 360);
    assert.ok(
      issue?.startsWith("RenderedPreparedParagraphDashFaceMismatch:0;expected="),
      `unexpected issue: ${issue}`,
    );
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("shared prepared DOM validator compares vertical geometry across inline fragments", () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { paragraph, entry } = fixture({ shapingBoundary: true });
    const boundary = entry.querySelector("[data-tq-shaping-boundary]");
    boundary!.top = 0;
    boundary!.setAttribute("data-tq-advance", "18");
    boundary!.width = 18;
    const sentinel = entry.querySelector("[data-tq-line-end-sentinel]");
    entry.removeChild(sentinel!);
    const firstInline = asFakeElement(paragraph.ownerDocument!.createElement("span"));
    firstInline.setAttribute("data-tq-advance", "9");
    firstInline.setAttribute("data-tq-geometry", "true");
    firstInline.setAttribute("data-tq-x", "18");
    firstInline.textContent = " ";
    firstInline.left = 18;
    firstInline.top = 0;
    firstInline.width = 9;
    const secondInline = asFakeElement(paragraph.ownerDocument!.createElement("span"));
    secondInline.setAttribute("data-tq-advance", "9");
    secondInline.setAttribute("data-tq-geometry", "true");
    secondInline.setAttribute("data-tq-x", "27");
    secondInline.textContent = " ";
    secondInline.left = 27;
    secondInline.top = 0;
    secondInline.width = 9;
    entry.append(firstInline, secondInline, sentinel!);
    while (paragraph.firstChild) paragraph.removeChild(paragraph.firstChild);
    for (const child of entry.childNodes) paragraph.appendChild(child.cloneNode(true));
    paragraph.setAttribute("data-tq-canonical-plain", "true");
    assert.equal(renderedPreparedParagraphIssue(paragraph as FakeElementAsElement, 360), null);

    paragraph.querySelectorAll("[data-tq-advance]")[2].top = 2;
    assert.match(
      renderedPreparedParagraphIssue(paragraph as FakeElementAsElement, 360)!,
      /^RenderedPreparedParagraphLineAdvanceMismatch:0;contributor-top;/u,
    );
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("shaping boundaries may carry engine-owned letter spacing when their advance matches", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = (element: Element | null, pseudo?: string | null): CSSStyleDeclaration => {
    const fakeElement = element as FakeElementAsElement | null;
    return fixtureComputedStyle(
      fakeElement,
      pseudo,
      fakeElement?.hasAttribute("data-tq-shaping-boundary")
        ? { letterSpacing: "0.75px" }
        : {},
    );
  };
  try {
    const { root } = fixture({ shapingBoundary: true });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), { adopted: true, count: 1 });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("shared prepared DOM validator tolerates compatible-local subpixel segment drift", () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { paragraph, entry } = fixture({ segmentWidth: 36.6 });
    while (paragraph.firstChild) paragraph.removeChild(paragraph.firstChild);
    for (const child of entry.childNodes) paragraph.appendChild(child.cloneNode(true));
    paragraph.setAttribute("data-tq-canonical-plain", "true");
    assert.equal(renderedPreparedParagraphIssue(paragraph as FakeElementAsElement, 360), null);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("shared prepared DOM validator allows one browser quantization step beyond the probe tolerance", () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { paragraph, entry } = fixture({
      localSource: true,
      segmentLeft: 0.765625,
      lineEnd: 36.765625,
    });
    while (paragraph.firstChild) paragraph.removeChild(paragraph.firstChild);
    for (const child of entry.childNodes) paragraph.appendChild(child.cloneNode(true));
    paragraph.setAttribute("data-tq-canonical-plain", "true");
    assert.equal(renderedPreparedParagraphIssue(paragraph as FakeElementAsElement, 360), null);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("strict snapshot adoption preserves and restores the original SSR node identity", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph, originalText } = fixture();
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, { adopted: true, count: 1 });
    assert.equal(isPrecomputedSnapshotAdopted(root as FakeElementAsHTMLElement), true);
    assert.equal(root.dataset.tiqianSnapshotFontPolicy, "url-only");
    assert.equal(root.getAttribute("data-tiqian-enhanced-count"), "1");
    assert.equal(root.getAttribute("data-tiqian-snapshot-count"), "1");
    assert.equal(paragraph.getAttribute("data-tq-rendered"), "true");
    assert.equal(paragraph.getAttribute("data-tq-canonical-source"), "true");
    assert.equal(paragraph.getAttribute("data-tq-snapshot-prepared-dom"), "true");
    assert.notStrictEqual(paragraph.firstChild, originalText);

    const preparedNode = paragraph.firstChild;
    assert.equal(detachPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root)), true);
    assert.equal(isPrecomputedSnapshotAdopted(root as FakeElementAsHTMLElement), true);
    assert.strictEqual(paragraph.firstChild, preparedNode);

    assert.equal(restorePrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root)), true);
    assert.equal(isPrecomputedSnapshotAdopted(root as FakeElementAsHTMLElement), false);
    assert.strictEqual(paragraph.firstChild, originalText);
    assert.equal(paragraph.getAttribute("data-tq-rendered"), null);
    assert.equal(paragraph.getAttribute("data-tq-canonical-source"), null);
    assert.equal(paragraph.getAttribute("data-tq-snapshot-prepared-dom"), null);
    assert.equal(root.dataset.tiqianSnapshotFontPolicy, undefined);
    assert.equal(root.getAttribute("data-tiqian-snapshot-count"), null);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("server-rendered compact snapshot adopts without replacing its first-paint DOM", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { documentObject, root, paragraph, entry } = fixture();
    while (paragraph.firstChild) paragraph.removeChild(paragraph.firstChild);
    for (const child of entry.childNodes) paragraph.appendChild(child.cloneNode(true));
    paragraph.setAttribute("data-tq-rendered", "true");
    paragraph.setAttribute("data-tq-canonical-plain", "true");
    paragraph.setAttribute("data-tq-canonical-source", "true");
    root.setAttribute("data-tq-ssr-snapshot", "tq-page");
    root.setAttribute("data-tiqian-snapshot-render-font", "true");
    attachServerSource(documentObject);
    const template = documentObject.elements.get("tq-page")!;
    const manifestScript = template.content!.querySelector("[data-tq-snapshot-manifest]");
    const manifest = JSON.parse(manifestScript!.textContent!);
    manifest.entrySource = "server-dom-v1";
    manifestScript!.textContent = JSON.stringify(manifest);
    template.content!.removeChild(entry);
    const firstPaintNode = paragraph.firstChild;

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), { adopted: true, count: 1 });
    assert.strictEqual(paragraph.firstChild, firstPaintNode);
    assert.equal(root.dataset.tiqianSnapshot, "maximum-measure");

    assert.equal(restorePrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root)), true);
    assert.equal(paragraph.textContent, "中国");
    assert.equal(paragraph.firstChild!.nodeType, 3);
    assert.equal(paragraph.getAttribute("data-tq-rendered"), null);
    assert.equal(paragraph.getAttribute("data-tq-canonical-source"), null);
    assert.equal(root.getAttribute("data-tq-ssr-snapshot"), null);
    assert.equal(root.getAttribute("data-tiqian-snapshot-render-font"), null);

    paragraph.width = 360;
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), { adopted: true, count: 1 });
    assert.equal(paragraph.firstChild!.nodeType, 1);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("a direct SSR width miss restores native source before runtime fallback", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { documentObject, root, paragraph, entry } = fixture();
    while (paragraph.firstChild) paragraph.removeChild(paragraph.firstChild);
    for (const child of entry.childNodes) paragraph.appendChild(child.cloneNode(true));
    paragraph.setAttribute("data-tq-rendered", "true");
    paragraph.setAttribute("data-tq-canonical-source", "true");
    paragraph.width = 240;
    root.setAttribute("data-tq-ssr-snapshot", "tq-page");
    root.setAttribute("data-tiqian-snapshot-render-font", "true");
    attachServerSource(documentObject);
    const template = documentObject.elements.get("tq-page")!;
    const manifestScript = template.content!.querySelector("[data-tq-snapshot-manifest]");
    const manifest = JSON.parse(manifestScript!.textContent!);
    manifest.entrySource = "server-dom-v1";
    manifestScript!.textContent = JSON.stringify(manifest);
    template.content!.removeChild(entry);

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), {
      adopted: false,
      reason: "SnapshotWidthMismatch",
    });
    assert.equal(paragraph.firstChild!.nodeType, 3);
    assert.equal(paragraph.textContent, "中国");
    assert.equal(paragraph.getAttribute("data-tq-rendered"), null);
    assert.equal(paragraph.getAttribute("data-tq-canonical-source"), null);
    assert.equal(root.getAttribute("data-tq-ssr-snapshot"), null);
    assert.equal(root.getAttribute("data-tiqian-snapshot-render-font"), null);

    paragraph.width = 360;
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), { adopted: true, count: 1 });
    assert.equal(paragraph.firstChild!.nodeType, 1);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("translation-only ancestor matrices preserve the exact snapshot geometry contract", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  try {
    for (const transform of [
      "matrix(1, 0, 0, 1, 12.5, -8)",
      "matrix3d(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 12.5, -8, 0, 1)",
    ]) {
      const { root, paragraph, originalText } = fixture();
      globalThis.getComputedStyle = (element: Element | null, pseudo?: string | null): CSSStyleDeclaration => {
        const fakeElement = element as FakeElementAsElement | null;
        return fixtureComputedStyle(
          fakeElement,
          pseudo,
          fakeElement === root ? { transform } : {},
        );
      };

      assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), { adopted: true, count: 1 });
      assert.notStrictEqual(paragraph.firstChild, originalText);
    }
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("non-translation ancestor transforms remain outside the exact snapshot contract", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  try {
    const ancestorStyles: FixtureComputedStyleOverrides[] = [
      { transform: "matrix(1.1, 0, 0, 1.1, 12, 8)" },
      { transform: "matrix(0, 1, -1, 0, 12, 8)" },
      { transform: "matrix(1, 0.2, 0, 1, 12, 8)" },
      { transform: "matrix3d(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, -0.001, 12, 8, 0, 1)" },
      { transform: "matrix3d(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 12, 8, 5, 1)" },
      { transform: "translateY(0px)" },
      { transform: "matrix(1, 0, 0, 1, NaN, 0)" },
      { scale: "1.1" },
    ];
    for (const ancestorStyle of ancestorStyles) {
      const { root, paragraph, originalText } = fixture();
      globalThis.getComputedStyle = (element: Element | null, pseudo?: string | null): CSSStyleDeclaration => {
        const fakeElement = element as FakeElementAsElement | null;
        return fixtureComputedStyle(
          fakeElement,
          pseudo,
          fakeElement === root ? ancestorStyle : {},
        );
      };

      assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), {
        adopted: false,
        reason: "SnapshotTypographyMismatch",
      });
      assert.strictEqual(paragraph.firstChild, originalText);
    }
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("a translation on the paragraph itself remains outside the exact snapshot contract", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  try {
    const { root, paragraph, originalText } = fixture();
    globalThis.getComputedStyle = asGetComputedStyle((element: FakeElement | null, pseudo?: string | null): CSSStyleDeclaration => fixtureComputedStyle(
      element,
      pseudo,
      element === paragraph ? { transform: "matrix(1, 0, 0, 1, 12, 8)" } : {},
    ));

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), {
      adopted: false,
      reason: "SnapshotTypographyMismatch",
    });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("duplicate manifest keys cannot corrupt source restoration", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { documentObject, root, paragraph, originalText } = fixture();
    const secondParagraph = documentObject.createElement("p");
    secondParagraph.setAttribute("data-tq-snapshot-key", "p-2");
    secondParagraph.width = 360;
    secondParagraph.height = 27;
    const secondText = new FakeText("中国");
    secondParagraph.appendChild(secondText);
    root.appendChild(secondParagraph);

    const template = documentObject.getElementById("tq-page");
    const manifestScript = template!.content!.querySelector("[data-tq-snapshot-manifest]");
    const manifest = JSON.parse(manifestScript!.textContent!);
    manifest.entries.push({ ...manifest.entries[0] });
    manifestScript!.textContent = JSON.stringify(manifest);

    assert.equal(precomputedSnapshotMaximumMeasureMatches(root as FakeElementAsHTMLElement), false);
    assert.deepEqual(await validatePrecomputedSnapshotFontContract(root as FakeElementAsHTMLElement), {
      matches: false,
      reason: "SnapshotManifestEntryKeyInvalid",
    });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), {
      adopted: false,
      reason: "SnapshotManifestEntryKeyInvalid",
    });
    assert.strictEqual(paragraph.firstChild, originalText);
    assert.strictEqual(secondParagraph.firstChild, secondText);
    assert.equal(isPrecomputedSnapshotAdopted(root as FakeElementAsHTMLElement), false);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("maximum-measure preflight is non-destructive and follows live paragraph width", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph, originalText } = fixture();
    // The preflight answers from the transport's verified cache, so the
    // fixture's table loads once before the synchronous reads.
    assert.notEqual(await snapshotTablesForRoot(root as FakeElementAsElement), null);
    assert.equal(precomputedSnapshotMaximumMeasureMatches(root as FakeElementAsHTMLElement), true);
    assert.strictEqual(paragraph.firstChild, originalText);

    paragraph.width = 368;
    assert.equal(precomputedSnapshotMaximumMeasureMatches(root as FakeElementAsHTMLElement), true);
    assert.strictEqual(paragraph.firstChild, originalText);

    paragraph.width = 378;
    assert.equal(precomputedSnapshotMaximumMeasureMatches(root as FakeElementAsHTMLElement), false);
    assert.strictEqual(paragraph.firstChild, originalText);

    paragraph.width = 240;
    assert.equal(precomputedSnapshotMaximumMeasureMatches(root as FakeElementAsHTMLElement), false);
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("snapshots adopt through the snapshot table reference", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph } = fixture();

    // The table is not in the sync cache yet, so the preflight reads a miss
    // without touching the DOM.
    assert.equal(precomputedSnapshotMaximumMeasureMatches(root as FakeElementAsHTMLElement), false);
    assert.equal(paragraph.getAttribute("data-tq-rendered"), null);

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), { adopted: true, count: 1 });
    assert.equal(paragraph.getAttribute("data-tq-rendered"), "true");

    // After adoption the verified table sits in the transport cache and the
    // synchronous preflight answers from it.
    assert.equal(precomputedSnapshotMaximumMeasureMatches(root as FakeElementAsHTMLElement), true);

    // A manifest pinning a different digest reads the cached reference as a
    // mismatch and misses without adopting anything.
    const mismatch = fixture({ snapshotTablesSha: "0".repeat(64) });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(mismatch.root as FakeElementAsHTMLElement, contextFor(mismatch.root), mismatch.root.ownerDocument!), {
      adopted: false,
      reason: "SnapshotTablesMissing",
    });
    assert.equal(isPrecomputedSnapshotAdopted(mismatch.root as FakeElementAsHTMLElement), false);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("snapshot adoption accepts a wider container in the same line-length grid cell", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph } = fixture();
    paragraph.width = 368;

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), { adopted: true, count: 1 });
    assert.equal(root.dataset.tiqianSnapshot, "maximum-measure");
    assert.equal(await adoptedPrecomputedSnapshotLiveIssue(root as FakeElementAsHTMLElement), null);

    paragraph.width = 378;
    assert.equal(await adoptedPrecomputedSnapshotLiveIssue(root as FakeElementAsHTMLElement), "SnapshotWidthMismatch");
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("snapshot adoption preserves native Text nodes for ordinary prepared prose", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph } = fixture({ nativeText: true });
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);

    assert.deepEqual(adopted, { adopted: true, count: 1 });
    assert.equal(paragraph.childNodes[1].nodeType, 3);
    assert.equal(paragraph.childNodes[1].textContent, "中国");
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("snapshot adoption accepts sparse inline geometry without an atomic shaping boundary", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root } = fixture({ shapingBoundary: false });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), { adopted: true, count: 1 });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("prepared geometry inherits shaping styles from its nearest semantic source wrapper", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = asGetComputedStyle((element: FakeElement | null, pseudo?: string | null): CSSStyleDeclaration => fixtureComputedStyle(
    element,
    pseudo,
    element?.closest?.("[data-tq-source-semantic]") ? { fontWeight: "700" } : {},
  ));
  try {
    const { root } = fixture({ semanticGeometry: true });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), { adopted: true, count: 1 });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("prepared geometry may carry an artifact-owned exact render-font projection", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = asGetComputedStyle((element: FakeElement | null, pseudo?: string | null): CSSStyleDeclaration => fixtureComputedStyle(
    element,
    pseudo,
    element?.hasAttribute?.("data-tq-render-font-projection")
      ? { fontFamily: '"Tiqian Exact Inline"' }
      : element?.closest?.("[data-tq-source-semantic]")
        ? { fontFamily: '"Host Inline"' }
        : {},
  ));
  try {
    const { root } = fixture({ semanticGeometry: true, renderFontProjection: true });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), { adopted: true, count: 1 });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("prepared geometry still rejects shaping styles that differ from its semantic source wrapper", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = asGetComputedStyle((element: FakeElement | null, pseudo?: string | null): CSSStyleDeclaration => fixtureComputedStyle(
    element,
    pseudo,
    element?.hasAttribute?.("data-tq-advance")
      ? { fontWeight: "600" }
      : element?.closest?.("[data-tq-source-semantic]")
        ? { fontWeight: "700" }
        : {},
  ));
  try {
    const { root, paragraph, originalText } = fixture({
      semanticGeometry: true,
      shapingBoundary: false,
    });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), {
      adopted: false,
      reason: "SnapshotAdoptionFailed:RenderedSnapshotGeometryMismatch:Geometry:fontWeight",
    });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("snapshot adoption requires the engine-owned punctuation feature lock", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = asGetComputedStyle((element: FakeElement | null, pseudo?: string | null): CSSStyleDeclaration => fixtureComputedStyle(
    element,
    pseudo,
    element?.closest?.("[data-tq-canonical-source]")
      ? { fontFeatureSettings: "normal" }
      : {},
  ));
  try {
    const { root, paragraph, originalText } = fixture();
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), {
      adopted: false,
      reason: "SnapshotAdoptionFailed:RenderedSnapshotHostContractMismatch:fontFeatureSettings",
    });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("maximum-measure snapshot atomically replaces and restores canonical runtime DOM", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { documentObject, root, paragraph, originalText } = fixture();
    paragraph.removeChild(originalText);
    paragraph.setAttribute("data-tq-rendered", "true");
    paragraph.setAttribute("data-tq-canonical-source", "true");
    paragraph.setAttribute("lang", "zh-Hans");
    const runtimeMarker = documentObject.createElement("span");
    runtimeMarker.setAttribute("data-tq-copy-ignore", "true");
    runtimeMarker.textContent = "paint-only";
    const runtimeRun = documentObject.createElement("span");
    runtimeRun.setAttribute("data-tq-shaping-boundary", "");
    runtimeRun.textContent = "中国";
    paragraph.append(runtimeMarker, runtimeRun);

    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, { adopted: true, count: 1 });
    assert.notStrictEqual(paragraph.firstChild, runtimeMarker);
    assert.equal(originalText.parentNode, null, "re-adoption must not expose retained SSR source");

    assert.equal(restorePrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root)), true);
    assert.strictEqual(paragraph.firstChild, runtimeMarker);
    assert.strictEqual(paragraph.childNodes[1], runtimeRun);
    assert.equal(paragraph.getAttribute("data-tq-rendered"), "true");
    assert.equal(paragraph.getAttribute("data-tq-canonical-source"), "true");
    assert.equal(originalText.parentNode, null);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("a same-face local() source can satisfy the compatible-local contract", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph, originalText } = fixture({ localSource: true });
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, { adopted: true, count: 1 });
    assert.notStrictEqual(paragraph.firstChild, originalText);
    assert.equal(isPrecomputedSnapshotAdopted(root as FakeElementAsHTMLElement), true);
    assert.equal(root.dataset.tiqianSnapshotFontPolicy, "compatible-local");
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("a local() token outside the build face name table is rejected", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph, originalText } = fixture({ localSource: true, localName: "Arial" });
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, { adopted: false, reason: "FontFaceContractMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("a compatible local face with a different probe advance is rejected", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph, originalText } = fixture({ localSource: true, probeWidth: 40 });
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, { adopted: false, reason: "FontAdvanceProbeMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("an optional render face cannot promise exact direct first paint", async () => {
  const setup = fixture({ fontDisplay: "optional", entrySource: "server-dom-v1" });
  globalThis.document = asDocument(setup.documentObject);
  globalThis.getComputedStyle = asGetComputedStyle((element: FakeElement | null, pseudo?: string | null): CSSStyleDeclaration => fixtureComputedStyle(element, pseudo));
  try {
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(setup.root as FakeElementAsHTMLElement, contextFor(setup.root), setup.root.ownerDocument!), {
      adopted: false,
      reason: "FontFaceContractMismatch",
    });
  } finally {
    delete (globalThis as Record<string, unknown>).document;
    delete (globalThis as Record<string, unknown>).getComputedStyle;
  }
});

test("an inert snapshot may adopt a swap face only after its exact probe loads", async () => {
  const setup = fixture({ fontDisplay: "swap" });
  globalThis.document = asDocument(setup.documentObject);
  globalThis.getComputedStyle = asGetComputedStyle((element: FakeElement | null, pseudo?: string | null): CSSStyleDeclaration => fixtureComputedStyle(element, pseudo));
  try {
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(setup.root as FakeElementAsHTMLElement, contextFor(setup.root), setup.root.ownerDocument!), { adopted: true, count: 1 });
  } finally {
    delete (globalThis as Record<string, unknown>).document;
    delete (globalThis as Record<string, unknown>).getComputedStyle;
  }
});

test("post-adoption segment advance mismatch restores the original paragraph", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph, originalText } = fixture({ localSource: true, segmentWidth: 38 });
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, {
      adopted: false,
      reason: "SnapshotAdoptionFailed:RenderedSnapshotSegmentAdvanceMismatch:0;expected=36;actual=38;text=\"中国\";letterSpacing=normal;features=none;source=same",
    });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("post-adoption line pen mismatch restores the original paragraph", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph, originalText } = fixture({ localSource: true, lineEnd: 38 });
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, {
      adopted: false,
      reason: "SnapshotAdoptionFailed:RenderedSnapshotLineAdvanceMismatch:0;sentinel;expectedFlow=36;expectedCore=36;actual=38;contentWidth=360",
    });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("an exact engine-owned line pen may protrude beyond the raw content box", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root } = fixture({
      lineEnd: 36.015625,
      paragraphWidth: 35,
      maximumWidth: 35,
    });

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), { adopted: true, count: 1 });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("post-adoption baseline drift restores the original paragraph", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph, originalText } = fixture({ sentinelTop: 20.1 });
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, {
      adopted: false,
      reason: "SnapshotAdoptionFailed:RenderedSnapshotLineVerticalMismatch:0",
    });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("post-adoption paragraph height drift restores the original paragraph", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph, originalText } = fixture({ paragraphHeight: 28 });
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, {
      adopted: false,
      reason: "SnapshotAdoptionFailed:RenderedSnapshotLineVerticalMismatch:paragraph",
    });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("post-adoption prefix position drift cannot cancel out at the line end", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph, originalText } = fixture({
      localSource: true,
      segmentLeft: 1,
      lineEnd: 36,
    });
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, {
      adopted: false,
      reason: "SnapshotAdoptionFailed:RenderedSnapshotLineAdvanceMismatch:0;position;expected=0;actual=1",
    });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("an ambiguous sibling face prevents exact-source adoption", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph, originalText } = fixture({ unsafeSibling: true });
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, { adopted: false, reason: "FontFaceContractMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("an overlapping unicode-range sibling prevents exact-source adoption", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { documentObject, root, paragraph, originalText } = fixture();
    const sheet = documentObject.styleSheets[0];
    sheet.cssRules.push({
      type: 5,
      style: styleDeclaration({
        "font-family": "\"Fixture CJK\"",
        "font-style": "normal",
        "font-weight": "400",
        "unicode-range": "U+4E2D",
        src: 'local("Fixture CJK"),url("/assets/other-feedface.woff2")',
      }),
      parentStyleSheet: { href: sheet.href },
    });
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, { adopted: false, reason: "FontFaceContractMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("font-face metric override descriptors cannot satisfy exact evidence", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { documentObject, root, paragraph, originalText } = fixture();
    const rule = documentObject.styleSheets[0].cssRules[0];
    const originalStyle = rule.style;
    rule.style = styleDeclaration({
      "font-family": originalStyle.getPropertyValue("font-family"),
      "font-style": originalStyle.getPropertyValue("font-style"),
      "font-weight": originalStyle.getPropertyValue("font-weight"),
      "unicode-range": originalStyle.getPropertyValue("unicode-range"),
      src: originalStyle.getPropertyValue("src"),
      "size-adjust": "110%",
    });
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, { adopted: false, reason: "FontFaceContractMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("non-default shaping CSS misses before DOM adoption", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = asGetComputedStyle((element: FakeElement | null, pseudo?: string | null): CSSStyleDeclaration => fixtureComputedStyle(element, pseudo, {
    wordSpacing: "2px",
    fontVariantLigatures: "none",
  }));
  try {
    const { root, paragraph, originalText } = fixture();
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, { adopted: false, reason: "SnapshotTypographyMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("lining numeric typography validates the matching lnum font probe", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = asGetComputedStyle((element: FakeElement | null, pseudo?: string | null): CSSStyleDeclaration => fixtureComputedStyle(element, pseudo, {
    fontVariantNumeric: "lining-nums",
  }));
  try {
    const { root, paragraph, originalText, measuredProbeStyles } = fixture({
      fontVariantNumeric: "lining-nums",
      probeFeatures: ["lnum"],
    });

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!), { adopted: true, count: 1 });
    assert.notStrictEqual(paragraph.firstChild, originalText);
    assert.ok(measuredProbeStyles.some((style) =>
      style.includes("font-variant-numeric:lining-nums!important")));
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("generated pseudo content is outside the plain-text snapshot contract", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = asGetComputedStyle((element: FakeElement | null, pseudo?: string | null): CSSStyleDeclaration => fixtureComputedStyle(element, pseudo, {
    content: pseudo === "::before" ? '"※"' : "none",
  }));
  try {
    const { root, paragraph, originalText } = fixture();
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, { adopted: false, reason: "SnapshotTypographyMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("prepared pseudo isolation avoids per-node pseudo probes after adoption", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = asGetComputedStyle((element: FakeElement | null, pseudo?: string | null): CSSStyleDeclaration => fixtureComputedStyle(element, pseudo, {
    content: element?.hasAttribute?.("data-tq-geometry") && pseudo === "::before" ? '"※"' : "none",
  }));
  try {
    const { root, paragraph, originalText } = fixture();
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, { adopted: true, count: 1 });
    assert.notStrictEqual(paragraph.firstChild, originalText);
    assert.equal(isPrecomputedSnapshotAdopted(root as FakeElementAsHTMLElement), true);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("horizontal padding cannot masquerade as the prepared content width", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = asGetComputedStyle((element: FakeElement | null, pseudo?: string | null): CSSStyleDeclaration => fixtureComputedStyle(element, pseudo, {
    paddingLeft: "20px",
    paddingRight: "20px",
    borderLeftWidth: "0px",
    borderRightWidth: "0px",
  }));
  try {
    const { root, paragraph, originalText } = fixture();
    paragraph.width = 400;
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, { adopted: false, reason: "SnapshotTypographyMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("typography manifest tampering misses before DOM adoption", async () => {
  const { root, paragraph, originalText } = fixture({ typographyDigest: "c".repeat(64) });
  const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
  assert.deepEqual(adopted, { adopted: false, reason: "SnapshotTypographyDigestMismatch" });
  assert.strictEqual(paragraph.firstChild, originalText);
});

test("rendered snapshot artifact tampering misses before DOM adoption", async () => {
  const { documentObject, root, paragraph, originalText } = fixture();
  const templateElement = documentObject.getElementById("tq-page");
  assert.ok(templateElement != null);
  const entryElement = templateElement.content!.querySelector("[data-tq-entry]");
  assert.ok(entryElement != null);
  entryElement.textContent = "错误";
  const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
  assert.deepEqual(adopted, { adopted: false, reason: "SnapshotArtifactDigestMismatch" });
  assert.strictEqual(paragraph.firstChild, originalText);
});

test("host text alignment outside the v1 contract misses before DOM adoption", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = asGetComputedStyle((element: FakeElement | null, pseudo?: string | null): CSSStyleDeclaration => fixtureComputedStyle(element, pseudo, {
    textAlign: "center",
  }));
  try {
    const { root, paragraph, originalText } = fixture();
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!);
    assert.deepEqual(adopted, { adopted: false, reason: "SnapshotTypographyMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("a superseded async validation never mutates the live paragraph", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { documentObject, root, paragraph, originalText } = fixture();
    let current = true;
    documentObject.fonts.load = async (): Promise<Record<string, never>[]> => {
      current = false;
      return [{}];
    };
    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!, () => current);
    assert.deepEqual(adopted, { adopted: false, reason: "superseded" });
    assert.strictEqual(paragraph.firstChild, originalText);
    assert.equal(isPrecomputedSnapshotAdopted(root as FakeElementAsHTMLElement), false);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("a superseded post-adoption proof rolls back only its provisional DOM", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  const previousPerformance = globalThis.performance;
  const previousScheduler = (globalThis as Record<string, unknown>).scheduler;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    const { root, paragraph, originalText } = fixture();
    let current = true;
    let clock = 0;
    Object.defineProperty(globalThis, "performance", {
      configurable: true,
      value: { now: (): number => (clock += 10) },
    });
    (globalThis as Record<string, unknown>).scheduler = {
      async yield(): Promise<void> {
        if (paragraph.firstChild !== originalText) current = false;
      },
    };

    const adopted = await tryAdoptPrecomputedSnapshot(root as FakeElementAsHTMLElement, contextFor(root), root.ownerDocument!, () => current);
    assert.deepEqual(adopted, { adopted: false, reason: "superseded" });
    assert.strictEqual(paragraph.firstChild, originalText);
    assert.equal(isPrecomputedSnapshotAdopted(root as FakeElementAsHTMLElement), false);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
    Object.defineProperty(globalThis, "performance", {
      configurable: true,
      value: previousPerformance,
    });
    if (previousScheduler === undefined) delete (globalThis as Record<string, unknown>).scheduler;
    else (globalThis as Record<string, unknown>).scheduler = previousScheduler;
  }
});

interface CssCandidateFace {
  family: string;
  style: string;
  weight: string;
  stretch: string;
  unicodeRanges: Array<[number, number]>;
  urls: string[];
  hasLocalSource: boolean;
  localNames: string[];
  sizeAdjust?: string;
  ascentOverride?: string;
  descentOverride?: string;
  lineGapOverride?: string;
  featureSettings?: string;
  variationSettings?: string;
  languageOverride?: string;
  namedInstance?: string;
  display?: string;
}

test("cssFaceContract produces EmptyCandidateSet when no candidate faces exist", () => {
  const evidence: SnapshotManifestFace = {
    family: "Fixture CJK",
    style: "normal",
    weight: [400, 400],
    unicodeRange: "U+4E00-9FFF",
    publicUrl: "/assets/fixture-deadbeef.woff2",
    sourceSha256: "a".repeat(64),
    sfntSha256: "b".repeat(64),
    faceIndex: 0,
    sourceOrder: 0,
    axes: {},
    localNames: ["Fixture CJK"],
    probe: {
      text: "中国",
      advancePx: 36,
      fontSizePx: 18,
      fontWeight: 400,
      italic: false,
      script: "Hani",
      language: "zh-Hans",
      features: [],
    },
  };
  const doc = asDocument({
    baseURI: "https://example.test/",
    elements: new Map(),
    styleSheets: [],
    fonts: { load: async () => [{}] },
    createDocumentFragment: () => new FakeFragment(),
    createElement: (tagName: string) => new FakeElement(tagName),
    createRange: () => ({
      selectNodeContents: () => {},
      getBoundingClientRect: () => ({ width: 0 }),
    }),
    getElementById: () => null,
    body: new FakeElement("body"),
  });
  const result = cssFaceContract(evidence, [], doc);
  assert.equal(result.matches, false);
  assert.deepEqual(result.detail, { kind: "EmptyCandidateSet" });
});

test("cssFaceContract produces FieldMismatch with ordered firstField (family -> style -> weight -> unicode-range -> src)", () => {
  const evidence: SnapshotManifestFace = {
    family: "Fixture CJK",
    style: "normal",
    weight: [400, 400],
    unicodeRange: "U+4E00-9FFF",
    publicUrl: "/assets/fixture-deadbeef.woff2",
    sourceSha256: "a".repeat(64),
    sfntSha256: "b".repeat(64),
    faceIndex: 0,
    sourceOrder: 0,
    axes: {},
    localNames: ["Fixture CJK"],
    probe: {
      text: "中国",
      advancePx: 36,
      fontSizePx: 18,
      fontWeight: 400,
      italic: false,
      script: "Hani",
      language: "zh-Hans",
      features: [],
    },
  };
  const doc = asDocument({
    baseURI: "https://example.test/",
    elements: new Map(),
    styleSheets: [],
    fonts: { load: async () => [{}] },
    createDocumentFragment: () => new FakeFragment(),
    createElement: (tagName: string) => new FakeElement(tagName),
    createRange: () => ({
      selectNodeContents: () => {},
      getBoundingClientRect: () => ({ width: 0 }),
    }),
    getElementById: () => null,
    body: new FakeElement("body"),
  });

  const baseFace = {
    stretch: "normal",
    hasLocalSource: false,
    localNames: [],
    sizeAdjust: "",
    ascentOverride: "",
    descentOverride: "",
    lineGapOverride: "",
    featureSettings: "",
    variationSettings: "",
    languageOverride: "",
    namedInstance: "",
    display: "",
  };
  const cjkRange: [number, number][] = [[0x4e00, 0x9fff]];
  const asciiRange: [number, number][] = [[0x0020, 0x007f]];

  // 1. Family mismatch
  const familyMismatchFace = {
    family: "Other Font",
    style: "normal",
    weight: "400",
    unicodeRanges: cjkRange,
    urls: ["https://example.test/assets/fixture-deadbeef.woff2"],
    ...baseFace,
  };
  const familyResult = cssFaceContract(evidence, [familyMismatchFace], doc);
  assert.equal(familyResult.matches, false);
  assert.deepEqual(familyResult.detail, {
    kind: "FieldMismatch",
    expectedFaces: 1,
    actualFaces: 1,
    firstField: "family",
  });

  // 2. Family matches but style mismatches (proves ordering before weight/unicode/src)
  const styleMismatchFace = {
    family: "Fixture CJK",
    style: "italic",
    weight: "400",
    unicodeRanges: cjkRange,
    urls: ["https://example.test/assets/fixture-deadbeef.woff2"],
    ...baseFace,
  };
  const styleResult = cssFaceContract(evidence, [styleMismatchFace], doc);
  assert.equal(styleResult.matches, false);
  assert.deepEqual(styleResult.detail, {
    kind: "FieldMismatch",
    expectedFaces: 1,
    actualFaces: 1,
    firstField: "style",
  });

  // 3. Family and style match, weight mismatches
  const weightMismatchFace = {
    family: "Fixture CJK",
    style: "normal",
    weight: "700",
    unicodeRanges: cjkRange,
    urls: ["https://example.test/assets/fixture-deadbeef.woff2"],
    ...baseFace,
  };
  const weightResult = cssFaceContract(evidence, [weightMismatchFace], doc);
  assert.equal(weightResult.matches, false);
  assert.deepEqual(weightResult.detail, {
    kind: "FieldMismatch",
    expectedFaces: 1,
    actualFaces: 1,
    firstField: "weight",
  });

  // 4. Family, style, weight match, unicode-range mismatches
  const unicodeMismatchFace = {
    family: "Fixture CJK",
    style: "normal",
    weight: "400",
    unicodeRanges: asciiRange,
    urls: ["https://example.test/assets/fixture-deadbeef.woff2"],
    ...baseFace,
  };
  const unicodeResult = cssFaceContract(evidence, [unicodeMismatchFace], doc);
  assert.equal(unicodeResult.matches, false);
  assert.deepEqual(unicodeResult.detail, {
    kind: "FieldMismatch",
    expectedFaces: 1,
    actualFaces: 1,
    firstField: "unicode-range",
  });

  // 5. Family, style, weight, unicode-range match, src mismatches
  const srcMismatchFace = {
    family: "Fixture CJK",
    style: "normal",
    weight: "400",
    unicodeRanges: cjkRange,
    urls: ["https://example.test/assets/wrong-font.woff2"],
    ...baseFace,
  };
  const srcResult = cssFaceContract(evidence, [srcMismatchFace], doc);
  assert.equal(srcResult.matches, false);
  assert.deepEqual(srcResult.detail, {
    kind: "FieldMismatch",
    expectedFaces: 1,
    actualFaces: 1,
    firstField: "src",
  });
});

test("snapshot exact font validation carries EmptyCandidateSet and FieldMismatch structured details", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle as FixtureComputedStyleAsHost;
  try {
    // EmptyCandidateSet: stylesheet has no rules
    const emptySetup = fixture();
    emptySetup.documentObject.styleSheets[0].cssRules = [];
    const emptyResult = await validatePrecomputedSnapshotFontContract(emptySetup.root as FakeElementAsHTMLElement);
    assert.deepEqual(emptyResult, {
      matches: false,
      reason: "FontFaceContractMismatch",
      detail: { kind: "EmptyCandidateSet" },
    });

    // FieldMismatch: rule has style mismatch (family matches, style differs)
    const fieldSetup = fixture();
    fieldSetup.documentObject.styleSheets[0].cssRules[0].style = styleDeclaration({
      "font-family": "\"Fixture CJK\"",
      "font-style": "italic",
      "font-weight": "400",
      "font-display": "block",
      "unicode-range": "U+4E00-9FFF",
      src: "url(\"/assets/fixture-deadbeef.woff2\")",
    });
    const fieldResult = await validatePrecomputedSnapshotFontContract(fieldSetup.root as FakeElementAsHTMLElement);
    assert.deepEqual(fieldResult, {
      matches: false,
      reason: "FontFaceContractMismatch",
      detail: {
        kind: "FieldMismatch",
        expectedFaces: 1,
        actualFaces: 1,
        firstField: "style",
      },
    });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});
