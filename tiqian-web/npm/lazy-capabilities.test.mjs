import assert from "node:assert/strict";
import test from "node:test";

import {
  fontLoadingAffectsTypography,
  lineLengthGridCellCount,
  lineLengthGridMeasure,
  loadedPrecomputedSnapshots,
  needsCjkDashShaping,
  parseCssFontFamilies,
  prepareCjkDashShapingIfNeeded,
  waitForTypographyFonts,
} from "./lazy-capabilities.js";

test("responsive invalidation follows the engine line-length grid", () => {
  assert.equal(lineLengthGridCellCount(912, 15), 60);
  assert.equal(lineLengthGridCellCount(911, 15), 60);
  assert.equal(lineLengthGridCellCount(900, 15), 60);
  assert.equal(lineLengthGridCellCount(899, 15), 59);
  assert.equal(lineLengthGridCellCount(0, 15), 1);
  assert.equal(lineLengthGridCellCount(320, 0), null);
  assert.equal(lineLengthGridMeasure(912, 15), 900);
  assert.equal(lineLengthGridMeasure(911, 15), 900);
  assert.notEqual(lineLengthGridMeasure(10, 15), lineLengthGridMeasure(12, 15));
  assert.equal(lineLengthGridCellCount(305.98, 15.3), 19);
  assert.equal(lineLengthGridCellCount(306, 15.3), 20);
  assert.equal(lineLengthGridCellCount(306.02, 15.3), 20);
  assert.equal(lineLengthGridMeasure(305.98, 15.3), Math.fround(19 * Math.fround(15.3)));
  assert.equal(lineLengthGridMeasure(306.02, 15.3), 306);
});

test("plain roots do not load optional snapshot or dash modules", async () => {
  delete globalThis.__TiqianWebFontShaping;
  const root = { textContent: "普通中文正文。" };

  assert.equal(needsCjkDashShaping(root), false);
  assert.equal(loadedPrecomputedSnapshots(), null);
  assert.deepEqual(await prepareCjkDashShapingIfNeeded(root), { status: "not-needed" });
  assert.equal(globalThis.__TiqianWebFontShaping, undefined);
});

test("dash detection covers paired and two-em source forms", () => {
  assert.equal(needsCjkDashShaping({ textContent: "甲——乙" }), true);
  assert.equal(needsCjkDashShaping({ textContent: "甲⸺乙" }), true);
  assert.equal(needsCjkDashShaping({ textContent: "甲—乙" }), false);
});

test("font loading invalidation filters unrelated family and face variants", () => {
  assert.deepEqual(
    parseCssFontFamilies('"IBM Plex Sans SC", system-ui, \'Noto Sans\''),
    ["ibm plex sans sc", "system-ui", "noto sans"],
  );
  const elements = [{}];
  const getStyle = () => ({
    getPropertyValue(property) {
      return {
        "font-family": '"IBM Plex Sans SC", sans-serif',
        "font-weight": "500",
        "font-style": "normal",
      }[property] ?? "";
    },
  });

  assert.equal(fontLoadingAffectsTypography({
    fontfaces: [{ family: "Unrelated", weight: "400", style: "normal" }],
  }, elements, getStyle), false);
  assert.equal(fontLoadingAffectsTypography({
    fontfaces: [{ family: "IBM Plex Sans SC", weight: "400", style: "normal" }],
  }, elements, getStyle), false);
  assert.equal(fontLoadingAffectsTypography({
    fontfaces: [{ family: "IBM Plex Sans SC", weight: "100 900", style: "normal" }],
  }, elements, getStyle), true);
  assert.equal(fontLoadingAffectsTypography({ fontfaces: [] }, elements, getStyle), true);
});

test("initial font readiness waits only for prose font descriptors and subsets", async () => {
  const calls = [];
  let releaseBodyFont;
  const bodyFont = new Promise((resolve) => { releaseBodyFont = resolve; });
  const fonts = {
    ready: bodyFont,
    load(descriptor, sample) {
      calls.push({ descriptor, sample });
      return Promise.resolve([]);
    },
  };
  const elements = [
    { textContent: "甲乙甲" },
    { textContent: "乙丙" },
    { textContent: "code" },
  ];
  const getStyle = (element) => ({
    getPropertyValue(property) {
      const mono = element === elements[2];
      return {
        "font-family": mono ? '"JetBrains Mono", monospace' : '"IBM Plex Sans SC", sans-serif',
        "font-size": mono ? "14px" : "16px",
        "font-style": "normal",
        "font-weight": mono ? "400" : "500",
        "font-stretch": "100%",
      }[property] ?? "";
    },
  });

  const outcome = await waitForTypographyFonts(fonts, elements, getStyle);

  assert.deepEqual(calls, [
    {
      descriptor: 'normal 500 100% 16px "IBM Plex Sans SC", sans-serif',
      sample: "甲乙丙",
    },
    {
      descriptor: 'normal 400 100% 14px "JetBrains Mono", monospace',
      sample: "code",
    },
  ]);
  assert.equal(outcome.status, "settled");
  assert.equal(await Promise.race([bodyFont.then(() => "ready"), Promise.resolve("not-awaited")]), "not-awaited");
  releaseBodyFont();
});

test("initial font readiness times out without abandoning eventual completion", async () => {
  let releaseFont;
  const font = new Promise((resolve) => { releaseFont = resolve; });
  const fonts = { load: () => font };
  const element = { textContent: "正文" };
  const getStyle = () => ({
    getPropertyValue(property) {
      return {
        "font-family": '"Example CJK", sans-serif',
        "font-size": "16px",
        "font-style": "normal",
        "font-weight": "400",
        "font-stretch": "100%",
      }[property] ?? "";
    },
  });

  const outcome = await waitForTypographyFonts(
    fonts,
    [element],
    getStyle,
    { timeoutMs: 0 },
  );

  assert.equal(outcome.status, "timeout");
  releaseFont([]);
  await outcome.completion;
});

test("a rejected face settles on the browser fallback instead of timing out", async () => {
  const fonts = { load: () => Promise.reject(new Error("font unavailable")) };
  const getStyle = () => ({
    getPropertyValue(property) {
      return {
        "font-family": "sans-serif",
        "font-size": "16px",
      }[property] ?? "";
    },
  });

  const outcome = await waitForTypographyFonts(
    fonts,
    [{ textContent: "正文" }],
    getStyle,
    { timeoutMs: 0 },
  );

  assert.equal(outcome.status, "settled");
});
