// FrameworkCommitConflict: React and Svelte keep references to the DOM nodes
// they render and commit mutations through them. Tiqian takeover moves a
// paragraph's semantic children into a detached raw-dom fragment, so a
// framework commit that re-parents, anchors, or removes those children would
// either throw NotFoundError against the live paragraph or edit inside
// the raw-dom fragment where no live observer fires. This suite drives REAL framework
// runtimes (react-dom 19 via its CJS build, Svelte 5 via locally compiled
// components; both are devDependencies served straight from node_modules)
// through mount, text update, anchored insert, remove, reorder, conditional
// swap, batch, mid-flight update, and unmount scenarios, and asserts after
// every step that the paragraph re-rendered from the framework's current
// content with no framework commit errors.
//
// Long-page scenarios mount several concurrent roots on a tall page and edit
// paragraphs in all three engine tiers: inside the viewport, inside the
// observer band but off-screen, and beyond the band. Roots and paragraphs
// both enter and leave the DOM and the viewport mid-test.
//
// Svelte components are compiled once at test start with the local
// svelte/compiler. The page loads frameworks through a small in-page
// CommonJS loader (react-dom 19 ships no UMD) and an import map that maps
// the two bare specifiers svelte's own source uses (svelte, esm-env).

import test, { type TestContext } from "node:test";
import assert from "node:assert/strict";
import { spawn, type ChildProcess } from "node:child_process";
import { createServer, type IncomingMessage, type ServerResponse, type Server } from "node:http";
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { compile } from "svelte/compiler";
import type {
  CdpEvaluateResponse,
  CdpPendingCallback,
  CdpTarget,
  CdpWsMessage,
  DirectOpsResult,
  PostSuiteResult,
  ReactAnchorResult,
  ReactBatchResult,
  ReactEachResult,
  ReactMidflightResult,
  ReactRootflowResult,
  ReactStressResult,
  ReactSwapResult,
  ReactTextResult,
  ReactUnmountResult,
  ReactZonesResult,
  SvelteBasicResult,
  SvelteComponents,
  SvelteEachResult,
  SvelteIfResult,
  SvelteMultirootResult,
  SvelteStressResult,
  SvelteUnmountResult,
} from "./types.js";

const webDemoDir: string = fileURLToPath(new URL("..", import.meta.url));
const repoRoot: string = fileURLToPath(new URL("../../..", import.meta.url));
const npmDir: string = join(repoRoot, "platforms/web/client/web-component");
const npmCoreDir: string = join(repoRoot, "platforms/web/client/core");
const ffiRuntimeDir: string = join(repoRoot, "platforms/web/client/engine-runtime/runtime");
// The npm workspace installs shared packages (react, scheduler, react-dom,
// svelte, clsx) into the repo-root node_modules rather than demo/web's own,
// so fixture lookups walk up from demo/web to the repo root and take the
// first existing node_modules/<file> candidate; only a miss at every level
// falls through to sendFile's 404.
const nodeModuleDirs: string[] = (() => {
  const start: string = resolve(webDemoDir);
  const stop: string = resolve(repoRoot);
  const dirs: string[] = [];
  for (let dir: string = start; ; dir = dirname(dir)) {
    dirs.push(dir);
    if (dir === stop || dirname(dir) === dir) break;
  }
  return dirs;
})();

function nodeModulesFile(...segments: string[]): string {
  for (const dir of nodeModuleDirs) {
    const candidate: string = join(dir, "node_modules", ...segments);
    if (existsSync(candidate)) return candidate;
  }
  return join(nodeModuleDirs[0], "node_modules", ...segments);
}

const demoPort: number = 8995;
const cdpPort: number = 9985;
const demoUrl: string = `http://127.0.0.1:${demoPort}/`;

// Pure-CJK scenario strings. The engine inserts spacing between latin and
// CJK runs, so expected strings avoid latin entirely; the live-rendered
// comparison strips whitespace on both sides as a second layer.
// Instance-level $state with a bind() callback: module-level $state compiles
// to a plain object in svelte 5, so the page reaches the reactive values
// through setters the component hands back at mount.
const SVELTE_SOURCE: string = `
<script>
  let { bind } = $props();
  let text = $state("初稿文本用于观察排版变化。");
  let em = $state("强调片段在此。");
  let show = $state(true);
  let tail = $state("段落尾部文本。");
  let items = $state([
    { id: 1, t: "首项条目内容。" },
    { id: 2, t: "次项条目内容。" },
    { id: 3, t: "三项条目内容。" },
  ]);
  bind({
    set text(v) { text = v; },
    set em(v) { em = v; },
    set show(v) { show = v; },
    set tail(v) { tail = v; },
    set items(v) { items = v; },
  });
</script>

<p id="first">{text}{#if show}<em>{em}</em>{/if}{tail}</p>
<p id="list">{#each items as item (item.id)}<span>{item.t}</span>{/each}</p>
`;

// Long-page fixture: the component itself owns several tiqian-prose roots
// separated by tall spacers, so one mount yields a page with roots in every
// tier. Spacers of 1200px and 2800px put the second root inside the observer
// band (viewport 900px plus one viewport each way) and the third beyond it.
const SVELTE_MULTI_SOURCE: string = `
<script>
  let { bind } = $props();
  let a1 = $state("甲根首段原稿文本。");
  let b1 = $state("乙根近带段原稿。");
  let c1 = $state("丙根远带段原稿。");
  let showB = $state(true);
  let showC = $state(true);
  let extraA = $state(false);
  bind({
    set a1(v) { a1 = v; },
    set b1(v) { b1 = v; },
    set c1(v) { c1 = v; },
    set showB(v) { showB = v; },
    set showC(v) { showC = v; },
    set extraA(v) { extraA = v; },
  });
</script>

<tiqian-prose data-fixture="s-multi-a"><div><p>{a1}</p>{#if extraA}<p>追加段落进入甲根。</p>{/if}</div></tiqian-prose>
<div style="height:1200px"></div>
{#if showB}
  <tiqian-prose data-fixture="s-multi-b"><div><p>{b1}</p></div></tiqian-prose>
{/if}
<div style="height:2800px"></div>
{#if showC}
  <tiqian-prose data-fixture="s-multi-c"><div><p>{c1}</p></div></tiqian-prose>
{/if}
`;

// The compiled component keeps its bare svelte/internal/* specifiers: the
// page import map resolves them (a path rewrite would bypass the map, since
// leading-slash URLs are never looked up in it).
function compileSvelteSource(source: string, name: string): string {
  const out = compile(source, { generate: "client", css: "injected", name });
  return out.js.code;
}

async function compileSvelteComponent(): Promise<string> {
  return compileSvelteSource(SVELTE_SOURCE, "FrameworkFixture");
}

async function compileSvelteMultiComponent(): Promise<string> {
  return compileSvelteSource(SVELTE_MULTI_SOURCE, "FrameworkMultiFixture");
}

