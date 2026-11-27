// Host transport and bundle-assembly tests (ADR 0052 TableTransport). The
// assembly fixtures mirror the precompute suite: hand-built prepared entries
// exercise the ordering rules without a local font.

import { createHash } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";

import type { PreparedParagraph } from "../src/precompute.js";

type TransportModule = typeof import("../src/transport.js");

let transport: TransportModule | null = null;
try {
  transport = (await import("../lib/transport.js")) as TransportModule;
} catch {
  transport = null;
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

function sha256(value: string | Buffer): string {
  return createHash("sha256").update(value).digest("hex");
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

function fixturePrepared(input: { key: string; text: string; publicUrl: string }): PreparedBranch {
  return {
    status: "prepared",
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v17",
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
    fontEvidence: {
      backendRevision: "tiqian-shared-harfbuzz-v5",
      harfbuzzVersion: "fixture",
      faces: [{
        faceId: `fixture-face-${input.publicUrl}`,
        sourceOrder: 0,
        family: "Fixture CJK",
        publicUrl: input.publicUrl,
        coverageText: input.text,
        probe: {
          text: input.text[0],
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
    },
    plan: fixturePlan(input.text),
    html: "",
    renderArtifactSha256: "c".repeat(64),
  };
}

test("the file transport writes, reads, lists, and sweeps by sha", () => {
  assert.ok(transport);
  const directory = mkdtempSync(path.join(tmpdir(), "tiqian-transport-"));
  try {
    const files = transport.createSnapshotTableFileTransport({ directory });
    const shaA = "a".repeat(64);
    const shaB = "b".repeat(64);
    assert.equal(files.urlFor(shaA), `/tiqian-tables/${shaA}.tiqtbl`);
    assert.equal(files.write({ bytes: Buffer.from("a"), sha256: shaA }), files.urlFor(shaA));
    files.write({ bytes: Buffer.from("b"), sha256: shaB });
    assert.deepEqual(new Set(files.listShas()), new Set([shaA, shaB]));
    assert.equal(files.read(shaA)?.toString("utf8"), "a");
    assert.equal(files.read("not-a-sha"), undefined);
    assert.equal(files.read("c".repeat(64)), undefined);
    assert.equal(files.sweep(new Set([shaA])), 1);
    assert.deepEqual(files.listShas(), [shaA]);
    assert.equal(files.sweep(new Set([shaA])), 0);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("the url pattern matches the emitted urls and nothing else", () => {
  assert.ok(transport);
  const directory = path.join(tmpdir(), "tiqian-transport-absent");
  const files = transport.createSnapshotTableFileTransport({ directory, urlPrefix: "/tables/" });
  const sha = "0123456789abcdef".repeat(4);
  const pattern = files.urlPattern();
  assert.deepEqual(Array.from(files.urlFor(sha).matchAll(pattern), (m) => m[1]), [sha]);
  pattern.lastIndex = 0;
  assert.equal(pattern.test(`/other/${sha}.tiqtbl`), false);
  pattern.lastIndex = 0;
  assert.equal(pattern.test(`/tables/${sha}.json`), false);
});

test(
  "a standalone bundle freezes its own table",
  { skip: transport === null },
  () => {
    assert.ok(transport);
    const item = fixturePrepared({ key: "p-1", text: "正文", publicUrl: "/fonts/a.woff2" });
    const standalone = transport.renderStandaloneSnapshotBundle(
      { paragraphs: [item], fontContractParagraphs: [] },
      "tq-item",
    );
    assert.ok(standalone);
    assert.equal(standalone.bundle.id, "tq-item");
    assert.equal(standalone.fontContractOnly, false);
    assert.equal(sha256(standalone.tableFile.bytes), standalone.tableFile.sha256);
    assert.equal(standalone.tableFile.bytes.subarray(0, 7).toString("utf8"), "TIQTBL0");
    assert.equal(
      transport.renderStandaloneSnapshotBundle({ paragraphs: [], fontContractParagraphs: [] }, "tq-empty"),
      undefined,
    );
  },
);

test(
  "a session interleaves absorb and data phases, freezes once, and assembles every bundle",
  { skip: transport === null },
  () => {
    assert.ok(transport);
    const first = fixturePrepared({ key: "p-1", text: "正文", publicUrl: "/fonts/a.woff2" });
    const second = fixturePrepared({ key: "p-2", text: "后文", publicUrl: "/fonts/b.woff2" });
    const session = transport.createSnapshotTableSession();
    let tableSha: string;
    try {
      const renderedFirst = session.renderData(
        { paragraphs: [first], fontContractParagraphs: [] },
        "tq-first",
      );
      assert.ok(renderedFirst);
      session.absorb([first]);
      const renderedSecond = session.renderData(
        { paragraphs: [second], fontContractParagraphs: [] },
        "tq-second",
      );
      assert.ok(renderedSecond);
      session.absorb([second]);
      const finalized = session.finish();
      tableSha = finalized.sha256;
      assert.equal(sha256(finalized.bytes), finalized.sha256);
      assert.equal(session.assemble(renderedFirst).id, "tq-first");
      assert.equal(session.assemble(renderedSecond).id, "tq-second");
      // The session table carries both faces; a standalone table one.
      assert.equal(finalized.bytes.readUInt32LE(8 + 8 * 4), 2);
      const standalone = transport.renderStandaloneSnapshotBundle(
        { paragraphs: [first], fontContractParagraphs: [] },
        "tq-first",
      );
      assert.ok(standalone);
      assert.equal(standalone.tableFile.bytes.readUInt32LE(8 + 8 * 4), 1);
      assert.notEqual(standalone.tableFile.sha256, tableSha);
    } finally {
      session.close();
    }
    assert.throws(() => session.absorb([]), /SnapshotTableSessionClosed/);
  },
);

test(
  "session guards reject mutation after the freeze and assembly before it",
  { skip: transport === null },
  () => {
    assert.ok(transport);
    const item = fixturePrepared({ key: "p-1", text: "正文", publicUrl: "/fonts/a.woff2" });
    const session = transport.createSnapshotTableSession();
    try {
      // A font-contract corpus never interns through its data phase, so the
      // entry absorbs first.
      session.absorb([item]);
      const rendered = session.renderData(
        { paragraphs: [], fontContractParagraphs: [item] },
        "tq-contract",
      );
      assert.ok(rendered);
      assert.equal(rendered.fontContractOnly, true);
      assert.throws(() => session.assemble(rendered), /SnapshotTableSessionUnfrozen/);
      session.finish();
      assert.throws(() => session.absorb([item]), /SnapshotTableSessionFrozen/);
      assert.throws(() => session.renderData({ paragraphs: [], fontContractParagraphs: [] }, "x"), /SnapshotTableSessionFrozen/);
      assert.throws(() => session.finish(), /SnapshotTableSessionFrozen/);
      assert.equal(session.assemble(rendered).id, "tq-contract");
    } finally {
      session.close();
      session.close();
    }
  },
);
