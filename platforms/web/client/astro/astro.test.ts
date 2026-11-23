import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

import { transform } from "@astrojs/compiler-rs";
import { build } from "astro";

import { tiqian } from "./dist/integration.js";
import {
  hoistTiqianAstroAssets,
  renderAstroSnapshotAssets,
} from "./dist/transport.js";

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
  const coreManifest = JSON.parse(await readFile(new URL("../core/package.json", import.meta.url), "utf8"));
  const webComponentManifest = JSON.parse(await readFile(new URL("../web-component/package.json", import.meta.url), "utf8"));
  const precompute = JSON.parse(
    await readFile(new URL("../../../../platforms/web/server/core/package.json", import.meta.url), "utf8"),
  );
  assert.equal(manifest.dependencies["@tiqian/core"], coreManifest.version);
  assert.equal(manifest.peerDependencies["@tiqian/web-component"], webComponentManifest.version);
  assert.equal(manifest.peerDependencies["@tiqian/precompute"], precompute.version);
  assert.equal(manifest.engines.node, webComponentManifest.engines.node);
  assert.deepEqual(Object.keys(manifest.exports).sort(), [".", "./TiqianProse.astro"]);
  assert.ok(manifest.files.includes("TiqianProse.astro"));
  assert.ok(manifest.files.includes("dist"));
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
  interface MockPlugin {
    resolveId(id: string): string | null;
    load(id: string | null): string | null;
  }
  interface MockViteConfig {
    vite?: {
      plugins?: readonly MockPlugin[];
    };
  }
  let vitePlugin: MockPlugin | undefined;
  const configSetup = integration.hooks["astro:config:setup"];
  assert.ok(configSetup);
  (configSetup as (options: { updateConfig: (config: MockViteConfig) => void }) => void)({
    updateConfig(config: MockViteConfig) {
      vitePlugin = config.vite?.plugins?.[0];
    },
  });
  assert.ok(vitePlugin);
  const resolved = vitePlugin.resolveId("virtual:@tiqian/astro/preparer");
  assert.ok(resolved);
  const source = vitePlugin.load(resolved);
  assert.ok(source);
  assert.match(source, /const defaultSnapshot = null/u);
  assert.doesNotMatch(source, /maxWidthPx/u);
});

test("runtime-only Astro integration needs no typography or maximum width", () => {
  const integration = tiqian();
  interface MockPlugin {
    resolveId(id: string): string | null;
    load(id: string | null): string | null;
  }
  interface MockViteConfig {
    vite?: {
      plugins?: readonly MockPlugin[];
    };
  }
  let vitePlugin: MockPlugin | undefined;
  const configSetup = integration.hooks["astro:config:setup"];
  assert.ok(configSetup);
  (configSetup as (options: { updateConfig: (config: MockViteConfig) => void }) => void)({
    updateConfig(config: MockViteConfig) {
      vitePlugin = config.vite?.plugins?.[0];
    },
  });
  assert.ok(vitePlugin);
  const resolved = vitePlugin.resolveId("virtual:@tiqian/astro/preparer");
  assert.ok(resolved);
  const source = vitePlugin.load(resolved);
  assert.ok(source);
  assert.match(source, /html: String\(html\)/u);
  assert.doesNotMatch(source, /createHtmlPreparer|maxWidthPx/u);
});

