import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

// ProgressiveViewportAnchorCompensation: when the runtime enhances an article
// the reader has already scrolled into, progressive slices replace content
// whose height differs from the native rendering, which would drag the
// reading position away. The coordinator brackets each slice drain with a
// same-task anchor capture/compensate pair, so the paragraph nearest the
// viewport center keeps its on-screen position. Because both reads share one
// task, entrance animations (whose transforms are identical on both sides of
// the pair) never leak into the correction, and a scroller resting at offset
// zero is never adjusted at all — the two failure modes of the external
// MutationObserver + rAF prototype this design replaces.

const webDemoDir = fileURLToPath(new URL("..", import.meta.url));

class CdpClient {
  constructor(wsUrl) {
    this.wsUrl = wsUrl;
    this.ws = null;
    this.id = 0;
    this.pending = new Map();
  }

  async connect() {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(this.wsUrl);
      this.ws.onopen = () => resolve();
      this.ws.onerror = (err) => reject(err);
      this.ws.onmessage = (event) => {
        const msg = JSON.parse(event.data);
        if (msg.id && this.pending.has(msg.id)) {
          const { resolve, reject } = this.pending.get(msg.id);
          this.pending.delete(msg.id);
          if (msg.error) {
            reject(new Error(msg.error.message || JSON.stringify(msg.error)));
          } else {
            resolve(msg.result);
          }
        }
      };
    });
  }

  async send(method, params = {}) {
    const id = ++this.id;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  async evaluate(expression) {
    const res = await this.send("Runtime.evaluate", {
      expression,
      awaitPromise: true,
      returnByValue: true,
    });
    if (res.exceptionDetails) {
      throw new Error(`Runtime exception: ${JSON.stringify(res.exceptionDetails)}`);
    }
    return res.result?.value;
  }

  close() {
    this.ws?.close();
  }
}

async function ensureServerRunning() {
  try {
    const res = await fetch("http://localhost:8888/", { method: "HEAD" });
    if (res.ok) return null;
  } catch {}
  const proc = spawn("bun", ["run", "start"], {
    cwd: webDemoDir,
    stdio: "ignore",
    detached: false,
  });
  for (let i = 0; i < 60; i++) {
    try {
      const res = await fetch("http://localhost:8888/", { method: "HEAD" });
      if (res.ok) return proc;
    } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }
  proc.kill();
  throw new Error("Failed to start web demo server on port 8888");
}

// Marks every root disabled while the document streams in, so the page loads
// with untouched native paragraphs — the "runtime arrives late" scenario.
const DISABLE_ON_PARSE = `
  new MutationObserver((records) => {
    for (const record of records) {
      for (const node of record.addedNodes) {
        if (node.nodeType !== 1) continue;
        if (node.tagName === "TIQIAN-PROSE") node.setAttribute("disabled", "");
        if (typeof node.querySelectorAll === "function") {
          for (const root of node.querySelectorAll("tiqian-prose")) {
            root.setAttribute("disabled", "");
          }
        }
      }
    }
  }).observe(document, { childList: true, subtree: true });
`;

