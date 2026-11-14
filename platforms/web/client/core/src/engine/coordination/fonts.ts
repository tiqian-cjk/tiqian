// FontCoordinationState: the page-level, once-per-document fonts and
// declared-face coordination record. Per the service-directory rule (see
// core/services/global-services.ts), font readiness, declared @font-face
// registration, the browser font session loader and the replay registry are
// all page-wide singletons by definition: one document owns one snapshot-font
// fallback gate, one refcounted declared-face registry and one browser font
// backend regardless of how many roots attach or how many times a duplicated
// bundle chunk evaluates this module.
//
// This cluster module holds NO state of its own: it exports the state record
// type plus factory-free helpers that operate on a passed-in record, and the
// CoordinationService holds the single instance. The individual loaders and
// registries keep their public call surface; they consult this service-owned
// record instead of module-level mutable state.
//
// The replay registry is created and owned by the FontCoordinationState
// service instance; it is shared across bundle copies through the
// globalServices container (Symbol.for key).
import { FONT_REPLAY_REVISION } from "../../sampler/snapshot/snapshot-schema.js";
import type { SnapshotFontFallbackLoader } from "../loaders/font-loader.js";
import type { BrowserFontSessionLoader } from "../../measurement/browser-fonts.js";
import type { BrowserFontFaceLoader } from "../../measurement/font-face-loader.js";
import type { ReplayRegistry } from "../../measurement/browser-font-replay.js";
import type {
  DeclaredFaceEntry,
  DeclaredFaceVoidCallbackFn,
} from "../../sampler/snapshot/declared-faces.js";

export interface FontCoordinationState {
  fontFaceLoader?: BrowserFontFaceLoader;
  snapshotFontFallbackPromise: Promise<SnapshotFontFallbackLoader> | undefined;
  declaredFacesEntries: Map<string, DeclaredFaceEntry>;
  declaredFacesChangeListeners: Set<DeclaredFaceVoidCallbackFn>;
  // Constructed lazily on first use (see browser-fonts.ts): constructing it
  // here would statically pull the browser-fonts module graph — which leads
  // to precomputed.ts and prepared-dom.ts, whose module body installs the
  // read-only prepared renderer bridge — into every module that imports the
  // service accessor, ahead of test fixtures that pre-seed that slot.
  browserFontLoader: BrowserFontSessionLoader | undefined;
  replayRegistry: ReplayRegistry;
}

// The replay registry is created once by the service on first construction;
// later copies (and test-injected fresh services) reuse the same page-global
// slot through the globalServices container.
export function createReplayRegistry(): ReplayRegistry {
  return {
    sessions: new Map(),
    shapeResults: new Map(),
    metricResults: new Map(),
    nextSessionId: 1,
    nextResultId: 1,
  };
}