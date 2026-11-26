// Worker-necessity bench (ADR 0053 batch 0, section 5).
//
// Measures, per paragraph, the cost of producing a layout plan through the
// server-replay session (Form A: table replay, Form B: repeat cache-hit
// reruns) and the fixed main-thread roundtrip overhead per paragraph
// (serialize take+issue, structuredClone, plan stringify/parse). The numbers
// feed the decomposition report's decision on whether a dedicated Worker is
// necessary for a snapshot-manifest page.
//
// Runs under three runners with plain node, no build step:
//   node bench/worker-necessity.ts
//   bun bench/worker-necessity.ts
//   node --jitless bench/worker-necessity.ts          # slow; use TIQIAN_BENCH_PASSES=3
//
// TIQIAN_BENCH_PASSES overrides the measured pass count (default 30).
//
// No files are written; this script reads bench/fixtures/corpus/ only and
// prints the table plus a single BENCH_JSON line on stdout.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { performance } from "node:perf_hooks";

import { snapshotTablesFromBytes } from "@tiqian/core/snapshot-tables.js";
import type { SnapshotTableBinaryView } from "@tiqian/core/snapshot-table-binary.js";
import { parseSnapshotManifest } from "@tiqian/core/snapshot-manifest.js";
import type { ExpandedSnapshotManifest, SnapshotManifestEntry, SnapshotManifestFace } from "@tiqian/core/snapshot-manifest.js";

type PrecomputeParagraphFn = (
  sessionId: string,
  text: string,
  maxWidthPx: number,
  fontFamilies: readonly string[] | string,
  fontSizePx: number,
  lineHeightPx: number,
  locale: string,
  fontWeight: number,
  italic: boolean,
  firstLineIndentIc: number,
  lineLengthGridEnabled: boolean,
  sourceBoundaries: string,
  textSpans: unknown,
  inlineBoxes: unknown,
  lineBreakSpans: unknown,
  inlineObjects: unknown,
) => string;

interface FfiModule {
  readonly precomputeParagraph?: PrecomputeParagraphFn;
}

interface ServerReplayFontSessionOptions {
  readonly sessionPrefix?: string;
  readonly replay?: unknown;
  readonly faceMetadata?: readonly SnapshotManifestFace[];
  readonly harfbuzzVersion?: string;
}

interface ServerReplayFontSession {
  readonly id: string;
  readonly faces: readonly SnapshotManifestFace[];
  close?(): void;
}

type CreateServerReplayFontSessionFn = (
  specs: readonly Record<string, unknown>[],
  options: ServerReplayFontSessionOptions,
) => Promise<ServerReplayFontSession>;

type MergeSerializedSourceBoundariesFn = (
  primary: string,
  subset: string,
) => string;

type WorkerSnapshotSubsetSourceBoundariesFn = (
  faces: readonly SnapshotManifestFace[],
  request: BenchLayoutRequest,
) => string;

interface BrowserFontReplayModule {
  readonly createServerReplayFontSession: CreateServerReplayFontSessionFn;
}

interface FontFaceBoundariesModule {
  readonly mergeSerializedSourceBoundaries: MergeSerializedSourceBoundariesFn;
  readonly workerSnapshotSubsetSourceBoundaries: WorkerSnapshotSubsetSourceBoundariesFn;
}

interface AssemblyFieldsModule {
  readonly LAYOUT_REQUEST_FIELDS: readonly string[];
}

const BENCH_DIR: string = dirname(fileURLToPath(import.meta.url));
const FIXTURE_DIR: string = join(BENCH_DIR, "fixtures", "corpus");

// Pass configuration: Form A warms up three unmeasured full passes so the
// Kotlin/JS engine and JIT reach steady state before any number is taken.
const FORM_A_WARMUP_PASSES: number = 3;
const FORM_B_DISCARD_PASSES: number = 2;
const DEFAULT_MEASURED_PASSES: number = 30;
const ROUNDTRIP_SAMPLES: number = 200;

const SHORT_BUCKET_MAX: number = 80;
const MEDIUM_BUCKET_MAX: number = 200;

