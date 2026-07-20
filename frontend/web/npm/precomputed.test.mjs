import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";

import {
  adoptedPrecomputedSnapshotLiveIssue,
  detachPrecomputedSnapshot,
  isPrecomputedSnapshotAdopted,
  precomputedSnapshotMaximumMeasureMatches,
  renderedPreparedParagraphIssue,
  restorePrecomputedSnapshot,
  tryAdoptPrecomputedSnapshot,
  validatePrecomputedExactFontReplayContract,
  validatePrecomputedExactFontReplayLiveContract,
  validatePrecomputedExactFontReplayRuntimeContract,
  validatePrecomputedSnapshotExactFontContract,
} from "./precomputed.js";
import { FONT_REPLAY_REVISION, stableStringify } from "./snapshot-schema.js";

function matchesSelector(element, selector) {
  if (selector === "*") return element.nodeType === 1;
  if (selector === ":is(p, li)[data-tq-snapshot-key]") {
    return ["P", "LI"].includes(element.tagName) && element.hasAttribute("data-tq-snapshot-key");
  }
  if (selector === "tiqian-prose, [data-tiqian-root]") {
    return element.tagName === "TIQIAN-PROSE" || element.hasAttribute("data-tiqian-root");
  }
  const tagMatch = /^([a-z0-9-]+)?(?:\[([^=\]]+)(?:="([^"]*)")?\])?$/iu.exec(selector);
  if (!tagMatch) return false;
  if (tagMatch[1] && element.tagName !== tagMatch[1].toUpperCase()) return false;
  if (!tagMatch[2]) return true;
  if (!element.hasAttribute(tagMatch[2])) return false;
  return tagMatch[3] == null || element.getAttribute(tagMatch[2]) === tagMatch[3];
}

class FakeNode {
  constructor(nodeType) {
    this.nodeType = nodeType;
    this.childNodes = [];
    this.parentNode = null;
    this.parentElement = null;
  }

  get firstChild() {
    return this.childNodes[0] ?? null;
  }

  append(...nodes) {
    for (const node of nodes) this.appendChild(node);
  }

  appendChild(node) {
    if (node.nodeType === 11) {
      while (node.firstChild) this.appendChild(node.firstChild);
      return node;
    }
    if (node.parentNode) node.parentNode.removeChild(node);
    this.childNodes.push(node);
    node.parentNode = this;
    node.parentElement = this.nodeType === 1 ? this : null;
    return node;
  }

  removeChild(node) {
    const index = this.childNodes.indexOf(node);
    if (index < 0) throw new Error("NotAChild");
    this.childNodes.splice(index, 1);
    node.parentNode = null;
    node.parentElement = null;
    return node;
  }

  remove() {
    this.parentNode?.removeChild(this);
  }

  get textContent() {
    return this.childNodes.map((node) => node.textContent).join("");
  }

  set textContent(value) {
    while (this.firstChild) this.removeChild(this.firstChild);
    if (value) this.appendChild(new FakeText(String(value)));
  }

  querySelectorAll(selector) {
    const result = [];
    const visit = (node) => {
      for (const child of node.childNodes) {
        if (child.nodeType === 1 && matchesSelector(child, selector)) result.push(child);
        visit(child);
      }
    };
    visit(this);
    return result;
  }

  querySelector(selector) {
    return this.querySelectorAll(selector)[0] ?? null;
  }
}

class FakeText extends FakeNode {
  constructor(value) {
    super(3);
    this.value = value;
  }

  get textContent() {
    return this.value;
  }

  set textContent(value) {
    this.value = String(value);
  }

  cloneNode() {
    return new FakeText(this.value);
  }
}

class FakeElement extends FakeNode {
  constructor(tagName) {
    super(1);
    this.tagName = tagName.toUpperCase();
    this.attributes = new Map();
    this.dataset = {};
    this.style = { cssText: "" };
    this.ownerDocument = null;
    this.width = 0;
    this.height = 0;
    this.left = 0;
    this.top = 0;
    this._innerText = null;
  }

  setAttribute(name, value) {
    this.attributes.set(name, String(value));
  }

  getAttribute(name) {
    return this.attributes.get(name) ?? null;
  }

  hasAttribute(name) {
    return this.attributes.has(name);
  }

  removeAttribute(name) {
    this.attributes.delete(name);
  }

  get innerText() {
    return this._innerText ?? this.textContent;
  }

  set innerText(value) {
    this._innerText = String(value);
  }

  getBoundingClientRect() {
    if (this._fixtureProbeWidth != null && this.style.cssText.includes("position:absolute!important")) {
      this._onFixtureProbeMeasure?.(this.style.cssText);
      return {
        width: this._fixtureProbeWidth,
        left: 0,
        right: this._fixtureProbeWidth,
        top: 0,
        bottom: 0,
        height: 0,
      };
    }
    return {
      width: this.width,
      left: this.left,
      right: this.left + this.width,
      top: this.top,
      bottom: this.top + this.height,
      height: this.height,
    };
  }

  getClientRects() {
    return [this.getBoundingClientRect()];
  }

  closest(selector) {
    for (let node = this; node; node = node.parentElement) {
      if (node.nodeType === 1 && matchesSelector(node, selector)) return node;
    }
    return null;
  }

  cloneNode(deep = false) {
    const clone = new FakeElement(this.tagName);
    clone.ownerDocument = this.ownerDocument;
    clone.width = this.width;
    clone.height = this.height;
    clone.left = this.left;
    clone.top = this.top;
    clone._innerText = this._innerText;
    clone.attributes = new Map(this.attributes);
    clone.dataset = { ...this.dataset };
    clone.style.cssText = this.style.cssText;
    if (deep) for (const child of this.childNodes) clone.appendChild(child.cloneNode(true));
    return clone;
  }
}

