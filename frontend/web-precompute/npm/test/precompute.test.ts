// Native-lane ports of the @tiqian/prose precompute suite (ADR 0050). The
// pure computation entries run wherever an addon build exists; the engine
// path additionally needs a local CJK font and covers both build flavors: a
// build without the engine archive reports PrecomputeEngineNotLinked.

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import type {
  CreatePrecomputerOptions,
  NormalizedTypography,
  PreparedEntry,
  PreparedParagraph,
  SnapshotTypography,
} from "../src/precompute.js";

type PrecomputeModule = typeof import("../src/precompute.js");

let precompute: PrecomputeModule | null = null;
try {
  precompute = (await import("../lib/precompute.js")) as PrecomputeModule;
} catch {
  precompute = null;
}

function readLocalFont(fileName: string): Buffer | null {
  try {
    return readFileSync(`${process.env.HOME}/.local/share/fonts/${fileName}`);
  } catch {
    return null; // no font available; the engine path needs a CJK-covering face
  }
}

/** The prepared branch of the `PreparedParagraph` union. */
type PreparedBranch = Extract<PreparedParagraph, { status: "prepared" }>;

const fixtureTypography = Object.freeze({
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
  fontVariantNumeric: "normal",
});

const baseTypography: SnapshotTypography = {
  fontFamilies: ["Fixture CJK"],
  fontSizePx: 18,
  lineHeightPx: 27,
};

// The runtime rejects values the public type rules out; js callers can still
// pass them, so the gates are tested through a widened patch.
function invalidTypography(patch: {
  locale?: string;
  lineLengthGridEnabled?: boolean;
  fontVariantNumeric?: string;
}): SnapshotTypography {
  return { ...baseTypography, ...patch } as SnapshotTypography;
}

function sha256(value: string | Buffer): string {
  return createHash("sha256").update(value).digest("hex");
}

// The binary table header: 8 magic bytes then twelve little-endian u32 counts.
function readTableHeader(bytes: Buffer) {
  const count = (index: number) => bytes.readUInt32LE(8 + index * 4);
  return {
    replayStringCount: count(0),
    stringCount: count(1),
    metricCount: count(2),
    metricValueCount: count(3),
    probeCount: count(4),
    probeAdvanceCount: count(5),
    probeStyleCount: count(6),
    probeFeatureCount: count(7),
    faceCount: count(8),
    typographyCount: count(9),
    valueStyleCount: count(10),
    fontPreloadCount: count(11),
  };
}

function fixturePlan(text: string) {
  return {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    lines: [{
      rangeStart: 0,
      rangeEnd: text.length,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: 36,
      hyphenAdvance: 0,
      endReason: "ParagraphEnd",
      cells: [{
        rangeStart: 0,
        rangeEnd: text.length,
        source: text,
        display: text,
        drawX: 0,
        naturalWidth: 36,
        leadingLayoutAdvance: 0,
      }],
    }],
  };
}

interface FixtureFace {
  faceId: string;
  sourceOrder: number;
  family: string;
  publicUrl: string;
  coverageText: string;
  probe: { text: string };
}

interface FixtureEvidence {
  backendRevision: string;
  harfbuzzVersion: string;
  faces: FixtureFace[];
  replay: { revision: string; shapes: never[]; metrics: never[] };
}

function fixtureEvidence(text: string, publicUrl: string): FixtureEvidence {
  return {
    backendRevision: "tiqian-shared-harfbuzz-v5",
    harfbuzzVersion: "fixture",
    faces: [{
      faceId: "fixture-face",
      sourceOrder: 0,
      family: "Fixture CJK",
      publicUrl,
      coverageText: text,
      probe: {
        text: text[0],
        advancePx: 16,
        fontSizePx: 16,
        fontWeight: 400,
        italic: false,
        script: "hani",
        language: "ZH",
        features: [],
      },
    }],
    replay: {
      revision: "tiqian-server-shaping-replay-v1",
      shapes: [],
      metrics: [],
    },
  };
}

function fixturePrepared(input: { key: string; text: string }): PreparedBranch {
  return {
    status: "prepared",
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v15",
    key: input.key,
    sourceText: input.text,
    sourceSha256: sha256(input.text),
    sourceArtifactSha256: sha256(JSON.stringify({ text: input.text, semantics: [] })),
    semantics: [],
    inlineBoxes: [],
    renderTextSpans: [],
    typographySha256: sha256(JSON.stringify(fixtureTypography)),
    maxWidthPx: 360,
    typography: fixtureTypography,
    renderFontFamilies: ["Snapshot Sans"],
    fontEvidence: fixtureEvidence(input.text, "/fonts/fixture-deadbeef.woff2"),
    plan: fixturePlan(input.text),
    html: "",
    renderArtifactSha256: "c".repeat(64),
  };
}

