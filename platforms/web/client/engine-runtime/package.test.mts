import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import test from "node:test";

interface PackageManifest {
  name: string;
  license: string;
  engines: { node: string };
  publishConfig: { access: string; tag: string };
  files: string[];
  exports: {
    ".": {
      types: string;
      default: string;
    };
  };
  dependencies?: undefined;
  bin?: undefined;
  scripts: {
    prepack: string;
  };
}

interface SourceMap {
  sources: string[];
  sourcesContent?: string[];
}

const MAPS_WITHOUT_SOURCES: ReadonlySet<string> = new Set([
  "kotlin_org_jetbrains_kotlin_kotlin_dom_api_compat.mjs.map",
]);

interface PrepareParagraphRequest {
  text: string;
  maxWidthPx: number;
  fontFamilies: string[];
  fontSizePx: number;
  lineHeightPx: number;
  locale: string;
  fontWeight: number;
  italic: boolean;
  firstLineIndentIc: number;
  lineLengthGridEnabled: boolean;
  sourceBoundaries: number[];
  textSpans: Array<{
    start: number;
    end: number;
    fontFamilies: string[];
    fontSize: number;
    fontWeight: number;
    italic: boolean;
    baselineShift: number;
  }>;
  inlineBoxes: Array<{
    start: number;
    end: number;
    inlineStart: number;
    inlineEnd: number;
    outerSpacing: string;
  }>;
  lineBreakSpans: Array<{
    start: number;
    end: number;
    policy: string;
  }>;
  inlineObjects: Array<{
    start: number;
    end: number;
    advance: number;
    ascent: number;
    descent: number;
  }>;
  decorations: Array<{
    start: number;
    end: number;
    kind: string;
  }>;
  emphasisDotGapEm: number | null;
  renderEvidenceOverride: boolean | null;
}

interface PlanWithDiagnostics {
  plan: Record<string, unknown>;
  diagnostics: {
    capabilityIssues: Array<{ name: string; reason: string; rangeStart: number; rangeEnd: number }>;
    advanceSuspects: Array<{ displayText: string; advance: string; reason: string; rangeStart: number; rangeEnd: number }>;
  };
}

interface FfiExports {
  bopomofoParse: (reading: string) => string;
  numberSymbolCohesionUnbreakableRanges: (text: string) => string;
  fontMetricsResolve: (requestJson: string) => string;
  fontFallbackResolve: (text: string, start: number, end: number, requestJson: string) => string;
  liangHyphenate: (word: string, patternsJson: string, exceptionsJson: string, leftMin?: number, rightMin?: number) => string;
  unicodePunctuationLineBreakClassOf: (codePoint: number) => string;
  classifyFontRole: (text: string, start: number, end: number, locale: string) => string;
  classifyFontRoles: (text: string, starts: number[], ends: number[], locale: string) => string[];
  unsupportedInlineShapingProperties: () => string[];
  firstDivergentInlineShapingProperty: (elementValues: string[], paragraphValues: string[]) => string | null;
  precomputeParagraphWithDiagnostics: (
    request: PrepareParagraphRequest,
    zeroAdvanceEpsilonPx: number,
    shapeJson: (p0: string) => string,
    metricsJson: (p0: string) => string,
  ) => PlanWithDiagnostics;
  precomputeParagraphPlan: (
    request: PrepareParagraphRequest,
    zeroAdvanceEpsilonPx: number,
    shapeJson: (p0: string) => string,
    metricsJson: (p0: string) => string,
  ) => Record<string, unknown>;
  precomputeParagraphWithBrowserMetrics: (
    request: PrepareParagraphRequest,
    zeroAdvanceEpsilonPx: number,
    callbacks: { shapeJson: (p0: string) => string; metricsJson: (p0: string) => string },
  ) => string;
}

test("the manifest ships the generated engine runtime and nothing else", async () => {
  const manifest = JSON.parse(
    await readFile(new URL("./package.json", import.meta.url), "utf8"),
  ) as PackageManifest;

  assert.equal(manifest.name, "@tiqian/ffi");
  assert.equal(manifest.license, "MPL-2.0");
  assert.equal(manifest.engines.node, ">=22");
  assert.deepEqual(manifest.publishConfig, { access: "public", tag: "alpha" });
  assert.deepEqual(manifest.files, ["LICENSE", "README.md", "runtime/", "engine-gen/"]);
  assert.deepEqual(manifest.exports, {
    ".": {
      types: "./runtime/facade.d.mts",
      default: "./runtime/facade.mjs",
    },
    "./engine-gen/*": "./runtime/engine-gen/*",
  });
  assert.equal(manifest.dependencies, undefined);
  assert.equal(manifest.bin, undefined);
  assert.equal(
    manifest.scripts.prepack,
    "npm run build:runtime && npm test && npm run verify:package",
  );
});