// The in-page driver: framework loaders, scenario registry, settle helpers,
// and per-scenario state snapshots. Served at /page-driver.mjs.
const PAGE_DRIVER: string = `
  import { registerTiqianProse } from "@tiqian/web-component/element";
  registerTiqianProse();

  const stage = document.getElementById("stage");
  globalThis.__pageErrors = [];
  window.addEventListener("error", (event) => {
    __pageErrors.push(String(event.error && event.error.stack || event.message));
  });

  // Host-side test probe: ADR 0053 rules that the product carries no DOM
  // property for the raw-DOM fragment, so tests dig through this seam instead;
  // the library face is unchanged. The host session keys the rawDomParagraphs
  // entry by the paragraph element itself.
  globalThis.__tiqianRawDomFragment = (paragraph) => {
    const host = paragraph.closest("tiqian-prose");
    return host ? host.rawDomFragmentOf(paragraph) : null;
  };

  // ---- react-dom 19 through a minimal CommonJS loader ----
  const CJS_FILES = {
    react: "/cjs/react",
    scheduler: "/cjs/scheduler",
    "react-dom": "/cjs/react-dom",
    "react-dom/client": "/cjs/react-dom-client",
  };
  const cjsCache = new Map();
  globalThis.__cjsRequire = async (name) => {
    if (cjsCache.has(name)) return cjsCache.get(name).exports;
    const url = CJS_FILES[name];
    if (!url) throw new Error("unknown cjs module: " + name);
    const source = await (await fetch(url)).text();
    const module = { exports: {} };
    cjsCache.set(name, module);
    const require = (dep) => {
      if (!cjsCache.has(dep)) throw new Error(dep + " must be preloaded before " + name);
      return cjsCache.get(dep).exports;
    };
    new Function("require", "module", "exports", source)(require, module, module.exports);
    return module.exports;
  };
  globalThis.__loadReact = async () => {
    await __cjsRequire("react");
    await __cjsRequire("scheduler");
    await __cjsRequire("react-dom");
    await __cjsRequire("react-dom/client");
    return {
      React: cjsCache.get("react").exports,
      ReactDOMClient: cjsCache.get("react-dom/client").exports,
    };
  };

  // ---- shared tiqian helpers ----
  // Engine output carries zero-width characters the semantic text does not,
  // so both sides are normalized before comparison.
  const norm = (s) => (s || "").replace(/[\\s\\u200b-\\u200d\\ufeff]/g, "");
  globalThis.__norm = norm;
  globalThis.__makeProseRoot = (id) => {
    const root = document.createElement("tiqian-prose");
    root.dataset.fixture = id;
    const container = document.createElement("div");
    root.appendChild(container);
    stage.appendChild(root);
    return { root, container };
  };
  globalThis.__paras = (root) => Array.from(root.querySelectorAll("p"));
  globalThis.__waitRendered = async (root, timeoutMs = 30000) => {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const paras = __paras(root);
      if (paras.length > 0 && paras.every((p) => p.getAttribute("data-tq-rendered") === "true")) {
        return true;
      }
      await new Promise((resolve) => setTimeout(resolve, 150));
    }
    return false;
  };
  // Wait until every paragraph's raw-dom text matches the expected plain
  // strings and the live output carries the same characters.
  globalThis.__waitContent = async (root, expectations, timeoutMs = 30000) => {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const paras = __paras(root);
      const snapshot = __snapshot(root);
      const allRendered = paras.length === expectations.length &&
        paras.every((p) => p.getAttribute("data-tq-rendered") === "true" &&
          p.querySelectorAll("[data-tq-line-index]").length > 0);
      const contentOk = expectations.every((expected, index) => {
        const para = paras[index];
        if (!para) return false;
        const rawDom = __tiqianRawDomFragment(para);
        return rawDom && norm(rawDom.textContent) === norm(expected) &&
          norm(para.textContent) === norm(expected);
      });
      if (allRendered && contentOk) return { ok: true, snapshot };
      await new Promise((resolve) => setTimeout(resolve, 150));
    }
    return { ok: false, snapshot: __snapshot(root) };
  };
  globalThis.__snapshot = (root) => __paras(root).map((p) => {
    const fragment = __tiqianRawDomFragment(p);
    return {
      rendered: p.getAttribute("data-tq-rendered"),
      lines: p.querySelectorAll("[data-tq-line-index]").length,
      rawDom: fragment ? norm(fragment.textContent) : null,
      live: norm(p.textContent),
    };
  });
  globalThis.__quiet = async (ms) => {
    await new Promise((resolve) => setTimeout(resolve, ms));
  };
  // Long-page helpers. __zoneOf mirrors the engine's IntersectionObserver
  // band (viewport plus one full viewport each way): 1 intersects the
  // viewport, 2 sits inside the band but off-screen, 3 lies beyond the band.
  globalThis.__rootOf = (fixture) =>
    document.querySelector('tiqian-prose[data-fixture="' + fixture + '"]');
  globalThis.__zoneOf = (el) => {
    const rect = el.getBoundingClientRect();
    const vh = innerHeight;
    if (rect.bottom >= 0 && rect.top <= vh) return 1;
    if (rect.bottom >= -vh && rect.top <= vh * 2) return 2;
    return 3;
  };
  globalThis.__zonesOf = (root) => __paras(root).map((p) => __zoneOf(p));
  globalThis.__scrollToEl = (el) => {
    el.scrollIntoView({ block: "center" });
  };
  globalThis.__scrollTop = () => {
    window.scrollTo(0, 0);
  };
  globalThis.__clearStage = () => {
    window.scrollTo(0, 0);
    stage.innerHTML = "";
    return __quiet(600);
  };
  globalThis.__drainErrors = () => {
    const errors = __pageErrors.slice();
    __pageErrors.length = 0;
    return errors;
  };
`;

// React scenario definitions. Each returns { mount, container, act } where
// act(state) applies a new component state through a real React commit.
const REACT_APP: string = `
  globalThis.__mountReact = async (fixtureId, render, initialState) => {
    const { React, ReactDOMClient } = await __loadReact();
    const { root, container } = __makeProseRoot(fixtureId);
    const api = { state: initialState, set: null };
    const App = () => {
      const [state, setState] = React.useState(api.state);
      api.set = setState;
      return render(state);
    };
    const reactRoot = ReactDOMClient.createRoot(container);
    reactRoot.render(React.createElement(App));
    const flush = async () => {
      await new Promise((resolve) => setTimeout(resolve, 60));
    };
    return { root, container, reactRoot, api, flush };
  };

  // Stage-level mount for long-page scenarios: React renders the whole page
  // including several tiqian-prose custom elements and the spacers between
  // them, so roots entering and leaving the render tree are plain React
  // commits against the live document.
  globalThis.__mountReactStage = async (render, initialState) => {
    const { React, ReactDOMClient } = await __loadReact();
    const container = document.createElement("div");
    stage.appendChild(container);
    const api = { state: initialState, set: null };
    const App = () => {
      const [state, setState] = React.useState(api.state);
      api.set = setState;
      return render(state);
    };
    const reactRoot = ReactDOMClient.createRoot(container);
    reactRoot.render(React.createElement(App));
    const flush = async () => {
      await new Promise((resolve) => setTimeout(resolve, 60));
    };
    return { container, reactRoot, api, flush };
  };
`;

class CdpClient {
  wsUrl: string;
  ws: WebSocket | null = null;
  id: number = 0;
  pending: Map<number, CdpPendingCallback> = new Map();

  constructor(wsUrl: string) {
    this.wsUrl = wsUrl;
  }

