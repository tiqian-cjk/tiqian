// End-to-end bridge tests over the real addon (ADR 0052): the submission
// lanes must produce entry bytes identical to the JSON lanes, the drain and
// prefetch protocol must carry artifacts between precomputers, and the
// hash-only lane must serve hits without moving content.

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import type { CreatePrecomputerOptions } from "../src/precompute.js";
import { KIND_CONTRACT, KIND_SNAPSHOT } from "../lib/canonical.js";

type PrecomputeModule = typeof import("../src/precompute.js");
type CacheModule = typeof import("../src/cache.js");

let precompute: PrecomputeModule | null = null;
let cacheModule: CacheModule | null = null;
try {
  precompute = (await import("../lib/precompute.js")) as PrecomputeModule;
  cacheModule = (await import("../lib/cache.js")) as CacheModule;
} catch {
  precompute = null;
  cacheModule = null;
}

function readLocalFont(fileName: string): Buffer | null {
  try {
    return readFileSync(`${process.env.HOME}/.local/share/fonts/${fileName}`);
  } catch {
    return null;
  }
}

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

function artifactText(artifact: Uint8Array): string {
  return Buffer.from(artifact).toString("utf8");
}

test("submission bytes equal the JSON lane entry bytes", { skip: precompute === null }, async () => {
  assert.ok(precompute);
  assert.ok(cacheModule);
  const options = cjkPrecomputerOptions();
  if (options === null) return; // the engine path needs a CJK-covering face
  const precomputer = await precompute.createPrecomputer(options);
  const snapshotInput = { key: "p-0", text: "中文文字排版段落", maxWidthPx: 144 };
  const outcomes = precomputer.cache.submitContents([
    cacheModule.submissionItem(snapshotInput, KIND_SNAPSHOT),
  ]);
  assert.equal(outcomes.length, 1);
  assert.equal(outcomes[0]?.status, "computed");
  if (outcomes[0]?.status !== "computed") return;
  const lane = JSON.stringify(await precomputer.prepareParagraph(snapshotInput));
  assert.equal(artifactText(outcomes[0].artifact), lane);

  const contractInput = { key: "fc-0", text: "字体样本段落" };
  const contractOutcomes = precomputer.cache.submitContents([
    cacheModule.submissionItem(contractInput, KIND_CONTRACT),
  ]);
  assert.equal(contractOutcomes[0]?.status, "computed");
  if (contractOutcomes[0]?.status !== "computed") return;
  const contractLane = JSON.stringify(await precomputer.prepareFontContract(contractInput));
  assert.equal(artifactText(contractOutcomes[0].artifact), contractLane);
  precomputer.close();
});

test("drained records prefetch into a fresh precomputer", { skip: precompute === null }, async () => {
  assert.ok(precompute);
  assert.ok(cacheModule);
  const options = cjkPrecomputerOptions();
  if (options === null) return;
  const first = await precompute.createPrecomputer(options);
  const input = { key: "p-1", text: "中文文字排版段落", maxWidthPx: 144 };
  const item = cacheModule.submissionItem(input, KIND_SNAPSHOT);
  const outcomes = first.cache.submitContents([item]);
  assert.equal(outcomes[0]?.status, "computed");
  if (outcomes[0]?.status !== "computed") return;
  const expectedSha = createHash("sha256").update(outcomes[0].artifact).digest();

  const records = first.cache.drainWrites();
  assert.equal(records.length, 1);
  const record = records[0];
  assert.ok(record);
  assert.equal(record.tier, "snapshot");
  assert.equal(record.key.length, 32);
  assert.ok(Buffer.from(record.artifactSha).equals(expectedSha));

  // A fresh precomputer over the same configuration derives the same context,
  // so the records prefetch and the hash-only lane hits.
  const second = await precompute.createPrecomputer(options);
  const before = second.cache.submitHashes([item.hash]);
  assert.equal(before[0]?.status, "needContent");
  assert.equal(second.cache.prefetch(records), 1);
  const after = second.cache.submitHashes([item.hash]);
  assert.equal(after[0]?.status, "hit");
  if (after[0]?.status === "hit") {
    assert.ok(Buffer.from(after[0].artifactSha).equals(expectedSha));
  }
  // Eviction drops the warmed entry again.
  second.cache.evictExcept([]);
  assert.equal(second.cache.submitHashes([item.hash])[0]?.status, "needContent");
  first.close();
  second.close();
});

test("unsupported entries are cacheable values", { skip: precompute === null }, async () => {
  assert.ok(precompute);
  assert.ok(cacheModule);
  const options = cjkPrecomputerOptions();
  if (options === null) return;
  const precomputer = await precompute.createPrecomputer(options);
  const input = { key: "p-2", text: "带—破折号", maxWidthPx: 360 };
  const item = cacheModule.submissionItem(input, KIND_SNAPSHOT);
  const outcomes = precomputer.cache.submitContents([item]);
  assert.equal(outcomes[0]?.status, "computed");
  if (outcomes[0]?.status !== "computed") return;
  assert.match(artifactText(outcomes[0].artifact), /"status":"unsupported"/u);
  const markers = precomputer.cache.submitHashes([item.hash]);
  assert.equal(markers[0]?.status, "hit");
  precomputer.close();
});

test("prefilled content resolves through the waiting lane", { skip: precompute === null }, async () => {
  assert.ok(precompute);
  assert.ok(cacheModule);
  const options = cjkPrecomputerOptions();
  if (options === null) return;
  const precomputer = await precompute.createPrecomputer(options);
  const input = { key: "p-3", text: "中文文字排版段落", maxWidthPx: 144 };
  const item = cacheModule.submissionItem(input, KIND_SNAPSHOT);
  const queued = precomputer.cache.prefillContents([item]);
  assert.equal(queued, 1);
  // The waiting lane attaches to the in-flight job or reads the written
  // entry; both resolve as computed with the lane bytes.
  const outcomes = precomputer.cache.submitContents([item]);
  assert.equal(outcomes[0]?.status, "computed");
  if (outcomes[0]?.status !== "computed") return;
  const lane = JSON.stringify(await precomputer.prepareParagraph(input));
  assert.equal(artifactText(outcomes[0].artifact), lane);
  precomputer.close();
});

test("the context hex differs across typography changes", { skip: precompute === null }, async () => {
  assert.ok(precompute);
  assert.ok(cacheModule);
  const options = cjkPrecomputerOptions();
  if (options === null) return;
  const base = await precompute.createPrecomputer(options);
  const changed = await precompute.createPrecomputer({
    ...options,
    typography: { ...options.typography, fontSizePx: 20 },
  });
  assert.match(base.cache.context(), /^[0-9a-f]{64}$/u);
  assert.notEqual(base.cache.context(), changed.cache.context());
  base.close();
  changed.close();
});
