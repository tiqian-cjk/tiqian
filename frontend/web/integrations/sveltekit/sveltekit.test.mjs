import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

import { compile } from "svelte/compiler";
import { attributes as renderSsrAttributes } from "svelte/internal/server";

import {
  createTiqianSvelteKit,
  injectTiqianSsrAssets,
} from "./server.js";

const fixtureAssets = {
  id: "tq-page",
  initialStyle: ":root{--fixture:1}",
  inertTemplate: '<template id="tq-page"></template>',
  fontPreloads: [],
};

function run(command, args, options) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { ...options, stdio: ["ignore", "pipe", "pipe"] });
    let output = "";
    child.stdout.on("data", (chunk) => { output += chunk; });
    child.stderr.on("data", (chunk) => { output += chunk; });
    child.on("error", reject);
    child.on("close", (code) => code === 0
      ? resolve(output)
      : reject(new Error(`FixtureBuildFailed:${code}\n${output}`)));
  });
}

test("Svelte component compiles for client and server", async () => {
  const source = await readFile(new URL("./TiqianProse.svelte", import.meta.url), "utf8");
  assert.doesNotThrow(() => compile(source, { filename: "TiqianProse.svelte", generate: "client" }));
  const server = compile(source, { filename: "TiqianProse.svelte", generate: "server" });
  assert.match(server.js.code, /'strong-as-emphasis-marks': strongAsEmphasisMarks \|\| undefined/u);
});

test("Svelte SSR omits a false disabled Boolean attribute", () => {
  assert.equal(renderSsrAttributes({ disabled: false }), "");
  assert.equal(renderSsrAttributes({ disabled: true }), ' disabled=""');
});

test("package manifest publishes only the component and server boundary", async () => {
  const manifest = JSON.parse(await readFile(new URL("./package.json", import.meta.url), "utf8"));
  const prose = JSON.parse(await readFile(new URL("../../npm/package.json", import.meta.url), "utf8"));
  const precompute = JSON.parse(
    await readFile(new URL("../../../web-precompute/npm/package.json", import.meta.url), "utf8"),
  );
  assert.equal(manifest.peerDependencies["@tiqian/prose"], prose.version);
  assert.equal(manifest.peerDependencies["@tiqian/precompute"], precompute.version);
  assert.equal(manifest.engines.node, prose.engines.node);
  assert.deepEqual(Object.keys(manifest.exports).sort(), [".", "./server"]);
  assert.ok(manifest.files.includes("TiqianProse.svelte"));
});

test("SSR transport injects each referenced snapshot once", () => {
  const html = '<html><head></head><body><tiqian-prose snapshot-ref="tq-page"></tiqian-prose>' +
    '<tiqian-prose snapshot-ref="tq-page"></tiqian-prose></body></html>';
  const output = injectTiqianSsrAssets(html, (id) => id === "tq-page" ? fixtureAssets : undefined);
  assert.equal(output.match(/<template id="tq-page"/gu)?.length, 1);
  assert.match(output, /data-tq-initial-snapshot="tq-page"/u);
  assert.ok(output.indexOf("<template") < output.indexOf("</head>"));
});

test("SSR transport preserves JavaScript replacement tokens in snapshot assets", () => {
  const replacementTokens = "$& $` $' $$";
  const assets = {
    ...fixtureAssets,
    inertTemplate: `<template id="tq-page">${replacementTokens}</template>`,
  };
  const html =
    '<html><head></head><body><tiqian-prose snapshot-ref="tq-page"></tiqian-prose></body></html>';
  const output = injectTiqianSsrAssets(html, () => assets);
  assert.ok(output.includes(`<template id="tq-page">${replacementTokens}</template>`));
});

test("server prepare returns only compact navigation state", async () => {
  const htmlPreparer = {
    async prepare(html) {
      return {
        html,
        rootAttributes: { "snapshot-ref": "tq-page" },
        clientBundle: {
          id: "tq-page",
          clientTemplate: '<template id="tq-page"></template>',
          initialStyle: "",
          fontPreloads: [],
        },
        serverAssets: fixtureAssets,
        issues: [],
      };
    },
    close() {},
  };
  const tiqian = createTiqianSvelteKit({ htmlPreparer });
  const prepared = await tiqian.prepare("<p>正文</p>");
  assert.equal(prepared.html, "<p>正文</p>");
  assert.equal("serverAssets" in prepared, false);
  assert.equal(tiqian.getServerAssets("tq-page"), fixtureAssets);
  await tiqian.close();
});

