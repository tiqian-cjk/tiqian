import assert from "node:assert/strict";
import test from "node:test";

import {
  normalizeSnapshotSemantics,
  snapshotSemanticMetricContractIssue,
  snapshotSourceArtifactString,
} from "./snapshot-source.js";

test("snapshot source semantics are nested deterministically and include behavior attributes", () => {
  const semantics = normalizeSnapshotSemantics("前链接后", [{
    start: 1,
    end: 3,
    tagName: "a",
    attributes: { title: "入口", href: "/first" },
  }, {
    start: 1,
    end: 3,
    tagName: "strong",
    attributes: {},
  }]);

  assert.deepEqual(semantics.map((span) => span.tagName), ["a", "strong"]);
  assert.notEqual(
    snapshotSourceArtifactString("前链接后", semantics),
    snapshotSourceArtifactString("前链接后", [{
      start: 1,
      end: 3,
      tagName: "a",
      attributes: { title: "入口", href: "/second" },
    }, {
      start: 1,
      end: 3,
      tagName: "strong",
      attributes: {},
    }]),
  );
});

test("snapshot semantics reject crossing ranges and active content attributes", () => {
  assert.throws(() => normalizeSnapshotSemantics("中文正文", [
    { start: 0, end: 3, tagName: "a", attributes: { href: "/a" } },
    { start: 2, end: 4, tagName: "em", attributes: {} },
  ]), /CrossingSnapshotSemanticRanges/u);
  assert.throws(() => normalizeSnapshotSemantics("链接", [
    { start: 0, end: 2, tagName: "a", attributes: { onclick: "alert(1)" } },
  ]), /UnsupportedSnapshotSemanticAttribute/u);
});

test("inline code requires an explicit exact-font and box metric contract", () => {
  const semantics = normalizeSnapshotSemantics("中code文", [{
    start: 1,
    end: 5,
    tagName: "code",
    attributes: {},
  }]);

  assert.equal(
    snapshotSemanticMetricContractIssue(semantics, [], []),
    "InlineCodeFontContractUnavailable",
  );
  const textSpans = [{
    start: 1,
    end: 5,
    fontFamilies: ["Host Exact Mono"],
    fontSizePx: 14,
    fontWeight: 400,
    italic: false,
    baselineShiftPx: 0,
  }];
  assert.equal(
    snapshotSemanticMetricContractIssue(semantics, textSpans, []),
    "InlineCodeBoxContractUnavailable",
  );
  assert.equal(snapshotSemanticMetricContractIssue(semantics, textSpans, [{
    start: 1,
    end: 5,
    inlineStartPx: 5.6,
    inlineEndPx: 5.6,
  }]), null);
});
