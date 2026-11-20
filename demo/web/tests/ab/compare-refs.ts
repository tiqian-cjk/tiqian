// RefVsRefComparison: build the web npm package at two git refs and compare
// the demo pages they render, box by box and pixel by pixel. This lands the
// manual "checkout base, rebuild, swap artifacts, eyeball" workflow as a
// repeatable tool. Each ref builds inside its own git worktree, so the
// working tree is never touched and each side's artifact cannot leak into
// the other (the artifact under platforms/web/client/engine-runtime/runtime/facade.mjs
// is git-ignored, which made manual swapping produce a false green once).
//
// Usage (from demo/web, inside nix develop):
//   node tests/ab/compare-refs.ts --base <git-ref> [--head <git-ref>]
//
// --head defaults to the current working tree, uncommitted changes included.
// Both refs must know the platforms/web/client/engine-runtime package. The demo
// page, viewport, fonts, and capture plan are identical constants for both
// sides, so the only variable is the engine build.
//
// Every width lane below re-settles, recomputes its capture plan, and
// compares the FULL measured surface (every root, every paragraph, every
// line marker, every direct child element and text node of every
// paragraph — no sampling) plus pixel-identical screenshots. The lanes are
// driven through the demo's own width axis: the page-wrapper maxWidth
// slider (360..1600, default 1280), so a divergence report speaks the same
// widths designers and the perf HUD see. Screenshots cover the full page
// plus up to MAX_SCROLL_STOPS evenly spaced scroll positions per lane;
// box coverage is complete regardless through the geometry lanes.
//
// Exit code 0 means, at every width: identical page height, identical
// measured boxes, and pixel-identical screenshots.

import { spawn, execFile, type ChildProcess, type ExecFileOptions } from "node:child_process";
import { createServer, type Server, type IncomingMessage, type ServerResponse } from "node:http";
import { readFile, mkdtemp, rm, stat } from "node:fs/promises";
import type { Stats } from "node:fs";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { inflateSync } from "node:zlib";
import {
  DEEP_GEOMETRY_HELPERS,
  deepGeometryCounts,
  diffDeepGeometry,
} from "../helpers/deep-geometry.js";
import type {
  DeepGeometryCounts,
  DeepGeometryReport,
  DeepGeometryStats,
  CdpTarget,
  CdpWsMessage,
} from "../types.js";

const WIDTH_LANES: readonly number[] = [1600, 1440, 1280, 1120, 1024, 960, 900, 820, 720, 620, 500, 360];
const MAX_SCROLL_STOPS: number = 6;

type PendingResolver = (val: unknown) => void;
type PendingRejecter = (err: unknown) => void;
type TimeoutRejecter = (err: Error) => void;
type RunResolver = (res: string) => void;
type RunRejecter = (err: Error) => void;
type ExecFileCallback = (err: Error | null, stdout: string, stderr: string) => void;
type ConnectResolver = () => void;
type ConnectRejecter = (err: unknown) => void;
type SendResolver = (val: unknown) => void;
type SendRejecter = (err: Error) => void;
type ServerListenResolver = (server: Server) => void;
type FetchBusyResolver = () => boolean;
type SleepResolver = () => void;
type BuildSideResolver = () => void;
type BuildSideRejecter = (err: Error) => void;
type BufferDataHandler = (d: Buffer) => void;
type ProcessExitHandler = (code: number | null) => void;
type VoidReturnHandler = () => void;
type PlanMapper = (width: number) => [number, CapturePlan];
type PaethFunction = (a: number, b: number, c: number) => number;

type GenericResolver<T> = (val: T) => void;

interface CdpWsPendingHandler {
  resolve: PendingResolver;
  reject: PendingRejecter;
}

interface CdpScreenshotResult {
  data: string;
}

interface CdpEvaluateExceptionDetails {
  text?: string;
  data?: unknown;
}

interface CdpEvaluateValue<T> {
  value?: T;
}

