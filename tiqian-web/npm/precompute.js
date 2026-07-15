import { createHash } from "node:crypto";

import { createBuildFontSession } from "./precompute-node-fonts.js";
import { renderPreparedParagraphArtifact } from "./prepared-dom.js";
import { compactSnapshotManifest } from "./snapshot-manifest.js";
import {
  normalizeSnapshotSemantics,
  snapshotSemanticMetricContractIssue,
  snapshotSourceArtifactString,
} from "./snapshot-source.js";
import {
  FONT_SOURCE_POLICY,
  LAYOUT_REVISION,
  RENDER_REVISION,
  SNAPSHOT_SCHEMA,
  stableStringify,
} from "./snapshot-schema.js";

const FAMILY_SEPARATOR = "\u001f";
const RECORD_SEPARATOR = "\u001e";
const FIELD_SEPARATOR = "\u001d";
const PLAIN_PARAGRAPH_SELECTOR = "p[data-tq-snapshot-key]";
const SNAPSHOT_LOCALE = "zh-Hans";
const PARAGRAPH_CAPABILITY_ISSUES = [
  "NoExactFontFace",
  "MissingGlyph",
  "NoExactMetricFace",
  "NonUniformUnicodeRangeMetrics",
  "MissingShapingFontEvidence",
  "EmptyParagraph",
  "SnapshotRenderFlowMismatch",
];
const SEMANTIC_CAPABILITY_ISSUES = [
  "UnsupportedSnapshotSemanticAttribute",
  "UnsupportedSnapshotSemanticTag",
  "UnsafeSnapshotSemanticHref",
  "CrossingSnapshotSemanticRanges",
];
let runtimePromise;

function loadPrecomputeRuntime() {
  runtimePromise ??= import("./precompute-runtime/Tiqian-tiqian-web-precompute.mjs");
  return runtimePromise;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function paragraphCapabilityIssue(error) {
  const message = String(error instanceof Error ? error.message : error);
  return PARAGRAPH_CAPABILITY_ISSUES.find((issue) => message.includes(issue)) ?? null;
}

function semanticCapabilityIssue(error) {
  const message = String(error instanceof Error ? error.message : error);
  return SEMANTIC_CAPABILITY_ISSUES.find((issue) => message.includes(issue)) ?? null;
}

function unsupportedParagraph(key, issue, error = null) {
  const detail = error == null ? undefined : String(error instanceof Error ? error.message : error);
  return Object.freeze({ status: "unsupported", key, issue, ...(detail ? { detail } : {}) });
}

function normalizeTypography(value = {}) {
  const fontFamilies = Array.isArray(value.fontFamilies)
    ? value.fontFamilies.map(String).map((family) => family.trim()).filter(Boolean)
    : [];
  if (fontFamilies.length === 0) throw new Error("MissingExplicitFontFamilies");
  const fontSizePx = Number(value.fontSizePx);
  const lineHeightPx = Number(value.lineHeightPx);
  const fontWeight = Number(value.fontWeight ?? 400);
  const firstLineIndentIc = Number(value.firstLineIndentIc ?? 0);
  if (!Number.isFinite(fontSizePx) || fontSizePx <= 0) throw new Error("InvalidFontSize");
  if (!Number.isFinite(lineHeightPx) || lineHeightPx <= 0) throw new Error("InvalidLineHeight");
  if (!Number.isInteger(fontWeight) || fontWeight < 1 || fontWeight > 1000) {
    throw new Error("InvalidFontWeight");
  }
  if (!Number.isFinite(firstLineIndentIc) || firstLineIndentIc !== 0) {
    throw new Error("UnsupportedSnapshotFirstLineIndent");
  }
  if (Number(value.letterSpacingPx ?? 0) !== 0) throw new Error("UnsupportedLetterSpacing");
  const locale = String(value.locale ?? SNAPSHOT_LOCALE);
  if (locale !== SNAPSHOT_LOCALE) throw new Error("UnsupportedSnapshotLocale");
  if (value.lineLengthGridEnabled === false) throw new Error("UnsupportedSnapshotLineLengthGrid");
  if (value.fontFeatureSettings != null && value.fontFeatureSettings !== "normal") {
    throw new Error("UnsupportedFontFeatureSettings");
  }
  if (value.fontVariationSettings != null && value.fontVariationSettings !== "normal") {
    throw new Error("UnsupportedFontVariationSettings");
  }
  const fontVariantNumeric = String(value.fontVariantNumeric ?? "normal");
  if (fontVariantNumeric !== "normal" && fontVariantNumeric !== "lining-nums") {
    throw new Error("UnsupportedFontVariantNumeric");
  }
  return Object.freeze({
    fontFamilies,
    fontSizePx,
    lineHeightPx,
    locale,
    fontWeight,
    italic: value.italic === true,
    firstLineIndentIc,
    lineLengthGridEnabled: true,
    letterSpacingPx: 0,
    fontFeatureSettings: "normal",
    fontVariationSettings: "normal",
    fontVariantNumeric,
  });
}

function validRange(text, value, issue) {
  const start = Number(value?.start);
  const end = Number(value?.end);
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) ||
      start < 0 || end <= start || end > text.length) throw new Error(issue);
  return { start, end };
}

