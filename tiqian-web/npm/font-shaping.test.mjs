import assert from "node:assert/strict";
import test from "node:test";

import {
  evaluateDashGeometry,
  parseFontFamilies,
  parseUnicodeRange,
  unicodeRangeContains,
} from "./font-shaping.js";

test("parses computed CSS family stacks without guessing generated names", () => {
  assert.deepEqual(
    parseFontFamilies('"MiSans VF-e4b68fca106b90e2", Inter, "PingFang SC", sans-serif'),
    ["MiSans VF-e4b68fca106b90e2", "Inter", "PingFang SC", "sans-serif"],
  );
});

test("matches explicit, ranged, and wildcard unicode-range entries", () => {
  const ranges = parseUnicodeRange("U+2013-2014, U+2E3A, U+4E??");
  assert.equal(unicodeRangeContains(ranges, 0x2014), true);
  assert.equal(unicodeRangeContains(ranges, 0x2e3a), true);
  assert.equal(unicodeRangeContains(ranges, 0x4e00), true);
  assert.equal(unicodeRangeContains(ranges, 0x4eff), true);
  assert.equal(unicodeRangeContains(ranges, 0x3000), false);
  assert.equal(unicodeRangeContains(null, 0x2e3a), true);
});

function pairedDash({ seamGap = 0, inkRight = 2 } = {}) {
  return {
    advance: 2,
    missingGlyphs: 0,
    ink: { left: 0, top: -0.445, right: inkRight, bottom: -0.335 },
    glyphs: [
      {
        advance: 1,
        positionedBounds: { left: 0, top: -0.445, right: 1, bottom: -0.335 },
      },
      {
        advance: 1,
        positionedBounds: { left: 1 + seamGap, top: -0.445, right: 2, bottom: -0.335 },
      },
    ],
  };
}

const hanProbe = {
  ink: { left: 0.059, top: -0.472, right: 0.94, bottom: -0.358 },
};

test("accepts a centered, contiguous two-em paired dash", () => {
  const result = evaluateDashGeometry(pairedDash(), hanProbe, "PairedEmDash");
  assert.equal(result.conforms, true);
  assert.equal(result.seamGapEm, 0);
  assert.ok(Math.abs(result.verticalCenterDeltaEm - 0.025) < 0.0001);
});

test("rejects a visible seam and underfilled two-em ink", () => {
  const seam = evaluateDashGeometry(pairedDash({ seamGap: 0.05 }), hanProbe, "PairedEmDash");
  assert.equal(seam.conforms, false);
  assert.ok(seam.failures.some((failure) => failure.startsWith("seam-gap=")));

  const underfilled = evaluateDashGeometry(pairedDash({ inkRight: 1.5 }), hanProbe, "PairedEmDash");
  assert.equal(underfilled.conforms, false);
  assert.ok(underfilled.failures.some((failure) => failure.startsWith("ink-coverage=")));
});
