import assert from "node:assert/strict";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { createBuildFontSession, parseBuildFontStylesheet } from "./precompute-node-fonts.js";

test("build font stylesheets reuse host families and resolve both asset namespaces", () => {
  const faces = parseBuildFontStylesheet(`
    @font-face {
      font-family: "Fixture CJK";
      font-style: normal;
      font-weight: 500;
      src: local("Fixture CJK Medium"), url("./shards/fixture-001.woff2") format("woff2");
      unicode-range: U+4E00-4EFF;
    }
  `, {
    source: new URL("./fixtures/host-fonts.css", import.meta.url),
    publicUrl: "/fonts/host-fonts.css",
  });

  assert.equal(faces.length, 1);
  assert.equal(faces[0].family, "Fixture CJK");
  assert.equal(faces[0].source, fileURLToPath(new URL(
    "./fixtures/shards/fixture-001.woff2",
    import.meta.url,
  )));
  assert.equal(faces[0].publicUrl, "/fonts/shards/fixture-001.woff2");
  assert.equal(faces[0].weight, 500);
  assert.equal(faces[0].style, "normal");
  assert.equal(faces[0].unicodeRange, "U+4E00-4EFF");
});

test("relative font assets require the stylesheet's browser URL", () => {
  assert.throws(() => parseBuildFontStylesheet(`
    @font-face { font-family: Fixture; src: url(fixture.woff2); }
  `, {
    source: new URL("./fixtures/host-fonts.css", import.meta.url),
  }), /MissingFontStylesheetPublicUrl/u);
});

test("Windows drive paths remain local font and stylesheet sources", async () => {
  for (const source of [
    "D:\\__tiqian_missing_windows_drive_path__\\misans-vf.woff2",
    "D:/__tiqian_missing_windows_drive_path__/misans-vf.woff2",
  ]) {
    await assert.rejects(createBuildFontSession({
      faces: [{
        family: "Fixture CJK",
        source,
        publicUrl: "/fonts/misans-vf.woff2",
        weight: 400,
        style: "normal",
      }],
    }), (error) => {
      assert.equal(error?.code, "ENOENT");
      assert.doesNotMatch(String(error?.message), /RemoteFontSourceNotSupported/u);
      return true;
    });
  }

  assert.doesNotThrow(() => parseBuildFontStylesheet(`
    @font-face {
      font-family: "Fixture CJK";
      src: url("./misans-vf.woff2") format("woff2");
    }
  `, {
    source: "D:\\repo\\neo-blog\\src\\fonts\\MiSans-VF\\result.css",
    publicUrl: "/fonts/result.css",
  }));
});

test("remote font and stylesheet URLs remain unsupported", async () => {
  await assert.rejects(createBuildFontSession({
    faces: [{
      family: "Fixture CJK",
      source: "https://example.com/misans-vf.woff2",
      publicUrl: "/fonts/misans-vf.woff2",
      weight: 400,
      style: "normal",
    }],
  }), /RemoteFontSourceNotSupported:https:\/\/example\.com\/misans-vf\.woff2/u);

  assert.throws(() => parseBuildFontStylesheet(`
    @font-face {
      font-family: "Fixture CJK";
      src: url("./misans-vf.woff2") format("woff2");
    }
  `, {
    source: "https://example.com/result.css",
    publicUrl: "/fonts/result.css",
  }), /RemoteFontStylesheetNotSupported:https:\/\/example\.com\/result\.css/u);
});
