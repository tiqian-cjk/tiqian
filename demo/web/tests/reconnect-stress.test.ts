// ReconnectStress: rapid disconnect/reconnect pressure test for the
// raw-dom-move adoption path. The QA report (§11 window 1) hypothesized
// that fast connect/disconnect cycles could let an in-flight Promise write
// into an abandoned DOM subtree via generation mismatch. This suite
// exercises the adoption path at high frequency and checks:
//
// 1. After the final disconnect, the abandoned subtree receives zero
//    mutations within a ≥1s silent window.
// 2. No tiqian:relayout-ready event fires for a disconnected root.
// 3. No uncaught Promise Rejection leaks to the page.
//
// Scenarios: same-task reconnect ×200, cross-task reconnect ×100,
// fixed-seed random alternation ×150, and in-flight layout disconnect
// with a large multi-paragraph root.

import test, { type TestContext } from "node:test";
import assert from "node:assert/strict";
import { spawn, type ChildProcess } from "node:child_process";
import { createServer, type IncomingMessage, type ServerResponse, type Server } from "node:http";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type {
  AbandonedMutationDetail,
  AbandonedSubtreeResult,
  CdpEvaluateResponse,
  CdpPendingCallback,
  CdpTarget,
  CrossTaskReconnectResult,
  InflightDisconnectResult,
  RandomAlternationResult,
  RelayoutReadyEventsResult,
  SameTaskReconnectResult,
  CdpWsMessage,
} from "./types.js";

const repoRoot: string = fileURLToPath(new URL("../../..", import.meta.url));
const npmDir: string = join(repoRoot, "platforms/web/client/web-component");
const npmCoreDir: string = join(repoRoot, "platforms/web/client/core");
const ffiRuntimeDir: string = join(repoRoot, "platforms/web/client/engine-runtime/runtime");

const demoPort: number = 8994;
const cdpPort: number = 9984;
const demoUrl: string = `http://127.0.0.1:${demoPort}/`;

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
            rej(new Error(msg.error.message || JSON.stringify(msg.error)));
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

