import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

import { compile } from "svelte/compiler";

import {
  createTiqianSvelteKit,
  createTiqianTables,
  injectTiqianSsrAssets,
} from "./dist/server.js";

const fixtureAssets = {
  id: "tq-page",
  initialStyle: ":root{--fixture:1}",
  inertTemplate: '<template id="tq-page"></template>',
  fontPreloads: [],
};

// SSR asset rendering goes through the native addon, and the fixture build
// resolves the web-component runtime artifact the bundler must find on disk. The
// suites for `@tiqian/precompute` and `@tiqian/astro` skip on the same
// conditions.
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
// The workspace install hoists @tiqian/* as root node_modules symlinks; the
// fixture build below resolves every dependency through that single root.
const webComponentWorkspaceLinkExists = existsSync(new URL("../../../../node_modules/@tiqian/web-component", import.meta.url));

interface SpawnOptions {
  readonly cwd?: string;
}

function run(command: string, args: readonly string[], options?: SpawnOptions): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args as string[], { ...options, stdio: ["ignore", "pipe", "pipe"] });
    let output = "";
    child.stdout.on("data", (chunk: Buffer | string): void => { output += chunk; });
    child.stderr.on("data", (chunk: Buffer | string): void => { output += chunk; });
    child.on("error", reject);
    child.on("close", (code: number | null): void => {
      if (code === 0) {
        resolve(output);
      } else {
        reject(new Error(`FixtureBuildFailed:${code}\n${output}`));
      }
    });
  });
}

test("Svelte component compiles for client and server", async () => {
  const source = await readFile(new URL("./TiqianProse.svelte", import.meta.url), "utf8");
  assert.doesNotThrow(() => compile(source, { filename: "TiqianProse.svelte", generate: "client" }));
  const server = compile(source, { filename: "TiqianProse.svelte", generate: "server" });
  assert.match(server.js.code, /'strong-as-emphasis-marks': strongAsEmphasisMarks \|\| undefined/u);
});

test("Svelte SSR omits a false disabled Boolean attribute", async () => {
  interface SvelteServerInternal {
    attributes(attributes: Record<string, unknown>): string;
  }
  const { attributes: renderSsrAttributes } = (await import("svelte/internal/server")) as SvelteServerInternal;
  assert.equal(renderSsrAttributes({ disabled: false }), "");
  assert.equal(renderSsrAttributes({ disabled: true }), ' disabled=""');
});

test("package manifest publishes only the component and server boundary", async () => {
  const manifest = JSON.parse(await readFile(new URL("./package.json", import.meta.url), "utf8"));
  const webComponentManifest = JSON.parse(await readFile(new URL("../web-component/package.json", import.meta.url), "utf8"));
  const precompute = JSON.parse(
    await readFile(new URL("../../../../platforms/web/server/core/package.json", import.meta.url), "utf8"),
  );
  assert.equal(manifest.peerDependencies["@tiqian/web-component"], webComponentManifest.version);
  assert.equal(manifest.peerDependencies["@tiqian/precompute"], precompute.version);
  assert.equal(manifest.engines.node, webComponentManifest.engines.node);
  assert.deepEqual(Object.keys(manifest.exports).sort(), [".", "./server"]);
  assert.ok(manifest.files.includes("TiqianProse.svelte"));
  assert.ok(manifest.files.includes("dist"));
});

test("SSR transport injects each referenced snapshot once", { skip: addonBuildExists ? false : "no @tiqian/precompute addon build" }, () => {
  const html = '<html><head></head><body><tiqian-prose snapshot-ref="tq-page"></tiqian-prose>' +
    '<tiqian-prose snapshot-ref="tq-page"></tiqian-prose></body></html>';
  const output = injectTiqianSsrAssets(html, (id: string) => id === "tq-page" ? fixtureAssets : undefined);
  assert.equal(output.match(/<template id="tq-page"/gu)?.length, 1);
  assert.match(output, /data-tq-initial-snapshot="tq-page"/u);
  assert.ok(output.indexOf("<template") < output.indexOf("</head>"));
});