type LengthBucket = "short" | "medium" | "long";

interface StatsResult {
  readonly count: number;
  readonly p50: number;
  readonly p95: number;
  readonly mean: number;
  readonly min: number;
  readonly max: number;
}

interface StatsByBucketResult {
  readonly short: StatsResult;
  readonly medium: StatsResult;
  readonly long: StatsResult;
}

interface DurationRecord {
  readonly bucket: LengthBucket;
  readonly durationUs: number;
}

interface BenchMetaBuckets {
  readonly short: number;
  readonly medium: number;
  readonly long: number;
}

interface BenchMeta {
  readonly paragraphCount: number;
  readonly totalCharacters: number;
  readonly buckets: BenchMetaBuckets;
}

interface BenchLayoutRequest {
  readonly text: string;
  readonly maxWidthPx: number;
  readonly fontFamilies: readonly string[];
  readonly fontSizePx: number;
  readonly lineHeightPx: number;
  readonly locale: string;
  readonly fontWeight: number;
  readonly italic: boolean;
  readonly firstLineIndentIc: number;
  readonly sourceBoundaries: string;
  readonly textSpans: unknown;
  readonly inlineBoxes: unknown;
  readonly lineBreakSpans: unknown;
  readonly inlineObjects: unknown;
  readonly [key: string]: unknown;
}

interface ReplaySessionResult {
  readonly session: ServerReplayFontSession;
  readonly requests: readonly BenchLayoutRequest[];
}

type PlanCallback = (plan: string) => void;
type VoidOperation = () => void;

function layoutRequestKey(request: BenchLayoutRequest | null | undefined, layoutFields: readonly string[]): string {
  return JSON.stringify(layoutFields.map((field: string): unknown => request?.[field] ?? null));
}

function bucketOf(textLength: number): LengthBucket {
  if (textLength < SHORT_BUCKET_MAX) return "short";
  if (textLength < MEDIUM_BUCKET_MAX) return "medium";
  return "long";
}

function percentile(sortedValues: readonly number[], fraction: number): number {
  if (sortedValues.length === 0) return Number.NaN;
  const index: number = Math.max(0, Math.ceil(fraction * sortedValues.length) - 1);
  return sortedValues[index];
}

function statsOf(durations: readonly number[]): StatsResult {
  const sorted: readonly number[] = [...durations].sort((left: number, right: number): number => left - right);
  const count: number = sorted.length;
  const sum: number = sorted.reduce((total: number, value: number): number => total + value, 0);
  return {
    count,
    p50: percentile(sorted, 0.5),
    p95: percentile(sorted, 0.95),
    mean: count > 0 ? sum / count : Number.NaN,
    min: count > 0 ? sorted[0] : Number.NaN,
    max: count > 0 ? sorted[count - 1] : Number.NaN,
  };
}

function statsByBucket(records: readonly DurationRecord[]): StatsByBucketResult {
  const buckets: Record<LengthBucket, number[]> = { short: [], medium: [], long: [] };
  for (const record of records) buckets[record.bucket].push(record.durationUs);
  return {
    short: statsOf(buckets.short),
    medium: statsOf(buckets.medium),
    long: statsOf(buckets.long),
  };
}

