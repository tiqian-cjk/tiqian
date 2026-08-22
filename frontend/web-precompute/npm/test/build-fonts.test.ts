// Native-lane ports of the @tiqian/prose font-source suite (ADR 0050). The
// wrapper owns file reads and URL resolution; the CSS parse runs in Rust.
// These cases never read a font file, so they run wherever an addon build
// exists.

import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

import type { CreatePrecomputerOptions, SnapshotTypography } from "../src/precompute.js";

type PrecomputeModule = typeof import("../src/precompute.js");
type LoadModule = typeof import("../src/load.js");

let precompute: PrecomputeModule | null = null;
let load: LoadModule | null = null;
try {
  precompute = (await import("../lib/precompute.js")) as PrecomputeModule;
  load = (await import("../lib/load.js")) as LoadModule;
} catch {
  precompute = null;
  load = null;
}

const baseTypography: SnapshotTypography = {
  fontFamilies: ["Fixture CJK"],
  fontSizePx: 18,
  lineHeightPx: 27,
};

interface StylesheetFace {
  family: string;
  source: string;
  publicUrl: string;
  weight: number | [number, number] | null;
  style: string;
  unicodeRange: string;
}

test("explicit and stylesheet font sources conflict by name", { skip: precompute === null }, async () => {
  assert.ok(precompute);
  const options: CreatePrecomputerOptions = {
    typography: baseTypography,
    faces: [{ family: "Fixture CJK", publicUrl: "/fonts/f.woff2", source: Uint8Array.of(1) }],
    fontStylesheets: [{ source: "./host-fonts.css" }],
  };
  await assert.rejects(() => precompute.resolveFaces(options), /ConflictingBuildFontSources/u);
  await assert.rejects(
    () => precompute.resolveFaces({ typography: baseTypography }),
    /MissingBuildFontSource/u,
  );
});

test("remote font and stylesheet URLs remain unsupported", { skip: precompute === null }, async () => {
  assert.ok(precompute);
  await assert.rejects(
    () => precompute.resolveFaces({
      typography: baseTypography,
      faces: [{
        family: "Fixture CJK",
        publicUrl: "/fonts/misans-vf.woff2",
        source: "https://example.com/misans-vf.woff2",
      }],
    }),
    /RemoteFontSourceNotSupported:https:\/\/example\.com\/misans-vf\.woff2/u,
  );
  await assert.rejects(
    () => precompute.resolveFaces({
      typography: baseTypography,
      fontStylesheets: [{ source: "https://example.com/result.css" }],
    }),
    /RemoteFontStylesheetNotSupported:https:\/\/example\.com\/result\.css/u,
  );
});

test("Windows drive paths remain local font sources", { skip: precompute === null }, async () => {
  assert.ok(precompute);
  for (const source of [
    "D:\\__tiqian_missing_windows_drive_path__\\misans-vf.woff2",
    "D:/__tiqian_missing_windows_drive_path__/misans-vf.woff2",
  ]) {
    await assert.rejects(
      () => precompute.resolveFaces({
        typography: baseTypography,
        faces: [{ family: "Fixture CJK", publicUrl: "/fonts/misans-vf.woff2", source }],
      }),
      (error: unknown) => {
        assert.equal((error as NodeJS.ErrnoException).code, "ENOENT");
        assert.doesNotMatch(String((error as Error).message), /RemoteFontSourceNotSupported/u);
        return true;
      },
    );
  }
});

test("build font stylesheets reuse host families and resolve both asset namespaces", { skip: load === null }, () => {
  assert.ok(load);
  const css = `
    @font-face {
      font-family: "Fixture CJK";
      font-style: normal;
      font-weight: 500;
      src: local("Fixture CJK Medium"), url("./shards/fixture-001.woff2") format("woff2");
      unicode-range: U+4E00-4EFF;
    }
  `;
  const sourceUrl = new URL("./fixtures/host-fonts.css", import.meta.url);
  const faces = JSON.parse(load.addon.parseBuildFontStylesheet(css, sourceUrl.href, "/fonts/host-fonts.css")) as StylesheetFace[];

  assert.equal(faces.length, 1);
  assert.equal(faces[0].family, "Fixture CJK");
  assert.equal(
    faces[0].source,
    fileURLToPath(new URL("./fixtures/shards/fixture-001.woff2", import.meta.url)),
  );
  assert.equal(faces[0].publicUrl, "/fonts/shards/fixture-001.woff2");
  assert.equal(faces[0].weight, 500);
  assert.equal(faces[0].style, "normal");
  assert.equal(faces[0].unicodeRange, "U+4E00-4EFF");
});

test("relative font assets require the stylesheet's browser URL", { skip: load === null }, () => {
  assert.ok(load);
  assert.throws(
    () => load.addon.parseBuildFontStylesheet(
      "@font-face { font-family: Fixture; src: url(fixture.woff2); }",
      new URL("./fixtures/host-fonts.css", import.meta.url).href,
      null,
    ),
    /MissingFontStylesheetPublicUrl/u,
  );
});

test("Windows drive stylesheet URLs parse without a host filesystem", { skip: load === null }, () => {
  assert.ok(load);
  const faces = JSON.parse(load.addon.parseBuildFontStylesheet(
    "@font-face { font-family: \"Fixture CJK\"; src: url(\"./misans-vf.woff2\") format(\"woff2\"); }",
    "file:///D:/repo/neo-blog/src/fonts/MiSans-VF/result.css",
    "/fonts/result.css",
  )) as StylesheetFace[];
  assert.equal(faces.length, 1);
  assert.equal(faces[0].family, "Fixture CJK");
});