test("SSR transport preserves JavaScript replacement tokens in snapshot assets", { skip: addonBuildExists ? false : "no @tiqian/precompute addon build" }, () => {
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
    async prepare(html: string) {
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

test("a tables option writes per-item table files and stamps the root URL", async () => {
  const root = await mkdtemp(path.join(process.cwd(), ".sveltekit-tables-"));
  try {
    const sha256 = "a".repeat(64);
    const bytes = Buffer.from("TIQTBL03-fixture");
    const htmlPreparer = {
      async prepare(html: string) {
        return {
          html,
          rootAttributes: { "snapshot-ref": "tq-page" },
          clientBundle: null,
          serverAssets: fixtureAssets,
          tables: { bytes, sha256 },
          issues: [],
        };
      },
      close() {},
    };
    const tiqian = createTiqianSvelteKit({
      htmlPreparer,
      tables: { directory: path.join(root, "tables") },
    });
    const prepared = await tiqian.prepare("<p>正文</p>");
    assert.equal(prepared.rootAttributes["tq-tables"], `/tiqian-tables/${sha256}.tiqtbl`);
    assert.ok(tiqian.tables);
    assert.deepEqual(tiqian.tables.read(sha256), bytes);
    assert.deepEqual(tiqian.tables.listShas(), [sha256]);
    await tiqian.close();
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("createTiqianTables requires a directory option", () => {
  assert.throws(() => (createTiqianTables as () => void)(), /TiqianSvelteKitTablesOptionsInvalid/u);
  assert.throws(() => (createTiqianTables as (opt: null) => void)(null), /TiqianSvelteKitTablesOptionsInvalid/u);
  assert.throws(() => (createTiqianTables as (opt: Record<string, never>) => void)({}), /TiqianSvelteKitTablesDirectoryRequired/u);
  assert.throws(
    () => (createTiqianTables as (opt: { directory: string; devDirectory: number }) => void)({ directory: "tables", devDirectory: 3 }),
    /TiqianSvelteKitTablesOptionsInvalid/u,
  );
});

test("createTiqianTables writes devDirectory outside production", async () => {
  const root = await mkdtemp(path.join(process.cwd(), ".sveltekit-tables-"));
  const previousNodeEnv = process.env.NODE_ENV;
  try {
    const build = path.join(root, "build");
    const dev = path.join(root, "dev");
    const sha256 = "b".repeat(64);
    const bytes = Buffer.from("TIQTBL03-fixture");

    process.env.NODE_ENV = "development";
    const development = createTiqianTables({ directory: build, devDirectory: dev });
    development.write({ bytes, sha256 });
    assert.deepEqual(development.read(sha256), bytes);
    assert.equal(existsSync(path.join(build, `${sha256}.tiqtbl`)), false);

    delete process.env.NODE_ENV;
    const unset = createTiqianTables({ directory: build, devDirectory: dev });
    unset.write({ bytes, sha256 });
    assert.equal(existsSync(path.join(build, `${sha256}.tiqtbl`)), false);

    process.env.NODE_ENV = "production";
    const production = createTiqianTables({ directory: build, devDirectory: dev });
    production.write({ bytes, sha256 });
    assert.deepEqual(production.read(sha256), bytes);
    assert.equal(existsSync(path.join(build, `${sha256}.tiqtbl`)), true);
    assert.equal(production.urlFor(sha256), `/tiqian-tables/${sha256}.tiqtbl`);
  } finally {
    if (previousNodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = previousNodeEnv;
    await rm(root, { recursive: true, force: true });
  }
});

test("a tables option routes non-production writes through devDirectory", async () => {
  const root = await mkdtemp(path.join(process.cwd(), ".sveltekit-tables-"));
  const previousNodeEnv = process.env.NODE_ENV;
  try {
    process.env.NODE_ENV = "development";
    const build = path.join(root, "build");
    const dev = path.join(root, "dev");
    const sha256 = "c".repeat(64);
    const bytes = Buffer.from("TIQTBL03-fixture");
    const htmlPreparer = {
      async prepare(html: string) {
        return {
          html,
          rootAttributes: { "snapshot-ref": "tq-page" },
          clientBundle: null,
          serverAssets: fixtureAssets,
          tables: { bytes, sha256 },
          issues: [],
        };
      },
      close() {},
    };
    const tiqian = createTiqianSvelteKit({
      htmlPreparer,
      tables: { directory: build, devDirectory: dev },
    });
    const prepared = await tiqian.prepare("<p>正文</p>");
    assert.equal(prepared.rootAttributes["tq-tables"], `/tiqian-tables/${sha256}.tiqtbl`);
    assert.ok(tiqian.tables);
    assert.deepEqual(tiqian.tables.read(sha256), bytes);
    assert.equal(existsSync(path.join(build, `${sha256}.tiqtbl`)), false);
    assert.equal(existsSync(path.join(dev, `${sha256}.tiqtbl`)), true);
    await tiqian.close();
  } finally {
    if (previousNodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = previousNodeEnv;
    await rm(root, { recursive: true, force: true });
  }
});

test("server integration rejects an unbounded retention setting", () => {
  assert.throws(
    () => createTiqianSvelteKit({ maximumRetainedBundles: 0, htmlPreparer: { prepare: async () => ({} as never), close() {} } }),
    /InvalidMaximumRetainedTiqianBundles/u,
  );
});

test("one retention scope rejects conflicting assets that reuse an id", async () => {
  const htmlPreparer = {
    async prepare(html: string) {
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

test("concurrent requests cannot exchange assets that reuse an explicit id", { skip: addonBuildExists ? false : "no @tiqian/precompute addon build" }, async () => {
  const htmlPreparer = {
    async prepare(html: string) {
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
  interface MockEvent {
    readonly source: string;
  }
  interface MockResolveOptions {
    transformPageChunk(input: { html: string; done: boolean }): string;
  }
  const render = (source: string): Promise<string> => (tiqian.handle as (input: {
    event: MockEvent;
    resolve: (event: MockEvent, options: MockResolveOptions) => Promise<string>;
  }) => Promise<string>)({
    event: { source },
    resolve: async (event: MockEvent, options: MockResolveOptions): Promise<string> => {
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

test("component builds in a real SvelteKit application", { skip: webComponentWorkspaceLinkExists ? false : "no @tiqian/web-component workspace link" }, async () => {
  const root = await mkdtemp(path.join(process.cwd(), ".sveltekit-fixture-"));
  try {
    const routes = path.join(root, "src", "routes");
    await mkdir(routes, { recursive: true });
    await symlink(
      fileURLToPath(new URL("../../../../node_modules", import.meta.url)),
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
      [fileURLToPath(new URL("../../../../node_modules/vite/bin/vite.js", import.meta.url)), "build"],
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