// Loads the fixtures and rebuilds the replay session by replicating
// layout-worker.js manifestSession (layout-worker.js:12-52): decode the tables,
// expand the manifest, dedupe evidence faces by the full face-identity key,
// sort by sourceOrder, then create the server-replay session with the pinned
// replay data and the empty face specs the worker passes.
async function replaySession(): Promise<ReplaySessionResult> {
  const manifestText: string = readFileSync(join(FIXTURE_DIR, "manifest.txt"), "utf8");
  const tablesBytes: Uint8Array = new Uint8Array(readFileSync(join(FIXTURE_DIR, "tables.tiqtbl")));
  const tables: SnapshotTableBinaryView | null = tablesBytes.length > 0 ? snapshotTablesFromBytes(tablesBytes) : null;
  const manifest: ExpandedSnapshotManifest = parseSnapshotManifest(manifestText, tables);
  const entries: readonly SnapshotManifestEntry[] = [...(manifest.entries ?? []), ...(manifest.fontContractEntries ?? [])];
  const evidence: readonly SnapshotManifestFace[] = entries.flatMap(
    (entry: SnapshotManifestEntry): readonly SnapshotManifestFace[] => entry?.fontEvidence?.faces ?? [],
  );
  if (evidence.length === 0 || !manifest.fontReplay) {
    throw new Error("LayoutWorkerFontContractInvalid");
  }
  const faces: SnapshotManifestFace[] = [];
  const seen: Set<string> = new Set<string>();
  for (const face of evidence) {
    const key: string = JSON.stringify([
      face.sfntSha256,
      face.faceIndex,
      face.sourceOrder,
      face.family,
      face.style,
      face.weight,
      face.unicodeRange,
      face.publicUrl,
    ]);
    if (seen.has(key)) continue;
    seen.add(key);
    faces.push(face);
  }
  faces.sort((left: SnapshotManifestFace, right: SnapshotManifestFace): number => Number(left.sourceOrder) - Number(right.sourceOrder));
  const first = entries.find((entry: SnapshotManifestEntry): boolean => Boolean(entry?.fontEvidence))?.fontEvidence;
  const browserFontReplayModule: BrowserFontReplayModule = (await import(
    new URL("@tiqian/core/browser-font-replay.js", import.meta.url).href
  )) as BrowserFontReplayModule;
  const session: ServerReplayFontSession = await browserFontReplayModule.createServerReplayFontSession(
    faces.map((): Record<string, unknown> => ({})),
    {
      sessionPrefix: "tq-worker-bench",
      replay: manifest.fontReplay,
      faceMetadata: faces,
      harfbuzzVersion: first?.harfbuzzVersion ?? "",
    },
  );
  const requests: readonly BenchLayoutRequest[] = JSON.parse(readFileSync(join(FIXTURE_DIR, "requests.json"), "utf8")) as readonly BenchLayoutRequest[];
  return { session, requests };
}

// Replicates the per-request worker body (layout-worker.js:82-102): the exact
// source boundaries merge, then precomputeParagraph with the fixed
// lineLengthGridEnabled=true argument the worker passes.
function callParagraph(
  session: ServerReplayFontSession,
  request: BenchLayoutRequest,
  boundariesModule: FontFaceBoundariesModule,
  precomputeParagraph: PrecomputeParagraphFn | undefined,
): string {
  const sourceBoundaries: string = boundariesModule.mergeSerializedSourceBoundaries(
    request.sourceBoundaries,
    boundariesModule.workerSnapshotSubsetSourceBoundaries(session.faces, request),
  );
  if (!precomputeParagraph) {
    throw new Error("PrecomputeParagraphNotExported");
  }
  return precomputeParagraph(
    session.id,
    request.text,
    request.maxWidthPx,
    request.fontFamilies,
    request.fontSizePx,
    request.lineHeightPx,
    request.locale,
    request.fontWeight,
    request.italic,
    request.firstLineIndentIc,
    true,
    sourceBoundaries,
    request.textSpans,
    request.inlineBoxes,
    request.lineBreakSpans,
    request.inlineObjects,
  );
}

function runFullPass(
  session: ServerReplayFontSession,
  requests: readonly BenchLayoutRequest[],
  boundariesModule: FontFaceBoundariesModule,
  precomputeParagraph: PrecomputeParagraphFn | undefined,
): void {
  for (const request of requests) callParagraph(session, request, boundariesModule, precomputeParagraph);
}

