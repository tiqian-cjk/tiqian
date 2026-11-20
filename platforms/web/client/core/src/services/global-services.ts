// GlobalServices: the page-wide Service container (wc-s5 ruling R9,
// 2026-08-26). A service is behavior plus the private state that behavior
// owns; the container holds exactly the services whose scope is the whole
// document. Today that is one member: the coordination service, which owns
// the page frame clock, admission ordering, worker grants and the
// font/measurement coordination state those grants read.
//
// Container admission criteria: a member must be page-level behavior reached
// from async host callbacks (ResizeObserver, IntersectionObserver,
// requestAnimationFrame entry points) that never see a construction context.
// Behavior-less state records do not belong here: state that only needs
// cross-copy sharing lives in its owning module's closure behind a
// Symbol.for registry key (the prepared-styles, snapshot-table,
// snapshot-adoption, viewport-anchor and stylesheet-loader records moved to
// that pattern in this ruling).
//
// The container must be one per document rather than one per module copy
// because client routers, dev HMR and duplicated package chunks can evaluate
// this module more than once in the same document. The Symbol.for key shares
// one container across those copies. Members are resolved through the
// globalServices() accessor rather than passed as parameters because hosts
// reach the services from async callbacks without a construction context.
//
// Explicit initialization (wc-s6 scope 8): the container is not auto-
// constructed on first access. Hosts must call initializeGlobalServices()
// before any service access; registerTiqianProse does this. Access before
// initialization throws an error pointing to the initialization function.
//
// Library-internal, test-only injection: installGlobalServicesForTesting
// swaps the container for an explicit replacement and returns a restore
// function. Hosts must not touch it.
import { CoordinationService } from "../engine/coordination/coordination-service.js";
import { ClipboardManager } from "./clipboard-manager.js";

export interface GlobalServices {
  coordination: CoordinationService;
  clipboard: ClipboardManager;
}

type GlobalServicesRegistry = Record<symbol, GlobalServices | undefined>;

export type GlobalServicesRestoreFn = () => void;

const GLOBAL_SERVICES_KEY: unique symbol = Symbol.for("@tiqian/web-component.global-services.v1");

function createGlobalServices(): GlobalServices {
  return {
    coordination: new CoordinationService(),
    clipboard: new ClipboardManager(),
  };
}

// Explicit initialization: idempotent. Called by registerTiqianProse and
// the /auto entry. Returns the initialized container.
export function initializeGlobalServices(): GlobalServices {
  const registry = globalThis as GlobalServicesRegistry;
  let services = registry[GLOBAL_SERVICES_KEY];
  if (!services) {
    services = createGlobalServices();
    registry[GLOBAL_SERVICES_KEY] = services;
  }
  return services;
}

// Accessor: throws if not initialized. Hosts must call initializeGlobalServices
// before accessing services.
export function globalServices(): GlobalServices {
  const registry = globalThis as GlobalServicesRegistry;
  const services = registry[GLOBAL_SERVICES_KEY];
  if (!services) {
    throw new Error("GlobalServices not initialized. Call initializeGlobalServices() or registerTiqianProse() first.");
  }
  return services;
}

export function installGlobalServicesForTesting(container: GlobalServices): GlobalServicesRestoreFn {
  const registry = globalThis as GlobalServicesRegistry;
  const previous = registry[GLOBAL_SERVICES_KEY];
  registry[GLOBAL_SERVICES_KEY] = container;
  return () => {
    if (previous === undefined) delete registry[GLOBAL_SERVICES_KEY];
    else registry[GLOBAL_SERVICES_KEY] = previous;
  };
}
