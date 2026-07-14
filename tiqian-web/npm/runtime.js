let runtimePromise;

export function loadTiqianRuntime() {
  runtimePromise ??= import("./runtime/tiqian-web.js");
  return runtimePromise;
}

export function currentTiqianRuntime() {
  return runtimePromise;
}

export async function withTiqianRuntime(action) {
  await loadTiqianRuntime();
  return action(globalThis.TiqianWeb);
}