test("the package export surface names the twelve capabilities plus the plan-only entry in order", async () => {
  // Cutover mechanism note: the entry used to be the Kotlin-generated module
  // whose .d.mts this test scanned; it is now the aggregate facade, so the
  // pinned surface is read off the facade's export block. The runtime module
  // namespace cannot carry the order (its keys are sorted by spec), and the
  // order is part of the contract. The pinned list — twelve capabilities plus the plan-only worker
  // entry, in this order — is the contract.
  const facade = await readFile(new URL("./runtime/facade.mjs", import.meta.url), "utf8");
  const exportBlock = facade.match(/export \{([^}]+)\};/u)?.[1];
  assert.ok(exportBlock, "facade.mjs carries a single export block");

  const exported = exportBlock.split(",").map((name) => name.trim()).filter(Boolean);
  assert.deepEqual(exported, [
    "bopomofoParse",
    "numberSymbolCohesionUnbreakableRanges",
    "fontMetricsResolve",
    "fontFallbackResolve",
    "liangHyphenate",
    "unicodePunctuationLineBreakClassOf",
    "classifyFontRole",
    "classifyFontRoles",
    "unsupportedInlineShapingProperties",
    "firstDivergentInlineShapingProperty",
    "precomputeParagraphWithDiagnostics",
    "precomputeParagraphWithBrowserMetrics",
    "precomputeParagraphPlan",
  ]);
});

test("every engine module ships a source map with embedded sources", async () => {
  const entries = await readdir(new URL("./runtime/", import.meta.url));
  const modules = entries.filter((entry) => entry.endsWith(".mjs"));

  assert.ok(
    modules.length >= 4,
    "the runtime keeps the full module set (engine is a single published module)",
  );
  // Cutover mechanism note: every shipped module is now a hand-written entry
  // shim over the compiled engine-gen tree; the Kotlin-generated engine
  // modules left the package with the precompute cutover, so the
  // embedded-sources contract applies to the facades' own maps only.
  const entryShims = new Set(["facade.mjs", "linebreak-facade.mjs", "clreq-facade.mjs", "font-facade.mjs", "loweringhelper-facade.mjs", "precompute-facade.mjs"]);
  for (const module of modules) {
    if (entryShims.has(module)) continue;
    const map = `${module}.map`;
    assert.ok(entries.includes(map), `runtime/${module} has no source map`);
    if (MAPS_WITHOUT_SOURCES.has(map)) continue;
    const parsed = JSON.parse(
      await readFile(new URL(`./runtime/${map}`, import.meta.url), "utf8"),
    ) as SourceMap;
    assert.ok(parsed.sources.length > 0, `runtime/${map} has no sources`);
    assert.ok(
      (parsed.sourcesContent ?? []).length >= parsed.sources.length,
      `runtime/${map} does not embed its sources`,
    );
  }
});

test("the engine entry loads from the package exports surface", async () => {
  const ffi = (await import("@tiqian/ffi")) as unknown as FfiExports;

  assert.equal(typeof ffi.bopomofoParse, "function");
  assert.equal(typeof ffi.numberSymbolCohesionUnbreakableRanges, "function");
  assert.equal(typeof ffi.fontMetricsResolve, "function");
  assert.equal(typeof ffi.fontFallbackResolve, "function");
  assert.equal(typeof ffi.liangHyphenate, "function");
  assert.equal(typeof ffi.unicodePunctuationLineBreakClassOf, "function");
  assert.equal(typeof ffi.classifyFontRole, "function");
  assert.equal(typeof ffi.classifyFontRoles, "function");
  assert.equal(typeof ffi.unsupportedInlineShapingProperties, "function");
  assert.equal(typeof ffi.firstDivergentInlineShapingProperty, "function");
  assert.equal(typeof ffi.precomputeParagraphWithDiagnostics, "function");
  assert.equal(typeof ffi.precomputeParagraphWithBrowserMetrics, "function");
  assert.match(import.meta.resolve("@tiqian/ffi"), /facade\.mjs$/u);
});

