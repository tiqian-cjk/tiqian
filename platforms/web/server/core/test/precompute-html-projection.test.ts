// The server-lane DOM projection (Html-B2). The whole-document preparer in
// precompute-html.test.ts imports the native precompute addon and skips when it
// is not built, but snapshotSourceArtifactFromDom / snapshotProjection /
// projectedTextOnly are pure TypeScript over the generated SnapshotSource lane
// plus linkedom, so their parity with the client-lane snapshot-source.ts walk
// is pinned here without the addon. This is the "Node 侧投影单测" for B2.

import { test } from "node:test";
import assert from "node:assert/strict";
import { parseHTML } from "linkedom";

import type { DomNode } from "@tiqian/shared/org/tiqian/shared/html/DomNode";
import {
  projectedTextOnly,
  snapshotProjection,
  snapshotSourceArtifactFromDom,
} from "../lib/precompute-html-projection.js";

function paragraph(inner: string): DomNode {
  const { document } = parseHTML(`<p>${inner}</p>`);
  const element = document.querySelector("p");
  assert.ok(element !== null, "the probe paragraph must contain a <p>");
  return element as DomNode;
}

test("snapshotProjection returns the folded text of a plain paragraph", () => {
  assert.deepEqual(snapshotProjection(paragraph("你好世界")), { text: "你好世界" });
});

test("snapshotProjection declines when an inline semantic survives the fold", () => {
  assert.equal(snapshotProjection(paragraph("你好<strong>世界</strong>")), null);
});

test("snapshotProjection declines when an unsafe tag enters the walk", () => {
  assert.equal(snapshotProjection(paragraph("你好<script>alert(1)</script>")), null);
});

test("projectedTextOnly keeps a hard break and collapses a whitespace run", () => {
  assert.equal(projectedTextOnly(paragraph("你好 <b>世界</b><br>再见")), "你好 世界\n再见");
});

test("snapshotSourceArtifactFromDom folds a semantic range through whitespace", () => {
  const artifact = snapshotSourceArtifactFromDom(paragraph("你好 <em>世界</em>"));
  assert.ok(artifact !== null, "a safe semantic paragraph must produce an artifact");
  assert.equal(artifact.text, "你好 世界");
  assert.equal(artifact.semantics.length, 1);
  assert.deepEqual(artifact.semantics[0], {
    start: 3,
    end: 5,
    tagName: "em",
    attributes: [],
    order: 0,
  });
});
