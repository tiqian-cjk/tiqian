// The unified font session over the native addon (ADR 0050). The session
// surface matches `createFontSession` from the former
// `@tiqian/prose/precompute-fonts` module; shape and metrics are session
// methods here because the native world has no global WASM backend handle
// protocol.

import { currentPlatform } from "@neon-rs/load";
import { addon } from "./load.js";

const SUPPORTED_PLATFORMS = new Set([
  "win32-x64-msvc",
  "darwin-arm64",
  "linux-x64-gnu",
  "linux-arm64-gnu",
]);

const platform = currentPlatform();
if (!SUPPORTED_PLATFORMS.has(platform)) {
  throw new Error(`UnsupportedPrecomputePlatform:${platform}`);
}

/**
 * Parses a JSON string produced by the shared Rust emitters. The addon and
 * the Kotlin/JS oracle emit the same bytes; parsing happens only here, at
 * the boundary.
 */
function parse<T>(json: string): T {
  return JSON.parse(json) as T;
}

function toBuffer(source: Uint8Array | Buffer): Buffer {
  return Buffer.isBuffer(source) ? source : Buffer.from(source);
}

/**
 * One `@font-face` input of `createFontSession`.
 */
export interface FontFaceSpecInput {
  family: string;
  publicUrl: string;
  source: Uint8Array | Buffer;
  weight?: number | [number, number];
  style?: string;
  unicodeRange?: string;
  sourceOrder?: number;
  faceIndex?: number;
}

export interface FontSessionOptions {
  sessionPrefix?: string;
  /** Only `lnum` is accepted; any other tag throws `UnsupportedFontSessionBaseFeatures`. */
  baseFeatures?: string[];
}

export interface ShapeGlyph {
  id: number;
  cluster: number;
  advance: number;
  x: number;
  y: number;
  bounds?: number[];
}

export interface ShapeResult {
  faceId: string;
  fontInstanceId: string;
  script: string;
  features: string[];
  probeFeatures: string[];
  unsafeBreakCount: number;
  advance: number;
  glyphs: ShapeGlyph[];
}

export interface FaceInfo {
  family: string;
  style: string;
  weight: [number, number];
  unicodeRange: string;
  publicUrl: string;
  sourceSha256: string;
  sfntSha256: string;
  faceIndex: number;
  sourceOrder: number;
  axisTags: string[];
  localNames: string[];
}

export interface BoundaryStyleInput {
  fontFamilies: string[];
  fontSizePx: number;
  fontWeight: number;
  italic: boolean;
  baselineShiftPx?: number;
}

export interface BoundaryTextSpanInput {
  start: number;
  end: number;
  style: BoundaryStyleInput;
}

/** Paragraph typography of the `precomputeParagraph` call. */
export interface ParagraphTypography {
  fontFamilies: string[];
  fontSizePx: number;
  lineHeightPx: number;
  locale: string;
  fontWeight: number;
  italic: boolean;
  firstLineIndentIc: number;
  lineLengthGridEnabled: boolean;
}

/** One styled span inside a paragraph. Indices count UTF-16 code units. */
export interface ParagraphTextSpanInput {
  start: number;
  end: number;
  families: string[];
  fontSizePx: number;
  fontWeight: number;
  italic: boolean;
  baselineShiftPx: number;
}

/** One inline box inside a paragraph. */
export interface ParagraphInlineBoxInput {
  start: number;
  end: number;
  inlineStartPx: number;
  inlineEndPx: number;
  /** Omitted boxes use the `Narrow` default of the protocol. */
  outerSpacing?: "Narrow" | "Source";
}

/** One line-break policy span inside a paragraph. */
export interface ParagraphLineBreakSpanInput {
  start: number;
  end: number;
  policy: "ProgressiveTechnical";
}

/** Optional span sections of a paragraph request. */
export interface ParagraphSpans {
  sourceBoundaries?: number[];
  textSpans?: ParagraphTextSpanInput[];
  inlineBoxes?: ParagraphInlineBoxInput[];
  lineBreakSpans?: ParagraphLineBreakSpanInput[];
}

/** Why a line ended; the engine names match `LineEndReason`. */
export type PlanEndReason = "AutoWrap" | "MandatoryBreak" | "ParagraphEnd";

/** One laid-out cell of a plan line. */
export interface PlanCell {
  rangeStart: number;
  rangeEnd: number;
  source: string;
  display: string;
  drawX: number;
  naturalWidth: number;
  leadingLayoutAdvance: number;
  /** Present only when the cell opens a shaping boundary. */
  shapingBoundary?: true;
  /** Present only when the run carries OpenType features. */
  openTypeFeatures?: string[];
}

/** One line of the plan JSON. */
export interface PlanLine {
  rangeStart: number;
  rangeEnd: number;
  top: number;
  bottom: number;
  baseline: number;
  indent: number;
  visualWidth: number;
  hyphenAdvance: number;
  endReason: PlanEndReason;
  cells: PlanCell[];
}

/** The plan JSON of one paragraph, parsed at the boundary. */
export interface PreparedPlan {
  schema: string;
  layoutRevision: string;
  width: number;
  height: number;
  lines: PlanLine[];
}