interface CdpEvaluateResult<T = unknown> {
  exceptionDetails?: CdpEvaluateExceptionDetails;
  result?: CdpEvaluateValue<T>;
}

interface DecodedPng {
  width: number;
  height: number;
  idat: Buffer;
}

interface DecodedPixels {
  width: number;
  height: number;
  bpp: number;
  pixels: Buffer;
}

interface ScreenshotComparison {
  equal: boolean;
  differentPixels: number;
  detail: string | null;
}

interface SettleResult {
  settled: boolean;
  pageHeight: number;
  enhanced: number;
}

interface ClipRect {
  x: number;
  y: number;
  width: number;
  height: number;
  scale?: number;
}

interface CapturePlan {
  rect: ClipRect;
  viewportHeight: number;
  pageHeight: number;
  scrolls: number[];
}

interface LaneCapture {
  shots: Record<string, Buffer>;
  plan: CapturePlan;
  geometry: DeepGeometryReport;
  pageHeight: number;
}

interface CaptureSideOptions {
  label: string;
  pkgDir: string;
  port: number;
  cdpPort: number;
  plans: Record<number, CapturePlan> | null;
}

interface CaptureSideResult {
  label: string;
  lanes: Record<number, LaneCapture>;
}

interface BuildSideResult {
  artifact: string;
  hash: string;
}

const webDemoDir: string = fileURLToPath(new URL("../..", import.meta.url));
const repoRoot: string = fileURLToPath(new URL("../../../..", import.meta.url));

const args: readonly string[] = process.argv.slice(2);
const readArg = (name: string): string | null => {
  const prefix: string = "--" + name + "=";
  const inline: string | undefined = args.find((a: string): boolean => a.startsWith(prefix));
  if (inline) return inline.slice(prefix.length);
  const at: number = args.indexOf("--" + name);
  return at >= 0 ? (args[at + 1] ?? null) : null;
};
const baseRef: string | null = readArg("base");
const headRef: string | null = readArg("head"); // null means the current working tree
if (!baseRef) {
  console.error("usage: node tests/ab/compare-refs.ts --base <git-ref> [--head <git-ref>]");
  console.error("--head defaults to the current working tree including uncommitted changes");
  process.exit(2);
}

function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((_: GenericResolver<T>, reject: TimeoutRejecter): void => {
      setTimeout((): void => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
    }),
  ]);
}

const run = (cmd: string, runArgs: readonly string[], opts: ExecFileOptions = {}): Promise<string> =>
  withTimeout(new Promise<string>((resolve: RunResolver, reject: RunRejecter): void => {
    const cb: ExecFileCallback = (err: Error | null, stdout: string, stderr: string): void => {
      if (err) reject(new Error(`${cmd} ${runArgs.join(" ")} failed: ${stderr || err.message}`));
      else resolve(stdout);
    };
    execFile(cmd, runArgs as string[], opts, cb);
  }), 120000, `${cmd} ${runArgs[0]}`);

class CdpClient {
  readonly wsUrl: string;
  ws: WebSocket | null = null;
  id: number = 0;
  readonly pending: Map<number, CdpWsPendingHandler> = new Map();

  constructor(wsUrl: string) {
    this.wsUrl = wsUrl;
  }

  async connect(): Promise<void> {
    return withTimeout(new Promise<void>((resolve: ConnectResolver, reject: ConnectRejecter): void => {
      this.ws = new WebSocket(this.wsUrl);
      this.ws.onopen = (): void => resolve();
      this.ws.onerror = (err: unknown): void => reject(err);
      this.ws.onmessage = (event: MessageEvent): void => {
        const msg: CdpWsMessage = JSON.parse(event.data as string) as CdpWsMessage;
        if (msg.id && this.pending.has(msg.id)) {
          const handler: CdpWsPendingHandler | undefined = this.pending.get(msg.id);
          this.pending.delete(msg.id);
          if (handler) {
            if (msg.error) {
              const detail: string = msg.error.data ? ` (${msg.error.data})` : "";
              handler.reject(new Error((msg.error.message ?? "CDP Error") + detail));
            } else {
              handler.resolve(msg.result);
            }
          }
        }
      };
    }), 15000, "cdp connect");
  }