class FakeFragment extends FakeNode {
  constructor() {
    super(11);
  }

  cloneNode(deep = false) {
    const clone = new FakeFragment();
    if (deep) for (const child of this.childNodes) clone.appendChild(child.cloneNode(true));
    return clone;
  }
}

function styleDeclaration(values) {
  return {
    getPropertyValue(name) {
      return values[name] ?? "";
    },
  };
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function canonicalFixtureNode(node) {
  if (node.nodeType === 3) return ["#", node.textContent];
  return [
    node.tagName.toLocaleLowerCase(),
    Array.from(node.attributes, ([name, value]) => [name, value])
      .sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0),
    node.childNodes.map(canonicalFixtureNode),
  ];
}

function fixtureComputedStyle(element, _pseudo, overrides = {}) {
  const boundary = element?.hasAttribute?.("data-tq-shaping-boundary") === true;
  const engineHyphen = element?.hasAttribute?.("data-tq-engine-hyphen") === true;
  const measuredGeometry = !boundary && element?.hasAttribute?.("data-tq-advance") === true;
  const proportionalQuote = element?.getAttribute?.("data-tq-open-type-features") === "pwid,palt";
  const canonicalPreparedFlow = element?.closest?.("[data-tq-canonical-plain]") != null ||
    element?.closest?.("[data-tq-canonical-source]") != null;
  return {
    display: boundary
      ? "inline"
      : engineHyphen
        ? "inline-block"
        : measuredGeometry
          ? "inline"
          : element?.tagName === "LI" ? "list-item" : "block",
    whiteSpace: boundary || engineHyphen ? "pre" : "normal",
    verticalAlign: "baseline",
    direction: "ltr",
    unicodeBidi: boundary || engineHyphen ? "isolate" : "normal",
    fontFamily: "\"Fixture CJK\"",
    fontSize: "18px",
    lineHeight: canonicalPreparedFlow ? "0px" : "27px",
    fontWeight: "400",
    fontStyle: "normal",
    letterSpacing: "normal",
    wordSpacing: "normal",
    fontFeatureSettings: proportionalQuote
      ? '"halt" 0, "chws" 0, "palt" 1'
      : canonicalPreparedFlow ? '"halt" 0, "chws" 0, "palt" 0' : "normal",
    fontVariationSettings: "normal",
    fontStretch: "100%",
    fontKerning: "normal",
    fontOpticalSizing: "none",
    fontVariantLigatures: "normal",
    fontVariantAlternates: "normal",
    fontVariantEastAsian: proportionalQuote ? "proportional-width" : "normal",
    fontVariantCaps: "normal",
    fontVariantNumeric: "normal",
    fontVariantPosition: "normal",
    fontLanguageOverride: "normal",
    fontSizeAdjust: "none",
    textTransform: "none",
    textRendering: "auto",
    textAlign: "start",
    textAlignLast: "auto",
    textJustify: "auto",
    writingMode: "horizontal-tb",
    whiteSpaceCollapse: "preserve",
    textWrapMode: "nowrap",
    overflowWrap: "normal",
    wordBreak: "normal",
    hyphens: "manual",
    textAutospace: "no-autospace",
    marginLeft: "0px",
    marginRight: "0px",
    transform: "none",
    scale: "none",
    content: "none",
    cssFloat: "none",
    ...overrides,
  };
}