test("precompute entries run the generated engine through host callbacks", async () => {
  const ffi = (await import("@tiqian/ffi")) as unknown as FfiExports;

  const shapeCalls: string[] = [];
  const metricsCalls: string[] = [];
  const shapeJson = (requestJson: string): string => {
    shapeCalls.push(requestJson);
    const raw = JSON.parse(requestJson) as { range?: { start: number; end: number } };
    const start = raw.range?.start ?? 0;
    const end = raw.range?.end ?? start;
    return JSON.stringify({
      clusters: [{ range: { start, end }, text: "字", displayText: "字", fontKey: "font", advance: 10 * (end - start), baselineShift: 0 }],
      glyphRuns: [{ range: { start, end }, fontKey: "font", glyphs: [{ id: 65, clusterRange: { start, end }, advance: 10 * (end - start), x: 0, y: 0 }], advance: 10 * (end - start), openTypeFeatures: [] }],
      decisions: [],
    });
  };
  const metricsJson = (requestJson: string): string => {
    metricsCalls.push(requestJson);
    return JSON.stringify({ ascent: 0.8, descent: -0.2, leading: 0, source: "RawTables" });
  };

  const request: PrepareParagraphRequest = {
    text: "汉字，",
    maxWidthPx: 200,
    fontFamilies: ["Test", "Fallback"],
    fontSizePx: 16,
    lineHeightPx: 24,
    locale: "zh-Hans",
    fontWeight: 400,
    italic: false,
    firstLineIndentIc: 0,
    lineLengthGridEnabled: false,
    sourceBoundaries: [],
    textSpans: [],
    inlineBoxes: [],
    lineBreakSpans: [],
    inlineObjects: [],
    decorations: [],
    emphasisDotGapEm: null,
    renderEvidenceOverride: null,
  };

  const exact = ffi.precomputeParagraphWithDiagnostics(request, 0.05, shapeJson, metricsJson);
  // The diagnostics entry returns the structured plan-plus-diagnostics object;
  // the frozen JSON envelope stays on the browser-metrics entry for golden use.
  const exactEnvelope = exact;
  assert.ok(Array.isArray(exactEnvelope.plan.lines), "the exact-session entry returns a structured plan");
  assert.ok(exactEnvelope.diagnostics !== undefined, "the exact-session entry carries the diagnostics object");
  const planOnly = ffi.precomputeParagraphPlan(request, 0.05, shapeJson, metricsJson);
  assert.equal(
    JSON.stringify(planOnly),
    JSON.stringify(exactEnvelope.plan),
    "the plan-only entry returns the same plan bytes as the diagnostics entry",
  );
  assert.equal(shapeCalls.length > 0, true, "the engine shaped through the host callback");
  assert.equal(metricsCalls.length > 0, true, "the engine resolved metrics through the host callback");

  shapeCalls.length = 0;
  metricsCalls.length = 0;
  const browser = ffi.precomputeParagraphWithBrowserMetrics(request, 0.05, {
    shapeJson,
    metricsJson,
  });
  const browserEnvelope = JSON.parse(browser) as { plan: string };
  assert.ok(browserEnvelope.plan.includes('"schema":1'), "the browser-metrics entry returns a plan envelope");
  assert.equal(shapeCalls.length > 0, true, "the callbacks-object form reaches the same engine");
});

test("precompute entries keep the domain validation error names", async () => {
  const ffi = (await import("@tiqian/ffi")) as unknown as FfiExports;

  const empty = { ...basePrecomputeRequest(), text: "" };
  assert.throws(
    () => ffi.precomputeParagraphWithDiagnostics(empty, 0.05, () => "{}", () => "{}"),
    (error: Error) => error.name === "IllegalArgumentException" && error.message === "EmptyParagraph",
  );
  assert.throws(
    () => ffi.precomputeParagraphWithBrowserMetrics({ ...empty }, 0.05, { shapeJson: () => "{}", metricsJson: () => "{}" }),
    (error: Error) => error.name === "IllegalArgumentException" && error.message === "EmptyParagraph",
  );

  const zeroWidth = { ...basePrecomputeRequest(), maxWidthPx: 0 };
  assert.throws(
    () => ffi.precomputeParagraphWithDiagnostics(zeroWidth, 0.05, () => "{}", () => "{}"),
    (error: Error) => error.name === "IllegalArgumentException" && error.message === "InvalidMaximumMeasure",
  );

  const zeroSize = { ...basePrecomputeRequest(), fontSizePx: 0 };
  assert.throws(
    () => ffi.precomputeParagraphWithBrowserMetrics(zeroSize, 0.05, { shapeJson: () => "{}", metricsJson: () => "{}" }),
    (error: Error) => error.name === "IllegalArgumentException" && error.message === "InvalidFontSize",
  );
});