// Runs `measuredPasses` passes and returns one duration record per paragraph,
// tagged with its length bucket for the overall and per-bucket stats.
function measurePasses(
  session: ServerReplayFontSession,
  requests: readonly BenchLayoutRequest[],
  measuredPasses: number,
  boundariesModule: FontFaceBoundariesModule,
  precomputeParagraph: PrecomputeParagraphFn | undefined,
  onPlan?: PlanCallback,
): DurationRecord[] {
  const records: DurationRecord[] = [];
  for (let pass: number = 0; pass < measuredPasses; pass += 1) {
    for (const request of requests) {
      const startedAt: number = performance.now();
      const plan: string = callParagraph(session, request, boundariesModule, precomputeParagraph);
      records.push({
        bucket: bucketOf(request.text.length),
        durationUs: (performance.now() - startedAt) * 1000,
      });
      onPlan?.(plan);
    }
  }
  return records;
}

function measureMicroseconds(operation: VoidOperation): number {
  operation();
  const startedAt: number = performance.now();
  for (let index: number = 0; index < ROUNDTRIP_SAMPLES; index += 1) operation();
  return ((performance.now() - startedAt) / ROUNDTRIP_SAMPLES) * 1000;
}

function formatUs(value: number): string {
  return Number.isFinite(value) ? value.toFixed(1) : "n/a";
}

function formatStats(stats: StatsResult): string {
  return `p50=${formatUs(stats.p50)} p95=${formatUs(stats.p95)} ` +
    `mean=${formatUs(stats.mean)} min=${formatUs(stats.min)} max=${formatUs(stats.max)} (n=${stats.count})`;
}

function printBucketRows(title: string, byBucket: StatsByBucketResult): void {
  console.log(`  ${title} (us)`);
  for (const name of ["short", "medium", "long"] as const) {
    console.log(`    ${name.padEnd(6)} ${formatStats(byBucket[name])}`);
  }
}

interface BenchJsonCorpus {
  readonly paragraphs: number;
  readonly totalCharacters: number;
  readonly buckets: BenchMetaBuckets;
}

interface BenchJsonPasses {
  readonly formAWarmup: number;
  readonly formBDiscard: number;
  readonly measured: number;
}

interface BenchJsonFormData {
  readonly overall: StatsResult;
  readonly byBucket: StatsByBucketResult;
}

interface BenchJsonRoundtrip {
  readonly serializeTakeIssueUs: number;
  readonly structuredCloneUs: number;
  readonly planRoundtripUs: number;
  readonly fixedOverheadUs: number;
}

interface BenchJson {
  readonly corpus: BenchJsonCorpus;
  readonly passes: BenchJsonPasses;
  readonly formA: BenchJsonFormData;
  readonly formB: BenchJsonFormData;
  readonly roundtrip: BenchJsonRoundtrip;
}

