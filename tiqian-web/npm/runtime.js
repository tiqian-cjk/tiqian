let runtimePromise;

export function loadTiqianRuntime() {
  runtimePromise ??= import("./runtime/Tiqian-tiqian-web.mjs");
  return runtimePromise;
}

export function currentTiqianRuntime() {
  return runtimePromise;
}

export async function withTiqianRuntime(action) {
  await loadTiqianRuntime();
  return action(globalThis.TiqianWeb);
}