test("Astro check may configure the integration without a build output", () => {
  const hook = tiqian().hooks["astro:config:done"];
  assert.ok(hook);
  assert.doesNotThrow(() => (hook as (options: { buildOutput: undefined; injectTypes(): void }) => void)({ buildOutput: undefined, injectTypes() {} }));
  assert.throws(
    () => (hook as (options: { buildOutput: string; injectTypes(): void }) => void)({ buildOutput: "server", injectTypes() {} }),
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

test("the tables middleware serves transport URLs and passes others through", async () => {
  const { normalizeTiqianAstroTablesOptions, tiqianAstroTables, tiqianAstroTableMiddleware } =
    await import("./dist/tables.js");
  const root = await mkdtemp(path.join(process.cwd(), ".astro-tables-"));
  try {
    const sha = "1".repeat(64);
    const transport = tiqianAstroTables(
      normalizeTiqianAstroTablesOptions({ directory: path.join(root, "tables") }),
    );
    assert.ok(transport);
    transport.write({ bytes: Buffer.from("TIQTBL03-fixture"), sha256: sha });
    const middleware = tiqianAstroTableMiddleware(transport);
    interface ServeResult {
      readonly body?: string;
      readonly passed?: boolean;
    }
    const serve = (url: string): Promise<ServeResult> => new Promise((resolve) => {
      const chunks: string[] = [];
      middleware(
        { method: "GET", url },
        {
          setHeader(): void {},
          end(body?: Buffer | string): void {
            resolve({ body: chunks.join("") + (body ? String(body) : "") });
          },
        },
        () => resolve({ passed: true }),
      );
    });
    assert.deepEqual(await serve(`/tiqian-tables/${sha}.tiqtbl`), { body: "TIQTBL03-fixture" });
    assert.deepEqual(await serve(`/tiqian-tables/${"2".repeat(64)}.tiqtbl`), { passed: true });
    assert.deepEqual(await serve("/other.css"), { passed: true });
    assert.deepEqual(await serve(`/tiqian-tables/${sha}.tiqtbl?v=1`), { body: "TIQTBL03-fixture" });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("a tables-only integration ships referenced tables and sweeps stale ones", { skip: addonBuildExists ? false : "no @tiqian/precompute addon build" }, async () => {
  const { shipTiqianAstroTables, normalizeTiqianAstroTablesOptions, tiqianAstroTables } =
    await import("./dist/tables.js");
  const root = await mkdtemp(path.join(process.cwd(), ".astro-tables-ship-"));
  try {
    const transport = tiqianAstroTables(
      normalizeTiqianAstroTablesOptions({ directory: path.join(root, "cache") }),
    );
    assert.ok(transport);
    const live = "3".repeat(64);
    const stale = "4".repeat(64);
    transport.write({ bytes: Buffer.from("live"), sha256: live });
    transport.write({ bytes: Buffer.from("stale"), sha256: stale });
    const output = path.join(root, "dist");
    await mkdir(output, { recursive: true });
    await writeFile(
      path.join(output, "index.html"),
      `<html><head></head><body><tiqian-prose tq-tables="/tiqian-tables/${live}.tiqtbl"></tiqian-prose></body></html>`,
    );
    const logs: string[] = [];
    const result = await shipTiqianAstroTables(transport, output, {
      info(message: string) { logs.push(message); },
      error(message: string) { logs.push(message); },
    });
    assert.deepEqual(result, { shipped: 1, swept: 1, missing: [] });
    assert.deepEqual(await readFile(path.join(output, "tiqian-tables", `${live}.tiqtbl`), "utf8"), "live");
    assert.deepEqual(transport.listShas(), [live]);
    assert.match(logs.join("\n"), /snapshot tables: 1 shipped, 1 swept/u);
    // The integration entry registers the same hooks without typography.
    const integration = tiqian({ tables: { directory: path.join(root, "cache") } });
    assert.deepEqual(Object.keys(integration.hooks).sort(), [
      "astro:build:done",
      "astro:config:done",
      "astro:config:setup",
      "astro:server:setup",
    ]);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("runtime-only component builds in a real static Astro site", { skip: addonBuildExists ? false : "no @tiqian/precompute addon build" }, async () => {
  const root = await mkdtemp(path.join(process.cwd(), ".astro-fixture-"));
  try {
    const pages = path.join(root, "src", "pages");
    await mkdir(pages, { recursive: true });
    await symlink(
      fileURLToPath(new URL("../../../../node_modules", import.meta.url)),
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