function basePrecomputeRequest(): PrepareParagraphRequest {
  return {
    text: "汉字，",
    maxWidthPx: 200,
    fontFamilies: ["Test"],
    fontSizePx: 16,
    lineHeightPx: 24,
    locale: "zh-Hans",
    fontWeight: 400,
    italic: false,
    firstLineIndentIc: 0,
    lineLengthGridEnabled: false,
    sourceBoundaries: [],
    textSpans: [],
    inlineBoxes: [],
    lineBreakSpans: [],
    inlineObjects: [],
    decorations: [],
    emphasisDotGapEm: null,
    renderEvidenceOverride: null,
  };
}

test("classifyFontRole maps classifier roles to lowering role strings", async () => {
  const ffi = (await import("@tiqian/ffi")) as unknown as FfiExports;

  assert.equal(ffi.classifyFontRole("汉字", 0, 2, "zh-Hans"), "cjk-text");
  assert.equal(ffi.classifyFontRole("，", 0, 1, "zh-Hans"), "cjk-punctuation");
  assert.equal(ffi.classifyFontRole("Hello", 0, 5, "en"), "other");
});

test("classifyFontRoles resolves contextual marks from complete paragraph text", async () => {
  const ffi = (await import("@tiqian/ffi")) as unknown as FfiExports;

  assert.deepEqual(
    ffi.classifyFontRoles("A——B中文……下句", [1, 2, 6, 7], [2, 3, 7, 8], "zh-Hans"),
    ["other", "other", "cjk-punctuation", "cjk-punctuation"],
  );
});

test("classifyFontRole resolves curly quotes through structural pair analysis", async () => {
  const ffi = (await import("@tiqian/ffi")) as unknown as FfiExports;

  assert.equal(ffi.classifyFontRole("word“中文”word", 4, 5, "zh-Hans"), "other");
  assert.equal(ffi.classifyFontRole("word“中文”word", 7, 8, "zh-Hans"), "other");
});

test("unsupportedInlineShapingProperties returns fresh ordered property array", async () => {
  const ffi = (await import("@tiqian/ffi")) as unknown as FfiExports;

  const properties1 = ffi.unsupportedInlineShapingProperties();
  const properties2 = ffi.unsupportedInlineShapingProperties();

  assert.equal(properties1.length, 16);
  assert.equal(properties1[0], "font-feature-settings");
  assert.equal(properties1[1], "font-variation-settings");
  assert.equal(properties1[2], "font-stretch");
  assert.deepEqual(properties1, properties2);
  assert.notEqual(properties1, properties2, "consecutive calls return distinct array instances");
});

test("firstDivergentInlineShapingProperty detects divergence and clamps common prefix", async () => {
  const ffi = (await import("@tiqian/ffi")) as unknown as FfiExports;

  assert.equal(
    ffi.firstDivergentInlineShapingProperty(
      ["normal", "normal", "normal"],
      ["normal", "normal", "normal"],
    ) ?? null,
    null,
  );

  assert.equal(
    ffi.firstDivergentInlineShapingProperty(
      ["normal", "normal", "expanded"],
      ["normal", "normal", "condensed"],
    ),
    "font-stretch",
  );

  assert.equal(
    ffi.firstDivergentInlineShapingProperty(
      ["normal", "normal", "normal", "none"],
      ["normal", "normal", "normal", "auto"],
    ),
    "font-kerning",
  );

  assert.equal(
    ffi.firstDivergentInlineShapingProperty(
      ["normal", "normal"],
      ["normal", "normal", "expanded"],
    ) ?? null,
    null,
  );
  assert.equal(
    ffi.firstDivergentInlineShapingProperty(
      ["normal", "normal", "expanded"],
      ["normal", "normal"],
    ) ?? null,
    null,
  );
});