function assertPrepared(entry: PreparedEntry): PreparedBranch {
  if (entry.status !== "prepared") {
    throw new Error(`expected a prepared entry, got issue ${entry.issue}`);
  }
  return entry;
}

test("v1 plain-text snapshots reject scripts whose browser shaping cannot be replayed exactly", { skip: precompute === null }, () => {
  assert.ok(precompute);
  assert.equal(precompute.snapshotPlainTextIssue("中文 Latin 123，。"), null);
  assert.equal(precompute.snapshotPlainTextIssue("Ελληνικά"), "UnsupportedSnapshotScript");
  assert.equal(precompute.snapshotPlainTextIssue("Блог"), "UnsupportedSnapshotScript");
  assert.equal(precompute.snapshotPlainTextIssue("ㄅㄆㄇ"), "UnsupportedSnapshotScript");
  assert.equal(precompute.snapshotPlainTextIssue("á"), "UnsupportedSnapshotScript");
  assert.equal(precompute.snapshotPlainTextIssue("ạ"), "UnsupportedSnapshotScript");
  assert.equal(precompute.snapshotPlainTextIssue("Ａ"), "UnsupportedSnapshotScript");
  assert.equal(precompute.snapshotPlainTextIssue("带—破折号"), "CjkDashRequiresBrowserFaceVerification");
});

test("snapshot template keeps the prepared DOM inert and Pagefind-ignored", { skip: precompute === null }, () => {
  assert.ok(precompute);
  const template = precompute.renderSnapshotTemplate([fixturePrepared({ key: "p-1", text: "正文" })], {
    id: "tq-page",
  });
  assert.match(template, /^<template /);
  assert.match(template, /data-pagefind-ignore/);
  assert.match(template, /data-tq-snapshot-manifest/);
  assert.match(template, /data-tq-entry="p-1"/);
  assert.doesNotMatch(template, / style=/u);
  assert.match(template, /class="tq-line tqv-0"/u);
});