function normalizeTextSpans(text, value, typography) {
  if (value == null) return Object.freeze([]);
  if (!Array.isArray(value)) throw new Error("InvalidSnapshotTextSpans");
  return Object.freeze(value.map((span) => {
    const range = validRange(text, span, "InvalidSnapshotTextSpanRange");
    const fontFamilies = Array.isArray(span.fontFamilies)
      ? span.fontFamilies.map(String).map((family) => family.trim()).filter(Boolean)
      : typography.fontFamilies;
    const fontSizePx = Number(span.fontSizePx ?? typography.fontSizePx);
    const fontWeight = Number(span.fontWeight ?? typography.fontWeight);
    const baselineShiftPx = Number(span.baselineShiftPx ?? 0);
    if (fontFamilies.length === 0 || fontFamilies.some((family) =>
      family.includes(FAMILY_SEPARATOR) || family.includes(FIELD_SEPARATOR) ||
      family.includes(RECORD_SEPARATOR))) throw new Error("InvalidSnapshotTextSpanFontFamilies");
    if (!Number.isFinite(fontSizePx) || fontSizePx <= 0) throw new Error("InvalidSnapshotTextSpanFontSize");
    if (!Number.isSafeInteger(fontWeight) || fontWeight < 1 || fontWeight > 1000) {
      throw new Error("InvalidSnapshotTextSpanFontWeight");
    }
    if (!Number.isFinite(baselineShiftPx)) throw new Error("InvalidSnapshotTextSpanBaselineShift");
    return Object.freeze({
      ...range,
      fontFamilies: Object.freeze(fontFamilies),
      fontSizePx,
      fontWeight,
      italic: span.italic ?? typography.italic,
      baselineShiftPx,
    });
  }));
}

function normalizeInlineBoxes(text, value) {
  if (value == null) return Object.freeze([]);
  if (!Array.isArray(value)) throw new Error("InvalidSnapshotInlineBoxes");
  return Object.freeze(value.map((box) => {
    const range = validRange(text, box, "InvalidSnapshotInlineBoxRange");
    const inlineStartPx = Number(box.inlineStartPx ?? 0);
    const inlineEndPx = Number(box.inlineEndPx ?? 0);
    if (!Number.isFinite(inlineStartPx) || !Number.isFinite(inlineEndPx)) {
      throw new Error("InvalidSnapshotInlineBoxGeometry");
    }
    return Object.freeze({ ...range, inlineStartPx, inlineEndPx });
  }));
}

function encodedTextSpans(spans) {
  return spans.map((span) => [
    span.start,
    span.end,
    span.fontFamilies.join(FAMILY_SEPARATOR),
    span.fontSizePx,
    span.fontWeight,
    span.italic,
    span.baselineShiftPx,
  ].join(FIELD_SEPARATOR)).join(RECORD_SEPARATOR);
}