  async send(method: string, params?: Record<string, unknown>): Promise<unknown> {
    const id: number = ++this.id;
    return withTimeout(new Promise<unknown>((resolve: SendResolver, reject: SendRejecter): void => {
      this.pending.set(id, {
        resolve,
        reject: (err: unknown): void => {
          const e: Error = err instanceof Error ? err : new Error(String(err));
          reject(new Error(`${method}: ${e.message}`));
        },
      });
      this.ws?.send(JSON.stringify({ id, method, params }));
    }), 90000, `cdp ${method}`);
  }

  async evaluate<T = unknown>(expression: string): Promise<T> {
    const res: CdpEvaluateResult<T> = (await this.send("Runtime.evaluate", {
      expression,
      awaitPromise: true,
      returnByValue: true,
    })) as CdpEvaluateResult<T>;
    if (res.exceptionDetails) {
      throw new Error(`Runtime exception: ${JSON.stringify(res.exceptionDetails)}`);
    }
    return res.result?.value as T;
  }

  async screenshot(params: Record<string, unknown> = {}): Promise<Buffer> {
    const res: CdpScreenshotResult = (await this.send("Page.captureScreenshot", {
      format: "png",
      ...params,
    })) as CdpScreenshotResult;
    return Buffer.from(res.data, "base64");
  }

  close(): void {
    this.ws?.close();
  }
}

// Minimal dependency-free PNG decode (8-bit RGB/RGBA, non-interlaced) and a
// strict pixel comparison: any differing pixel fails the comparison.
function decodePng(buf: Buffer): DecodedPng {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error("not a PNG");
  let pos: number = 8;
  let width: number = 0;
  let height: number = 0;
  const idat: Buffer[] = [];
  while (pos < buf.length) {
    const len: number = buf.readUInt32BE(pos);
    const type: string = buf.toString("ascii", pos + 4, pos + 8);
    const data: Buffer = buf.subarray(pos + 8, pos + 8 + len);
    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      const bitDepth: number = data[8];
      const colorType: number = data[9];
      const interlace: number = data[12];
      if (bitDepth !== 8 || (colorType !== 6 && colorType !== 2) || interlace !== 0) {
        throw new Error(`unsupported PNG: depth=${bitDepth} color=${colorType} interlace=${interlace}`);
      }
    } else if (type === "IDAT") {
      idat.push(data);
    } else if (type === "IEND") {
      break;
    }
    pos += 12 + len;
  }
  return { width, height, idat: Buffer.concat(idat) };
}

function decodePixels(png: Buffer): DecodedPixels {
  const { width, height, idat }: DecodedPng = decodePng(png);
  const colorType: number = png[25];
  const bpp: number = colorType === 6 ? 4 : 3;
  const raw: Buffer = inflateSync(idat);
  const stride: number = width * bpp;
  const out: Buffer = Buffer.alloc(height * stride);
  const paeth: PaethFunction = (a: number, b: number, c: number): number => {
    const p: number = a + b - c;
    const pa: number = Math.abs(p - a);
    const pb: number = Math.abs(p - b);
    const pc: number = Math.abs(p - c);
    return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
  };
  for (let y: number = 0; y < height; y++) {
    const filter: number = raw[y * (stride + 1)];
    const rowStart: number = y * (stride + 1) + 1;
    const row: Buffer = raw.subarray(rowStart, rowStart + stride);
    const prev: Buffer | null = y > 0 ? out.subarray((y - 1) * stride, y * stride) : null;
    const cur: Buffer = out.subarray(y * stride, (y + 1) * stride);
    for (let x: number = 0; x < stride; x++) {
      const left: number = x >= bpp ? cur[x - bpp] : 0;
      const up: number = prev ? prev[x] : 0;
      const upLeft: number = prev && x >= bpp ? prev[x - bpp] : 0;
      let value: number = row[x];
      if (filter === 1) value = (value + left) & 0xff;
      else if (filter === 2) value = (value + up) & 0xff;
      else if (filter === 3) value = (value + ((left + up) >> 1)) & 0xff;
      else if (filter === 4) value = (value + paeth(left, up, upLeft)) & 0xff;
      cur[x] = value;
    }
  }
  return { width, height, bpp, pixels: out };
}