test("snapshot bundle exposes compact SSR artifacts without inline geometry", { skip: precompute === null }, () => {
  assert.ok(precompute);
  const prepared = fixturePrepared({ key: "p-1", text: "正文" });
  const bundle = precompute.renderSnapshotBundle([prepared], { id: "tq-page" });

  assert.equal(bundle.id, "tq-page");
  assert.equal(bundle.entries.length, 1);
  assert.equal(bundle.entries[0].key, "p-1");
  assert.match(bundle.entries[0].html, /class="tq-line tqv-0"/u);
  assert.doesNotMatch(bundle.entries[0].html, / style=/u);
  assert.match(bundle.initialStyle, /SharedRuntimeGeometryCss/u);
  assert.match(bundle.initialStyle, /SharedLineMetricStrutCss/u);
  assert.match(bundle.initialStyle, /text-wrap-mode:\s*nowrap\s*!important/u);
  assert.match(bundle.initialStyle, /tiqian-prose\[snapshot-ref="tq-page"\]/u);
  assert.doesNotMatch(bundle.initialStyle, /font-family\s*:|--tq-.*render-font-family/u);
  assert.match(bundle.initialStyle, /font-kerning:normal!important;font-optical-sizing:none!important/u);
  assert.match(bundle.initialStyle, /\.tqv-0\{/u);
  assert.deepEqual(bundle.renderFontFamilies, ["Snapshot Sans"]);
  assert.deepEqual(bundle.fontPreloads, []);
  assert.deepEqual(bundle.rootAttributes, { "data-tiqian-exact-render-font": "true" });
  assert.match(bundle.template, /^<template /u);
  assert.equal(bundle.template, bundle.inertTemplate);
  assert.match(bundle.template, /:is\(p, li\)\[data-tq-snapshot-key\]/u);
  assert.match(bundle.template, /data-tq-entry=/u);
  assert.match(bundle.inertTemplate, /^<template /u);
  assert.match(bundle.inertTemplate, /data-tq-entry="p-1"/u);
  assert.doesNotMatch(bundle.inertTemplate, /server-dom-v1/u);
  assert.match(bundle.clientTemplate, /font-contract-v1/u);
  assert.doesNotMatch(bundle.clientTemplate, /data-tq-entry=/u);
  assert.ok(bundle.clientTemplate.length < bundle.template.length);

  const laterFace: PreparedBranch = {
    ...prepared,
    key: "p-2",
    sourceSha256: "d".repeat(64),
    fontEvidence: {
      ...fixtureEvidence("正文", "/fonts/fixture-deadbeef.woff2"),
      faces: [{
        ...fixtureEvidence("正文", "/fonts/fixture-deadbeef.woff2").faces[0],
        publicUrl: "/fonts/below-fold-deadbeef.woff2",
        coverageText: "后文",
        probe: { text: "后" },
      }],
    },
  };
  const boundedPreloads = precompute.renderSnapshotBundle([prepared, laterFace], {
    id: "tq-page-two",
  });
  assert.deepEqual(boundedPreloads.fontPreloads, []);

  const semanticContract = precompute.renderSnapshotBundle([prepared], {
    id: "tq-page-semantic",
    fontContractParagraphs: [laterFace],
  });
  assert.equal(semanticContract.entries.length, 1);
  assert.equal(semanticContract.entries[0].key, "p-1");
  assert.match(semanticContract.template, /fontContractEntries/u);
  assert.match(semanticContract.template, /below-fold-deadbeef/u);
  assert.match(semanticContract.clientTemplate, /below-fold-deadbeef/u);

  const fontContract = precompute.renderFontContractBundle([prepared], { id: "tq-font-contract" });
  assert.deepEqual(fontContract.entries, []);
  assert.deepEqual(fontContract.rootAttributes, {});
  assert.equal(fontContract.template, fontContract.clientTemplate);
  assert.equal(fontContract.inertTemplate, fontContract.clientTemplate);
  assert.match(fontContract.clientTemplate, /font-contract-v1/u);
  assert.match(fontContract.clientTemplate, /:is\(p, li\):not\(\[data-tiqian-skip\]\)/u);
  assert.doesNotMatch(fontContract.clientTemplate, /:is\(p, li\)\[data-tq-snapshot-key\]/u);
  assert.doesNotMatch(fontContract.initialStyle, /\.tqv-/u);
});

test("snapshot renderers reject invalid corpora and template ids by name", { skip: precompute === null }, () => {
  assert.ok(precompute);
  const prepared = fixturePrepared({ key: "p-1", text: "正文" });
  assert.throws(
    () => precompute.renderSnapshotBundle([], { id: "tq-page" }),
    /MissingPreparedParagraphs/u,
  );
  assert.throws(
    () => precompute.renderSnapshotBundle([prepared], { id: "" }),
    /MissingSnapshotTemplateId/u,
  );
  assert.throws(
    () => precompute.renderSnapshotBundle([prepared], { id: "1x" }),
    /InvalidSnapshotTemplateId/u,
  );
  assert.throws(
    () => precompute.renderSnapshotBundle([prepared, prepared], { id: "tq-page" }),
    /DuplicateSnapshotKey/u,
  );
  const stale: PreparedBranch = { ...prepared, renderRevision: "prebroken-dom-v0" };
  assert.throws(
    () => precompute.renderSnapshotTemplate([stale], { id: "tq-stale" }),
    /SnapshotTemplateContainsStalePreparedParagraph/u,
  );
  const selector = ".paragraph[data-tq-snapshot-key]";
  assert.throws(
    () => precompute.renderSnapshotTemplate([prepared], {
      id: "tq-custom-selector",
      paragraphSelector: selector as ":is(p, li)[data-tq-snapshot-key]",
    }),
    /UnsupportedSnapshotParagraphSelector/u,
  );
});

test("split render assembles per-article bundles against one frozen table", { skip: precompute === null }, () => {
  assert.ok(precompute);
  const first = fixturePrepared({ key: "p-1", text: "正文" });
  const second = fixturePrepared({ key: "p-2", text: "后文" });
  const tables = precompute.createSnapshotTables();
  precompute.absorbSnapshotTables(tables, [first, second]);

  const dataFirst = precompute.renderSnapshotBundleData([first], {
    id: "tq-page-a",
    snapshotTables: tables,
  });
  const dataSecond = precompute.renderSnapshotBundleData([second], {
    id: "tq-page-b",
    snapshotTables: tables,
  });
  // Assembly needs the frozen rows; the data phase left the table mutable.
  assert.throws(
    () => precompute.assembleSnapshotBundle(dataFirst, tables),
    /SnapshotTablesNotFinalized/u,
  );

  const file = precompute.finalizeSnapshotTables(tables);
  assert.equal(file.bytes.subarray(0, 8).toString("latin1"), "TIQTBL03");
  assert.equal(file.sha256, sha256(file.bytes));
  const header = readTableHeader(file.bytes);
  // Both articles share one face row; each distinct probe keeps its own row.
  assert.equal(header.faceCount, 1);
  assert.equal(header.probeCount, 2);

  const bundleFirst = precompute.assembleSnapshotBundle(dataFirst, tables);
  const bundleSecond = precompute.assembleSnapshotBundle(dataSecond, tables);
  for (const bundle of [bundleFirst, bundleSecond]) {
    assert.equal(bundle.entries.length, 1);
    assert.match(bundle.entries[0].html, /class="tq-line tqv-0"/u);
    assert.match(bundle.initialStyle, /\.tqv-0\{/u);
    // Value styles stay table-scoped: the manifest carries the table
    // reference instead of a per-article valueStyles array.
    assert.doesNotMatch(bundle.template, /valueStyles/u);
    assert.match(bundle.template, new RegExp(file.sha256, "u"));
    assert.match(bundle.clientTemplate, /font-contract-v1/u);
    assert.match(bundle.clientTemplate, /probeRef/u);
  }
  assert.equal(bundleFirst.entries[0].key, "p-1");
  assert.equal(bundleSecond.entries[0].key, "p-2");
  // The classes index the shared table rows, and the per-article snapshot
  // refs scope the first-paint rules to their own root.
  assert.match(bundleFirst.initialStyle, /snapshot-ref="tq-page-a"/u);
  assert.match(bundleSecond.initialStyle, /snapshot-ref="tq-page-b"/u);

  // A restored table extends the union under one address across builds.
  const restored = precompute.restoreSnapshotTables(file.bytes);
  precompute.absorbSnapshotTablesMetadata(restored, { valueStyles: ["font-weight:700"] });
  const dataThird = precompute.renderSnapshotBundleData([first], {
    id: "tq-page-c",
    snapshotTables: restored,
  });
  const refile = precompute.finalizeSnapshotTables(restored);
  assert.notEqual(refile.sha256, file.sha256);
  const bundleThird = precompute.assembleSnapshotBundle(dataThird, restored);
  assert.match(bundleThird.initialStyle, /\.tqv-0\{/u);
  assert.match(bundleThird.template, new RegExp(refile.sha256, "u"));
  precompute.closeSnapshotTables(tables);
  precompute.closeSnapshotTables(restored);
});

test("split font-contract data assembles into a client-only bundle", { skip: precompute === null }, () => {
  assert.ok(precompute);
  const prepared = fixturePrepared({ key: "p-1", text: "正文" });
  const tables = precompute.createSnapshotTables();
  precompute.absorbSnapshotTables(tables, [prepared]);
  const data = precompute.renderFontContractBundleData([prepared], {
    id: "tq-contract-a",
    snapshotTables: tables,
  });
  precompute.finalizeSnapshotTables(tables);
  const bundle = precompute.assembleFontContractBundle(data, tables);
  assert.deepEqual(bundle.entries, []);
  assert.deepEqual(bundle.rootAttributes, {});
  assert.equal(bundle.template, bundle.clientTemplate);
  assert.match(bundle.clientTemplate, /font-contract-v1/u);
  assert.match(bundle.clientTemplate, /:is\(p, li\):not\(\[data-tiqian-skip\]\)/u);
  assert.doesNotMatch(bundle.initialStyle, /\.tqv-/u);
  precompute.closeSnapshotTables(tables);
});

test("v1 snapshot typography stays aligned with the browser fallback contract", { skip: precompute === null }, async () => {
  assert.ok(precompute);
  const base: CreatePrecomputerOptions = { faces: [], typography: baseTypography };
  await assert.rejects(
    () => precompute.createPrecomputer({
      ...base,
      typography: invalidTypography({ locale: "ja" }),
    }),
    /UnsupportedSnapshotLocale/u,
  );
  await assert.rejects(
    () => precompute.createPrecomputer({
      ...base,
      typography: invalidTypography({ lineLengthGridEnabled: false }),
    }),
    /UnsupportedSnapshotLineLengthGrid/u,
  );
  await assert.rejects(
    () => precompute.createPrecomputer({
      ...base,
      typography: invalidTypography({ fontVariantNumeric: "oldstyle-nums" }),
    }),
    /UnsupportedFontVariantNumeric/u,
  );
  // Typography validates before any font source is resolved, the js order.
  await assert.rejects(
    () => precompute.createPrecomputer({
      faces: [{ family: "Fixture CJK", publicUrl: "/fonts/f.woff2", source: "https://example.com/f.woff2" }],
      typography: invalidTypography({ locale: "ja" }),
    }),
    /UnsupportedSnapshotLocale/u,
  );
  await assert.rejects(
    () => precompute.createPrecomputer(base),
    /MissingBuildFontSource/u,
  );
});

test("cache write budget tiers validate before font sources are resolved", { skip: precompute === null }, async () => {
  assert.ok(precompute);
  const base: CreatePrecomputerOptions = { faces: [], typography: baseTypography };
  // A js caller can pass any string past the declared tier union.
  await assert.rejects(
    () => precompute.createPrecomputer({ ...base, cacheWriteBudget: "huge" as never }),
    /UnknownCacheWriteBudget/u,
  );
  assert.throws(
    () => precompute.setCacheWriteBudget("huge" as never),
    /UnknownCacheWriteBudget/u,
  );
  // A valid tier restores the default and the create call reaches the
  // ordinary font validation; tier semantics live in the rust suite.
  precompute.setCacheWriteBudget(precompute.CacheWriteBudget.Tight);
  await assert.rejects(
    () => precompute.createPrecomputer(base),
    /MissingBuildFontSource/u,
  );
  precompute.setCacheWriteBudget(precompute.CacheWriteBudget.Normal);
});

test("engine-owned hyphens are visual-only in the source-faithful copy contract", { skip: precompute === null }, () => {
  assert.ok(precompute);
  const html = precompute.renderPreparedParagraph({
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    lines: [{
      rangeStart: 0,
      rangeEnd: 3,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: 25,
      hyphenAdvance: 5,
      endReason: "AutoWrap",
      cells: [{
        rangeStart: 0,
        rangeEnd: 3,
        source: "int",
        display: "int",
        drawX: 0,
        naturalWidth: 25,
        leadingLayoutAdvance: 0,
      }],
    }],
  }, { fontFamilies: ["Fixture CJK"], fontSizePx: 18, lineHeightPx: 27, locale: "zh-Hans" });
  assert.match(html, /<span [^>]*aria-hidden="true"[^>]*data-tq-copy-ignore="true"[^>]*>-<\/span>/u);
  assert.match(html, /data-tq-line-flow-width="30"/u);
  assert.match(html, /data-tq-line-width="30"/u);
  assert.doesNotMatch(html, /data-tq-shaping-boundary[^>]*margin-right/u);
  assert.match(html, /data-tq-engine-hyphen="true"/u);
  assert.doesNotMatch(html, /(?:all:unset|display:inline-block|white-space:pre)/u);
});

test("snapshot lowering rejects a first-cell placement it cannot reproduce in inline flow", { skip: precompute === null }, () => {
  assert.ok(precompute);
  assert.throws(
    () => precompute.renderPreparedParagraph({
      schema: 1,
      layoutRevision: "tiqian-layout-v2",
      height: 27,
      lines: [{
        rangeStart: 0,
        rangeEnd: 1,
        top: 0,
        bottom: 27,
        baseline: 20,
        indent: 0,
        visualWidth: 18,
        hyphenAdvance: 0,
        endReason: "ParagraphEnd",
        cells: [{
          rangeStart: 0,
          rangeEnd: 1,
          source: "中",
          display: "中",
          drawX: 2,
          naturalWidth: 18,
          leadingLayoutAdvance: 2,
        }],
      }],
    }, { fontFamilies: ["Fixture CJK"], fontSizePx: 18, lineHeightPx: 27, locale: "zh-Hans" }),
    /SnapshotRenderFlowMismatch/u,
  );
});

function cjkPrecomputerOptions(): CreatePrecomputerOptions | null {
  const bytes = readLocalFont("chinese.msyh.ttf");
  if (bytes === null) return null;
  return {
    faces: [{ family: "Microsoft YaHei", publicUrl: "/fonts/msyh.ttf", source: bytes }],
    typography: {
      fontFamilies: ["Microsoft YaHei"],
      fontSizePx: 18,
      lineHeightPx: 27,
      locale: "zh-Hans",
      fontWeight: 400,
      italic: false,
      firstLineIndentIc: 0,
      lineLengthGridEnabled: true,
    },
  };
}

// Input validation runs before the engine call, so these named errors surface
// in both build flavors.
test("precomputer input gates report by name before the engine runs", { skip: precompute === null }, async () => {
  assert.ok(precompute);
  const options = cjkPrecomputerOptions();
  if (options === null) return; // the session needs a CJK-covering face
  const precomputer = await precompute.createPrecomputer(options);
  const normalized: NormalizedTypography = precomputer.typography;
  assert.equal(normalized.locale, "zh-Hans");
  assert.equal(normalized.lineLengthGridEnabled, true);
  assert.deepEqual(normalized.fontFamilies, ["Microsoft YaHei"]);
  await assert.rejects(
    () => precomputer.prepareParagraph({ key: "", text: "正文", maxWidthPx: 360 }),
    /MissingSnapshotKey/u,
  );
  await assert.rejects(
    () => precomputer.prepareParagraph({ key: "p-0", text: "正文", maxWidthPx: 0 }),
    /InvalidMaximumMeasure/u,
  );
  // The dash gate answers without a plan.
  const dashed = await precomputer.prepareParagraph({ key: "p-1", text: "带—破折号", maxWidthPx: 360 });
  assert.equal(dashed.status, "unsupported");
  if (dashed.status === "unsupported") {
    assert.equal(dashed.issue, "CjkDashRequiresBrowserFaceVerification");
  }
  precomputer.close();
  await assert.rejects(
    () => precomputer.prepareParagraph({ key: "p-2", text: "正文", maxWidthPx: 360 }),
    /PrecomputerClosed/u,
  );
});

test("prepareParagraph plans through the engine or reports PrecomputeEngineNotLinked", { skip: precompute === null }, async () => {
  assert.ok(precompute);
  const options = cjkPrecomputerOptions();
  if (options === null) return; // the engine path needs a CJK-covering face
  const precomputer = await precompute.createPrecomputer(options);
  const input = { key: "p-0", text: "中文文字排版段落", maxWidthPx: 144 };
  let entry: PreparedEntry;
  try {
    entry = await precomputer.prepareParagraph(input);
  } catch (error) {
    assert.match((error as Error).message, /PrecomputeEngineNotLinked/);
    precomputer.close();
    return;
  }
  const prepared = assertPrepared(entry);
  assert.equal(prepared.schema, 1);
  assert.equal(prepared.layoutRevision, "tiqian-layout-v2");
  assert.equal(prepared.key, "p-0");
  assert.equal(prepared.sourceText, "中文文字排版段落");
  assert.equal(prepared.typography.locale, "zh-Hans");
  assert.ok(prepared.html.length > 0);
  assert.ok(prepared.plan);

  // The batch lane returns the same entries in input order.
  const second = { key: "p-1", text: "第二段落正文", maxWidthPx: 144 };
  const batch = await precomputer.prepareParagraphs([input, second]);
  assert.deepEqual(
    batch.map((item) => [item.status, item.key]),
    [["prepared", "p-0"], ["prepared", "p-1"]],
  );
  assert.equal(assertPrepared(batch[0]).html, prepared.html);
  assert.equal(assertPrepared(batch[0]).renderArtifactSha256, prepared.renderArtifactSha256);
  const sequential = await precomputer.prepareParagraph(second);
  assert.equal(assertPrepared(sequential).html, assertPrepared(batch[1]).html);

  const contract = await precomputer.prepareFontContract({ key: "f-0", text: "正文契约正文" });
  assert.equal(assertPrepared(contract).key, "f-0");
  // The batch contract lane returns the same entries in input order.
  const secondContract = { key: "f-1", text: "第二段落契约正文" };
  const contractBatch = await precomputer.prepareFontContracts([
    { key: "f-0", text: "正文契约正文" },
    secondContract,
  ]);
  assert.deepEqual(
    contractBatch.map((item) => [item.status, item.key]),
    [["prepared", "f-0"], ["prepared", "f-1"]],
  );
  assert.equal(assertPrepared(contractBatch[0]).html, assertPrepared(contract).html);
  const sequentialContract = await precomputer.prepareFontContract(secondContract);
  assert.equal(
    assertPrepared(sequentialContract).html,
    assertPrepared(contractBatch[1]).html,
  );
  // The batch reports the lowest failing index, the sequential `?` order.
  await assert.rejects(
    () => precomputer.prepareFontContracts([{ key: "f-2", text: "正文" }, { key: "", text: "正文" }]),
    /MissingSnapshotKey/u,
  );
  precomputer.close();
});