async function main(): Promise<void> {
  const measuredPasses: number = Number.parseInt(process.env.TIQIAN_BENCH_PASSES ?? "", 10) ||
    DEFAULT_MEASURED_PASSES;
  const meta: BenchMeta = JSON.parse(readFileSync(join(FIXTURE_DIR, "meta.json"), "utf8")) as BenchMeta;
  console.log(
    `tiqian worker-necessity bench | corpus ${meta.paragraphCount} paragraphs ` +
    `(${JSON.stringify(meta.buckets)}) | ${measuredPasses} measured passes`,
  );

  const ffiModule: FfiModule = (await import(
    new URL("@tiqian/engine", import.meta.url).href
  )) as FfiModule;
  const precomputeParagraphFn: PrecomputeParagraphFn | undefined = ffiModule.precomputeParagraph;

  const boundariesModule: FontFaceBoundariesModule = (await import(
    new URL("@tiqian/core/font-face-boundaries.js", import.meta.url).href
  )) as FontFaceBoundariesModule;

  const assemblyModule: AssemblyFieldsModule = (await import(
    new URL("@tiqian/core/src/engine/web-worker/assembly-record-fields.js", import.meta.url).href
  )) as AssemblyFieldsModule;

  const { session, requests } = await replaySession();

  // Form A: table replay through the server-replay session.
  for (let pass: number = 0; pass < FORM_A_WARMUP_PASSES; pass += 1) {
    runFullPass(session, requests, boundariesModule, precomputeParagraphFn);
  }
  let capturedPlan: string | null = null;
  const formA: readonly DurationRecord[] = measurePasses(
    session,
    requests,
    measuredPasses,
    boundariesModule,
    precomputeParagraphFn,
    (plan: string): void => {
      if (capturedPlan === null) capturedPlan = plan;
    },
  );

  // Form B: repeat the same requests in the same session. Passes 0 and 1 are
  // discarded so the reported numbers sit in the registry-hit regime where
  // every shaping/metrics read is a Map lookup against the session tables.
  for (let pass: number = 0; pass < FORM_B_DISCARD_PASSES; pass += 1) {
    runFullPass(session, requests, boundariesModule, precomputeParagraphFn);
  }
  const formB: readonly DurationRecord[] = measurePasses(session, requests, measuredPasses, boundariesModule, precomputeParagraphFn);

  // Per-paragraph fixed roundtrip overhead.
  const referenceRequest: BenchLayoutRequest = requests[0];
  const serializeTakeIssueUs: number = measureMicroseconds((): void => {
    // One take + one issue each serialize the layout request key and the
    // request (worker-channel.js:100-101). Each sample runs the pair twice, so
    // the reported figure covers two take+issue pairs and overstates the
    // per-paragraph cost in the conservative direction.
    for (let index: number = 0; index < 2; index += 1) {
      layoutRequestKey(referenceRequest, assemblyModule.LAYOUT_REQUEST_FIELDS);
      JSON.stringify(referenceRequest);
    }
  });
  const structuredCloneUs: number = measureMicroseconds((): void => {
    structuredClone(referenceRequest);
  });
  const capturedPlanObject: unknown = JSON.parse(capturedPlan ?? "null");
  const planRoundtripUs: number = measureMicroseconds((): void => {
    JSON.parse(JSON.stringify(capturedPlanObject));
  });
  const fixedOverheadUs: number = serializeTakeIssueUs + structuredCloneUs + planRoundtripUs;

  const formAOverall: StatsResult = statsOf(formA.map((record: DurationRecord): number => record.durationUs));
  const formBOverall: StatsResult = statsOf(formB.map((record: DurationRecord): number => record.durationUs));

  console.log(`\nForm A (table replay, after ${FORM_A_WARMUP_PASSES} warmup passes):`);
  console.log(`  overall   ${formatStats(formAOverall)}`);
  printBucketRows("short (<80), medium (80-199), long (>=200)", statsByBucket(formA));
  console.log(`\nForm B (cache-hit rerun, passes >= ${FORM_B_DISCARD_PASSES}):`);
  console.log(`  overall   ${formatStats(formBOverall)}`);
  printBucketRows("short (<80), medium (80-199), long (>=200)", statsByBucket(formB));
  console.log(`\nPer-paragraph fixed roundtrip overhead (us):`);
  console.log(`  serialize take+issue  ${formatUs(serializeTakeIssueUs)}`);
  console.log(`  structuredClone       ${formatUs(structuredCloneUs)}`);
  console.log(`  plan stringify/parse  ${formatUs(planRoundtripUs)}`);
  console.log(`  sum (fixed overhead)  ${formatUs(fixedOverheadUs)}`);

  session.close?.();
  const benchJson: BenchJson = {
    corpus: {
      paragraphs: meta.paragraphCount,
      totalCharacters: meta.totalCharacters,
      buckets: meta.buckets,
    },
    passes: {
      formAWarmup: FORM_A_WARMUP_PASSES,
      formBDiscard: FORM_B_DISCARD_PASSES,
      measured: measuredPasses,
    },
    formA: {
      overall: formAOverall,
      byBucket: statsByBucket(formA),
    },
    formB: {
      overall: formBOverall,
      byBucket: statsByBucket(formB),
    },
    roundtrip: {
      serializeTakeIssueUs,
      structuredCloneUs,
      planRoundtripUs,
      fixedOverheadUs,
    },
  };
  console.log(`\nBENCH_JSON ${JSON.stringify(benchJson)}`);
}

main().catch((error: unknown): void => {
  console.error(`[bench] ${error instanceof Error ? error.stack : String(error)}`);
  process.exitCode = 1;
});