function fixture({
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
  paragraphTag = "p",
  paragraphSelector = "p[data-tq-snapshot-key]",
  paragraphWidth = 360,
  maximumWidth = 360,
} = {}) {
  const measuredProbeStyles = [];
  const documentObject = {
    baseURI: "https://example.test/post/",
    elements: new Map(),
    styleSheets: [],
    fonts: { load: async () => [{}] },
    createDocumentFragment: () => new FakeFragment(),
    createElement(tagName) {
      const element = new FakeElement(tagName);
      element.ownerDocument = documentObject;
      element._fixtureProbeWidth = probeWidth;
      element._onFixtureProbeMeasure = (style) => measuredProbeStyles.push(style);
      return element;
    },
    createRange() {
      let selectedNode = null;
      return {
        selectNodeContents(node) {
          selectedNode = node;
        },
        getBoundingClientRect() {
          if (selectedNode?.style?.cssText) measuredProbeStyles.push(selectedNode.style.cssText);
          return { width: probeWidth };
        },
      };
    },
    getElementById(id) {
      return documentObject.elements.get(id) ?? null;
    },
  };
  documentObject.body = documentObject.createElement("body");

  const root = documentObject.createElement("tiqian-prose");
  root.setAttribute("snapshot-ref", "tq-page");
  const paragraph = documentObject.createElement(paragraphTag);
  paragraph.setAttribute("data-tq-snapshot-key", "p-1");
  paragraph.width = paragraphWidth;
  paragraph.height = paragraphHeight;
  paragraph.innerText = "中国";
  const originalText = new FakeText("中国");
  paragraph.appendChild(originalText);
  root.appendChild(paragraph);

  const typography = {
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
  const evidence = {
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
  const template = documentObject.createElement("template");
  template.content = new FakeFragment();
  const entry = documentObject.createElement("div");
  entry.setAttribute("data-tq-entry", "p-1");
  const marker = documentObject.createElement("span");
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
  const rendered = nativeText ? new FakeText("中国") : documentObject.createElement("span");
  if (!nativeText) {
    rendered.setAttribute("data-tq-advance", "36");
    rendered.setAttribute("data-tq-geometry", "true");
    if (renderFontProjection) rendered.setAttribute("data-tq-render-font-projection", "true");
    if (shapingBoundary) rendered.setAttribute("data-tq-shaping-boundary", "current-segment");
    if (boundaryFeatureSignature != null) {
      rendered.setAttribute("data-tq-open-type-features", boundaryFeatureSignature);
    }
    rendered.setAttribute("data-tq-x", "0");
    rendered.width = segmentWidth;
    rendered.left = segmentLeft;
    rendered.textContent = "中国";
  }
  const sentinel = documentObject.createElement("span");
  sentinel.setAttribute("data-tq-geometry", "true");
  sentinel.setAttribute("data-tq-line-end-sentinel", "0");
  sentinel.left = lineEnd;
  sentinel.top = sentinelTop;
  const renderedParent = semanticGeometry
    ? documentObject.createElement("strong")
    : null;
  if (renderedParent) {
    renderedParent.setAttribute("data-tq-source-semantic", "true");
    renderedParent.appendChild(rendered);
  }
  entry.append(marker, renderedParent ?? rendered, sentinel);
  const manifest = {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v15",
    fontSourcePolicy: "host-compatible-stylesheet-v1",
    ...(entrySource === undefined ? {} : { entrySource }),
    renderFontFamilies: ["Fixture CJK"],
    paragraphSelector,
    valueStyles: [],
    valueStylesSha256: sha256(stableStringify([])),
    typographies: [{
      sha256: typographyDigest ?? sha256(stableStringify(typography)),
      value: typography,
    }],
    fontEvidence: {
      backendRevision: "tiqian-shared-harfbuzz-v5",
      harfbuzzVersion: "fixture",
      faces: [{
        ...Object.fromEntries(Object.entries(evidence).filter(([key]) =>
          key !== "coverageText" && key !== "probe")),
      }],
    },
    fontReplay: {
      revision: FONT_REPLAY_REVISION,
      shapes: [],
      metrics: [],
    },
    entries: [{
      key: "p-1",
      sourceSha256: sha256("中国"),
      typographyRef: 0,
      maxWidthPx: maximumWidth,
      fontFaceEvidence: [{ faceRef: 0, coverageText: evidence.coverageText, probe: evidence.probe }],
      renderArtifactSha256: sha256(stableStringify(entry.childNodes.map(canonicalFixtureNode))),
    }],
  };
  const script = documentObject.createElement("script");
  script.setAttribute("data-tq-snapshot-manifest", "");
  script.textContent = JSON.stringify(manifest);
  template.content.append(script, entry);
  documentObject.elements.set("tq-page", template);

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
  documentObject.styleSheets.push({
    href: sheet.href,
    cssRules,
  });

  return { documentObject, root, paragraph, originalText, entry, measuredProbeStyles };
}

function attachServerSource(documentObject, text = "中国") {
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
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { documentObject, root, paragraph } = fixture();
    paragraph.width = 240;

    assert.deepEqual(await validatePrecomputedSnapshotExactFontContract(root), {
      matches: true,
      reason: null,
      paragraphSelector: "p[data-tq-snapshot-key]",
      compatibleLocalDeclared: false,
    });

    paragraph.innerText = "中国—";
    assert.deepEqual(await validatePrecomputedSnapshotExactFontContract(root), {
      matches: false,
      reason: "SnapshotSourceMismatch",
    });
    assert.deepEqual(await validatePrecomputedExactFontReplayContract(root), {
      matches: true,
      reason: null,
      paragraphSelector: "p[data-tq-snapshot-key]",
      compatibleLocalDeclared: false,
    });
    assert.deepEqual(validatePrecomputedExactFontReplayLiveContract(root), {
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
    assert.deepEqual(validatePrecomputedExactFontReplayLiveContract(root), {
      matches: false,
      reason: "FontFaceContractChangedDuringFontPreparation",
    });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("runtime font replay validates the same host CSS contract as snapshots", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root } = fixture();
    assert.deepEqual(await validatePrecomputedExactFontReplayRuntimeContract(root), {
      matches: true,
      reason: null,
      paragraphSelector: "p[data-tq-snapshot-key]",
      compatibleLocalDeclared: false,
    });
    assert.deepEqual(validatePrecomputedExactFontReplayLiveContract(root), {
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
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, paragraph } = fixture({
      paragraphTag: "li",
      paragraphSelector: ":is(p, li)[data-tq-snapshot-key]",
    });

    assert.deepEqual(await validatePrecomputedSnapshotExactFontContract(root), {
      matches: true,
      reason: null,
      paragraphSelector: ":is(p, li)[data-tq-snapshot-key]",
      compatibleLocalDeclared: false,
    });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), {
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
    globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(
      element,
      pseudo,
      element === paragraph ? { fontSize: "15.75px", lineHeight: "28px" } : {},
    );

    assert.deepEqual(await validatePrecomputedSnapshotExactFontContract(root), {
      matches: true,
      reason: null,
      paragraphSelector: "p[data-tq-snapshot-key]",
      compatibleLocalDeclared: false,
    });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), {
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
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { documentObject, root, paragraph } = fixture();
    documentObject.fonts.load = async () => {
      paragraph.innerText = "异步改写";
      return [{}];
    };

    assert.deepEqual(await validatePrecomputedSnapshotExactFontContract(root), {
      matches: false,
      reason: "SnapshotSourceChangedDuringValidation",
    });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("proportional quote evidence and prepared boundaries replay the same feature contract", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, measuredProbeStyles } = fixture({
      probeFeatures: ["pwid", "palt"],
      boundaryFeatureSignature: "pwid,palt",
    });

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), {
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
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, paragraph, originalText } = fixture({ probeFeatures: ["calt"] });

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), {
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
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { documentObject, root } = fixture();
    documentObject.styleSheets.push({
      href: "https://cross-origin.example/fonts.css",
      get cssRules() {
        throw new DOMException("Blocked", "SecurityError");
      },
    });

    assert.deepEqual(await validatePrecomputedSnapshotExactFontContract(root), {
      matches: false,
      reason: "FontFaceCssomUnverifiable",
    });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("a compact client font contract enables the exact runtime without claiming snapshot layout", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { documentObject, root } = fixture();
    const template = documentObject.elements.get("tq-page");
    const manifestScript = template.content.querySelector("[data-tq-snapshot-manifest]");
    manifestScript.textContent = JSON.stringify({
      ...JSON.parse(manifestScript.textContent),
      entrySource: "font-contract-v1",
    });

    assert.deepEqual(await validatePrecomputedSnapshotExactFontContract(root), {
      matches: true,
      reason: null,
      paragraphSelector: "p[data-tq-snapshot-key]",
      compatibleLocalDeclared: false,
    });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), {
      adopted: false,
      reason: "SnapshotLayoutArtifactUnavailable",
    });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("article-sized exact font evidence loads by face and shares one layout snapshot", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { documentObject, root, measuredProbeStyles } = fixture({
      entrySource: "font-contract-v1",
      paragraphSelector: "p",
    });
    const template = documentObject.elements.get("tq-page");
    const manifestScript = template.content.querySelector("[data-tq-snapshot-manifest]");
    const manifest = JSON.parse(manifestScript.textContent);
    const original = manifest.entries[0];
    for (let index = 1; index < 40; index += 1) {
      manifest.entries.push({
        ...original,
        key: `p-${index + 1}`,
        fontFaceEvidence: [{
          ...original.fontFaceEvidence[0],
          coverageText: `中国${String.fromCodePoint(0x4e00 + index)}`,
          probe: {
            ...original.fontFaceEvidence[0].probe,
            text: `中国${String.fromCodePoint(0x4e00 + index)}`,
          },
        }],
      });
    }
    manifestScript.textContent = JSON.stringify(manifest);

    let fontLoads = 0;
    documentObject.fonts.load = async () => {
      fontLoads += 1;
      return [{}];
    };
    let maximumAttachedProbes = 0;
    const createElement = documentObject.createElement;
    documentObject.createElement = (tagName) => {
      const element = createElement(tagName);
      const getBoundingClientRect = element.getBoundingClientRect.bind(element);
      element.getBoundingClientRect = () => {
        maximumAttachedProbes = Math.max(
          maximumAttachedProbes,
          documentObject.body.childNodes.length,
        );
        return getBoundingClientRect();
      };
      return element;
    };

    assert.deepEqual(await validatePrecomputedSnapshotExactFontContract(root), {
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
    globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(
      element,
      pseudo,
      element === halfWidthParagraph
        ? {
            fontFeatureSettings: '"hwid" 1',
            fontVariantEastAsian: "proportional-width",
          }
        : {},
    );

    assert.deepEqual(await validatePrecomputedSnapshotExactFontContract(root), {
      matches: true,
      reason: null,
      paragraphSelector: "p",
      compatibleLocalDeclared: false,
    });
    assert.equal(root.getAttribute("data-tiqian-snapshot-typography-issue"), null);
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), {
      adopted: false,
      reason: "SnapshotLayoutArtifactUnavailable",
    });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("shared prepared DOM validator reports the same vertical gate used for SSR adoption", () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { paragraph, entry } = fixture({ sentinelTop: 20.1 });
    while (paragraph.firstChild) paragraph.removeChild(paragraph.firstChild);
    for (const child of entry.childNodes) paragraph.appendChild(child.cloneNode(true));
    paragraph.setAttribute("data-tq-canonical-plain", "true");
    assert.equal(
      renderedPreparedParagraphIssue(paragraph, 360),
      "RenderedPreparedParagraphLineVerticalMismatch:0",
    );
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("shared prepared DOM validator accepts the isolated engine hyphen contract", () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { paragraph, entry } = fixture();
    const rendered = entry.querySelector("[data-tq-advance]");
    rendered.setAttribute("data-tq-advance", "18");
    rendered.width = 18;
    const sentinel = entry.querySelector("[data-tq-line-end-sentinel]");
    entry.removeChild(sentinel);
    const hyphen = paragraph.ownerDocument.createElement("span");
    hyphen.setAttribute("data-tq-advance", "18");
    hyphen.setAttribute("data-tq-geometry", "true");
    hyphen.setAttribute("data-tq-engine-hyphen", "true");
    hyphen.setAttribute("data-tq-x", "18");
    hyphen.textContent = "-";
    hyphen.left = 18;
    hyphen.top = 8;
    hyphen.width = 18;
    entry.append(hyphen, sentinel);
    while (paragraph.firstChild) paragraph.removeChild(paragraph.firstChild);
    for (const child of entry.childNodes) paragraph.appendChild(child.cloneNode(true));
    paragraph.setAttribute("data-tq-canonical-plain", "true");
    assert.equal(renderedPreparedParagraphIssue(paragraph, 360), null);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("shared prepared DOM validator compares vertical geometry across inline fragments", () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { paragraph, entry } = fixture({ shapingBoundary: true });
    const boundary = entry.querySelector("[data-tq-shaping-boundary]");
    boundary.top = 0;
    boundary.setAttribute("data-tq-advance", "18");
    boundary.width = 18;
    const sentinel = entry.querySelector("[data-tq-line-end-sentinel]");
    entry.removeChild(sentinel);
    const firstInline = paragraph.ownerDocument.createElement("span");
    firstInline.setAttribute("data-tq-advance", "9");
    firstInline.setAttribute("data-tq-geometry", "true");
    firstInline.setAttribute("data-tq-x", "18");
    firstInline.textContent = " ";
    firstInline.left = 18;
    firstInline.top = 0;
    firstInline.width = 9;
    const secondInline = paragraph.ownerDocument.createElement("span");
    secondInline.setAttribute("data-tq-advance", "9");
    secondInline.setAttribute("data-tq-geometry", "true");
    secondInline.setAttribute("data-tq-x", "27");
    secondInline.textContent = " ";
    secondInline.left = 27;
    secondInline.top = 0;
    secondInline.width = 9;
    entry.append(firstInline, secondInline, sentinel);
    while (paragraph.firstChild) paragraph.removeChild(paragraph.firstChild);
    for (const child of entry.childNodes) paragraph.appendChild(child.cloneNode(true));
    paragraph.setAttribute("data-tq-canonical-plain", "true");
    assert.equal(renderedPreparedParagraphIssue(paragraph, 360), null);

    paragraph.querySelectorAll("[data-tq-advance]")[2].top = 2;
    assert.match(
      renderedPreparedParagraphIssue(paragraph, 360),
      /^RenderedPreparedParagraphLineAdvanceMismatch:0;contributor-top;/u,
    );
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("shaping boundaries may carry engine-owned letter spacing when their advance matches", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(
    element,
    pseudo,
    element.hasAttribute?.("data-tq-shaping-boundary")
      ? { letterSpacing: "0.75px" }
      : {},
  );
  try {
    const { root } = fixture({ shapingBoundary: true });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), { adopted: true, count: 1 });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("shared prepared DOM validator tolerates compatible-local subpixel segment drift", () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { paragraph, entry } = fixture({ segmentWidth: 36.6 });
    while (paragraph.firstChild) paragraph.removeChild(paragraph.firstChild);
    for (const child of entry.childNodes) paragraph.appendChild(child.cloneNode(true));
    paragraph.setAttribute("data-tq-canonical-plain", "true");
    assert.equal(renderedPreparedParagraphIssue(paragraph, 360), null);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("shared prepared DOM validator allows one browser quantization step beyond the probe tolerance", () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { paragraph, entry } = fixture({
      localSource: true,
      segmentLeft: 0.765625,
      lineEnd: 36.765625,
    });
    while (paragraph.firstChild) paragraph.removeChild(paragraph.firstChild);
    for (const child of entry.childNodes) paragraph.appendChild(child.cloneNode(true));
    paragraph.setAttribute("data-tq-canonical-plain", "true");
    assert.equal(renderedPreparedParagraphIssue(paragraph, 360), null);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("strict snapshot adoption preserves and restores the original SSR node identity", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, paragraph, originalText } = fixture();
    const adopted = await tryAdoptPrecomputedSnapshot(root);
    assert.deepEqual(adopted, { adopted: true, count: 1 });
    assert.equal(isPrecomputedSnapshotAdopted(root), true);
    assert.equal(root.dataset.tiqianSnapshotFontPolicy, "url-only");
    assert.equal(root.getAttribute("data-tiqian-enhanced-count"), "1");
    assert.equal(root.getAttribute("data-tiqian-snapshot-count"), "1");
    assert.equal(paragraph.getAttribute("data-tq-rendered"), "true");
    assert.equal(paragraph.getAttribute("data-tq-canonical-source"), "true");
    assert.equal(paragraph.getAttribute("data-tq-exact-prepared-dom"), "true");
    assert.notStrictEqual(paragraph.firstChild, originalText);

    const preparedNode = paragraph.firstChild;
    assert.equal(detachPrecomputedSnapshot(root), true);
    assert.equal(isPrecomputedSnapshotAdopted(root), true);
    assert.strictEqual(paragraph.firstChild, preparedNode);

    assert.equal(restorePrecomputedSnapshot(root), true);
    assert.equal(isPrecomputedSnapshotAdopted(root), false);
    assert.strictEqual(paragraph.firstChild, originalText);
    assert.equal(paragraph.getAttribute("data-tq-rendered"), null);
    assert.equal(paragraph.getAttribute("data-tq-canonical-source"), null);
    assert.equal(paragraph.getAttribute("data-tq-exact-prepared-dom"), null);
    assert.equal(root.dataset.tiqianSnapshotFontPolicy, undefined);
    assert.equal(root.getAttribute("data-tiqian-snapshot-count"), null);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("server-rendered compact snapshot adopts without replacing its first-paint DOM", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { documentObject, root, paragraph, entry } = fixture();
    while (paragraph.firstChild) paragraph.removeChild(paragraph.firstChild);
    for (const child of entry.childNodes) paragraph.appendChild(child.cloneNode(true));
    paragraph.setAttribute("data-tq-rendered", "true");
    paragraph.setAttribute("data-tq-canonical-plain", "true");
    paragraph.setAttribute("data-tq-canonical-source", "true");
    root.setAttribute("data-tq-ssr-snapshot", "tq-page");
    root.setAttribute("data-tiqian-exact-render-font", "true");
    attachServerSource(documentObject);
    const template = documentObject.elements.get("tq-page");
    const manifestScript = template.content.querySelector("[data-tq-snapshot-manifest]");
    manifestScript.textContent = JSON.stringify({
      ...JSON.parse(manifestScript.textContent),
      entrySource: "server-dom-v1",
    });
    template.content.removeChild(entry);
    const firstPaintNode = paragraph.firstChild;
    root.setAttribute(
      "data-tiqian-exact-layout-issue",
      "p-0:RenderedPreparedParagraphLineAdvanceMismatch:stale",
    );

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), { adopted: true, count: 1 });
    assert.strictEqual(paragraph.firstChild, firstPaintNode);
    assert.equal(root.dataset.tiqianSnapshot, "maximum-measure");
    assert.equal(root.getAttribute("data-tiqian-exact-layout-issue"), null);

    assert.equal(restorePrecomputedSnapshot(root), true);
    assert.equal(paragraph.textContent, "中国");
    assert.equal(paragraph.firstChild.nodeType, 3);
    assert.equal(paragraph.getAttribute("data-tq-rendered"), null);
    assert.equal(paragraph.getAttribute("data-tq-canonical-source"), null);
    assert.equal(root.getAttribute("data-tq-ssr-snapshot"), null);
    assert.equal(root.getAttribute("data-tiqian-exact-render-font"), null);

    paragraph.width = 360;
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), { adopted: true, count: 1 });
    assert.equal(paragraph.firstChild.nodeType, 1);
    assert.equal(paragraph.getAttribute("data-tq-rendered"), "true");
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("a direct SSR width miss restores native source before runtime fallback", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { documentObject, root, paragraph, entry } = fixture();
    while (paragraph.firstChild) paragraph.removeChild(paragraph.firstChild);
    for (const child of entry.childNodes) paragraph.appendChild(child.cloneNode(true));
    paragraph.setAttribute("data-tq-rendered", "true");
    paragraph.setAttribute("data-tq-canonical-source", "true");
    paragraph.width = 240;
    root.setAttribute("data-tq-ssr-snapshot", "tq-page");
    root.setAttribute("data-tiqian-exact-render-font", "true");
    attachServerSource(documentObject);
    const template = documentObject.elements.get("tq-page");
    const manifestScript = template.content.querySelector("[data-tq-snapshot-manifest]");
    manifestScript.textContent = JSON.stringify({
      ...JSON.parse(manifestScript.textContent),
      entrySource: "server-dom-v1",
    });
    template.content.removeChild(entry);

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), {
      adopted: false,
      reason: "SnapshotWidthMismatch",
    });
    assert.equal(paragraph.firstChild.nodeType, 3);
    assert.equal(paragraph.textContent, "中国");
    assert.equal(paragraph.getAttribute("data-tq-rendered"), null);
    assert.equal(paragraph.getAttribute("data-tq-canonical-source"), null);
    assert.equal(root.getAttribute("data-tq-ssr-snapshot"), null);
    assert.equal(root.getAttribute("data-tiqian-exact-render-font"), null);

    paragraph.width = 360;
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), { adopted: true, count: 1 });
    assert.equal(paragraph.firstChild.nodeType, 1);
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
      globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(
        element,
        pseudo,
        element === root ? { transform } : {},
      );

      assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), { adopted: true, count: 1 });
      assert.notStrictEqual(paragraph.firstChild, originalText);
    }
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("non-translation ancestor transforms remain outside the exact snapshot contract", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  try {
    for (const ancestorStyle of [
      { transform: "matrix(1.1, 0, 0, 1.1, 12, 8)" },
      { transform: "matrix(0, 1, -1, 0, 12, 8)" },
      { transform: "matrix(1, 0.2, 0, 1, 12, 8)" },
      { transform: "matrix3d(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, -0.001, 12, 8, 0, 1)" },
      { transform: "matrix3d(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 12, 8, 5, 1)" },
      { transform: "translateY(0px)" },
      { transform: "matrix(1, 0, 0, 1, NaN, 0)" },
      { scale: "1.1" },
    ]) {
      const { root, paragraph, originalText } = fixture();
      globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(
        element,
        pseudo,
        element === root ? ancestorStyle : {},
      );

      assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), {
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
    globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(
      element,
      pseudo,
      element === paragraph ? { transform: "matrix(1, 0, 0, 1, 12, 8)" } : {},
    );

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), {
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
  globalThis.getComputedStyle = fixtureComputedStyle;
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
    const manifestScript = template.content.querySelector("[data-tq-snapshot-manifest]");
    const manifest = JSON.parse(manifestScript.textContent);
    manifest.entries.push({ ...manifest.entries[0] });
    manifestScript.textContent = JSON.stringify(manifest);

    assert.equal(precomputedSnapshotMaximumMeasureMatches(root), false);
    assert.deepEqual(await validatePrecomputedSnapshotExactFontContract(root), {
      matches: false,
      reason: "SnapshotManifestEntryKeyInvalid",
    });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), {
      adopted: false,
      reason: "SnapshotManifestEntryKeyInvalid",
    });
    assert.strictEqual(paragraph.firstChild, originalText);
    assert.strictEqual(secondParagraph.firstChild, secondText);
    assert.equal(isPrecomputedSnapshotAdopted(root), false);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("maximum-measure preflight is non-destructive and follows live paragraph width", () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, paragraph, originalText } = fixture();
    assert.equal(precomputedSnapshotMaximumMeasureMatches(root), true);
    assert.strictEqual(paragraph.firstChild, originalText);

    paragraph.width = 368;
    assert.equal(precomputedSnapshotMaximumMeasureMatches(root), true);
    assert.strictEqual(paragraph.firstChild, originalText);

    paragraph.width = 378;
    assert.equal(precomputedSnapshotMaximumMeasureMatches(root), false);
    assert.strictEqual(paragraph.firstChild, originalText);

    paragraph.width = 240;
    assert.equal(precomputedSnapshotMaximumMeasureMatches(root), false);
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("snapshot adoption accepts a wider container in the same line-length grid cell", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, paragraph } = fixture();
    paragraph.width = 368;

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), { adopted: true, count: 1 });
    assert.equal(root.dataset.tiqianSnapshot, "maximum-measure");
    assert.equal(await adoptedPrecomputedSnapshotLiveIssue(root), null);

    paragraph.width = 378;
    assert.equal(await adoptedPrecomputedSnapshotLiveIssue(root), "SnapshotWidthMismatch");
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("snapshot adoption preserves native Text nodes for ordinary prepared prose", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, paragraph } = fixture({ nativeText: true });
    const adopted = await tryAdoptPrecomputedSnapshot(root);

    assert.deepEqual(adopted, { adopted: true, count: 1 });
    assert.equal(paragraph.childNodes[1].nodeType, 3);
    assert.equal(paragraph.childNodes[1].textContent, "中国");
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("snapshot adoption accepts sparse inline geometry without an atomic shaping boundary", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root } = fixture({ shapingBoundary: false });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), { adopted: true, count: 1 });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("prepared geometry inherits shaping styles from its nearest semantic source wrapper", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(
    element,
    pseudo,
    element.closest?.("[data-tq-source-semantic]") ? { fontWeight: "700" } : {},
  );
  try {
    const { root } = fixture({ semanticGeometry: true });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), { adopted: true, count: 1 });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("prepared geometry may carry an artifact-owned exact render-font projection", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(
    element,
    pseudo,
    element.hasAttribute?.("data-tq-render-font-projection")
      ? { fontFamily: '"Tiqian Exact Inline"' }
      : element.closest?.("[data-tq-source-semantic]")
        ? { fontFamily: '"Host Inline"' }
        : {},
  );
  try {
    const { root } = fixture({ semanticGeometry: true, renderFontProjection: true });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), { adopted: true, count: 1 });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("prepared geometry still rejects shaping styles that differ from its semantic source wrapper", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(
    element,
    pseudo,
    element.hasAttribute?.("data-tq-advance")
      ? { fontWeight: "600" }
      : element.closest?.("[data-tq-source-semantic]")
        ? { fontWeight: "700" }
        : {},
  );
  try {
    const { root, paragraph, originalText } = fixture({
      semanticGeometry: true,
      shapingBoundary: false,
    });
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), {
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
  globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(
    element,
    pseudo,
    element.closest?.("[data-tq-canonical-source]")
      ? { fontFeatureSettings: "normal" }
      : {},
  );
  try {
    const { root, paragraph, originalText } = fixture();
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), {
      adopted: false,
      reason: "SnapshotAdoptionFailed:RenderedSnapshotHostContractMismatch",
    });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("maximum-measure snapshot atomically replaces and restores canonical runtime DOM", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
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

    const adopted = await tryAdoptPrecomputedSnapshot(root);
    assert.deepEqual(adopted, { adopted: true, count: 1 });
    assert.notStrictEqual(paragraph.firstChild, runtimeMarker);
    assert.equal(originalText.parentNode, null, "re-adoption must not expose retained SSR source");

    assert.equal(restorePrecomputedSnapshot(root), true);
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
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, paragraph, originalText } = fixture({ localSource: true });
    const adopted = await tryAdoptPrecomputedSnapshot(root);
    assert.deepEqual(adopted, { adopted: true, count: 1 });
    assert.notStrictEqual(paragraph.firstChild, originalText);
    assert.equal(isPrecomputedSnapshotAdopted(root), true);
    assert.equal(root.dataset.tiqianSnapshotFontPolicy, "compatible-local");
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("a local() token outside the build face name table is rejected", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, paragraph, originalText } = fixture({ localSource: true, localName: "Arial" });
    const adopted = await tryAdoptPrecomputedSnapshot(root);
    assert.deepEqual(adopted, { adopted: false, reason: "FontFaceContractMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("a compatible local face with a different probe advance is rejected", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, paragraph, originalText } = fixture({ localSource: true, probeWidth: 40 });
    const adopted = await tryAdoptPrecomputedSnapshot(root);
    assert.deepEqual(adopted, { adopted: false, reason: "FontAdvanceProbeMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("an optional render face cannot promise exact direct first paint", async () => {
  const setup = fixture({ fontDisplay: "optional", entrySource: "server-dom-v1" });
  globalThis.document = setup.documentObject;
  globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(element, pseudo);
  try {
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(setup.root), {
      adopted: false,
      reason: "FontFaceContractMismatch",
    });
  } finally {
    delete globalThis.document;
    delete globalThis.getComputedStyle;
  }
});

test("an inert snapshot may adopt a swap face only after its exact probe loads", async () => {
  const setup = fixture({ fontDisplay: "swap" });
  globalThis.document = setup.documentObject;
  globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(element, pseudo);
  try {
    assert.deepEqual(await tryAdoptPrecomputedSnapshot(setup.root), { adopted: true, count: 1 });
  } finally {
    delete globalThis.document;
    delete globalThis.getComputedStyle;
  }
});

test("post-adoption segment advance mismatch restores the original paragraph", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, paragraph, originalText } = fixture({ localSource: true, segmentWidth: 38 });
    const adopted = await tryAdoptPrecomputedSnapshot(root);
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
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, paragraph, originalText } = fixture({ localSource: true, lineEnd: 38 });
    const adopted = await tryAdoptPrecomputedSnapshot(root);
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
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root } = fixture({
      lineEnd: 36.015625,
      paragraphWidth: 35,
      maximumWidth: 35,
    });

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), { adopted: true, count: 1 });
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("post-adoption baseline drift restores the original paragraph", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, paragraph, originalText } = fixture({ sentinelTop: 20.1 });
    const adopted = await tryAdoptPrecomputedSnapshot(root);
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
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, paragraph, originalText } = fixture({ paragraphHeight: 28 });
    const adopted = await tryAdoptPrecomputedSnapshot(root);
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
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, paragraph, originalText } = fixture({
      localSource: true,
      segmentLeft: 1,
      lineEnd: 36,
    });
    const adopted = await tryAdoptPrecomputedSnapshot(root);
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
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, paragraph, originalText } = fixture({ unsafeSibling: true });
    const adopted = await tryAdoptPrecomputedSnapshot(root);
    assert.deepEqual(adopted, { adopted: false, reason: "FontFaceContractMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("an overlapping unicode-range sibling prevents exact-source adoption", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
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
    const adopted = await tryAdoptPrecomputedSnapshot(root);
    assert.deepEqual(adopted, { adopted: false, reason: "FontFaceContractMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("font-face metric override descriptors cannot satisfy exact evidence", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
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
    const adopted = await tryAdoptPrecomputedSnapshot(root);
    assert.deepEqual(adopted, { adopted: false, reason: "FontFaceContractMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("non-default shaping CSS misses before DOM adoption", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(element, pseudo, {
    wordSpacing: "2px",
    fontVariantLigatures: "none",
  });
  try {
    const { root, paragraph, originalText } = fixture();
    const adopted = await tryAdoptPrecomputedSnapshot(root);
    assert.deepEqual(adopted, { adopted: false, reason: "SnapshotTypographyMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("lining numeric typography validates the matching lnum font probe", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(element, pseudo, {
    fontVariantNumeric: "lining-nums",
  });
  try {
    const { root, paragraph, originalText, measuredProbeStyles } = fixture({
      fontVariantNumeric: "lining-nums",
      probeFeatures: ["lnum"],
    });

    assert.deepEqual(await tryAdoptPrecomputedSnapshot(root), { adopted: true, count: 1 });
    assert.notStrictEqual(paragraph.firstChild, originalText);
    assert.ok(measuredProbeStyles.some((style) =>
      style.includes("font-variant-numeric:lining-nums!important")));
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("generated pseudo content is outside the plain-text snapshot contract", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(element, pseudo, {
    content: pseudo === "::before" ? '"※"' : "none",
  });
  try {
    const { root, paragraph, originalText } = fixture();
    const adopted = await tryAdoptPrecomputedSnapshot(root);
    assert.deepEqual(adopted, { adopted: false, reason: "SnapshotTypographyMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("prepared pseudo isolation avoids per-node pseudo probes after adoption", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(element, pseudo, {
    content: element.hasAttribute?.("data-tq-geometry") && pseudo === "::before" ? '"※"' : "none",
  });
  try {
    const { root, paragraph, originalText } = fixture();
    const adopted = await tryAdoptPrecomputedSnapshot(root);
    assert.deepEqual(adopted, { adopted: true, count: 1 });
    assert.notStrictEqual(paragraph.firstChild, originalText);
    assert.equal(isPrecomputedSnapshotAdopted(root), true);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("horizontal padding cannot masquerade as the prepared content width", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(element, pseudo, {
    paddingLeft: "20px",
    paddingRight: "20px",
    borderLeftWidth: "0px",
    borderRightWidth: "0px",
  });
  try {
    const { root, paragraph, originalText } = fixture();
    paragraph.width = 400;
    const adopted = await tryAdoptPrecomputedSnapshot(root);
    assert.deepEqual(adopted, { adopted: false, reason: "SnapshotTypographyMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("typography manifest tampering misses before DOM adoption", async () => {
  const { root, paragraph, originalText } = fixture({ typographyDigest: "c".repeat(64) });
  const adopted = await tryAdoptPrecomputedSnapshot(root);
  assert.deepEqual(adopted, { adopted: false, reason: "SnapshotTypographyDigestMismatch" });
  assert.strictEqual(paragraph.firstChild, originalText);
});

test("rendered snapshot artifact tampering misses before DOM adoption", async () => {
  const { documentObject, root, paragraph, originalText } = fixture();
  documentObject.getElementById("tq-page").content
    .querySelector("[data-tq-entry]").firstChild.textContent = "错误";
  const adopted = await tryAdoptPrecomputedSnapshot(root);
  assert.deepEqual(adopted, { adopted: false, reason: "SnapshotArtifactDigestMismatch" });
  assert.strictEqual(paragraph.firstChild, originalText);
});

test("host text alignment outside the v1 contract misses before DOM adoption", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = (element, pseudo) => fixtureComputedStyle(element, pseudo, {
    textAlign: "center",
  });
  try {
    const { root, paragraph, originalText } = fixture();
    const adopted = await tryAdoptPrecomputedSnapshot(root);
    assert.deepEqual(adopted, { adopted: false, reason: "SnapshotTypographyMismatch" });
    assert.strictEqual(paragraph.firstChild, originalText);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("a superseded async validation never mutates the live paragraph", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { documentObject, root, paragraph, originalText } = fixture();
    let current = true;
    documentObject.fonts.load = async () => {
      current = false;
      return [{}];
    };
    const adopted = await tryAdoptPrecomputedSnapshot(root, () => current);
    assert.deepEqual(adopted, { adopted: false, reason: "superseded" });
    assert.strictEqual(paragraph.firstChild, originalText);
    assert.equal(isPrecomputedSnapshotAdopted(root), false);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("a superseded post-adoption proof rolls back only its provisional DOM", async () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  const previousPerformance = globalThis.performance;
  const previousScheduler = globalThis.scheduler;
  globalThis.getComputedStyle = fixtureComputedStyle;
  try {
    const { root, paragraph, originalText } = fixture();
    let current = true;
    let clock = 0;
    Object.defineProperty(globalThis, "performance", {
      configurable: true,
      value: { now: () => (clock += 10) },
    });
    globalThis.scheduler = {
      async yield() {
        if (paragraph.firstChild !== originalText) current = false;
      },
    };

    const adopted = await tryAdoptPrecomputedSnapshot(root, () => current);
    assert.deepEqual(adopted, { adopted: false, reason: "superseded" });
    assert.strictEqual(paragraph.firstChild, originalText);
    assert.equal(isPrecomputedSnapshotAdopted(root), false);
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
    Object.defineProperty(globalThis, "performance", {
      configurable: true,
      value: previousPerformance,
    });
    if (previousScheduler === undefined) delete globalThis.scheduler;
    else globalThis.scheduler = previousScheduler;
  }
});