  async connect(): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      this.ws = new WebSocket(this.wsUrl);
      this.ws.onopen = (): void => resolve();
      this.ws.onerror = (err: Event): void => reject(err);
      this.ws.onmessage = (event: MessageEvent): void => {
        const msg = JSON.parse(String(event.data)) as CdpWsMessage;
        if (msg.id && this.pending.has(msg.id)) {
          const { resolve: res, reject: rej } = this.pending.get(msg.id)!;
          this.pending.delete(msg.id);
          if (msg.error) {
            const detail: string = msg.error.data ? ` (${msg.error.data})` : "";
            rej(new Error(msg.error.message + detail));
          } else {
            res(msg.result);
          }
        }
      };
    });
  }

  async send(method: string, params: Record<string, unknown> = {}): Promise<unknown> {
    const id = ++this.id;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.ws!.send(JSON.stringify({ id, method, params }));
    });
  }

  async evaluate<T = unknown>(expression: string): Promise<T> {
    const res = (await this.send("Runtime.evaluate", {
      expression,
      awaitPromise: true,
      returnByValue: true,
    })) as CdpEvaluateResponse<T>;
    if (res.exceptionDetails) {
      const detail: string = res.exceptionDetails.exception?.description ??
        JSON.stringify(res.exceptionDetails);
      throw new Error(`Runtime exception: ${detail}`);
    }
    return res.result?.value as T;
  }

  close(): void {
    this.ws?.close();
  }
}

async function waitForCdpEndpoint(port: number, timeoutMs: number = 15000): Promise<void> {
  const start: number = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res: Response = await fetch(`http://127.0.0.1:${port}/json/version`);
      if (res.ok) return;
    } catch {
      // retry
    }
    await new Promise<void>((resolve) => setTimeout(resolve, 200));
  }
  throw new Error(`Timeout waiting for browser remote debugging port on ${port}`);
}

function startFixtureServer(svelteComponents: SvelteComponents): Promise<Server> {
  const server: Server = createServer(async (req: IncomingMessage, res: ServerResponse) => {
    const path: string = decodeURIComponent(new URL(req.url!, "http://x").pathname);
    const send = (data: string | Buffer, type: string): void => {
      res.setHeader("content-type", type);
      res.end(data);
    };
    const sendFile = async (file: string, type: string): Promise<void> => {
      const data: Buffer | null = await readFile(file).catch(() => null);
      if (data) {
        // Module workers do not see the document import map, so the dev-tree
        // layout worker in core gets its bare "@tiqian/ffi" import
        // rewritten to the absolute /npm-engine-runtime/ URL served below.
        if (file === join(npmCoreDir, "layout-worker.js")) {
          const source: string = data.toString("utf8");
          const occurrences: number = source.split('from "@tiqian/ffi"').length - 1;
          assert.ok(occurrences <= 1, `unexpected engine import count ${occurrences}`);
          if (occurrences === 1) {
            send(source.replace('from "@tiqian/ffi"', 'from "/npm-engine-runtime/Tiqian-tiqian-ffi-js.mjs"'), type);
            return;
          }
        }
        send(data, type);
      }
      else {
        res.statusCode = 404;
        res.end("not found");
      }
    };
    try {
      if (path === "/") {
        send(`<!doctype html>
<html lang="zh-Hans">
<head>
<meta charset="utf-8" />
<title>framework commit conflict fixture</title>
<link rel="stylesheet" href="/core/styles.css" data-tiqian-stylesheet="true" />
<style>
  body { font-family: "Noto Sans CJK SC", "PingFang SC", sans-serif; margin: 24px; }
  tiqian-prose { display: block; margin: 16px 0; }
</style>
<script type="importmap">
{
  "imports": {
    "@tiqian/web-component/element": "/npm/element.js",
    "@tiqian/web-component/": "/npm/",
    "@tiqian/core/": "/core/",
    "@tiqian/ffi": "/npm-engine-runtime/Tiqian-tiqian-ffi-js.mjs",
    "svelte": "/svelte/src/index-client.js",
    "svelte/internal/client": "/svelte/src/internal/client/index.js",
    "svelte/internal/disclose-version": "/svelte/src/internal/disclose-version.js",
    "svelte/internal/flags/legacy": "/svelte/src/internal/flags/legacy.js",
    "#client/constants": "/svelte/src/internal/client/constants.js",
    "clsx": "/clsx/dist/clsx.mjs",
    "esm-env": "/shims/esm-env.mjs"
  }
}
</script>
</head>
<body>
<div id="stage"></div>
<script type="module" src="/page-driver.mjs"></script>
</body>
</html>`, "text/html; charset=utf-8");
        return;
      }
      if (path === "/page-driver.mjs") {
        send(PAGE_DRIVER + REACT_APP, "text/javascript");
        return;
      }
      if (path === "/svelte-component/main.js") {
        send(svelteComponents.main, "text/javascript");
        return;
      }
      if (path === "/svelte-component/multi.js") {
        send(svelteComponents.multi, "text/javascript");
        return;
      }
      if (path === "/shims/esm-env.mjs") {
        send("export const DEV = false;\nexport const PROD = true;\nexport const BROWSER = true;\nexport const SSR = false;\n", "text/javascript");
        return;
      }
      if (path === "/cjs/react") {
        await sendFile(nodeModulesFile("react/cjs/react.production.js"), "text/javascript");
        return;
      }
      if (path === "/cjs/scheduler") {
        await sendFile(nodeModulesFile("scheduler/cjs/scheduler.production.js"), "text/javascript");
        return;
      }
      if (path === "/cjs/react-dom") {
        await sendFile(nodeModulesFile("react-dom/cjs/react-dom.production.js"), "text/javascript");
        return;
      }
      if (path === "/cjs/react-dom-client") {
        await sendFile(nodeModulesFile("react-dom/cjs/react-dom-client.production.js"), "text/javascript");
        return;
      }
      if (path.startsWith("/svelte/")) {
        const rest: string = path.slice("/svelte/".length);
        await sendFile(nodeModulesFile("svelte", rest), "text/javascript");
        return;
      }
      if (path.startsWith("/clsx/")) {
        const rest: string = path.slice("/clsx/".length);
        await sendFile(nodeModulesFile("clsx", rest), "text/javascript");
        return;
      }
      if (path.startsWith("/npm-engine-runtime/")) {
        const rest: string = path.slice("/npm-engine-runtime/".length);
        await sendFile(join(ffiRuntimeDir, rest), "text/javascript");
        return;
      }
      if (path.startsWith("/npm/")) {
        const rest: string = path.slice("/npm/".length);
        const type: string = rest.endsWith(".css") ? "text/css" : "text/javascript";
        await sendFile(join(npmDir, rest), type);
        return;
      }
      if (path.startsWith("/core/")) {
        const rest: string = path.slice("/core/".length);
        const type: string = rest.endsWith(".css") ? "text/css" : "text/javascript";
        await sendFile(join(npmCoreDir, rest), type);
        return;
      }
      res.statusCode = 404;
      res.end("not found");
    } catch (err: unknown) {
      console.error(`[fixture-server] error on ${path}:`, err);
      res.statusCode = 500;
      res.end(String(err));
    }
  });
  return new Promise<Server>((resolve) => server.listen(demoPort, "127.0.0.1", () => resolve(server)));
}

