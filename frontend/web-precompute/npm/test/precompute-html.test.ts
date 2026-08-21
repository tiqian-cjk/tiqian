// Native-lane ports of the @tiqian/prose precompute-html suite (ADR 0050).
// The scan, injection and asset entries run wherever an addon build exists;
// whole-document preparation additionally needs a local CJK font and covers
// both build flavors: a build without the engine archive reports
// PrecomputeEngineNotLinked from prepare.

import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import type { Precomputer, SnapshotTypography } from "../src/precompute.js";
import type { PreparedHtml } from "../src/precompute-html.js";

type PrecomputeModule = typeof import("../src/precompute.js");
type PrecomputeHtmlModule = typeof import("../src/precompute-html.js");

let precompute: PrecomputeModule | null = null;
let precomputeHtml: PrecomputeHtmlModule | null = null;
try {
  precompute = (await import("../lib/precompute.js")) as PrecomputeModule;
  precomputeHtml = (await import("../lib/precompute-html.js")) as PrecomputeHtmlModule;
} catch {
  precompute = null;
  precomputeHtml = null;
}

function readLocalFont(fileName: string): Buffer | null {
  try {
    return readFileSync(`${process.env.HOME}/.local/share/fonts/${fileName}`);
  } catch {
    return null; // no font available; document preparation needs a CJK face
  }
}