function compareScreenshots(a: Buffer, b: Buffer): ScreenshotComparison {
  if (a.equals(b)) return { equal: true, differentPixels: 0, detail: null };
  const da: DecodedPixels = decodePixels(a);
  const db: DecodedPixels = decodePixels(b);
  if (da.width !== db.width || da.height !== db.height) {
    return {
      equal: false,
      differentPixels: -1,
      detail: `dimensions ${da.width}x${da.height} vs ${db.width}x${db.height}`,
    };
  }
  const { width, height, bpp, pixels: pa }: DecodedPixels = da;
  const pb: Buffer = db.pixels;
  let different: number = 0;
  let first: string | null = null;
  for (let y: number = 0; y < height && !first; y++) {
    for (let x: number = 0; x < width; x++) {
      const offset: number = (y * width + x) * bpp;
      let delta: number = 0;
      for (let c: number = 0; c < bpp; c++) {
        delta = Math.max(delta, Math.abs(pa[offset + c] - pb[offset + c]));
      }
      if (delta > 0) {
        first = `(${x},${y}) rgba [${Array.from(pa.subarray(offset, offset + bpp)).join(",")}] vs [${Array.from(pb.subarray(offset, offset + bpp)).join(",")}]`;
        break;
      }
    }
  }
  for (let i: number = 0; i < pa.length; i += bpp) {
    for (let c: number = 0; c < bpp; c++) {
      if (pa[i + c] !== pb[i + c]) {
        different += 1;
        break;
      }
    }
  }
  return { equal: false, differentPixels: different, detail: first };
}

// Serves the current demo page with an import map that resolves
// @tiqian/web-component inside the given package directory, so the page chrome is a
// constant and the engine build is the only variable.
function startDemoServer(port: number, pkgDir: string, label: string): Promise<Server> {
  const server: Server = createServer(async (req: IncomingMessage, res: ServerResponse): Promise<void> => {
    const urlPath: string = decodeURIComponent(new URL(req.url ?? "/", "http://x").pathname);
    try {
      if (urlPath === "/") {
        const html: string = (await readFile(join(webDemoDir, "index.html"), "utf8")).replace(
          "</head>",
          `<script type="importmap">{"imports":{"@tiqian/web-component/element":"/platforms/web/client/web-component/element.js","@tiqian/web-component/":"/platforms/web/client/web-component/","@tiqian/web-component":"/platforms/web/client/web-component/element.js"}}</script></head>`,
        );
        res.setHeader("content-type", "text/html; charset=utf-8");
        res.end(html);
        return;
      }
      let file: string | null = null;
      let type: string = "text/javascript";
      if (urlPath === "/main.js" || urlPath === "/main.ts" || urlPath === "/index.css") {
        file = join(webDemoDir, urlPath.slice(1));
        if (urlPath.endsWith(".css")) type = "text/css";
      } else if (urlPath.startsWith("/platforms/web/client/web-component/")) {
        const rest: string = urlPath.slice("/platforms/web/client/web-component/".length);
        file = join(pkgDir, rest);
        if (rest.endsWith(".css")) type = "text/css";
      }
      const data: Buffer | null = file ? await readFile(file).catch((): null => null) : null;
      if (data) {
        res.setHeader("content-type", type);
        res.end(data);
        return;
      }
      if (urlPath === "/favicon.ico") {
        res.statusCode = 204;
        res.end();
        return;
      }
      res.statusCode = 404;
      res.end("not found");
    } catch (err: unknown) {
      console.error(`[${label}] server error on ${urlPath}: ${String(err)}`);
      res.statusCode = 500;
      res.end(String(err));
    }
  });
  return withTimeout(
    new Promise<Server>((resolve: ServerListenResolver): void => {
      server.listen(port, "127.0.0.1", (): void => resolve(server));
    }),
    10000,
    `listen ${port}`,
  );
}