test("FrameworkCommitConflict: framework commits survive and re-render through the tiqian raw-dom", { skip: "the demo served the removed @tiqian/ffi runtime; the engine now ships as the @tiqian/engine workspace tree, whose .ts sources the browser cannot load" }, async (_t: TestContext) => {
  const svelteMain: string = await compileSvelteComponent();
  assert.match(svelteMain, /svelte\/internal\/client/, "compiled fixture must use the svelte client runtime");

  const portBusy: boolean = await fetch(demoUrl).then(() => true, () => false);
  assert.ok(!portBusy, `Port ${demoPort} must be free before the test starts`);

  const server: Server = await startFixtureServer({ main: svelteMain, multi: await compileSvelteMultiComponent() });
  let browserProc: ChildProcess | null = null;
  let client: CdpClient | null = null;

  try {
    const chromeBin: string = process.env.CHROME_BIN || "chromium";
    browserProc = spawn(chromeBin, [
      "--headless=new",
      `--remote-debugging-port=${cdpPort}`,
      "--no-sandbox",
      "--disable-gpu",
      "--disable-dev-shm-usage",
      "about:blank",
    ], {
      stdio: "ignore",
      detached: true,
    });

    await waitForCdpEndpoint(cdpPort, 15000);
    const listRes: Response = await fetch(`http://127.0.0.1:${cdpPort}/json/list`);
    const targets = (await listRes.json()) as CdpTarget[];
    const pageTarget: CdpTarget | undefined = targets.find((tr: CdpTarget) => tr.type === "page" && tr.url === "about:blank");
    assert.ok(pageTarget, "Must find the blank page target");

    client = new CdpClient(pageTarget.webSocketDebuggerUrl);
    await client.connect();
    await client.send("Page.enable");
    await client.send("Runtime.enable");
    await client.send("Emulation.setDeviceMetricsOverride", {
      width: 1000,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false,
    });
    await client.send("Page.navigate", { url: demoUrl });
    await client.evaluate(`
      new Promise((resolve) => {
        if (document.readyState === "complete") setTimeout(resolve, 300);
        else window.addEventListener("load", () => setTimeout(resolve, 300));
      })
    `);
    await client.evaluate(`
      new Promise((resolve, reject) => {
        const deadline = Date.now() + 15000;
        const check = () => {
          if (globalThis.__makeProseRoot) resolve(true);
          else if (Date.now() > deadline) reject(new Error("page driver never loaded"));
          else setTimeout(check, 100);
        };
        check();
      })
    `);

    const run = <R = unknown>(expression: string): Promise<R> => client!.evaluate<R>(`(async () => { ${expression} })()`);
    const errorsOf = async (label: string): Promise<string[]> => {
      const errors: string[] = await client!.evaluate<string[]>("__drainErrors()");
      assert.deepEqual(errors, [], `[${label}] no uncaught page errors`);
      return errors;
    };

    // -------- React: mount and text updates (raw-dom characterData path)
    {
      const result: ReactTextResult = await run<ReactTextResult>(`
        const { React } = await __loadReact();
        const h = React.createElement;
        const render = (s) => h("p", null, s.text, s.em ? h("em", null, s.em) : null);
        const app = await __mountReact("r-text", render, { text: "初稿正文第一段。", em: "强调附注。" });
        if (!await __waitRendered(app.root)) throw new Error("initial mount never rendered");
        const first = await __waitContent(app.root, ["初稿正文第一段。强调附注。"]);
        // Same-fiber text rewrite: React commitTextUpdate writes .data on the
        // text node now held in the raw-dom fragment.
        app.api.set({ text: "改写之后的正文文本，长度不同。", em: "强调附注。" });
        await app.flush();
        const second = await __waitContent(app.root, ["改写之后的正文文本，长度不同。强调附注。"]);
        // Inline element removal from the middle of the paragraph.
        app.api.set({ text: "改写之后的正文文本，长度不同。", em: null });
        await app.flush();
        const third = await __waitContent(app.root, ["改写之后的正文文本，长度不同。"]);
        return { first: first.ok, second: second.ok, third: third.ok, snapshot: __snapshot(app.root) };
      `);
      assert.ok(result.first && result.second && result.third,
        `React text/inline updates must re-render: ${JSON.stringify(result)}`);
      await errorsOf("react-text");
      await run("await __clearStage()");
    }

    // -------- React: anchored insert and remove (raw-dom removeChild path)
    {
      const result: ReactAnchorResult = await run<ReactAnchorResult>(`
        const { React } = await __loadReact();
        const h = React.createElement;
        const render = (s) => h("p", null,
          s.head,
          s.strong ? h("strong", null, s.strong) : null,
          h("em", null, "尾部强调。"),
        );
        const app = await __mountReact("r-anchor", render, { head: "开头文本在此。", strong: null });
        if (!await __waitRendered(app.root)) throw new Error("initial mount never rendered");
        // Insert <strong> BEFORE the raw-dom-held <em>: React commits this as
        // insertBefore(paragraph, strongNode, emNode) with a raw-dom anchor.
        app.api.set({ head: "开头文本在此。", strong: "新插入的强调片段。" });
        await app.flush();
        const inserted = await __waitContent(app.root, ["开头文本在此。新插入的强调片段。尾部强调。"]);
        // Remove the <strong> again: React commits removeChild(paragraph,
        // strongNode) with the node held in the raw-dom fragment.
        app.api.set({ head: "开头文本在此。", strong: null });
        await app.flush();
        const removed = await __waitContent(app.root, ["开头文本在此。尾部强调。"]);
        return { inserted: inserted.ok, removed: removed.ok, snapshot: __snapshot(app.root) };
      `);
      assert.ok(result.inserted && result.removed,
        `React anchored insert/remove must re-render: ${JSON.stringify(result)}`);
      await errorsOf("react-anchor");
      await run("await __clearStage()");
    }

    // -------- React: conditional swap of a whole inline run
    {
      const result: ReactSwapResult = await run<ReactSwapResult>(`
        const { React } = await __loadReact();
        const h = React.createElement;
        const render = (s) => h("p", null,
          "固定开头。",
          s.mode === "甲" ? h("em", null, "甲模式强调文本。") : h("strong", null, "乙模式重点文本。"),
          "固定结尾。",
        );
        const app = await __mountReact("r-swap", render, { mode: "甲" });
        if (!await __waitRendered(app.root)) throw new Error("initial mount never rendered");
        const swapInitial = await __waitContent(app.root, ["固定开头。甲模式强调文本。固定结尾。"]);
        if (!swapInitial.ok) {
          throw new Error("initial content mismatch: " + JSON.stringify({
            snap: __snapshot(app.root),
            errors: __pageErrors.slice(),
          }));
        }
        app.api.set({ mode: "乙" });
        await app.flush();
        const swapped = await __waitContent(app.root, ["固定开头。乙模式重点文本。固定结尾。"]);
        app.api.set({ mode: "甲" });
        await app.flush();
        const back = await __waitContent(app.root, ["固定开头。甲模式强调文本。固定结尾。"]);
        return { swapped: swapped.ok, back: back.ok, snapshot: __snapshot(app.root) };
      `);
      assert.ok(result.swapped && result.back,
        `React conditional swap must re-render: ${JSON.stringify(result)}`);
      await errorsOf("react-swap");
      await run("await __clearStage()");
    }

    // -------- React: keyed list reorder inside one paragraph
    {
      const result: ReactEachResult = await run<ReactEachResult>(`
        const { React } = await __loadReact();
        const h = React.createElement;
        const render = (s) => h("p", null,
          s.items.map((item) => h("span", { key: item.id }, item.t)),
        );
        const initial = { items: [
          { id: 1, t: "首项条目。" }, { id: 2, t: "次项条目。" }, { id: 3, t: "三项条目。" },
        ] };
        const app = await __mountReact("r-each", render, initial);
        if (!await __waitRendered(app.root)) throw new Error("initial mount never rendered");
        const eachInitial = await __waitContent(app.root, ["首项条目。次项条目。三项条目。"]);
        if (!eachInitial.ok) {
          throw new Error("initial content mismatch: " + JSON.stringify({ snap: __snapshot(app.root), errors: __pageErrors.slice() }));
        }
        // Reverse order: React moves nodes with insertBefore against raw-dom
        // anchors and removes the displaced ones.
        app.api.set({ items: [
          { id: 3, t: "三项条目。" }, { id: 1, t: "首项条目。" }, { id: 2, t: "次项条目。" },
        ] });
        await app.flush();
        const reversed = await __waitContent(app.root, ["三项条目。首项条目。次项条目。"]);
        // Remove from the middle and insert at the head in one commit.
        app.api.set({ items: [
          { id: 4, t: "新添头部。" }, { id: 1, t: "首项条目。" },
        ] });
        await app.flush();
        const reshaped = await __waitContent(app.root, ["新添头部。首项条目。"]);
        return { reversed: reversed.ok, reshaped: reshaped.ok, snapshot: __snapshot(app.root), errors: __pageErrors.slice() };
      `);
      assert.ok(result.reversed && result.reshaped,
        `React keyed reorder must re-render: ${JSON.stringify(result)}`);
      await errorsOf("react-each");
      await run("await __clearStage()");
    }

    // -------- React: batch updates across paragraphs, whole-paragraph removal
    {
      const result: ReactBatchResult = await run<ReactBatchResult>(`
        const { React } = await __loadReact();
        const h = React.createElement;
        const render = (s) => h("div", null,
          s.showFirst ? h("p", null, s.first) : null,
          h("p", null, s.second),
          h("p", null, s.third),
        );
        const initial = {
          showFirst: true,
          first: "首段文本内容。",
          second: "次段文本内容。",
          third: "三段文本内容。",
        };
        const app = await __mountReact("r-batch", render, initial);
        if (!await __waitRendered(app.root)) throw new Error("initial mount never rendered");
        const batchInitial = await __waitContent(app.root, ["首段文本内容。", "次段文本内容。", "三段文本内容。"]);
        if (!batchInitial.ok) {
          throw new Error("initial content mismatch: " + JSON.stringify({ snap: __snapshot(app.root), errors: __pageErrors.slice() }));
        }
        // One commit touching every paragraph: text rewrite plus structural
        // removal of the first paragraph.
        app.api.set({ showFirst: false, first: "", second: "改写次段文本。", third: "三段文本内容。" });
        await app.flush();
        const batched = await __waitContent(app.root, ["改写次段文本。", "三段文本内容。"]);
        return { batched: batched.ok, snapshot: __snapshot(app.root) };
      `);
      assert.ok(result.batched, `React batch commit must re-render: ${JSON.stringify(result)}`);
      await errorsOf("react-batch");
      await run("await __clearStage()");
    }

    // -------- React: update issued before initial enhancement settles
    {
      const result: ReactMidflightResult = await run<ReactMidflightResult>(`
        const { React } = await __loadReact();
        const h = React.createElement;
        const render = (s) => h("p", null, s.text);
        const app = await __mountReact("r-midflight", render, { text: "中途更新前的初始文本。" });
        // Wait only for React's first commit, never for the tiqian settle:
        // change content while the engine is still adopting the paragraph.
        for (let i = 0; i < 100 && typeof app.api.set !== "function"; i++) {
          await new Promise((resolve) => setTimeout(resolve, 30));
        }
        app.api.set({ text: "中途更新后的最终文本。" });
        await app.flush();
        const settled = await __waitContent(app.root, ["中途更新后的最终文本。"], 45000);
        await __quiet(1200);
        return { settled: settled.ok, snapshot: __snapshot(app.root) };
      `);
      assert.ok(result.settled, `React mid-flight update must converge: ${JSON.stringify(result)}`);
      await errorsOf("react-midflight");
      await run("await __clearStage()");
    }

    // -------- React: rapid interleaved updates
    {
      const result: ReactStressResult = await run<ReactStressResult>(`
        const { React } = await __loadReact();
        const h = React.createElement;
        const render = (s) => h("p", null,
          s.text,
          s.strong ? h("strong", null, s.strong) : null,
          "固定尾巴。",
        );
        const app = await __mountReact("r-stress", render, { text: "起点文本。", strong: null });
        if (!await __waitRendered(app.root)) throw new Error("initial mount never rendered");
        const steps = [
          { text: "第一次更新文本。", strong: "第一次强调。" },
          { text: "第二次更新文本加长内容。", strong: null },
          { text: "第三次更新。", strong: "第三次强调。" },
          { text: "最终稳定文本内容。", strong: null },
          { text: "最终稳定文本内容。再加一句。", strong: "最后强调。" },
        ];
        for (const step of steps) {
          app.api.set(step);
          await new Promise((resolve) => setTimeout(resolve, 40));
        }
        const settled = await __waitContent(app.root, ["最终稳定文本内容。再加一句。最后强调。固定尾巴。"], 45000);
        await __quiet(1200);
        return { settled: settled.ok, snapshot: __snapshot(app.root) };
      `);
      assert.ok(result.settled, `React rapid updates must converge: ${JSON.stringify(result)}`);
      await errorsOf("react-stress");
      await run("await __clearStage()");
    }

    // -------- React: full unmount while paragraphs are held in the raw-dom fragment
    {
      const result: ReactUnmountResult = await run<ReactUnmountResult>(`
        const { React } = await __loadReact();
        const h = React.createElement;
        const render = (s) => h("p", null, s.text, h("em", null, "内联强调。"));
        const app = await __mountReact("r-unmount", render, { text: "卸载前的段落文本。" });
        if (!await __waitRendered(app.root)) throw new Error("initial mount never rendered");
        const unmountInitial = await __waitContent(app.root, ["卸载前的段落文本。内联强调。"]);
        if (!unmountInitial.ok) {
          throw new Error("initial content mismatch: " + JSON.stringify({ snap: __snapshot(app.root), errors: __pageErrors.slice() }));
        }
        app.reactRoot.unmount();
        await __quiet(800);
        const remaining = __paras(app.root).length;
        return { remaining };
      `);
      assert.equal(result.remaining, 0, "unmount must remove every paragraph");
      await errorsOf("react-unmount");
      await run("await __clearStage()");
    }

    // -------- React: long page, two concurrent roots, edits in every tier
    {
      const result: ReactZonesResult = await run<ReactZonesResult>(`
        const { React } = await __loadReact();
        const h = React.createElement;
        const filler = "正文填充句读测试。";
        const paraText = (tag) => tag + "开头。" + filler.repeat(60);
        let a0 = paraText("甲零");
        let a5 = paraText("甲五");
        let b0 = "乙段远带原稿文本。" + filler.repeat(3);
        const expectA = () => [
          a0, paraText("甲一"), paraText("甲二"), paraText("甲三"), paraText("甲四"), a5,
        ];
        const render = (s) => h("div", null,
          h("tiqian-prose", { "data-fixture": "r-zone-a" }, h("div", null,
            h("p", null, s.a0),
            h("p", null, paraText("甲一")),
            h("p", null, paraText("甲二")),
            h("p", null, paraText("甲三")),
            h("p", null, paraText("甲四")),
            h("p", null, s.a5))),
          h("div", { style: { height: "1200px" } }),
          h("tiqian-prose", { "data-fixture": "r-zone-b" }, h("div", null, h("p", null, s.b0))));
        const app = await __mountReactStage(render, { a0, a5, b0 });
        await app.flush();
        const rootA = __rootOf("r-zone-a");
        const rootB = __rootOf("r-zone-b");
        if (!rootA || !rootB) throw new Error("long-page roots missing after mount");
        if (!await __waitRendered(rootA, 60000)) throw new Error("root A never rendered");
        if (!await __waitRendered(rootB, 60000)) throw new Error("root B never rendered");
        const initial = await __waitContent(rootA, expectA(), 60000);
        const zonesA = __zonesOf(rootA);
        const zoneB = __zoneOf(__paras(rootB)[0]);
        // Tier 1: in-viewport paragraph, no scroll involved.
        app.api.set({ a0: a0 = paraText("甲零改"), a5, b0 });
        await app.flush();
        const inView = await __waitContent(rootA, expectA(), 30000);
        // Tier 2: off-screen but inside the observer band.
        app.api.set({ a0, a5: a5 = paraText("甲五改"), b0 });
        await app.flush();
        const near = await __waitContent(rootA, expectA(), 30000);
        // Tier 3: beyond the band. Whether it re-renders in place is
        // scheduling policy; the edit must not be lost either way.
        app.api.set({ a0, a5, b0: b0 = "乙段远带改写文本。" + filler.repeat(2) });
        await app.flush();
        await __quiet(1200);
        const earlyB = __snapshot(rootB)[0].live;
        __scrollToEl(__paras(rootB)[0]);
        const far = await __waitContent(rootB, [b0], 45000);
        // Root B now holds the viewport; A's last paragraph sits above it
        // inside the band and an edit there must still re-render.
        const zoneA5Scrolled = __zoneOf(__paras(rootA)[5]);
        app.api.set({ a0, a5: a5 = paraText("甲五再改"), b0 });
        await app.flush();
        const above = await __waitContent(rootA, expectA(), 45000);
        __scrollTop();
        const finalA = await __waitContent(rootA, expectA(), 30000);
        const finalB = await __waitContent(rootB, [b0], 30000);
        return {
          initial: initial.ok, inView: inView.ok, near: near.ok, far: far.ok,
          above: above.ok, finalA: finalA.ok, finalB: finalB.ok,
          zonesA, zoneB, zoneA5Scrolled,
          farRenderedBeforeScroll: earlyB === __norm(b0),
        };
      `);
      assert.ok(result.zonesA[0] === 1 && result.zonesA[5] === 2 && result.zoneB === 3,
        `long-page paragraphs must start in all three tiers: ${JSON.stringify(result)}`);
      assert.equal(result.zoneA5Scrolled, 2,
        `scrolling to root B must leave A's tail in the near band: ${JSON.stringify(result)}`);
      assert.ok(result.initial && result.inView && result.near && result.far,
        `tier edits must re-render: ${JSON.stringify(result)}`);
      assert.ok(result.above && result.finalA && result.finalB,
        `edits around viewport crossings must converge: ${JSON.stringify(result)}`);
      console.log(
        `[react-zones] tiers p0=${result.zonesA[0]} p5=${result.zonesA[5]} b=${result.zoneB} ` +
        `p5AfterScroll=${result.zoneA5Scrolled} farRenderedBeforeScroll=${result.farRenderedBeforeScroll}`,
      );
      await errorsOf("react-zones");
      await run("await __clearStage()");
    }

    // -------- React: roots and paragraphs enter and leave the document
    {
      const result: ReactRootflowResult = await run<ReactRootflowResult>(`
        const { React } = await __loadReact();
        const h = React.createElement;
        let aParas = ["甲段首行文本。", "甲段中间行文本。", "甲段末行文本。"];
        let showB = true;
        let b1 = "乙根首段文本。";
        let showD = false;
        let d1 = "丁根新到文本。";
        const render = (s) => h("div", null,
          h("tiqian-prose", { "data-fixture": "r-flow-a" }, h("div", null,
            s.aParas.map((t) => h("p", { key: t }, t)))),
          h("div", { style: { height: "1100px" } }),
          s.showB ? h("tiqian-prose", { "data-fixture": "r-flow-b" }, h("div", null, h("p", null, s.b1))) : null,
          h("div", { style: { height: "2600px" } }),
          s.showD ? h("tiqian-prose", { "data-fixture": "r-flow-d" }, h("div", null, h("p", null, s.d1))) : null);
        const app = await __mountReactStage(render, { aParas, showB, b1, showD, d1 });
        await app.flush();
        const rootA = __rootOf("r-flow-a");
        const rootB = __rootOf("r-flow-b");
        if (!rootA || !rootB) throw new Error("flow roots missing after mount");
        if (!await __waitRendered(rootA, 60000)) throw new Error("root A never rendered");
        if (!await __waitRendered(rootB, 60000)) throw new Error("root B never rendered");
        const initialA = await __waitContent(rootA, aParas, 60000);
        // Root B leaves the document; A must keep its rendered content.
        const beforeA = __snapshot(rootA);
        app.api.set({ aParas, showB: false, b1, showD, d1 });
        await app.flush();
        await __quiet(1200);
        const bGone = !__rootOf("r-flow-b");
        const aStable = JSON.stringify(beforeA) === JSON.stringify(__snapshot(rootA));
        // The paragraph set inside the surviving root rewrites and shrinks.
        aParas = ["甲段改写首行。", "甲段末行文本。"];
        app.api.set({ aParas, showB: false, b1, showD, d1 });
        await app.flush();
        const shrunk = await __waitContent(rootA, aParas, 45000);
        // A brand-new root enters far below the fold.
        showD = true;
        app.api.set({ aParas, showB: false, b1, showD, d1 });
        await app.flush();
        const rootD = __rootOf("r-flow-d");
        if (!rootD) throw new Error("root D missing after join");
        const dRendered = await __waitRendered(rootD, 60000);
        const dContent = await __waitContent(rootD, [d1], 60000);
        // Root B re-enters with fresh content.
        b1 = "乙根重挂文本。";
        showB = true;
        app.api.set({ aParas, showB, b1, showD, d1 });
        await app.flush();
        const rootB2 = __rootOf("r-flow-b");
        if (!rootB2) throw new Error("root B missing after re-entry: " + JSON.stringify({
          fixtures: Array.from(document.querySelectorAll("tiqian-prose")).map((e) => e.dataset.fixture),
          errors: __pageErrors.slice(-3),
          html: app.container.innerHTML.slice(0, 300),
        }));
        const bBack = await __waitContent(rootB2, [b1], 60000);
        const finalA = await __waitContent(rootA, aParas, 30000);
        return {
          initialA: initialA.ok, bGone, aStable, shrunk: shrunk.ok,
          dRendered, dContent: dContent.ok, bBack: bBack.ok, finalA: finalA.ok,
          snapshotA: __snapshot(rootA),
        };
      `);
      assert.ok(result.initialA && result.bGone && result.aStable,
        `root removal must be clean: ${JSON.stringify(result)}`);
      assert.ok(result.shrunk && result.finalA,
        `paragraph set changes must re-render: ${JSON.stringify(result)}`);
      assert.ok(result.dRendered && result.dContent && result.bBack,
        `entering roots must enhance and render: ${JSON.stringify(result)}`);
      await errorsOf("react-rootflow");
      await run("await __clearStage()");
    }

    // -------- Svelte: mount and reactive text update
    {
      const result: SvelteBasicResult = await run<SvelteBasicResult>(`
        const { default: Fixture } = await import("/svelte-component/main.js");
        const { mount } = await import("svelte");
        const { root } = __makeProseRoot("s-basic");
        let api = null;
        const app = mount(Fixture, { target: root, props: { bind: (x) => (api = x) } });
        if (!api) throw new Error("fixture never handed back its api");
        if (!await __waitRendered(root)) throw new Error("svelte mount never rendered");
        const first = await __waitContent(root, [
          "初稿文本用于观察排版变化。强调片段在此。段落尾部文本。",
          "首项条目内容。次项条目内容。三项条目内容。",
        ]);
        // set_data rewrites .data on the text node held in the raw-dom fragment.
        api.text = "改写后的文本内容，长度变化。";
        const second = await __waitContent(root, [
          "改写后的文本内容，长度变化。强调片段在此。段落尾部文本。",
          "首项条目内容。次项条目内容。三项条目内容。",
        ]);
        return { first: first.ok, second: second.ok, snapshot: __snapshot(root) };
      `);
      assert.ok(result.first && result.second,
        `Svelte text update must re-render: ${JSON.stringify(result)}`);
      await errorsOf("svelte-text");
      await run("await __clearStage()");
    }

    // -------- Svelte: if-block off and on around raw-dom-held siblings
    {
      const result: SvelteIfResult = await run<SvelteIfResult>(`
        const { default: Fixture } = await import("/svelte-component/main.js");
        const { mount } = await import("svelte");
        const { root } = __makeProseRoot("s-if");
        let api = null;
        const app = mount(Fixture, { target: root, props: { bind: (x) => (api = x) } });
        api.text = "主体文本保持不变。";
        api.em = "待移除强调。";
        api.items = [{ id: 1, t: "列表保持。" }];
        if (!await __waitRendered(root)) throw new Error("svelte mount never rendered");
        const initial = await __waitContent(root, [
          "主体文本保持不变。待移除强调。段落尾部文本。",
          "列表保持。",
        ]);
        // Toggling off detaches the <em> through parentNode, which resolves to
        // the raw-dom fragment.
        api.show = false;
        const off = await __waitContent(root, ["主体文本保持不变。段落尾部文本。", "列表保持。"]);
        // Toggling back on re-inserts before the raw-dom-held tail text node.
        api.show = true;
        const on = await __waitContent(root, ["主体文本保持不变。待移除强调。段落尾部文本。", "列表保持。"]);
        return { initial: initial.ok, off: off.ok, on: on.ok, snapshot: __snapshot(root) };
      `);
      assert.ok(result.initial && result.off && result.on,
        `Svelte if-block toggle must re-render: ${JSON.stringify(result)}`);
      await errorsOf("svelte-if");
      await run("await __clearStage()");
    }

    // -------- Svelte: keyed each reorder, head insert, middle remove
    {
      const result: SvelteEachResult = await run<SvelteEachResult>(`
        const { default: Fixture } = await import("/svelte-component/main.js");
        const { mount } = await import("svelte");
        const { root } = __makeProseRoot("s-each");
        let api = null;
        const app = mount(Fixture, { target: root, props: { bind: (x) => (api = x) } });
        api.text = "列表上方文本。";
        if (!await __waitRendered(root)) throw new Error("svelte mount never rendered");
        const initial = await __waitContent(root, [
          "列表上方文本。强调片段在此。段落尾部文本。",
          "首项条目内容。次项条目内容。三项条目内容。",
        ]);
        // Keyed reorder: svelte moves spans with insert/remove against
        // raw-dom-held anchors.
        api.items = [
          { id: 3, t: "三项条目内容。" },
          { id: 1, t: "首项条目内容。" },
        ];
        const reordered = await __waitContent(root, [
          "列表上方文本。强调片段在此。段落尾部文本。",
          "三项条目内容。首项条目内容。",
        ]);
        api.items = [
          { id: 4, t: "新头部条目。" },
          { id: 1, t: "首项条目内容。" },
          { id: 3, t: "三项条目内容。" },
        ];
        const grown = await __waitContent(root, [
          "列表上方文本。强调片段在此。段落尾部文本。",
          "新头部条目。首项条目内容。三项条目内容。",
        ]);
        return { initial: initial.ok, reordered: reordered.ok, grown: grown.ok, snapshot: __snapshot(root) };
      `);
      assert.ok(result.initial && result.reordered && result.grown,
        `Svelte each mutations must re-render: ${JSON.stringify(result)}`);
      await errorsOf("svelte-each");
      await run("await __clearStage()");
    }

    // -------- Svelte: interleaved rapid mutations
    {
      const result: SvelteStressResult = await run<SvelteStressResult>(`
        const { default: Fixture } = await import("/svelte-component/main.js");
        const { mount } = await import("svelte");
        const { root } = __makeProseRoot("s-stress");
        let api = null;
        const app = mount(Fixture, { target: root, props: { bind: (x) => (api = x) } });
        api.text = "起点文本内容。";
        api.em = "起点强调。";
        api.tail = "固定结尾。";
        api.items = [{ id: 1, t: "起点条目。" }];
        if (!await __waitRendered(root)) throw new Error("svelte mount never rendered");
        api.text = "第一次文本。";
        api.show = false;
        await new Promise((resolve) => setTimeout(resolve, 40));
        api.items = [{ id: 2, t: "新条目甲。" }, { id: 3, t: "新条目乙。" }];
        api.em = "更新强调。";
        await new Promise((resolve) => setTimeout(resolve, 40));
        api.show = true;
        api.text = "最终文本内容。";
        const settled = await __waitContent(root, [
          "最终文本内容。更新强调。固定结尾。",
          "新条目甲。新条目乙。",
        ], 45000);
        await __quiet(1200);
        return { settled: settled.ok, snapshot: __snapshot(root) };
      `);
      assert.ok(result.settled, `Svelte rapid mutations must converge: ${JSON.stringify(result)}`);
      await errorsOf("svelte-stress");
      await run("await __clearStage()");
    }

    // -------- Svelte: unmount with paragraphs held in the raw-dom fragment
    {
      const result: SvelteUnmountResult = await run<SvelteUnmountResult>(`
        const { default: Fixture } = await import("/svelte-component/main.js");
        const { mount, unmount } = await import("svelte");
        const { root } = __makeProseRoot("s-unmount");
        let api = null;
        const app = mount(Fixture, { target: root, props: { bind: (x) => (api = x) } });
        api.text = "卸载前文本。";
        api.em = "卸载前强调。";
        api.tail = "尾部。";
        api.items = [{ id: 1, t: "条目。" }];
        if (!await __waitRendered(root)) throw new Error("svelte mount never rendered");
        unmount(app);
        await __quiet(800);
        return { remaining: __paras(root).length };
      `);
      assert.equal(result.remaining, 0, "svelte unmount must remove every paragraph");
      await errorsOf("svelte-unmount");
      await run("await __clearStage()");
    }

    // -------- Svelte: owned roots on a long page, tier edits, re-entry
    {
      const result: SvelteMultirootResult = await run<SvelteMultirootResult>(`
        const { default: Multi } = await import("/svelte-component/multi.js");
        const { mount } = await import("svelte");
        const host = document.createElement("div");
        document.getElementById("stage").appendChild(host);
        let api = null;
        const app = mount(Multi, { target: host, props: { bind: (x) => (api = x) } });
        if (!api) throw new Error("multi fixture never handed back its api");
        const rootA = __rootOf("s-multi-a");
        const rootB = __rootOf("s-multi-b");
        const rootC = __rootOf("s-multi-c");
        if (!rootA || !rootB || !rootC) throw new Error("svelte long-page roots missing");
        if (!await __waitRendered(rootA, 60000)) throw new Error("root A never rendered");
        if (!await __waitRendered(rootB, 60000)) throw new Error("root B never rendered");
        if (!await __waitRendered(rootC, 60000)) throw new Error("root C never rendered");
        const initialA = await __waitContent(rootA, ["甲根首段原稿文本。"], 60000);
        const initialB = await __waitContent(rootB, ["乙根近带段原稿。"], 60000);
        const initialC = await __waitContent(rootC, ["丙根远带段原稿。"], 60000);
        const zones = {
          a: __zoneOf(__paras(rootA)[0]),
          b: __zoneOf(__paras(rootB)[0]),
          c: __zoneOf(__paras(rootC)[0]),
        };
        // Tier-3 edit from the top of the page, then promotion by scroll.
        api.c1 = "丙根远带改写文本。";
        await __quiet(1200);
        const earlyC = __snapshot(rootC)[0].live;
        __scrollToEl(__paras(rootC)[0]);
        const far = await __waitContent(rootC, ["丙根远带改写文本。"], 45000);
        __scrollTop();
        // Tier-2 edit without any scroll.
        api.b1 = "乙根近带改写文本。";
        const near = await __waitContent(rootB, ["乙根近带改写文本。"], 45000);
        // Root B leaves the document; A and C keep their content.
        const beforeA = __snapshot(rootA);
        const beforeC = __snapshot(rootC);
        api.showB = false;
        await __quiet(1200);
        const bGone = !__rootOf("s-multi-b");
        const aStable = JSON.stringify(beforeA) === JSON.stringify(__snapshot(rootA));
        const cStable = JSON.stringify(beforeC) === JSON.stringify(__snapshot(rootC));
        // A paragraph enters root A in place.
        api.extraA = true;
        const grown = await __waitContent(rootA, ["甲根首段原稿文本。", "追加段落进入甲根。"], 45000);
        // Root B re-enters with fresh content. Svelte flushes effects in a
        // microtask, so the re-created element needs one before the query.
        api.b1 = "乙根重挂文本。";
        api.showB = true;
        await __quiet(100);
        const rootB2 = __rootOf("s-multi-b");
        if (!rootB2) throw new Error("svelte root B missing after re-entry");
        const bBack = await __waitContent(rootB2, ["乙根重挂文本。"], 60000);
        const finalC = await __waitContent(rootC, ["丙根远带改写文本。"], 30000);
        return {
          initialA: initialA.ok, initialB: initialB.ok, initialC: initialC.ok,
          zones, far: far.ok, near: near.ok, bGone, aStable, cStable,
          grown: grown.ok, bBack: bBack.ok, finalC: finalC.ok,
          farRenderedBeforeScroll: earlyC === __norm("丙根远带改写文本。"),
        };
      `);
      assert.ok(result.zones.a === 1 && result.zones.b === 2 && result.zones.c === 3,
        `svelte roots must start in all three tiers: ${JSON.stringify(result)}`);
      assert.ok(result.initialA && result.initialB && result.initialC,
        `all three roots must render initially: ${JSON.stringify(result)}`);
      assert.ok(result.far && result.near && result.grown && result.bBack && result.finalC,
        `tier edits and re-entry must re-render: ${JSON.stringify(result)}`);
      assert.ok(result.bGone && result.aStable && result.cStable,
        `root removal must leave siblings untouched: ${JSON.stringify(result)}`);
      console.log(
        `[svelte-multiroot] tiers a=${result.zones.a} b=${result.zones.b} c=${result.zones.c} ` +
        `farRenderedBeforeScroll=${result.farRenderedBeforeScroll}`,
      );
      await errorsOf("svelte-multiroot");
      await run("await __clearStage()");
    }

    // -------- Direct DOM contract on taken-over paragraphs
    {
      const result: DirectOpsResult = await run<DirectOpsResult>(`
        const { root } = __makeProseRoot("x-direct");
        const p = document.createElement("p");
        p.append("直接操作契约检查文本。");
        const em = document.createElement("em");
        em.textContent = "中段强调。";
        p.append(em, "尾部文本。");
        root.appendChild(p);
        if (!await __waitRendered(root)) throw new Error("direct paragraph never rendered");
        const fragment = __tiqianRawDomFragment(p);
        if (!(fragment instanceof DocumentFragment)) throw new Error("raw-dom fragment missing");
        const kidCount = fragment.childNodes.length;
        // removeChild through the paragraph detaches the raw-dom-held <em>.
        const removed = p.removeChild(em);
        if (removed !== em) throw new Error("removeChild must return the same node");
        if (em.parentNode !== null) throw new Error("removeChild must detach the node from the raw-dom fragment");
        if (fragment.childNodes.length !== kidCount - 1) throw new Error("removeChild changed the wrong child count");
        // insertBefore with a raw-dom anchor lands inside the raw-dom fragment.
        const strong = document.createElement("strong");
        strong.textContent = "插入强调。";
        const tail = fragment.lastChild;
        p.insertBefore(strong, tail);
        if (strong.parentNode !== fragment || strong.nextSibling !== tail) {
          throw new Error("insertBefore did not land in the raw-dom fragment at the anchor");
        }
        // replaceChild with a raw-dom-held old child swaps inside the raw-dom fragment.
        const strong2 = document.createElement("strong");
        strong2.textContent = "替换重点。";
        p.replaceChild(strong2, strong);
        if (strong.parentNode !== null || strong2.parentNode !== fragment) {
          throw new Error("replaceChild did not swap inside the raw-dom fragment");
        }
        // appendChild while the raw-dom fragment is active appends into it, not the
        // live engine output.
        const strong3 = document.createElement("strong");
        strong3.textContent = "尾注强调。";
        p.appendChild(strong3);
        if (strong3.parentNode !== fragment) throw new Error("appendChild did not land in the raw-dom fragment");
        // The NotFoundError contract survives for nodes outside the paragraph
        // and its raw-dom fragment.
        const foreign = document.createTextNode("外来节点");
        let threw = false;
        try { p.removeChild(foreign); } catch (err) { threw = err.name === "NotFoundError"; }
        if (!threw) throw new Error("removeChild of a foreign node must still throw NotFoundError");
        const settled = await __waitContent(root, ["直接操作契约检查文本。替换重点。尾部文本。尾注强调。"], 45000);
        return { settled: settled.ok, snapshot: __snapshot(root) };
      `);
      assert.ok(result.settled,
        `Direct ops forwarded into the raw-dom fragment must re-render: ${JSON.stringify(result)}`);
      await errorsOf("direct-ops");
      await run("await __clearStage()");
    }

    // -------- Post-suite: page stays quiet with no leaked tracking
    {
      const result: PostSuiteResult = await client.evaluate<PostSuiteResult>(`
        (async () => {
          await __quiet(1500);
          const before = __pageErrors.length;
          await __quiet(1500);
          return {
            newErrors: __pageErrors.slice(before),
            stageChildren: document.getElementById("stage").children.length,
            roots: document.querySelectorAll("tiqian-prose").length,
          };
        })()
      `);
      assert.deepEqual(result.newErrors, [], "no late errors after the suite");
      assert.equal(result.stageChildren, 0, "stage must be empty after cleanup");
      assert.equal(result.roots, 0, "no tiqian roots may leak");
    }
  } finally {
    try { client?.close(); } catch {}
    if (browserProc?.pid) {
      try { process.kill(-browserProc.pid, "SIGKILL"); } catch {}
      try { process.kill(browserProc.pid, "SIGKILL"); } catch {}
    }
    server.close();
  }
});