export interface FontEvidence {
  backendRevision: string;
  harfbuzzVersion: string;
  faces: Array<Record<string, unknown>>;
  replay: {
    revision: string;
    shapes: Array<Record<string, unknown>>;
    metrics: Array<Record<string, unknown>>;
  };
}

export interface FontSession {
  id: string;
  backendRevision: string;
  harfbuzzVersion: string;
  readonly faces: FaceInfo[];
  shape(
    displayText: string,
    families: string[],
    fontSize: number,
    fontWeight: number,
    italic: boolean,
    locale: string,
    role?: string | null,
    sourceText?: string | null,
  ): ShapeResult;
  metrics(
    families: string[],
    fontSize: number,
    fontWeight: number,
    italic: boolean,
    role?: string | null,
    faceSelectionText?: string | null,
  ): number[];
  renderFamilies(requestedFamilies: string[]): string[];
  sourceBoundaries(
    text: string,
    baseStyle: BoundaryStyleInput,
    textSpans: BoundaryTextSpanInput[],
  ): number[];
  /**
   * Runs one paragraph through the engine with this session as the font
   * backend. Throws the named validation issues of the request; throws
   * `EngineNotLinked` when the addon was built without the engine archive.
   */
  precomputeParagraph(
    text: string,
    maxWidthPx: number,
    typography: ParagraphTypography,
    spans?: ParagraphSpans,
  ): PreparedPlan;
  beginCapture(): void;
  captureEvidence(): FontEvidence;
  close(): void;
}

/**
 * Creates a font session from explicit `@font-face` inputs. `faceSpecs`
 * entries carry their font binary as `source` (Uint8Array or Buffer).
 */
export async function createFontSession(
  faceSpecs: FontFaceSpecInput[],
  options: FontSessionOptions = {},
): Promise<FontSession> {
  if (!Array.isArray(faceSpecs) || faceSpecs.length === 0) {
    throw new Error("MissingExplicitFontFaces");
  }
  const sources: Buffer[] = [];
  const faces = faceSpecs.map((face) => {
    sources.push(toBuffer(face.source));
    return {
      family: face.family,
      publicUrl: face.publicUrl,
      font: sources.length - 1,
      faceIndex: face.faceIndex ?? null,
      weight: face.weight,
      style: face.style,
      unicodeRange: face.unicodeRange ?? null,
      sourceOrder: face.sourceOrder ?? null,
    };
  });
  const id = addon.createFontSession(faces, sources, {
    sessionPrefix: options.sessionPrefix ?? null,
    baseFeatures: options.baseFeatures ?? null,
  });
  return {
    id,
    backendRevision: addon.backendRevision(),
    harfbuzzVersion: addon.harfbuzzVersion(),
    get faces(): FaceInfo[] {
      return parse<FaceInfo[]>(addon.sessionFaces(id));
    },
    shape(
      displayText: string,
      families: string[],
      fontSize: number,
      fontWeight: number,
      italic: boolean,
      locale: string,
      role: string | null = null,
      sourceText: string | null = null,
    ): ShapeResult {
      return parse<ShapeResult>(
        addon.shape(
          id,
          displayText,
          families.join("\u001f"),
          fontSize,
          fontWeight,
          italic,
          locale,
          role,
          sourceText,
        ),
      );
    },
    metrics(
      families: string[],
      fontSize: number,
      fontWeight: number,
      italic: boolean,
      role: string | null = null,
      faceSelectionText: string | null = null,
    ): number[] {
      return parse<number[]>(
        addon.metrics(
          id,
          families.join("\u001f"),
          fontSize,
          fontWeight,
          italic,
          role,
          faceSelectionText,
        ),
      );
    },
    renderFamilies(requestedFamilies: string[]): string[] {
      return parse<string[]>(addon.renderFamilies(id, requestedFamilies));
    },
    sourceBoundaries(
      text: string,
      baseStyle: BoundaryStyleInput,
      textSpans: BoundaryTextSpanInput[],
    ): number[] {
      return parse<number[]>(addon.sourceBoundaries(id, text, baseStyle, textSpans));
    },
    precomputeParagraph(
      text: string,
      maxWidthPx: number,
      typography: ParagraphTypography,
      spans: ParagraphSpans = {},
    ): PreparedPlan {
      return parse<PreparedPlan>(
        addon.precomputeParagraph(
          id,
          text,
          maxWidthPx,
          typography.fontFamilies,
          typography.fontSizePx,
          typography.lineHeightPx,
          typography.locale,
          typography.fontWeight,
          typography.italic,
          typography.firstLineIndentIc,
          typography.lineLengthGridEnabled,
          spans.sourceBoundaries ?? [],
          spans.textSpans ?? [],
          spans.inlineBoxes ?? [],
          spans.lineBreakSpans ?? [],
        ),
      );
    },
    beginCapture(): void {
      addon.beginCapture(id);
    },
    captureEvidence(): FontEvidence {
      return parse<FontEvidence>(addon.captureEvidence(id));
    },
    close(): void {
      addon.closeSession(id);
    },
  };
}

export const backendRevision: string = addon.backendRevision();
export const harfbuzzVersion: string = addon.harfbuzzVersion();