// Attribute-agnostic quiescence: the base ref may predate current markers,
// so settle is defined by a full rendered-subtree fingerprint and page
// height, with at least one taken-over paragraph as a liveness proof.
const PAGE_HELPERS: string = `
  (() => {
    globalThis.__roots = () => Array.from(document.querySelectorAll("tiqian-prose"));
    const serialize = (node) => {
      if (node.nodeType === 3) return "t" + node.data.length + ":" + node.data;
      if (node.nodeType !== 1) return "o" + node.nodeType;
      const el = node;
      const attrs = Array.from(el.attributes, (a) => a.name + "=" + a.value).sort().join("|");
      return el.tagName + "[" + attrs + "]" + Array.from(el.childNodes, serialize).join(",");
    };
    globalThis.__fingerprint = () =>
      __roots().map((r) => Array.from(r.childNodes, serialize).join("#")).join("##") +
      "||" + document.documentElement.scrollHeight;
    globalThis.__settle = async (timeoutMs) => {
      await document.fonts.ready;
      const deadline = Date.now() + timeoutMs;
      const enhanced = () => document.querySelectorAll("tiqian-prose [data-tq-rendered]").length;
      let prev = __fingerprint();
      let stable = 0;
      let pageHeight = document.documentElement.scrollHeight;
      while (Date.now() < deadline && stable < 3) {
        await new Promise((resolve) => setTimeout(resolve, 350));
        pageHeight = document.documentElement.scrollHeight;
        const cur = __fingerprint();
        stable = cur === prev && enhanced() > 0 ? stable + 1 : 0;
        prev = cur;
      }
      return { settled: stable >= 3, pageHeight, enhanced: enhanced() };
    };
    const hud = document.querySelector(".floating-benchmark-hud");
    if (hud) hud.style.display = "none";
    globalThis.__setLaneWidth = (w) => {
      const wrapper = document.querySelector(".page-wrapper");
      if (wrapper) wrapper.style.maxWidth = w + "px";
      const slider = document.getElementById("width-slider");
      if (slider) slider.value = String(w);
    };
    ${DEEP_GEOMETRY_HELPERS}
  })()
`;