async function launchScenario({ disableRoots }) {
  const serverProc = await ensureServerRunning();
  const port = 9444;
  const chromeProc = spawn("chromium", [
    "--headless=new",
    `--remote-debugging-port=${port}`,
    "--no-sandbox",
    "--disable-gpu",
    "--disable-dev-shm-usage",
    "about:blank",
  ], { stdio: "ignore" });
  for (let i = 0; i < 40; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/json/version`);
      if (res.ok) break;
    } catch {}
    await new Promise((r) => setTimeout(r, 250));
  }
  const listRes = await fetch(`http://127.0.0.1:${port}/json/list`);
  const targets = await listRes.json();
  const page = targets.find((t) => t.type === "page");
  const cdp = new CdpClient(page.webSocketDebuggerUrl);
  await cdp.connect();
  await cdp.send("Page.enable");
  await cdp.send("Runtime.enable");
  // rAF-driven scheduling and every settle loop below freeze on a
  // backgrounded tab; front the page before anything waits on frames.
  await cdp.send("Page.bringToFront");
  await cdp.send("Emulation.setDeviceMetricsOverride", {
    width: 390,
    height: 844,
    deviceScaleFactor: 1,
    mobile: false,
  });
  if (disableRoots) {
    await cdp.send("Page.addScriptToEvaluateOnNewDocument", { source: DISABLE_ON_PARSE });
  }
  await cdp.send("Page.navigate", { url: "http://localhost:8888/" });
  // A cold parcel rebuild can hold the first response for many seconds; wait
  // for the article roots instead of a fixed delay.
  const deadline = Date.now() + 60000;
  while (Date.now() < deadline) {
    const roots = await cdp.evaluate(
      `document.querySelectorAll("tiqian-prose").length`,
    ).catch(() => 0);
    if (roots > 0) break;
    await new Promise((r) => setTimeout(r, 500));
  }
  await new Promise((r) => setTimeout(r, 1000));
  return { cdp, chromeProc, serverProc };
}

function releaseScenario({ cdp, chromeProc }) {
  cdp.close();
  chromeProc?.kill();
}

// Enhancement is settled when the taken-over paragraph count is nonzero and
// stays stable across a quiet window.
const SETTLE_EXPRESSION = `
  (async () => {
    const deadline = performance.now() + 25000;
    let last = -1;
    let stableSince = 0;
    while (performance.now() < deadline) {
      const count = document.querySelectorAll("tiqian-prose [data-tq-rendered]").length;
      if (count > 0 && count === last) {
        if (stableSince === 0) stableSince = performance.now();
        else if (performance.now() - stableSince > 800) return count;
      } else {
        stableSince = 0;
      }
      last = count;
      await new Promise((r) => requestAnimationFrame(r));
    }
    return document.querySelectorAll("tiqian-prose [data-tq-rendered]").length;
  })()
`;

const ANCHOR_PROBE_EXPRESSION = `
  (() => {
    const paragraphs = document.querySelectorAll("tiqian-prose p");
    const center = innerHeight / 2;
    let best = null;
    for (let i = 0; i < paragraphs.length; i++) {
      const rect = paragraphs[i].getBoundingClientRect();
      if (rect.bottom <= 0 || rect.top >= innerHeight) continue;
      if (!best || Math.abs(rect.top - center) < Math.abs(best.top - center)) {
        best = { index: i, top: rect.top };
      }
    }
    return best ? { ...best, scrollY, pageHeight: document.documentElement.scrollHeight } : null;
  })()
`;

function paragraphTopExpression(index) {
  return `
    (() => {
      const paragraph = document.querySelectorAll("tiqian-prose p")[${JSON.stringify(index)}];
      return paragraph
        ? {
          top: paragraph.getBoundingClientRect().top,
          scrollY,
          pageHeight: document.documentElement.scrollHeight,
        }
        : null;
    })()
  `;
}

// Scrolls a mid-page article's center into the viewport center, then lets the
// gesture grace opened by the scroll event lapse, mirroring a reader who
// stopped moving before the runtime arrives.
const SCROLL_TO_MID_EXPRESSION = `
  (async () => {
    const roots = document.querySelectorAll("tiqian-prose");
    const target = roots[Math.min(4, roots.length - 1)];
    const rect = target.getBoundingClientRect();
    scrollTo(0, rect.top + scrollY + rect.height / 2 - innerHeight / 2);
    await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
    return scrollY;
  })()
`;

const ENABLE_ROOTS_EXPRESSION = `
  (() => {
    const roots = document.querySelectorAll("tiqian-prose[disabled]");
    for (const root of roots) root.removeAttribute("disabled");
    return roots.length;
  })()
`;

// Per-slice corrections below the 0.5px epsilon are deliberately skipped, so
// a settled enhancement may leave a few pixels of accumulated residue; the
// uncompensated displacement in these scenarios is several times larger.
const ANCHOR_TOLERANCE_PX = 12;
const MEANINGFUL_SHIFT_PX = 24;

test("LateEnhanceScrollAnchor: enhancement under a mid-article reading position keeps the anchor paragraph still", async () => {
  const scenario = await launchScenario({ disableRoots: true });
  const { cdp } = scenario;
  try {
    await cdp.evaluate(SCROLL_TO_MID_EXPRESSION);
    await new Promise((r) => setTimeout(r, 600));
    const before = await cdp.evaluate(ANCHOR_PROBE_EXPRESSION);
    assert.ok(before, "an anchor paragraph must intersect the viewport before enhancement");

    const enabled = await cdp.evaluate(ENABLE_ROOTS_EXPRESSION);
    assert.ok(enabled > 0, "the disabled-on-parse scenario must find roots to enable");
    const rendered = await cdp.evaluate(SETTLE_EXPRESSION);
    assert.ok(rendered > 0, "enhancement must take over paragraphs after enabling");

    const after = await cdp.evaluate(paragraphTopExpression(before.index));
    assert.ok(after, "the anchor paragraph must survive enhancement");
    const pageHeightDelta = Math.abs(after.pageHeight - before.pageHeight);
    assert.ok(
      pageHeightDelta >= MEANINGFUL_SHIFT_PX,
      `enhancement must change the page height enough to make the scenario meaningful ` +
        `(got ${pageHeightDelta}px)`,
    );
    assert.ok(
      Math.abs(after.top - before.top) <= ANCHOR_TOLERANCE_PX,
      `anchor paragraph moved ${after.top - before.top}px in the viewport ` +
        `(page height changed ${pageHeightDelta}px; scrollY ${before.scrollY} -> ${after.scrollY})`,
    );
  } finally {
    releaseScenario(scenario);
  }
});

test("LateEnhanceScrollAnchor: enhancing at the top of the page during an entrance animation never scrolls", async () => {
  const scenario = await launchScenario({ disableRoots: true });
  const { cdp } = scenario;
  try {
    const samples = await cdp.evaluate(`
      (async () => {
        scrollTo(0, 0);
        const style = document.createElement("style");
        style.textContent =
          "@keyframes tq-test-fade-in-up { from { opacity: 0; transform: translateY(2rem); } " +
          "to { opacity: 1; transform: none; } } " +
          "main, body > :first-child { animation: 900ms tq-test-fade-in-up; }";
        document.head.appendChild(style);
        const held = document.querySelectorAll("tiqian-prose[disabled]").length;
        for (const root of document.querySelectorAll("tiqian-prose[disabled]")) {
          root.removeAttribute("disabled");
        }
        if (held === 0) return { held };
        const observed = [];
        const deadline = performance.now() + 1800;
        while (performance.now() < deadline) {
          observed.push(scrollY);
          await new Promise((r) => requestAnimationFrame(r));
        }
        return { held, observed };
      })()
    `);
    assert.ok(samples.held > 0, "the disabled-on-parse scenario must hold roots until the animation starts");
    const rendered = await cdp.evaluate(SETTLE_EXPRESSION);
    assert.ok(rendered > 0, "enhancement must take over paragraphs during the animation");
    assert.ok(
      samples.observed.every((value) => value === 0),
      `scroll position must stay at the top through animation and enhancement (saw ${
        samples.observed.find((value) => value !== 0)
      })`,
    );
  } finally {
    releaseScenario(scenario);
  }
});

test("LateEnhanceScrollAnchor: a running entrance animation does not pollute a mid-article compensation", async () => {
  const scenario = await launchScenario({ disableRoots: true });
  const { cdp } = scenario;
  try {
    await cdp.evaluate(SCROLL_TO_MID_EXPRESSION);
    await new Promise((r) => setTimeout(r, 600));
    const before = await cdp.evaluate(ANCHOR_PROBE_EXPRESSION);
    assert.ok(before);

    // The animation starts in the same task as the un-disable, so slices
    // commit while the surrounding transform is mid-flight.
    await cdp.evaluate(`
      (() => {
        const style = document.createElement("style");
        style.textContent =
          "@keyframes tq-test-fade-in-up { from { opacity: 0; transform: translateY(2rem); } " +
          "to { opacity: 1; transform: none; } } " +
          "main, body > :first-child { animation: 1200ms tq-test-fade-in-up; }";
        document.head.appendChild(style);
        const held = document.querySelectorAll("tiqian-prose[disabled]").length;
        for (const root of document.querySelectorAll("tiqian-prose[disabled]")) {
          root.removeAttribute("disabled");
        }
        return held;
      })()
    `);
    assert.ok(await cdp.evaluate("1") === 1, "page must stay responsive");
    const rendered = await cdp.evaluate(SETTLE_EXPRESSION);
    assert.ok(rendered > 0, "enhancement must take over paragraphs during the animation");
    // Wait out the animation so the final read sees the resting transform.
    await new Promise((r) => setTimeout(r, 1500));
    const after = await cdp.evaluate(paragraphTopExpression(before.index));
    assert.ok(after);
    assert.ok(
      Math.abs(after.top - before.top) <= ANCHOR_TOLERANCE_PX,
      `anchor paragraph moved ${after.top - before.top}px with an entrance animation running ` +
        `(scrollY ${before.scrollY} -> ${after.scrollY})`,
    );
  } finally {
    releaseScenario(scenario);
  }
});
