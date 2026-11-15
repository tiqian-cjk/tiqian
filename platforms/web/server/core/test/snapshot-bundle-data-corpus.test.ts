// Byte-parity gate of the shared renderer in the server package (criterion
// 3). The committed prepared-DOM corpus fixture carries the shared renderer's
// bytes; this test asserts the same file case by case. The
// bundle data phase drives the same shared module (`@tiqian/prose/prepared-dom`,
// the browser implementation), so replaying the fixture's call shape here
// must reproduce every committed byte.
//
// The bundle lane calls the renderer with a value-style class callback
// (`styleClassFor` -> `tqv-N`) where the fixture uses inline styles or the
// declaration-length callback; the second test pins that call shape's class
// sequence and the cross-gold test pins the artifact hash composition.

import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { renderPreparedParagraphArtifact } from "@tiqian/prose/prepared-dom";

import { renderSnapshotBundleData } from "../lib/precompute.js";
import { ValueStyleInterner } from "@tiqian/shared/org/tiqian/shared/ValueStyleInterner";

interface FixtureExpectOk {
  kind: "ok";
  html: string;
  artifact: string;
}
interface FixtureExpectError {
  kind: "error";
  error: string;
}
interface FixtureCase {
  name: string;
  plan: string;
  locale: string;
  options: Record<string, unknown>;
  expect: FixtureExpectOk | FixtureExpectError;
}

const fixture = JSON.parse(
  readFileSync(
    new URL("../../../client/web-component/tests/prepared-dom-corpus.fixture.json", import.meta.url),
    "utf8",
  ),
) as { cases: FixtureCase[] };

const STYLE_CLASS_MODES: Record<string, (declaration: string) => string> = {
  "declaration-length": (declaration: string) => "tqc-" + declaration.length,
};

const EMPHASIS_DOT_COLOR_MODES: Record<string, () => string> = {
  "fixed-color": () => "rgb(17, 34, 51)",
};

function fixtureCallOptions(options: Record<string, unknown>): Record<string, unknown> {
  const call: Record<string, unknown> = { ...options };
  const styleMode = options.styleClassFor;
  const dotMode = options.emphasisDotColor;
  delete call.styleClassFor;
  delete call.emphasisDotColor;
  if (typeof styleMode === "string") call.styleClassFor = STYLE_CLASS_MODES[styleMode];
  if (typeof dotMode === "string") call.emphasisDotColor = EMPHASIS_DOT_COLOR_MODES[dotMode];
  return call;
}

test("the shared renderer reproduces the Rust corpus bytes", () => {
  let checked = 0;
  for (const testCase of fixture.cases) {
    if (testCase.expect.kind === "ok") {
      checked += 1;
      const rendered = renderPreparedParagraphArtifact(
        testCase.plan,
        testCase.locale,
        fixtureCallOptions(testCase.options),
      );
      assert.equal(rendered.html, testCase.expect.html, "html: " + testCase.name);
      assert.equal(JSON.stringify(rendered.artifact), testCase.expect.artifact, "artifact: " + testCase.name);
    } else {
      const expectError = testCase.expect;
      assert.throws(
        () => renderPreparedParagraphArtifact(testCase.plan, testCase.locale, fixtureCallOptions(testCase.options)),
        (error: unknown) => {
          assert.equal((error as Error).message, expectError.error, "error: " + testCase.name);
          return true;
        },
      );
    }
  }
  assert.ok(checked >= 20, "the corpus keeps covering the lowering paths");
});

function tables() {
  return { kind: "snapshot-tables", handle: "corpus-unused", valueStyles: new ValueStyleInterner() };
}

function entry(plan: string, patch: Record<string, unknown> = {}) {
  return {
    status: "prepared",
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v16",
    key: "p-1",
    sourceSha256: "a".repeat(64),
    sourceArtifactSha256: "b".repeat(64),
    semantics: [],
    inlineBoxes: [],
    renderTextSpans: [],
    typographySha256: "c".repeat(64),
    maxWidthPx: 360,
    typography: { locale: "zh-Hans" },
    renderFontFamilies: ["Fixture CJK"],
    fontEvidence: null,
    plan,
    html: "",
    renderArtifactSha256: "d".repeat(64),
    ...patch,
  } as never;
}

const STYLE_DELTA_PLAN = '{"schema":1,"layoutRevision":"tiqian-layout-v2","width":320,"height":48,"lines":[{"rangeStart":0,"rangeEnd":2,"top":0,"bottom":32,"baseline":24,"indent":0,"visualWidth":36,"hyphenAdvance":0,"endReason":"ParagraphEnd","cells":[{"rangeStart":0,"rangeEnd":1,"source":"排","display":"排","drawX":0,"naturalWidth":18,"leadingLayoutAdvance":0},{"rangeStart":1,"rangeEnd":2,"source":"版","display":"版","drawX":18,"naturalWidth":18,"leadingLayoutAdvance":0,"style":{"fontSize":12,"fontWeight":700}}]}]}';

test("the data phase mints tqv classes in first-seen order", () => {
  const snapshotTables = tables();
  const data = renderSnapshotBundleData([entry(STYLE_DELTA_PLAN)], {
    id: "tq-page",
    snapshotTables: snapshotTables as never,
  });
  const rendered = (JSON.parse(data.json) as {
    renderedEntries: { html: string; renderArtifactSha256: string }[];
  }).renderedEntries[0];
  // The line marker's geometry declaration mints first, the style delta second.
  assert.match(rendered.html, /class="tq-line tqv-0"/u);
  assert.match(rendered.html, /class="tqv-1"/u);
  assert.deepEqual([...data.usedValueStyleIndexes], [0, 1]);
  assert.equal(snapshotTables.valueStyles.size(), 2);
  assert.equal(rendered.renderArtifactSha256.length, 64);
});

test("the data phase rejects the corpus error cases by name", () => {
  for (const testCase of fixture.cases) {
    if (testCase.expect.kind !== "error") continue;
    const expectError = testCase.expect;
    assert.throws(
      () => renderSnapshotBundleData([entry(testCase.plan, {
        semantics: testCase.options.semantics ?? [],
        inlineBoxes: testCase.options.inlineBoxes ?? [],
        renderTextSpans: testCase.options.renderTextSpans ?? [],
      })], { id: "tq-page", snapshotTables: tables() as never }),
      (error: unknown) => {
        assert.equal((error as Error).message, expectError.error, "error: " + testCase.name);
        return true;
      },
    );
  }
});