async function captureSide(options: CaptureSideOptions): Promise<CaptureSideResult> {
  const { label, pkgDir, port, cdpPort, plans }: CaptureSideOptions = options;
  const url: string = `http://127.0.0.1:${port}/`;
  const busyResolver: FetchBusyResolver = (): boolean => true;
  const notBusyResolver: FetchBusyResolver = (): boolean => false;
  const busy: boolean = await fetch(url).then(busyResolver, notBusyResolver);
  if (busy) throw new Error(`[${label}] port ${port} is busy`);
  const server: Server = await startDemoServer(port, pkgDir, label);
  const chromeBin: string = process.env.CHROME_BIN || "chromium";
  const browser: ChildProcess = spawn(chromeBin, [
    "--headless=new",
    `--remote-debugging-port=${cdpPort}`,
    "--no-sandbox",
    "--disable-gpu",
    "--disable-dev-shm-usage",
    "about:blank",
  ], { stdio: "ignore", detached: true });
  try {
    for (let i: number = 0; i < 75; i++) {
      try {
        const res: Response = await withTimeout(fetch(`http://127.0.0.1:${cdpPort}/json/version`), 3000, "v");
        if (res.ok) break;
      } catch {
        // retry
      }
      const sleepHandler: SleepResolver = (): void => {};
      await new Promise<void>((r: SleepResolver): NodeJS.Timeout => setTimeout(r, 200));
      void sleepHandler;
    }
    const targetsRes: Response = await fetch(`http://127.0.0.1:${cdpPort}/json/list`);
    const targets: CdpTarget[] = (await targetsRes.json()) as CdpTarget[];
    const pageTarget: CdpTarget | undefined = targets.find((t: CdpTarget): boolean => t.type === "page");
    if (!pageTarget) throw new Error(`[${label}] no page target found`);
    const client: CdpClient = new CdpClient(pageTarget.webSocketDebuggerUrl);
    await client.connect();
    await client.send("Page.enable");
    await client.send("Runtime.enable");
    await client.send("Page.navigate", { url });
    await client.evaluate("0");
    await client.send("Emulation.setDeviceMetricsOverride", {
      width: 1600,
      height: 900,
      deviceScaleFactor: 1,
      mobile: false,
    });
    await client.evaluate(`
      new Promise((resolve) => {
        if (document.readyState === "complete") setTimeout(resolve, 500);
        else window.addEventListener("load", () => setTimeout(resolve, 500));
      })
    `);
    await client.evaluate(PAGE_HELPERS);
    await client.send("Page.bringToFront");
    const settled: SettleResult = await client.evaluate<SettleResult>("__settle(45000)");
    if (!settled.settled || settled.enhanced === 0) {
      throw new Error(`[${label}] page did not settle (settled=${settled.settled} enhanced=${settled.enhanced})`);
    }
    // Each width is an independent comparison lane: resize, re-settle at the
    // new measure, recompute or replay the capture plan, then photograph and
    // measure the full surface. Plans travel from the base side so both
    // sides photograph identical regions.
    const lanes: Record<number, LaneCapture> = {};
    for (const width of WIDTH_LANES) {
      await client.evaluate(`__setLaneWidth(${width})`);
      await client.evaluate("window.scrollTo(0, 0)");
      const laneSettled: SettleResult = await client.evaluate<SettleResult>("__settle(30000)");
      if (!laneSettled.settled) {
        throw new Error(`[${label}] page did not settle at width ${width}`);
      }
      let plan: CapturePlan | undefined = plans?.[width];
      if (!plan) {
        plan = await client.evaluate<CapturePlan>(`
          (() => {
            const main = document.querySelector("main") ?? document.body;
            const rect = main.getBoundingClientRect();
            const viewportHeight = innerHeight;
            const pageHeight = document.documentElement.scrollHeight;
            const maxScroll = Math.max(0, pageHeight - viewportHeight);
            const stops = Math.max(1, Math.min(${MAX_SCROLL_STOPS}, Math.floor(maxScroll / viewportHeight) + 1));
            const scrolls = [];
            for (let i = 0; i < stops; i++) {
              scrolls.push(stops === 1 ? 0 : Math.round((maxScroll * i) / (stops - 1)));
            }
            return {
              rect: { x: rect.left + scrollX, y: rect.top + scrollY, width: rect.width, height: rect.height },
              viewportHeight,
              pageHeight,
              scrolls,
            };
          })()
        `);
      }
      const shots: Record<string, Buffer> = {};
      console.log(`[${label}] @${width} full clip=${JSON.stringify(plan.rect)}`);
      shots.full = await client.screenshot({
        clip: { x: plan.rect.x, y: plan.rect.y, width: plan.rect.width, height: plan.rect.height, scale: 1 },
        captureBeyondViewport: true,
      });
      for (const scroll of plan.scrolls) {
        await client.evaluate(`window.scrollTo(0, ${scroll})`);
        await new Promise<void>((r: SleepResolver): NodeJS.Timeout => setTimeout(r, 500));
        const at: SettleResult = await client.evaluate<SettleResult>("__settle(20000)");
        if (!at.settled) throw new Error(`[${label}] page did not settle at width ${width} scroll ${scroll}`);
        console.log(`[${label}] @${width} scroll=${scroll} clip y=${scroll} h=${Math.min(plan.viewportHeight, plan.pageHeight - scroll)}`);
        shots["scroll" + scroll] = await client.screenshot({
          clip: {
            x: plan.rect.x,
            y: scroll,
            width: plan.rect.width,
            height: Math.min(plan.viewportHeight, plan.pageHeight - scroll),
            scale: 1,
          },
          captureBeyondViewport: true,
        });
      }
      await client.evaluate("window.scrollTo(0, 0)");
      lanes[width] = {
        shots,
        plan,
        geometry: await client.evaluate<DeepGeometryReport>("__deepGeometry()"),
        pageHeight: await client.evaluate<number>("document.documentElement.scrollHeight"),
      };
    }
    client.close();
    return { label, lanes };
  } finally {
    if (browser.pid) {
      try { process.kill(-browser.pid, "SIGKILL"); } catch {}
      try { process.kill(browser.pid, "SIGKILL"); } catch {}
    }
    server.close();
  }
}

