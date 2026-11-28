// Prepared-paragraph entries served by the shared package: request
// normalization, LayoutInput assembly and the two plan serializations live in
// @tiqian/shared; core owns the host request shape, the two host callbacks and
// the error-name normalization the layout callers rely on.

import { LruWidthIndependentAnnotationCache } from "@tiqian/engine/org/tiqian/layout/WidthIndependentAnnotationCache";
import { TiqianIllegalArgumentException } from "@tiqian/engine/org/tiqian/core/TiqianIllegalArgumentException";
import { IllegalStateException } from "@tiqian/engine/org/tiqian/core/IllegalStateException";
import type { PlanWithDiagnostics } from "@tiqian/engine/org/tiqian/layout/PreparedParagraph";
import type { ShapingInput, ShapingResult } from "@tiqian/engine/org/tiqian/shaping/TextShaper";
import type { FontMetricsRequest } from "@tiqian/engine/org/tiqian/font/FontMetrics";
import type { RawFontMetrics } from "@tiqian/engine/org/tiqian/font/RawFontMetrics";
import { ParagraphRequestException } from "@tiqian/protocol/org/tiqian/protocol/ParagraphRequestException";
import type { ParagraphRequest } from "@tiqian/protocol/org/tiqian/protocol/ParagraphRequest";
import type { Plan } from "@tiqian/protocol/org/tiqian/protocol/Plan";
import { PreparedParagraphLayout } from "@tiqian/shared/org/tiqian/shared/layout/PreparedParagraphLayout";
import type { PrepareParagraphRequest } from "./wire-types.js";

export type { PlanWithDiagnostics };

/**
 * The host's two engine callbacks, as typed adapters. Object identity scopes
 * the annotation cache: a width-only relayout reuses the same callbacks and
 * therefore hits the cache instead of re-shaping every paragraph.
 */
export interface EngineCallbacks {
  readonly shape: (input: ShapingInput) => ShapingResult;
  readonly resolve: (request: FontMetricsRequest) => RawFontMetrics;
}

const annotationCacheStore = new WeakMap<EngineCallbacks, LruWidthIndependentAnnotationCache>();

/** A host shaping failure carried through the engine as its declared shaping fault. */
class HostShapingFault extends IllegalStateException {
  readonly hostError: unknown;

  constructor(hostError: unknown) {
    super(String(hostError instanceof Error ? hostError.message : hostError));
    this.hostError = hostError;
  }
}

const engineCallbackStore = new WeakMap<EngineCallbacks, EngineCallbacks>();

// Host shaping errors enter the engine as its shaping fault.
function engineCallbacks(callbacks: EngineCallbacks): EngineCallbacks {
  let entry = engineCallbackStore.get(callbacks);
  if (entry === undefined) {
    entry = {
      shape: (input: ShapingInput): ShapingResult => {
        try {
          return callbacks.shape(input);
        } catch (error) {
          if (error instanceof IllegalStateException) throw error;
          throw new HostShapingFault(error);
        }
      },
      resolve: callbacks.resolve,
    };
    engineCallbackStore.set(callbacks, entry);
  }
  return entry;
}

function annotationCache(callbacks: EngineCallbacks): LruWidthIndependentAnnotationCache {
  let entry = annotationCacheStore.get(callbacks);
  if (entry === undefined) {
    entry = new LruWidthIndependentAnnotationCache(512);
    annotationCacheStore.set(callbacks, entry);
  }
  return entry;
}

class IllegalArgumentException extends Error {
  constructor(message: string) {
    super(message);
    this.name = "IllegalArgumentException";
  }
}

function makeIllegalArgument(message: string): Error {
  return new IllegalArgumentException(message);
}

function asProtocolRequest(request: PrepareParagraphRequest): ParagraphRequest {
  return request as unknown as ParagraphRequest;
}

// The shared entry raises the protocol refusal for invalid requests and the
// engine's illegal-argument exception for a reversed or negative range; the
// layout callers catch the range kinds by name.
function mapRefusal(error: unknown): never {
  if (error instanceof HostShapingFault) {
    throw error.hostError;
  }
  if (error instanceof ParagraphRequestException) {
    throw makeIllegalArgument(error.message);
  }
  if (error instanceof TiqianIllegalArgumentException) {
    const kind = error.error.kind;
    if (kind === "NegativeStart" || kind === "StartGreaterThanEnd") {
      const named = new Error(error.message);
      named.name = kind;
      throw named;
    }
    throw makeIllegalArgument(error.message);
  }
  throw error;
}

/** Plan plus the capability-issue and advance diagnostics. */
export function preparedParagraphWithDiagnostics(
  request: PrepareParagraphRequest,
  zeroAdvanceEpsilonPx: number,
  callbacks: EngineCallbacks,
): PlanWithDiagnostics {
  try {
    return PreparedParagraphLayout.toPlanWithDiagnostics(
      asProtocolRequest(request),
      zeroAdvanceEpsilonPx,
      engineCallbacks(callbacks),
      annotationCache(callbacks),
      request.renderEvidenceOverride ?? null,
    );
  } catch (error) {
    mapRefusal(error);
  }
}

/** Plan-only entry for the layout worker; same serializer, no diagnostics pass. */
export function preparedParagraphPlan(
  request: PrepareParagraphRequest,
  callbacks: EngineCallbacks,
): Plan {
  try {
    return PreparedParagraphLayout.toPlan(
      asProtocolRequest(request),
      engineCallbacks(callbacks),
      annotationCache(callbacks),
      request.renderEvidenceOverride ?? null,
    );
  } catch (error) {
    mapRefusal(error);
  }
}
