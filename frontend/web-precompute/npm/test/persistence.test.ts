// Persistence SDK tests over the real addon (ADR 0052). The render lanes
// must return exactly the JSON batch lanes' entries, the second process must
// resolve from the store without computing, and a tampered store copy must
// demote to the content path instead of returning wrong bytes.

import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import type { CreatePrecomputerOptions } from "../src/precompute.js";
import type { PersistentCacheStore } from "../src/persistence.js";

type PrecomputeModule = typeof import("../src/precompute.js");
type PersistenceModule = typeof import("../src/persistence.js");

let precompute: PrecomputeModule | null = null;
let persistence: PersistenceModule | null = null;
try {
  precompute = (await import("../lib/precompute.js")) as PrecomputeModule;
  persistence = (await import("../lib/persistence.js")) as PersistenceModule;
} catch {
  precompute = null;
  persistence = null;
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

/** The plain address-to-bytes store the SDK expects from a host. */
function memoryStore(): PersistentCacheStore & { blobs: Map<string, Uint8Array> } {
  const blobs = new Map<string, Uint8Array>();
  return {
    blobs,
    read(addresses: readonly string[]): Map<string, Uint8Array> {
      const found = new Map<string, Uint8Array>();
      for (const address of addresses) {
        const blob = blobs.get(address);
        if (blob !== undefined) found.set(address, blob);
      }
      return found;
    },
    write(entries: readonly (readonly [string, Uint8Array])[]): void {
      for (const [address, blob] of entries) {
        blobs.set(address, blob);
      }
    },
  };
}

const SNAPSHOTS = [
  { key: "p-0", text: "中文文字排版段落", maxWidthPx: 144 },
  { key: "p-1", text: "第二段正文，含标点。", maxWidthPx: 144 },
  { key: "p-2", text: "带—破折号", maxWidthPx: 360 },
] as const;

test("render results equal the JSON batch lanes", { skip: precompute === null }, async () => {
  assert.ok(precompute);
  assert.ok(persistence);
  const options = cjkPrecomputerOptions();
  if (options === null) return; // the engine path needs a CJK-covering face
  const precomputer = await precompute.createPrecomputer(options);
  const cache = persistence.createPersistentCache(precomputer, memoryStore());
  const rendered = await cache.renderSnapshots(SNAPSHOTS);
  const lane = await precomputer.prepareParagraphs([...SNAPSHOTS]);
  assert.deepEqual(rendered, lane);
  assert.equal(rendered[2]?.status, "unsupported");
  const contracts = await cache.renderContracts([
    { key: "fc-0", text: "字体样本段落" },
    { key: "fc-1", text: "第二样本段落" },
  ]);
  const contractLane = await precomputer.prepareFontContracts([
    { key: "fc-0", text: "字体样本段落" },
    { key: "fc-1", text: "第二样本段落" },
  ]);
  assert.deepEqual(contracts, contractLane);
  precomputer.close();
});

test("a second precomputer resolves from the store without computing", { skip: precompute === null }, async () => {
  assert.ok(precompute);
  assert.ok(persistence);
  const options = cjkPrecomputerOptions();
  if (options === null) return;
  const store = memoryStore();
  const first = await precompute.createPrecomputer(options);
  const firstCache = persistence.createPersistentCache(first, store);
  const rendered = await firstCache.renderSnapshots(SNAPSHOTS);
  const written = await firstCache.flush();
  assert.equal(written, SNAPSHOTS.length);
  first.close();

  // A fresh precomputer over the same options shares the context, so every
  // address resolves from the store and nothing reaches the renderer.
  const second = await precompute.createPrecomputer(options);
  const secondCache = persistence.createPersistentCache(second, store);
  const again = await secondCache.renderSnapshots(SNAPSHOTS);
  assert.deepEqual(again, rendered);
  assert.equal(second.cache.drainWrites().length, 0);
  assert.equal(await secondCache.flush(), 0);
  // Warming against the same store reports every item accepted.
  assert.equal(await secondCache.warmSnapshots(SNAPSHOTS), SNAPSHOTS.length);
  second.close();
});

test("a tampered store copy demotes to the content path", { skip: precompute === null }, async () => {
  assert.ok(precompute);
  assert.ok(persistence);
  const options = cjkPrecomputerOptions();
  if (options === null) return;
  const store = memoryStore();
  const precomputer = await precompute.createPrecomputer(options);
  const cache = persistence.createPersistentCache(precomputer, store);
  const rendered = await cache.renderSnapshots(SNAPSHOTS);
  await cache.flush();
  // Corrupt one stored blob: the digest check must fail and the item must
  // come back from a fresh computation with the lane's bytes.
  const target = [...store.blobs.keys()].sort()[0];
  const blob = store.blobs.get(target);
  assert.ok(blob);
  const corrupted = Buffer.from(blob);
  corrupted[corrupted.length - 1] ^= 0xff;
  store.blobs.set(target, corrupted);
  const again = await cache.renderSnapshots(SNAPSHOTS);
  assert.deepEqual(again, rendered);
  precomputer.close();
});

test("addresses stay apart across typography contexts", { skip: precompute === null }, async () => {
  assert.ok(precompute);
  assert.ok(persistence);
  const options = cjkPrecomputerOptions();
  if (options === null) return;
  const store = memoryStore();
  const base = await precompute.createPrecomputer(options);
  const baseCache = persistence.createPersistentCache(base, store);
  const changed = await precompute.createPrecomputer({
    ...options,
    typography: { ...options.typography, lineHeightPx: 30 },
  });
  const changedCache = persistence.createPersistentCache(changed, store);
  const input = [{ key: "p-0", text: "中文文字排版段落", maxWidthPx: 144 }] as const;
  const baseEntry = await baseCache.renderSnapshots(input);
  const changedEntry = await changedCache.renderSnapshots(input);
  // Same content under two contexts: two addresses, two artifacts.
  await baseCache.flush();
  await changedCache.flush();
  assert.equal(store.blobs.size, 2);
  if (baseEntry[0]?.status === "prepared" && changedEntry[0]?.status === "prepared") {
    assert.notEqual(baseEntry[0].typographySha256, changedEntry[0].typographySha256);
  }
  base.close();
  changed.close();
});