async function buildSide(label: string, sideDir: string): Promise<BuildSideResult> {
  console.log(`[${label}] building the ffi runtime in ${sideDir}`);
  await new Promise<void>((resolve: BuildSideResolver, reject: BuildSideRejecter): void => {
    const proc: ChildProcess = spawn("npm", [
      "run",
      "build:runtime",
    ], { cwd: join(sideDir, "platforms/web/client/engine-runtime"), stdio: ["ignore", "pipe", "pipe"] });
    let stderr: string = "";
    const stdoutHandler: BufferDataHandler = (d: Buffer): void => {
      process.stdout.write(`[${label}] ${d.toString()}`);
    };
    const stderrHandler: BufferDataHandler = (d: Buffer): void => {
      stderr += d.toString();
      process.stderr.write(`[${label}] ${d.toString()}`);
    };
    proc.stdout?.on("data", stdoutHandler);
    proc.stderr?.on("data", stderrHandler);
    const timer: NodeJS.Timeout = setTimeout((): void => {
      proc.kill("SIGKILL");
      reject(new Error(`[${label}] gradle build timed out`));
    }, 15 * 60 * 1000);
    const exitHandler: ProcessExitHandler = (code: number | null): void => {
      clearTimeout(timer);
      if (code === 0) resolve();
      else reject(new Error(`[${label}] gradle build failed (${code ?? "null"}): ${stderr}`));
    };
    proc.on("exit", exitHandler);
  });
  const artifact: string = join(sideDir, "platforms/web/client/engine-runtime/runtime/facade.mjs");
  const info: Stats = await stat(artifact);
  const bytes: Buffer = await readFile(artifact);
  const hash: string = createHash("md5").update(bytes).digest("hex");
  console.log(`[${label}] artifact ${info.size} bytes md5=${hash}`);
  return { artifact, hash };
}

const worktrees: string[] = [];
const cleanup = async (): Promise<void> => {
  const ignoreCatch: VoidReturnHandler = (): void => {};
  for (const dir of worktrees.splice(0)) {
    await run("git", ["worktree", "remove", "--force", dir], { cwd: repoRoot }).catch(ignoreCatch);
    await rm(dir, { recursive: true, force: true }).catch(ignoreCatch);
  }
};