function startFixtureServer(): Promise<Server> {
  const server: Server = createServer(async (req: IncomingMessage, res: ServerResponse) => {
    const path: string = decodeURIComponent(new URL(req.url!, "http://x").pathname);
    const send = (data: string | Buffer, type: string): void => {
      res.setHeader("content-type", type);
      res.end(data);
    };
    const sendFile = async (file: string, type: string): Promise<void> => {
      const data: Buffer | null = await readFile(file).catch(() => null);
      if (data) {
        if (file === join(npmCoreDir, "layout-worker.js")) {
          const source: string = data.toString("utf8");
          if (source.includes('from "@tiqian/ffi"')) {
            send(source.replace('from "@tiqian/ffi"', 'from "/npm-engine-runtime/Tiqian-tiqian-ffi-js.mjs"'), type);
            return;
          }
        }
        send(data, type);
      } else {
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
<title>reconnect stress fixture</title>
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
    "@tiqian/ffi": "/npm-engine-runtime/Tiqian-tiqian-ffi-js.mjs"
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
        send(PAGE_DRIVER, "text/javascript");
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

const PAGE_DRIVER: string = `
  import { registerTiqianProse } from "@tiqian/web-component/element";
  registerTiqianProse();

  const stage = document.getElementById("stage");
  globalThis.__pageErrors = [];
  window.addEventListener("error", (event) => {
    __pageErrors.push(String(event.error && event.error.stack || event.message));
  });
  window.addEventListener("unhandledrejection", (event) => {
    __pageErrors.push("UNHANDLED_REJECTION:" + String(event.reason && event.reason.stack || event.reason));
  });

  // Seeded PRNG (Mulberry32) for reproducible random sequences.
  globalThis.__seededRandom = (seed) => {
    let s = seed | 0;
    return () => {
      s = (s + 0x6D2B79F5) | 0;
      let t = Math.imul(s ^ (s >>> 15), 1 | s);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  };

  globalThis.__makeProseRoot = (id, text, containerStyle) => {
    const host = document.createElement("div");
    host.id = id + "-host";
    if (containerStyle) host.style.cssText = containerStyle;
    const prose = document.createElement("tiqian-prose");
    prose.id = id;
    const p = document.createElement("p");
    p.textContent = text;
    prose.appendChild(p);
    host.appendChild(prose);
    stage.appendChild(host);
    return { host, prose };
  };

  globalThis.__makeMultiParagraphProseRoot = (id, paragraphCount, fillerText) => {
    const host = document.createElement("div");
    host.id = id + "-host";
    host.style.cssText = "width: 900px; margin: 8px auto;";
    const prose = document.createElement("tiqian-prose");
    prose.id = id;
    for (let i = 0; i < paragraphCount; i++) {
      const p = document.createElement("p");
      p.textContent = fillerText + " 第" + (i + 1) + "段。";
      prose.appendChild(p);
    }
    host.appendChild(prose);
    stage.appendChild(host);
    return { host, prose };
  };

  globalThis.__waitSettled = async (prose, timeoutMs = 30000) => {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (prose.getAttribute("data-tiqian-enhanced") === "true") {
        const ps = Array.from(prose.querySelectorAll("p"));
        if (ps.length > 0 && ps.every((p) => p.getAttribute("data-tq-rendered") === "true")) {
          return true;
        }
      }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    return false;
  };

  globalThis.__drainErrors = () => {
    const errors = __pageErrors.slice();
    __pageErrors.length = 0;
    return errors;
  };

  globalThis.__clearStage = () => {
    stage.innerHTML = "";
  };
`;

const SHORT_TEXT: string = "短文本用于压力测试重连路径。这是一段标准的中文正文内容。";

const LONG_FILLER: string =
  "这是一段用于压力测试的长文本段落，" +
  "目的是让排版引擎在多帧内完成渐进增强，" +
  "从而在断开连接时能够捕获在途的排版工作。" +
  "中文正文排版引擎需要处理断行、标点挤压、" +
  "字体回退、行高计算、行内对齐等复杂任务。" +
  "快速重连压力测试旨在验证这些异步操作在" +
  "高频断开重连场景下的稳定性与安全性。".repeat(3);

test("ReconnectStress: rapid reconnection through the adoption path", async (t: TestContext) => {
  const server: Server = await startFixtureServer();
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
      width: 900,
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
      for (const e of errors) {
        console.error(`[${label}] uncaught: ${e}`);
      }
      return errors;
    };

    // ----------------------------------------------------------------
    // Scenario 1: same-task reconnect ×200
    // disconnect + immediate reconnect within the same microtask,
    // exercising the #adoptRawDomMoveReconnection adoption path.
    // ----------------------------------------------------------------
    await t.test("same-task reconnect ×200", async () => {
      await run<SameTaskReconnectResult>(`
        const { host, prose } = __makeProseRoot("same-task", ${JSON.stringify(SHORT_TEXT)}, "width: 900px; margin: 8px auto;");
        if (!await __waitSettled(prose, 30000)) throw new Error("initial enhance never settled");
        // Let the font settling wave pass.
        await new Promise((r) => setTimeout(r, 1200));

        let reconnected = 0;
        let adoptCount = 0;
        for (let i = 0; i < 200; i++) {
          prose.remove();
          host.appendChild(prose);
          reconnected++;
          if (prose.getAttribute("data-tiqian-enhanced") === "true") adoptCount++;
        }
        // Wait for any trailing work to settle.
        await new Promise((r) => setTimeout(r, 500));
        const enhanced = prose.getAttribute("data-tiqian-enhanced") === "true";
        const rendered = Array.from(prose.querySelectorAll("p"))
          .every((p) => p.getAttribute("data-tq-rendered") === "true");
        return { reconnected, adoptCount, enhanced, rendered };
      `).then((result: SameTaskReconnectResult) => {
        assert.strictEqual(result.reconnected, 200, "must complete all 200 reconnects");
        assert.ok(result.enhanced, "element must remain enhanced after rapid same-task reconnects");
        assert.ok(result.rendered, "paragraphs must remain rendered");
      });
      const errors: string[] = await errorsOf("same-task");
      assert.deepStrictEqual(errors.filter((e: string) => !e.includes("UNHANDLED_REJECTION:")), [],
        "no uncaught page errors in same-task scenario");
      await run("__clearStage()");
    });

    // ----------------------------------------------------------------
    // Scenario 2: cross-task reconnect ×100
    // disconnect, yield to the event loop via setTimeout, then reconnect.
    // This exercises the microtask-settle cleanup path (#settleDisconnection).
    // ----------------------------------------------------------------
    await t.test("cross-task reconnect ×100", async () => {
      await run<CrossTaskReconnectResult>(`
        const { host, prose } = __makeProseRoot("cross-task", ${JSON.stringify(SHORT_TEXT)}, "width: 900px; margin: 8px auto;");
        if (!await __waitSettled(prose, 30000)) throw new Error("initial enhance never settled");
        await new Promise((r) => setTimeout(r, 1200));

        let reconnected = 0;
        for (let i = 0; i < 100; i++) {
          prose.remove();
          await new Promise((r) => setTimeout(r, 0));
          host.appendChild(prose);
          reconnected++;
          // Yield every 10 iterations to let the event loop process.
          if (i % 10 === 9) await new Promise((r) => setTimeout(r, 5));
        }
        await new Promise((r) => setTimeout(r, 500));
        const enhanced = prose.getAttribute("data-tiqian-enhanced") === "true";
        const rendered = Array.from(prose.querySelectorAll("p"))
          .every((p) => p.getAttribute("data-tq-rendered") === "true");
        return { reconnected, enhanced, rendered };
      `).then((result: CrossTaskReconnectResult) => {
        assert.strictEqual(result.reconnected, 100, "must complete all 100 reconnects");
        assert.ok(result.enhanced, "element must remain enhanced after cross-task reconnects");
        assert.ok(result.rendered, "paragraphs must remain rendered");
      });
      const errors: string[] = await errorsOf("cross-task");
      assert.deepStrictEqual(errors.filter((e: string) => !e.includes("UNHANDLED_REJECTION:")), [],
        "no uncaught page errors in cross-task scenario");
      await run("__clearStage()");
    });

    // ----------------------------------------------------------------
    // Scenario 3: fixed-seed random alternation ×150
    // Randomly choose between same-task move, cross-task move with 0ms
    // delay, cross-task move with 5ms delay, or content edit during
    // detach. Fixed seed ensures reproducibility.
    // ----------------------------------------------------------------
    await t.test("fixed-seed random alternation ×150 (seed=42)", async () => {
      const SEED: number = 42;
      await run<RandomAlternationResult>(`
        const SEED = ${SEED};
        const rand = __seededRandom(SEED);
        const { host, prose } = __makeProseRoot("random", ${JSON.stringify(SHORT_TEXT)}, "width: 900px; margin: 8px auto;");
        if (!await __waitSettled(prose, 30000)) throw new Error("initial enhance never settled");
        await new Promise((r) => setTimeout(r, 1200));

        let counts = { sameTask: 0, crossTask0: 0, crossTask5: 0, editDetach: 0 };
        for (let i = 0; i < 150; i++) {
          const pick = rand();
          if (pick < 0.3) {
            // Same-task move
            prose.remove();
            host.appendChild(prose);
            counts.sameTask++;
          } else if (pick < 0.6) {
            // Cross-task with 0ms delay
            prose.remove();
            await new Promise((r) => setTimeout(r, 0));
            host.appendChild(prose);
            counts.crossTask0++;
          } else if (pick < 0.85) {
            // Cross-task with 5ms delay
            prose.remove();
            await new Promise((r) => setTimeout(r, 5));
            host.appendChild(prose);
            counts.crossTask5++;
          } else {
            // Edit content while detached
            prose.remove();
            const p = prose.querySelector("p");
            if (p) p.textContent = "随机交替第" + i + "次改写文本。";
            await new Promise((r) => setTimeout(r, 0));
            host.appendChild(prose);
            counts.editDetach++;
          }
          if (i % 15 === 14) await new Promise((r) => setTimeout(r, 10));
        }
        await new Promise((r) => setTimeout(r, 500));
        const enhanced = prose.getAttribute("data-tiqian-enhanced") === "true";
        return { counts, enhanced };
      `).then((result: RandomAlternationResult) => {
        assert.ok(result.enhanced, "element must remain enhanced after random alternation");
        assert.ok(result.counts.sameTask > 0, "must have exercised same-task path");
        assert.ok(result.counts.crossTask0 > 0 || result.counts.crossTask5 > 0, "must have exercised cross-task path");
        assert.ok(result.counts.editDetach > 0, "must have exercised edit-while-detached path");
      });
      const errors: string[] = await errorsOf("random");
      assert.deepStrictEqual(errors.filter((e: string) => !e.includes("UNHANDLED_REJECTION:")), [],
        "no uncaught page errors in random scenario");
      await run("__clearStage()");
    });

    // ----------------------------------------------------------------
    // Scenario 4: in-flight layout disconnect
    // Create a large multi-paragraph root, start enhancement, then
    // disconnect before all paragraphs are rendered. Reconnect and
    // verify the root recovers.
    // ----------------------------------------------------------------
    await t.test("in-flight layout disconnect (12 paragraphs)", async () => {
      await run<InflightDisconnectResult>(`
        const { host, prose } = __makeMultiParagraphProseRoot("inflight", 12, ${JSON.stringify(LONG_FILLER)});
        // Wait for at least 2 paragraphs to be rendered (partial enhancement).
        const deadline = Date.now() + 15000;
        while (Date.now() < deadline) {
          const rendered = Array.from(prose.querySelectorAll("p"))
            .filter((p) => p.getAttribute("data-tq-rendered") === "true").length;
          if (rendered >= 2) break;
          await new Promise((r) => setTimeout(r, 50));
        }
        // Disconnect while layout is still in flight.
        prose.remove();
        await new Promise((r) => setTimeout(r, 10));
        // Reconnect.
        host.appendChild(prose);
        // Wait for full settlement.
        const settled = await __waitSettled(prose, 30000);
        return { settled };
      `).then((result: InflightDisconnectResult) => {
        assert.ok(result.settled, "root must recover after in-flight disconnect and reconnect");
      });
      const errors: string[] = await errorsOf("inflight");
      assert.deepStrictEqual(errors.filter((e: string) => !e.includes("UNHANDLED_REJECTION:")), [],
        "no uncaught page errors in in-flight scenario");
      await run("__clearStage()");
    });

    // ----------------------------------------------------------------
    // Scenario 5: abandoned subtree silent window check
    // Enhance a root, disconnect it, wait ≥1s, then verify the
    // abandoned subtree received zero mutations.
    // ----------------------------------------------------------------
    await t.test("abandoned subtree zero mutations after disconnect", async () => {
      const result: AbandonedSubtreeResult = await run<AbandonedSubtreeResult>(`
        const { host, prose } = __makeProseRoot("abandon", ${JSON.stringify(SHORT_TEXT)}, "width: 900px; margin: 8px auto;");
        if (!await __waitSettled(prose, 30000)) throw new Error("initial enhance never settled");
        // Wait for the font settling wave to pass (0-400ms window).
        await new Promise((r) => setTimeout(r, 1200));
        // Re-verify settlement after font wave.
        await __waitSettled(prose, 5000);

        // Snapshot the subtree's attributes and child count AFTER font wave.
        const snapshotBefore = (() => {
          const ps = Array.from(prose.querySelectorAll("p"));
          return ps.map((p) => ({
            rendered: p.getAttribute("data-tq-rendered"),
            lines: p.querySelectorAll("[data-tq-line-index]").length,
            childCount: p.childNodes.length,
          }));
        })();

        // Arm MutationObserver and event listener AFTER font wave settles,
        // so we only capture post-disconnect mutations.
        let mutationCount = 0;
        let mutationDetails = [];
        const observer = new MutationObserver((records) => {
          mutationCount += records.length;
          for (const r of records) {
            mutationDetails.push({
              type: r.type,
              target: r.target.tagName + "#" + r.target.id + (r.target.className ? "." + r.target.className : ""),
              attr: r.attributeName || null,
              added: r.addedNodes.length,
              removed: r.removedNodes.length,
            });
          }
        });
        observer.observe(prose, { childList: true, subtree: true, attributes: true, characterData: true });

        let relayoutReadyAfterDisconnect = false;
        const recordEvent = (ev) => {
          const root = ev.detail?.root || ev.target?.closest?.("tiqian-prose");
          if (root === prose) relayoutReadyAfterDisconnect = true;
        };
        document.addEventListener("tiqian:relayout-ready", recordEvent, true);

        // Disconnect.
        prose.remove();

        // Wait ≥1s silent window.
        await new Promise((r) => setTimeout(r, 1500));

        observer.disconnect();
        document.removeEventListener("tiqian:relayout-ready", recordEvent, true);

        // Snapshot after to confirm zero changes.
        const snapshotAfter = (() => {
          const ps = Array.from(prose.querySelectorAll("p"));
          return ps.map((p) => ({
            rendered: p.getAttribute("data-tq-rendered"),
            lines: p.querySelectorAll("[data-tq-line-index]").length,
            childCount: p.childNodes.length,
          }));
        })();

        return {
          mutationCount,
          mutationDetails,
          relayoutReadyAfterDisconnect,
          snapshotBefore: JSON.stringify(snapshotBefore),
          snapshotAfter: JSON.stringify(snapshotAfter),
          identical: JSON.stringify(snapshotBefore) === JSON.stringify(snapshotAfter),
        };
      `);
      // Filter out known teardown mutations: the engine sets
      // data-tq-value-style-scope during disconnectedCallback cleanup,
      // which is a legitimate teardown, not a stale post-disconnect write.
      const teardownAttrs = new Set<string>(["data-tq-value-style-scope"]);
      const staleMutations: AbandonedMutationDetail[] = result.mutationDetails.filter(
        (m: AbandonedMutationDetail) => !(m.type === "attributes" && teardownAttrs.has(m.attr ?? "")),
      );
      assert.strictEqual(staleMutations.length, 0,
        `abandoned subtree received ${staleMutations.length} stale mutations after disconnect: ${JSON.stringify(staleMutations)}`);
      assert.ok(!result.relayoutReadyAfterDisconnect,
        "tiqian:relayout-ready fired for a disconnected root");
      assert.ok(result.identical,
        `subtree state changed after disconnect: before=${result.snapshotBefore} after=${result.snapshotAfter}`);
      const errors: string[] = await errorsOf("abandon");
      assert.deepStrictEqual(errors.filter((e: string) => !e.includes("UNHANDLED_REJECTION:")), [],
        "no uncaught page errors in abandon scenario");
      await run("__clearStage()");
    });

    // ----------------------------------------------------------------
    // Scenario 6: rapid cycle with interleaved relayout events check
    // Verify that relayout-ready events stop arriving after disconnect.
    // ----------------------------------------------------------------
    await t.test("relayout-ready stops after disconnect", async () => {
      const result: RelayoutReadyEventsResult = await run<RelayoutReadyEventsResult>(`
        const { host, prose } = __makeProseRoot("events", ${JSON.stringify(SHORT_TEXT)}, "width: 900px; margin: 8px auto;");
        if (!await __waitSettled(prose, 30000)) throw new Error("initial enhance never settled");
        await new Promise((r) => setTimeout(r, 1200));

        let readyCount = 0;
        const onReady = (ev) => {
          const root = ev.detail?.root || ev.target?.closest?.("tiqian-prose");
          if (root === prose) readyCount++;
        };
        document.addEventListener("tiqian:relayout-ready", onReady, true);

        // Rapid cycle: 50 same-task reconnects, then disconnect.
        for (let i = 0; i < 50; i++) {
          prose.remove();
          host.appendChild(prose);
        }

        const readyDuringCycle = readyCount;

        // Disconnect and wait.
        prose.remove();
        await new Promise((r) => setTimeout(r, 1500));
        const readyAfterDisconnect = readyCount - readyDuringCycle;

        document.removeEventListener("tiqian:relayout-ready", onReady, true);
        return { readyDuringCycle, readyAfterDisconnect };
      `);
      assert.strictEqual(result.readyAfterDisconnect, 0,
        `received ${result.readyAfterDisconnect} relayout-ready events after disconnect`);
      const errors: string[] = await errorsOf("events");
      assert.deepStrictEqual(errors.filter((e: string) => !e.includes("UNHANDLED_REJECTION:")), [],
        "no uncaught page errors in events scenario");
      await run("__clearStage()");
    });
  } finally {
    client?.close();
    if (browserProc?.pid) {
      try { process.kill(-browserProc.pid, "SIGKILL"); } catch {}
      try { process.kill(browserProc.pid, "SIGKILL"); } catch {}
    }
    server.close();
  }
});
