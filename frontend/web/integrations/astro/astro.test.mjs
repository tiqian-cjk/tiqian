import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

import { transform } from "@astrojs/compiler-rs";
import { build } from "astro";

import { tiqian } from "./integration.js";
import {
  hoistTiqianAstroAssets,
  renderAstroSnapshotAssets,
} from "./transport.js";

// The real-site build prerenders snapshot assets through the native addon.
// A checkout without an addon build cannot exercise that path. The suite for
// `@tiqian/precompute` skips on the same condition.
let addonBuildExists = false;
try {
  const precomputeHtml = await import("@tiqian/precompute/precompute-html");
  precomputeHtml.renderSnapshotServerAssets({
    id: "addon-probe",
    initialStyle: "",
    inertTemplate: "",
    fontPreloads: [],
  });
  addonBuildExists = true;
} catch {
  addonBuildExists = false;
}

test("package manifest publishes only the integration surface", async () => {
  const manifest = JSON.parse(await readFile(new URL("./package.json", import.meta.url), "utf8"));
  const prose = JSON.parse(await readFile(new URL("../../npm/package.json", import.meta.url), "utf8"));
  const precompute = JSON.parse(
    await readFile(new URL("../../../web-precompute/npm/package.json", import.meta.url), "utf8"),
  );
  assert.equal(manifest.peerDependencies["@tiqian/prose"], prose.version);
  assert.equal(manifest.peerDependencies["@tiqian/precompute"], precompute.version);
  assert.equal(manifest.engines.node, prose.engines.node);
  assert.deepEqual(Object.keys(manifest.exports).sort(), [".", "./TiqianProse.astro"]);
  assert.ok(manifest.files.includes("TiqianProse.astro"));
});

test("Astro component compiles", async () => {
  const source = await readFile(new URL("./TiqianProse.astro", import.meta.url), "utf8");
  const result = await transform(source, { filename: "TiqianProse.astro" });
  assert.ok(result.code.includes("tiqian-prose"));
});

test("integration exposes width-free preparation unless snapshot is explicit", () => {
  const integration = tiqian({
    fontStylesheets: [{ source: "/tmp/article.css", publicUrl: "/article.css" }],
    typography: { fontFamilies: ["Article Sans"], fontSizePx: 18, lineHeightPx: 32 },
  });
  let vitePlugin;
  integration.hooks["astro:config:setup"]({
    updateConfig(config) {
      vitePlugin = config.vite.plugins[0];
    },
  });
  const resolved = vitePlugin.resolveId("virtual:@tiqian/astro/preparer");
  const source = vitePlugin.load(resolved);
  assert.match(source, /const defaultSnapshot = null/u);
  assert.doesNotMatch(source, /maxWidthPx/u);
});

test("runtime-only Astro integration needs no typography or maximum width", () => {
  const integration = tiqian();
  let vitePlugin;
  integration.hooks["astro:config:setup"]({
    updateConfig(config) {
      vitePlugin = config.vite.plugins[0];
    },
  });
  const resolved = vitePlugin.resolveId("virtual:@tiqian/astro/preparer");
  const source = vitePlugin.load(resolved);
  assert.match(source, /html: String\(html\)/u);
  assert.doesNotMatch(source, /createHtmlPreparer|maxWidthPx/u);
});

test("Astro check may configure the integration without a build output", () => {
  const hook = tiqian().hooks["astro:config:done"];
  assert.doesNotThrow(() => hook({ buildOutput: undefined, injectTypes() {} }));
  assert.throws(
    () => hook({ buildOutput: "server", injectTypes() {} }),
    /TiqianAstroStaticOutputRequired/u,
  );
});

test("static transport hoists and deduplicates snapshot assets", () => {
  const assets = '<style data-tq-initial-snapshot="tq-page">x</style><template id="tq-page"></template>';
  const marker = renderAstroSnapshotAssets("tq-page", assets);
  const result = hoistTiqianAstroAssets(`<html><head></head><body>${marker}${marker}</body></html>`);
  assert.equal(result.count, 1);
  assert.equal(result.html.match(/<template id="tq-page"/gu)?.length, 1);
  assert.ok(result.html.indexOf("<template") < result.html.indexOf("</head>"));
  assert.doesNotMatch(result.html, /tiqian-astro-assets/u);
});

test("static transport preserves JavaScript replacement tokens in snapshot assets", () => {
  const replacementTokens = "$& $` $' $$";
  const assets = `<template id="tq-page">${replacementTokens}</template>`;
  const marker = renderAstroSnapshotAssets("tq-page", assets);
  const result = hoistTiqianAstroAssets(`<html><head></head><body>${marker}</body></html>`);
  assert.ok(result.html.includes(`<template id="tq-page">${replacementTokens}</template>`));
});

test("runtime-only component builds in a real static Astro site", { skip: addonBuildExists ? false : "no @tiqian/precompute addon build" }, async () => {
  const root = await mkdtemp(path.join(process.cwd(), ".astro-fixture-"));
  try {
    const pages = path.join(root, "src", "pages");
    await mkdir(pages, { recursive: true });
    await symlink(
      fileURLToPath(new URL("./node_modules", import.meta.url)),
      path.join(root, "node_modules"),
      "dir",
    );
    await writeFile(path.join(pages, "index.astro"), `---
      import TiqianProse from "@tiqian/astro/TiqianProse.astro";
      const prepared = {
        html: "<p>宿主投影正文。</p>",
        rootAttributes: { "snapshot-ref": "tq-host" },
        serverAssets: {
          id: "tq-host",
          initialStyle: ":root{--host-projection:1}",
          inertTemplate: '<template id="tq-host"></template>',
          fontPreloads: [],
        },
      };
    ---
    <html><head><title>fixture</title></head><body>
      <TiqianProse><p>语义正文。</p></TiqianProse>
      <TiqianProse {prepared} />
    </body></html>`);
    await build({
      root,
      outDir: path.join(root, "dist"),
      integrations: [tiqian()],
      logLevel: "silent",
    });
    const html = await readFile(path.join(root, "dist", "index.html"), "utf8");
    assert.match(html, /<tiqian-prose[^>]*><p>语义正文。<\/p><\/tiqian-prose>/u);
    assert.match(html, /<tiqian-prose[^>]*snapshot-ref="tq-host"[^>]*><p>宿主投影正文。<\/p><\/tiqian-prose>/u);
    assert.match(html, /<head>[\s\S]*data-tq-initial-snapshot="tq-host"/u);
    assert.equal(html.match(/<template id="tq-host"/gu)?.length, 1);
    assert.doesNotMatch(html, /tiqian-astro-assets/u);
    assert.doesNotMatch(html, /disabled|strong-as-emphasis-marks/u);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
