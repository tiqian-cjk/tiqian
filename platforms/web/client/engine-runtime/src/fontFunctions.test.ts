// Migration of the retired Kotlin/JS FontExportsTest.kt
// (fontMetricsResolve / fontFallbackResolve cases) onto the generated-TS
// adapter. Inputs and assertion structure are kept from the Kotlin test; the
// expected metric numbers are rewritten to their exact f64 values per TCN-45
// (the old Kotlin/JS expectations carried f32-grid artifacts such as
// 5.184000015258789 for 18 * 0.288).
//
// Run: node --test src/fontFunctions.test.ts

import assert from "node:assert/strict";
import test from "node:test";

import {
  fontFallbackResolve,
  fontMetricsResolve,
  IllegalArgumentException,
} from "./fontFunctions.ts";

test("fontMetricsResolveReturnsRawMetricsJsonForCjkRole", () => {
  const requestJson =
    '{"fontKey":"cjk-key","fontSize":18,"role":"CjkText","locale":"zh-Hans","fontFamilies":["Source Han Sans"],"fontWeight":400,"italic":false,"faceSelectionText":"中"}';

  const json = fontMetricsResolve(requestJson);
  assert.equal(
    json,
    '{"ascent":20.88,"descent":5.183999999999999,"leading":0,"source":"RawTables","typoAscent":15.84,"typoDescent":2.16}',
  );

  const parsed = JSON.parse(json) as Record<string, unknown>;
  assert.equal(parsed.source, "RawTables");
  assert.ok(Math.abs((parsed.ascent as number) - 20.88) < 1e-6);
  assert.ok(Math.abs((parsed.descent as number) - 5.184) < 1e-6); // f64 shortest repr: 5.183999999999999
  assert.ok(Math.abs((parsed.typoAscent as number) - 15.84) < 1e-6);
  assert.ok(Math.abs((parsed.typoDescent as number) - 2.16) < 1e-6);
});

test("fontMetricsResolveOmitsTypoPairWhenAbsent", () => {
  const requestJson =
    '{"fontKey":"latin-key","fontSize":18,"role":"LatinText","locale":"en","fontFamilies":[],"fontWeight":400,"italic":false,"faceSelectionText":"Hi"}';

  const json = fontMetricsResolve(requestJson);
  assert.equal(json, '{"ascent":14.4,"descent":3.6,"leading":0,"source":"RawTables"}');

  const parsed = JSON.parse(json) as Record<string, unknown>;
  assert.equal("typoAscent" in parsed, false);
  assert.equal("typoDescent" in parsed, false);
});

test("fontFallbackResolveReturnsFontDecisionJson", () => {
  const cjkRequest = '{"preferredFamilies":["Source Han Sans"],"locale":"zh-Hans","role":"CjkText"}';
  const cjkJson = fontFallbackResolve("中文", 0, 1, cjkRequest);
  const cjk = JSON.parse(cjkJson) as Record<string, never>;
  assert.equal(cjk.range.start, 0);
  assert.equal(cjk.range.end, 1);
  assert.equal(cjk.candidate.key, "cjk-primary");
  assert.equal(cjk.candidate.family, "Source Han Sans");
  assert.equal(cjk.candidate.role, "CjkText");
  assert.equal(cjk.role, "CjkText");
  assert.equal(cjk.reason, "PreferCjkForAmbiguousPunctuationResolver:CjkText");
  assert.ok(cjkJson.includes('"candidate":{"key":"cjk-primary"'));

  const latinRequest = '{"preferredFamilies":[],"locale":"en","role":"LatinText"}';
  const latin = JSON.parse(
    fontFallbackResolve("Hi", 0, 2, latinRequest),
  ) as Record<string, never>;
  assert.equal(latin.candidate.key, "latin-primary");
  assert.equal(latin.candidate.family, "latin-primary");
  assert.equal(latin.role, "LatinText");
});

test("invalidRoleNameThrowsIllegalArgumentException", () => {
  assert.throws(
    () => fontMetricsResolve('{"fontSize":18,"role":"Bogus","locale":"zh-Hans"}'),
    IllegalArgumentException,
  );
});