test("server integration rejects an unbounded retention setting", () => {
  assert.throws(
    () => createTiqianSvelteKit({ maximumRetainedBundles: 0, htmlPreparer: {} }),
    /InvalidMaximumRetainedTiqianBundles/u,
  );
});

test("one retention scope rejects conflicting assets that reuse an id", async () => {
  const htmlPreparer = {
    async prepare(html) {
      return {
        html,
        rootAttributes: { "snapshot-ref": "shared-id" },
        clientBundle: null,
        serverAssets: {
          id: "shared-id",
          initialStyle: `:root{--source:${html}}`,
          inertTemplate: `<template id="shared-id" data-source="${html}"></template>`,
          fontPreloads: [],
        },
        issues: [],
      };
    },
    close() {},
  };
  const tiqian = createTiqianSvelteKit({ htmlPreparer });
  try {
    await tiqian.prepare("first", { id: "shared-id" });
    await assert.rejects(
      tiqian.prepare("second", { id: "shared-id" }),
      /ConflictingTiqianSvelteKitAssets:shared-id/u,
    );
  } finally {
    await tiqian.close();
  }
});

test("concurrent requests cannot exchange assets that reuse an explicit id", async () => {
  const htmlPreparer = {
    async prepare(html) {
      await new Promise((resolve) => setTimeout(resolve, html === "first" ? 5 : 0));
      return {
        html: `<p>${html}</p>`,
        rootAttributes: { "snapshot-ref": "shared-id" },
        clientBundle: null,
        serverAssets: {
          id: "shared-id",
          initialStyle: `:root{--request:${html}}`,
          inertTemplate: `<template id="shared-id" data-request="${html}"></template>`,
          fontPreloads: [],
        },
        issues: [],
      };
    },
    close() {},
  };
  const tiqian = createTiqianSvelteKit({ htmlPreparer });
  const render = (source) => tiqian.handle({
    event: { source },
    resolve: async (event, options) => {
      await tiqian.prepare(event.source, { id: "shared-id" });
      await new Promise((resolve) => setTimeout(resolve, event.source === "second" ? 10 : 0));
      return options.transformPageChunk({
        html: '<html><head></head><body><tiqian-prose snapshot-ref="shared-id"></tiqian-prose></body></html>',
        done: true,
      });
    },
  });

  const [first, second] = await Promise.all([render("first"), render("second")]);
  assert.match(first, /data-request="first"/u);
  assert.doesNotMatch(first, /data-request="second"/u);
  assert.match(second, /data-request="second"/u);
  assert.doesNotMatch(second, /data-request="first"/u);
  await tiqian.close();
});

test("component builds in a real SvelteKit application", async () => {
  const root = await mkdtemp(path.join(process.cwd(), ".sveltekit-fixture-"));
  try {
    const routes = path.join(root, "src", "routes");
    await mkdir(routes, { recursive: true });
    await symlink(
      fileURLToPath(new URL("./node_modules", import.meta.url)),
      path.join(root, "node_modules"),
      "dir",
    );
    await writeFile(path.join(root, "svelte.config.js"), `
      const adapter = { name: "fixture", async adapt() {} };
      export default { kit: { adapter } };
    `);
    await writeFile(path.join(root, "vite.config.js"), `
      import { sveltekit } from "@sveltejs/kit/vite";
      export default { plugins: [sveltekit()] };
    `);
    await writeFile(path.join(root, "src", "app.html"), `
      <!doctype html><html><head>%sveltekit.head%</head><body>
        <div style="display: contents">%sveltekit.body%</div>
      </body></html>
    `);
    await writeFile(path.join(routes, "+page.svelte"), `
      <script>
        import TiqianProse from "@tiqian/sveltekit";
      </script>
      <TiqianProse html="<p>语义正文。</p>" />
    `);
    await run(
      process.execPath,
      [fileURLToPath(new URL("./node_modules/vite/bin/vite.js", import.meta.url)), "build"],
      { cwd: root },
    );
    const serverManifest = await readFile(
      path.join(root, ".svelte-kit", "output", "server", "manifest-full.js"),
      "utf8",
    );
    assert.match(serverManifest, /id: "\/"/u);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