try {
  // A stale chromium from an aborted run would silently own a debug port and
  // answer /json/list with a foreign page, so ports are checked up front.
  const busyTrue: FetchBusyResolver = (): boolean => true;
  const busyFalse: FetchBusyResolver = (): boolean => false;
  for (const port of [9321, 9323, 9931, 9933]) {
    const taken: boolean = await fetch(`http://127.0.0.1:${port}/json/version`).then(busyTrue, busyFalse);
    if (taken) throw new Error(`port ${port} is already serving CDP; kill the stale chromium first`);
  }
  const baseDir: string = await mkdtemp(join(tmpdir(), "tq-ab-base-"));
  worktrees.push(baseDir);
  console.log(`[setup] git worktree for base ${baseRef} at ${baseDir}`);
  await run("git", ["worktree", "add", "--detach", baseDir, baseRef], { cwd: repoRoot });
  const baseBuild: BuildSideResult = await buildSide("base", baseDir);

  let headDir: string = repoRoot;
  if (headRef) {
    headDir = await mkdtemp(join(tmpdir(), "tq-ab-head-"));
    worktrees.push(headDir);
    console.log(`[setup] git worktree for head ${headRef} at ${headDir}`);
    await run("git", ["worktree", "add", "--detach", headDir, headRef], { cwd: repoRoot });
  } else {
    console.log("[setup] head side is the current working tree (uncommitted changes included)");
  }
  const headBuild: BuildSideResult = await buildSide("head", headDir);

  if (baseBuild.hash === headBuild.hash) {
    console.warn("[warn] both sides produced identical artifacts; the comparison below is a no-op");
  }

  const base: CaptureSideResult = await captureSide({
    label: "base",
    pkgDir: join(baseDir, "platforms/web/client/web-component"),
    port: 9321,
    cdpPort: 9931,
    plans: null,
  });
  const planMapper: PlanMapper = (width: number): [number, CapturePlan] => [width, base.lanes[width].plan];
  const headPlans: Record<number, CapturePlan> = Object.fromEntries(
    WIDTH_LANES.map(planMapper),
  );
  const head: CaptureSideResult = await captureSide({
    label: "head",
    pkgDir: join(headDir, "platforms/web/client/web-component"),
    port: 9323,
    cdpPort: 9933,
    plans: headPlans,
  });

  const failures: string[] = [];
  console.log("\n=== ref-vs-ref report ===");
  console.log(`base: ${baseRef} (${baseBuild.hash})`);
  console.log(`head: ${headRef ?? "working tree"} (${headBuild.hash})`);
  for (const width of WIDTH_LANES) {
    const laneBase: LaneCapture = base.lanes[width];
    const laneHead: LaneCapture = head.lanes[width];
    if (laneBase.pageHeight !== laneHead.pageHeight) {
      failures.push(`@${width}: pageHeight ${laneBase.pageHeight} vs ${laneHead.pageHeight}`);
    }
    const geoDiff: DeepGeometryStats = diffDeepGeometry(laneBase.geometry, laneHead.geometry);
    const geoCounts: DeepGeometryCounts = deepGeometryCounts(laneBase.geometry);
    if (!geoDiff.equal) {
      failures.push(
        `@${width}: geometry ${geoDiff.divergentBoxes} divergent boxes of ${geoDiff.boxesCompared} compared`,
      );
    }
    const shotFailures: string[] = [];
    for (const key of Object.keys(laneBase.shots)) {
      const result: ScreenshotComparison = compareScreenshots(laneBase.shots[key], laneHead.shots[key]);
      if (!result.equal) {
        shotFailures.push(`${key}: ${result.differentPixels} differing pixels, first ${result.detail ?? "?"}`);
      }
    }
    console.log(
      `@${width}: boxes=${geoDiff.boxesCompared} ` +
      `(lineMarks=${geoCounts.lineMarks} runEls=${geoCounts.runEls} texts=${geoCounts.textNodes}) ` +
      `pageHeight=${laneBase.pageHeight}${laneBase.pageHeight === laneHead.pageHeight ? "" : " vs " + laneHead.pageHeight} ` +
      `shots=${Object.keys(laneBase.shots).length}`,
    );
    if (geoDiff.examples.length) {
      console.log(`@${width}: geometry divergences:`);
      for (const example of geoDiff.examples) console.log("  " + example);
    }
    for (const failure of shotFailures) {
      failures.push(`@${width}: ${failure}`);
    }
  }
  if (failures.length) {
    console.log("FAILURES:");
    for (const failure of failures) console.log("  " + failure);
    process.exitCode = 1;
  } else {
    console.log(`RESULT: identical at all ${WIDTH_LANES.length} width lanes ${WIDTH_LANES[0]}..${WIDTH_LANES[WIDTH_LANES.length - 1]} (full boxes and pixels)`);
  }
} finally {
  await cleanup();
}
