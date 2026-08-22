// Boundary smoke over the native addon, run against the built lib/ output.
// Runs wherever an addon build exists (local `npm run debug:native`, or the
// CI build lane); on a checkout without a build the loader cannot resolve a
// platform package and the suite skips.

import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";
import type { PreparedPlan } from "../src/fonts.js";

type FontsModule = typeof import("../src/fonts.js");

let fonts: FontsModule | null = null;
try {
  fonts = (await import("../lib/fonts.js")) as FontsModule;
} catch {
  fonts = null;
}

function readLocalFont(fileName: string): Buffer | null {
  try {
    return readFileSync(`${process.env.HOME}/.local/share/fonts/${fileName}`);
  } catch {
    return null; // no font available; the named-error path needs a real face list
  }
}

test("addon loads and reports engine identity", { skip: fonts === null }, () => {
  assert.ok(fonts);
  assert.equal(fonts.backendRevision, "tiqian-shared-harfbuzz-v5");
  assert.match(fonts.harfbuzzVersion, /^harfrust-/);
});

test("empty face list reports MissingExplicitFontFaces", { skip: fonts === null }, async () => {
  assert.ok(fonts);
  await assert.rejects(() => fonts.createFontSession([]), /MissingExplicitFontFaces/);
});

test("unsupported base features report by name", { skip: fonts === null }, async () => {
  assert.ok(fonts);
  const bytes = readLocalFont("EBGaramond-Regular.ttf");
  if (bytes === null) return;
  await assert.rejects(
    () =>
      fonts.createFontSession(
        [{ family: "Garamond", publicUrl: "/fonts/garamond.ttf", source: bytes }],
        { baseFeatures: ["kern"] },
      ),
    /UnsupportedFontSessionBaseFeatures/,
  );
});

test("styled spans reach source boundaries", { skip: fonts === null }, async () => {
  assert.ok(fonts);
  const bytes = readLocalFont("EBGaramond-Regular.ttf");
  const italicBytes = readLocalFont("EBGaramond-Italic.ttf");
  if (bytes === null || italicBytes === null) return; // boundaries need real faces
  const session = await fonts.createFontSession([
    { family: "Garamond", publicUrl: "/fonts/garamond.ttf", source: bytes },
    { family: "Garamond", publicUrl: "/fonts/garamond-italic.ttf", source: italicBytes, style: "italic" },
  ]);
  const style = { fontFamilies: ["Garamond"], fontSizePx: 20, fontWeight: 400, italic: false };
  const boundaries = session.sourceBoundaries("typeset", style, [
    { start: 0, end: 4, style },
    { start: 4, end: 7, style: { ...style, italic: true } },
  ]);
  assert.ok(Array.isArray(boundaries));
  session.close();
});

// The debug:native build carries no engine archive, so the entry reports
// EngineNotLinked there; a build linked against the engine archive takes the
// full path. One test covers both flavors.
test("precomputeParagraph plans a paragraph or reports EngineNotLinked", { skip: fonts === null }, async () => {
  assert.ok(fonts);
  const bytes = readLocalFont("DelaGothicOne-Regular.ttf");
  if (bytes === null) return; // the engine path needs a CJK-covering face
  const session = await fonts.createFontSession([
    { family: "Dela Gothic One", publicUrl: "/fonts/dela-gothic.ttf", source: bytes },
  ]);
  const typography = {
    fontFamilies: ["Dela Gothic One"],
    fontSizePx: 18,
    lineHeightPx: 27,
    locale: "zh-Hans",
    fontWeight: 400,
    italic: false,
    firstLineIndentIc: 0,
    lineLengthGridEnabled: true,
  };
  const planOnce = () => session.precomputeParagraph("中文文字排版段落", 144, typography);
  let plan: PreparedPlan | undefined;
  try {
    plan = planOnce();
  } catch (error) {
    assert.match((error as Error).message, /EngineNotLinked/);
    session.close();
    return;
  }
  assert.ok(plan);
  assert.ok(plan.lines.length >= 1);
  assert.equal(plan.lines[plan.lines.length - 1].endReason, "ParagraphEnd");
  assert.equal(plan.layoutRevision, "tiqian-layout-v2");
  assert.deepEqual(planOnce(), plan);
  assert.throws(() => session.precomputeParagraph("  ", 144, typography), /EmptyParagraph/);
  assert.throws(
    () => session.precomputeParagraph("中文", 0, typography),
    /InvalidMaximumMeasure/,
  );
  session.close();
});