function encodedInlineBoxes(boxes) {
  return boxes.map((box) => [
    box.start,
    box.end,
    box.inlineStartPx,
    box.inlineEndPx,
  ].join(FIELD_SEPARATOR)).join(RECORD_SEPARATOR);
}

export function snapshotPlainTextIssue(text) {
  if (text.includes("\uFFFC")) return "UnsupportedInlineObject";
  if (text.includes("\u200D") || /[\uFE00-\uFE0F]/u.test(text)) return "UnsupportedEmojiSequence";
  if (/\p{Extended_Pictographic}/u.test(text)) return "UnsupportedEmojiFallback";
  if (/\p{Cf}/u.test(text) || /[\p{Cc}&&[^\n]]/v.test(text)) return "UnsupportedControlCharacter";
  if (Array.from(text).some((point) =>
    !/[\p{Script=Han}\p{Script=Common}A-Za-z\u00C0-\u024F]/u.test(point))) {
    return "UnsupportedSnapshotScript";
  }
  if (text.includes("—") || text.includes("⸺")) return "CjkDashRequiresBrowserFaceVerification";
  return null;
}

function escapeText(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function escapeAttribute(value) {
  return escapeText(value).replaceAll('"', "&quot;");
}

function cssString(value) {
  return `"${String(value).replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
}

function exactRenderFontStyle(id, renderFontFamilies) {
  const root = `:is(tiqian-prose,[data-tiqian-root])[snapshot-ref=${cssString(id)}]`;
  const prepared = `${root}[data-tiqian-exact-render-font=true]:not([data-tiqian-exact-layout-fallback]) [data-tq-rendered=true]`;
  return `${root}{--tq-exact-render-font-family:${renderFontFamilies.map(cssString).join(",")}}` +
    `${prepared}{font-family:var(--tq-exact-render-font-family)!important;` +
    `font-kerning:normal!important;font-optical-sizing:none!important}`;
}

function clientFontContractManifest(manifest) {
  const groups = new Map();
  for (const entry of [...manifest.entries, ...(manifest.fontContractEntries ?? [])]) {
    for (const evidence of entry.fontFaceEvidence) {
      let group = groups.get(evidence.faceRef);
      if (!group) {
        group = { coverage: new Set(), probes: new Map() };
        groups.set(evidence.faceRef, group);
      }
      for (const point of evidence.coverageText || evidence.probe?.text || "") {
        group.coverage.add(point);
      }
      const signature = stableStringify(evidence.probe);
      if (!group.probes.has(signature)) group.probes.set(signature, evidence.probe);
    }
  }
  let nextEntry = 0;
  const entries = [];
  for (const [faceRef, group] of groups) {
    for (const probe of group.probes.values()) {
      entries.push({
        key: `font-contract-${nextEntry++}`,
        sourceSha256: "0".repeat(64),
        typographyRef: 0,
        maxWidthPx: 1,
        fontFaceEvidence: [{
          faceRef,
          coverageText: Array.from(group.coverage).join(""),
          probe,
        }],
        renderArtifactSha256: "0".repeat(64),
      });
    }
  }
  if (entries.length === 0) throw new Error("SnapshotClientFontContractEmpty");
  const valueStyles = [];
  const { fontContractEntries: _fontContractEntries, ...baseManifest } = manifest;
  return {
    ...baseManifest,
    entrySource: "font-contract-v1",
    valueStyles,
    valueStylesSha256: sha256(stableStringify(valueStyles)),
    entries,
  };
}

export { renderPreparedParagraph } from "./prepared-dom.js";

export async function createPrecomputer(options = {}) {
  const typography = normalizeTypography(options.typography);
  const fontSession = await createBuildFontSession(options.faces, {
    baseFeatures: typography.fontVariantNumeric === "lining-nums" ? ["lnum"] : [],
  });
  const renderFontFamilies = fontSession.renderFamilies(typography.fontFamilies);
  let runtime;
  try {
    runtime = await loadPrecomputeRuntime();
  } catch (error) {
    fontSession.close();
    throw error;
  }
  let closed = false;
  const prepare = async (input, snapshotCandidate) => {
    if (closed) throw new Error("PrecomputerClosed");
    const key = String(input.key ?? "").trim();
    if (!key) throw new Error("MissingSnapshotKey");
    const text = String(input.text ?? "");
    let semantics;
    try {
      semantics = normalizeSnapshotSemantics(text, input.semantics ?? []);
    } catch (error) {
      const capabilityIssue = semanticCapabilityIssue(error);
      if (capabilityIssue) return unsupportedParagraph(key, capabilityIssue, error);
      throw error;
    }
    const semanticMetricIssue = snapshotSemanticMetricContractIssue(
      semantics,
      input.textSpans,
      input.inlineBoxes,
    );
    if (semanticMetricIssue) return unsupportedParagraph(key, semanticMetricIssue);
    const textSpans = normalizeTextSpans(text, input.textSpans, typography);
    const inlineBoxes = normalizeInlineBoxes(text, input.inlineBoxes);
    if (snapshotCandidate) {
      const issue = snapshotPlainTextIssue(text);
      if (issue) return unsupportedParagraph(key, issue);
    }
    const maxWidthPx = Number(input.maxWidthPx);
    if (!Number.isFinite(maxWidthPx) || maxWidthPx <= 0) throw new Error("InvalidMaximumMeasure");
    let plan;
    let fontEvidence;
    try {
      fontSession.beginCapture();
      const sourceBoundaries = new Set([
        ...(Array.isArray(input.sourceBoundaries) ? input.sourceBoundaries.map(Number) : []),
        ...semantics.flatMap((span) => [span.start, span.end]),
        ...textSpans.flatMap((span) => [span.start, span.end]),
        ...inlineBoxes.flatMap((span) => [span.start, span.end]),
        ...fontSession.sourceBoundaries(text, {
          fontFamilies: typography.fontFamilies,
          fontSizePx: typography.fontSizePx,
          fontWeight: typography.fontWeight,
          italic: typography.italic,
          baselineShiftPx: 0,
        }, textSpans),
      ]);
      if ([...sourceBoundaries].some((offset) =>
        !Number.isSafeInteger(offset) || offset < 0 || offset > text.length)) {
        throw new Error("InvalidSourceBoundary");
      }
      const serialized = runtime.precomputeParagraph(
        fontSession.id,
        text,
        maxWidthPx,
        typography.fontFamilies.join(FAMILY_SEPARATOR),
        typography.fontSizePx,
        typography.lineHeightPx,
        typography.locale,
        typography.fontWeight,
        typography.italic,
        typography.firstLineIndentIc,
        typography.lineLengthGridEnabled,
        [...sourceBoundaries].sort((left, right) => left - right).join(","),
        encodedTextSpans(textSpans),
        encodedInlineBoxes(inlineBoxes),
      );
      plan = JSON.parse(serialized);
      fontEvidence = fontSession.captureEvidence();
      if (fontEvidence.faces.length === 0) throw new Error("MissingShapingFontEvidence");
    } catch (error) {
      const capabilityIssue = paragraphCapabilityIssue(error);
      if (capabilityIssue) return unsupportedParagraph(key, capabilityIssue, error);
      throw error;
    }
    const typographySha256 = sha256(stableStringify(typography));
    let rendered;
    try {
      rendered = renderPreparedParagraphArtifact(plan, typography, {
        semantics,
        inlineBoxes,
        sourceText: text,
      });
    } catch (error) {
      const capabilityIssue = paragraphCapabilityIssue(error);
      if (capabilityIssue) return unsupportedParagraph(key, capabilityIssue, error);
      throw error;
    }
    return Object.freeze({
      status: "prepared",
      schema: SNAPSHOT_SCHEMA,
      layoutRevision: LAYOUT_REVISION,
      renderRevision: RENDER_REVISION,
      key,
      sourceText: text,
      sourceSha256: sha256(text),
      sourceArtifactSha256: sha256(snapshotSourceArtifactString(text, semantics)),
      semantics,
      inlineBoxes,
      typography,
      renderFontFamilies,
      typographySha256,
      maxWidthPx,
      fontEvidence,
      plan,
      html: rendered.html,
      renderArtifactSha256: sha256(stableStringify(rendered.artifact)),
    });
  };
  return Object.freeze({
    typography,
    renderFontFamilies,
    prepareParagraph: (input = {}) => prepare(input, true),
    prepareFontContract: (input = {}) => prepare(input, false),
    close() {
      if (closed) return;
      closed = true;
      fontSession.close();
    },
  });
}

function buildSnapshotBundle(preparedParagraphs, options = {}) {
  const entries = Array.from(preparedParagraphs ?? []);
  const fontContractEntries = Array.from(options.fontContractParagraphs ?? []);
  const contractCorpus = [...entries, ...fontContractEntries];
  if (entries.length === 0) throw new Error("MissingPreparedParagraphs");
  if (contractCorpus.some((entry) => entry.status !== "prepared")) {
    throw new Error("SnapshotTemplateContainsUnsupportedParagraph");
  }
  if (contractCorpus.some((entry) =>
    entry.schema !== SNAPSHOT_SCHEMA || entry.layoutRevision !== LAYOUT_REVISION ||
    entry.renderRevision !== RENDER_REVISION || typeof entry.renderArtifactSha256 !== "string")) {
    throw new Error("SnapshotTemplateContainsStalePreparedParagraph");
  }
  const keys = contractCorpus.map((entry) => entry.key);
  if (new Set(keys).size !== keys.length) throw new Error("DuplicateSnapshotKey");
  const renderFontFamilies = entries[0].renderFontFamilies;
  if (!Array.isArray(renderFontFamilies) || renderFontFamilies.length === 0 ||
      renderFontFamilies.some((family) => typeof family !== "string" || !family.trim())) {
    throw new Error("MissingExactRenderFontFamilies");
  }
  const renderFamilySignature = stableStringify(renderFontFamilies);
  if (contractCorpus.some((entry) =>
    stableStringify(entry.renderFontFamilies) !== renderFamilySignature)) {
    throw new Error("SnapshotRenderFontFamilyConflict");
  }
  const id = String(options.id ?? "").trim();
  if (!id) throw new Error("MissingSnapshotTemplateId");
  if (!/^[A-Za-z][A-Za-z0-9_-]*$/u.test(id)) throw new Error("InvalidSnapshotTemplateId");
  const paragraphSelector = String(options.paragraphSelector ?? PLAIN_PARAGRAPH_SELECTOR);
  if (paragraphSelector !== PLAIN_PARAGRAPH_SELECTOR) {
    throw new Error("UnsupportedSnapshotParagraphSelector");
  }
  const valueStyles = [];
  const valueStyleIndexes = new Map();
  const styleClassFor = (declaration) => {
    const existing = valueStyleIndexes.get(declaration);
    if (existing != null) return `tqv-${existing.toString(36)}`;
    const index = valueStyles.length;
    valueStyles.push(declaration);
    valueStyleIndexes.set(declaration, index);
    return `tqv-${index.toString(36)}`;
  };
  const renderedEntries = entries.map((entry) => {
    const rendered = renderPreparedParagraphArtifact(entry.plan, entry.typography, {
      styleClassFor,
      semantics: entry.semantics,
      inlineBoxes: entry.inlineBoxes,
      sourceText: entry.sourceText,
    });
    return {
      ...entry,
      html: rendered.html,
      renderArtifactSha256: sha256(stableStringify(rendered.artifact)),
    };
  });
  const compactCorpus = compactSnapshotManifest(
    [...renderedEntries, ...fontContractEntries],
    {
      schema: SNAPSHOT_SCHEMA,
      layoutRevision: LAYOUT_REVISION,
      renderRevision: RENDER_REVISION,
      fontSourcePolicy: FONT_SOURCE_POLICY,
      paragraphSelector,
      valueStyles,
      valueStylesSha256: sha256(stableStringify(valueStyles)),
      renderFontFamilies,
    },
  );
  const manifest = fontContractEntries.length === 0 ? compactCorpus : {
    ...compactCorpus,
    entries: compactCorpus.entries.slice(0, renderedEntries.length),
    fontContractEntries: compactCorpus.entries.slice(renderedEntries.length),
  };
  const manifestJson = JSON.stringify(manifest).replaceAll("<", "\\u003c");
  const body = renderedEntries.map((entry) =>
    `<div data-tq-entry="${escapeAttribute(entry.key)}">${entry.html}</div>`).join("");
  const inertTemplate = `<template id="${escapeAttribute(id)}" data-tq-snapshot-schema="${SNAPSHOT_SCHEMA}" ` +
    `data-tq-layout-revision="${LAYOUT_REVISION}" data-tq-render-revision="${RENDER_REVISION}" ` +
    `data-pagefind-ignore><script type="application/json" data-tq-snapshot-manifest>${manifestJson}</script>${body}</template>`;
  const serverManifestJson = JSON.stringify({
    ...manifest,
    entrySource: "server-dom-v1",
  }).replaceAll("<", "\\u003c");
  const template = `<template id="${escapeAttribute(id)}" data-tq-snapshot-schema="${SNAPSHOT_SCHEMA}" ` +
    `data-tq-layout-revision="${LAYOUT_REVISION}" data-tq-render-revision="${RENDER_REVISION}" ` +
    `data-pagefind-ignore><script type="application/json" data-tq-snapshot-manifest>${serverManifestJson}</script></template>`;
  // RuntimeSemanticFontContract: prepared DOM remains limited to canonical
  // plain paragraphs, while the browser exact session must also cover text
  // that is replayed through semantic DOM (links, code siblings, etc.).
  const clientManifestJson = JSON.stringify(clientFontContractManifest(manifest))
    .replaceAll("<", "\\u003c");
  const clientTemplate = `<template id="${escapeAttribute(id)}" data-tq-snapshot-schema="${SNAPSHOT_SCHEMA}" ` +
    `data-tq-layout-revision="${LAYOUT_REVISION}" data-tq-render-revision="${RENDER_REVISION}" ` +
    `data-pagefind-ignore><script type="application/json" data-tq-snapshot-manifest>${clientManifestJson}</script></template>`;
  const initialStyle = exactRenderFontStyle(id, renderFontFamilies) + valueStyles.map((declaration, index) =>
    `tiqian-prose[snapshot-ref="${escapeAttribute(id)}"] [data-tq-rendered="true"] .tqv-${index.toString(36)}{${declaration}}`
  ).join("");
  // FirstPreparedParagraphFontPreload: a CJK article can touch dozens of
  // unicode-range subsets. Preloading the whole article promotes every
  // below-fold face to critical bandwidth; the first prepared paragraph is
  // the bounded evidence set needed for the initial prose viewport. Remaining
  // faces keep their content-addressed @font-face demand-loading contract.
  const fontPreloads = Array.from(new Set(renderedEntries[0].fontEvidence.faces
    .map((face) => face.publicUrl)
    .filter((url) => typeof url === "string" && url.length > 0)));
  return Object.freeze({
    id,
    template,
    clientTemplate,
    inertTemplate,
    initialStyle,
    renderFontFamilies: Object.freeze([...renderFontFamilies]),
    fontPreloads: Object.freeze(fontPreloads),
    rootAttributes: Object.freeze({ "data-tiqian-exact-render-font": "true" }),
    entries: Object.freeze(renderedEntries.map((entry) => Object.freeze({
      key: entry.key,
      html: entry.html,
    }))),
  });
}

/**
 * Produces an inert prepared-DOM template plus the compact manifests used by
 * server and client-navigation adapters. Responsive SSR should inject
 * `inertTemplate` without replacing the keyed source paragraphs; the custom
 * element adopts it only after validating live geometry and font evidence.
 */
export function renderSnapshotBundle(preparedParagraphs, options = {}) {
  return buildSnapshotBundle(preparedParagraphs, options);
}

export function renderSnapshotTemplate(preparedParagraphs, options = {}) {
  return buildSnapshotBundle(preparedParagraphs, options).inertTemplate;
}