const normalizedTypography = Object.freeze({
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

test("opening-tag scan ignores literal paragraphs in comments, raw text and templates", { skip: precomputeHtml === null }, () => {
  assert.ok(precomputeHtml);
  const html = '<!-- <p>comment</p> --><p>正文</p><script>"<p>script</p>"</script>' +
    '<template><p>inert</p></template><li>条目</li>';
  assert.deepEqual(
    precomputeHtml.findHtmlOpeningTags(html).map(({ tagName, source }) => [tagName, source]),
    [["p", "<p>"], ["li", "<li>"]],
  );
});

test("attribute injection applies insertions at the given offsets", { skip: precomputeHtml === null }, () => {
  assert.ok(precomputeHtml);
  assert.equal(
    precomputeHtml.injectHtmlAttributes("<p>甲</p><p>乙</p>", [
      { offset: 10, attribute: ' data-b="2"' },
      { offset: 2, attribute: ' data-a="1"' },
    ]),
    '<p data-a="1">甲</p><p data-b="2">乙</p>',
  );
});

test("server asset entries degrade to null and empty output without a bundle", { skip: precomputeHtml === null }, () => {
  assert.ok(precomputeHtml);
  assert.equal(precomputeHtml.snapshotServerAssets(null), null);
  assert.equal(precomputeHtml.renderSnapshotServerAssets(null), "");
});

test("HTML projectors and foreign precomputers are rejected by name", { skip: precomputeHtml === null }, async () => {
  assert.ok(precomputeHtml);
  await assert.rejects(
    () => precomputeHtml.createHtmlPreparer({
      projectSnapshotParagraph: () => "",
      typography: {
        fontFamilies: ["Fixture CJK"],
        fontSizePx: 18,
        lineHeightPx: 27,
      },
      faces: [],
    }),
    /UnsupportedHtmlProjector/u,
  );
  const foreign: Precomputer = {
    typography: normalizedTypography,
    renderFontFamilies: ["Fixture CJK"],
    prepareParagraph: async (input) => ({ status: "unsupported", key: input.key, issue: "fixture" }),
    prepareParagraphs: async (inputs) =>
      inputs.map((input) => ({ status: "unsupported", key: input.key, issue: "fixture" })),
    prepareFontContract: async (input) => ({ status: "unsupported", key: input.key, issue: "fixture" }),
    prepareFontContracts: async (inputs) =>
      inputs.map((input) => ({ status: "unsupported", key: input.key, issue: "fixture" })),
    cache: {
      context: () => "",
      submitHashes: () => {
        throw new Error("fixture precomputer has no cache bridge");
      },
      submitContents: () => {
        throw new Error("fixture precomputer has no cache bridge");
      },
      prefillContents: () => {
        throw new Error("fixture precomputer has no cache bridge");
      },
      prefetch: () => {
        throw new Error("fixture precomputer has no cache bridge");
      },
      drainWrites: () => {
        throw new Error("fixture precomputer has no cache bridge");
      },
      evictExcept: () => {
        throw new Error("fixture precomputer has no cache bridge");
      },
    },
    close() {},
  };
  await assert.rejects(
    () => precomputeHtml.createHtmlPreparer({ precomputer: foreign }),
    /ForeignPrecomputer/u,
  );
});

test("owned preparer typography validates before font sources load", { skip: precomputeHtml === null }, async () => {
  assert.ok(precomputeHtml);
  // The runtime rejects a locale value the public type rules out; js callers
  // can still pass it, so the gate is tested through a widened value.
  const locale: string = "ja";
  const typography = {
    fontFamilies: ["Fixture CJK"],
    fontSizePx: 18,
    lineHeightPx: 27,
    locale,
  } as SnapshotTypography;
  await assert.rejects(
    () => precomputeHtml.createHtmlPreparer({ typography, faces: [] }),
    /UnsupportedSnapshotLocale/u,
  );
});

function cjkPrecomputer(): Promise<Precomputer> | null {
  const bytes = readLocalFont("chinese.msyh.ttf");
  if (bytes === null || precompute === null) return null;
  return precompute.createPrecomputer({
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
  });
}

// Measure validation and the closed gate run before the engine call, so
// these named errors surface in both build flavors.
test("html preparer gates report by name before the engine runs", { skip: precomputeHtml === null }, async () => {
  assert.ok(precomputeHtml);
  const created = cjkPrecomputer();
  if (created === null) return; // the preparer needs a CJK-covering face
  const precomputer = await created;
  const preparer = await precomputeHtml.createHtmlPreparer({ precomputer });
  await assert.rejects(
    () => preparer.prepare("<p>正文</p>", { snapshot: { maxWidthPx: 0 } }),
    /InvalidMaximumMeasure/u,
  );
  preparer.close();
  await assert.rejects(() => preparer.prepare("<p>正文</p>"), /HtmlPreparerClosed/u);
  precomputer.close();
});

test("whole-document preparation runs in one native call", { skip: precomputeHtml === null }, async () => {
  assert.ok(precomputeHtml);
  const created = cjkPrecomputer();
  if (created === null) return; // document preparation needs a CJK-covering face
  const precomputer = await created;
  const source = '<p>纯文本。</p><p><a href="/next">链接正文</a></p>' +
    '<div data-tiqian-skip><p>跳过段落</p></div>';
  const preparer = await precomputeHtml.createHtmlPreparer({ precomputer });
  assert.equal(preparer.typography.locale, "zh-Hans");

  let snapshot: PreparedHtml;
  try {
    snapshot = await preparer.prepare(source, { id: "tq-article", snapshot: { maxWidthPx: 720 } });
  } catch (error) {
    assert.match((error as Error).message, /PrecomputeEngineNotLinked/);
    preparer.close();
    precomputer.close();
    return;
  }
  // Plain paragraphs receive a snapshot key; linked prose and skipped
  // ancestors stay byte-for-byte intact.
  assert.equal(
    snapshot.html,
    '<p data-tq-snapshot-key="p-0">纯文本。</p><p><a href="/next">链接正文</a></p>' +
    '<div data-tiqian-skip><p>跳过段落</p></div>',
  );
  assert.deepEqual(snapshot.rootAttributes, {
    "snapshot-ref": "tq-article",
    "data-tiqian-exact-render-font": "true",
  });
  assert.ok(snapshot.bundle);
  const serverAssets = snapshot.serverAssets;
  assert.ok(serverAssets);
  assert.match(serverAssets.inertTemplate, /data-tq-entry="p-0"/u);
  const clientBundle = snapshot.clientBundle;
  assert.ok(clientBundle);
  assert.match(clientBundle.clientTemplate, /font-contract-v1/u);
  assert.deepEqual(snapshot.issues, []);
  assert.match(
    precomputeHtml.renderSnapshotServerAssets(serverAssets),
    /data-tq-initial-snapshot="tq-article"/u,
  );

  // Width-free preparation keeps every paragraph in the font-contract lane.
  const contractOnly = await preparer.prepare(source);
  assert.equal(contractOnly.html, source);
  assert.match(String(contractOnly.rootAttributes["snapshot-ref"] ?? ""), /^tq-prose-/u);
  const contractBundle = contractOnly.bundle;
  assert.ok(contractBundle);
  assert.deepEqual(contractBundle.entries, []);
  assert.match(contractBundle.clientTemplate, /font-contract-v1/u);
  preparer.close();
  precomputer.close();
});

test("a shared precomputer survives preparer closes", { skip: precomputeHtml === null }, async () => {
  assert.ok(precomputeHtml);
  const created = cjkPrecomputer();
  if (created === null) return; // the preparer needs a CJK-covering face
  const precomputer = await created;
  const first = await precomputeHtml.createHtmlPreparer({ precomputer });
  const second = await precomputeHtml.createHtmlPreparer({ precomputer });
  second.close();
  // A leaked close of the shared precomputer would surface as PrecomputerClosed.
  const third = await precomputeHtml.createHtmlPreparer({ precomputer });
  try {
    await third.prepare("<p>正文。</p>");
  } catch (error) {
    assert.doesNotMatch((error as Error).message, /PrecomputerClosed/u);
  }
  third.close();
  first.close();
  precomputer.close();
});
