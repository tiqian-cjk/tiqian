import { loadTiqianRuntime, withTiqianRuntime } from "./runtime.js";
import { prepareCjkDashShaping } from "./font-shaping.js";
import { ensureTiqianStyles } from "./styles.js";

export { loadTiqianRuntime };

const rootGenerations = new WeakMap();

function supersedeRootWork(root) {
  const generation = (rootGenerations.get(root) ?? 0) + 1;
  rootGenerations.set(root, generation);
  return generation;
}

async function withTiqianWeb(root, options, action) {
  const generation = supersedeRootWork(root);
  await Promise.all([loadTiqianRuntime(), ensureTiqianStyles()]);
  const cjkDashCapability = await prepareCjkDashShaping(root, options);
  // AsyncPreparationCancellation: navigation/destroy may happen while fonts or
  // Wasm are loading. A superseded request must never re-enhance detached DOM.
  if (rootGenerations.get(root) !== generation) return root;
  return withTiqianRuntime((api) => {
    if (rootGenerations.get(root) !== generation) return root;
    return action(api, { ...options, cjkDashCapability });
  });
}

export function enhance(root = document.body, options = {}) {
  return withTiqianWeb(root, options, (api, prepared) => api.enhance(root, prepared));
}

export function enhanceProgressively(root = document.body, options = {}) {
  return withTiqianWeb(root, options, (api, prepared) => api.enhanceProgressively(root, prepared));
}

export function destroy(root = document.body) {
  const generation = supersedeRootWork(root);
  return withTiqianRuntime((api) => {
    if (rootGenerations.get(root) !== generation) return;
    return api.destroy(root);
  });
}

export function enhanceAll(options = {}) {
  const roots = [...document.querySelectorAll("tiqian-prose, [data-tiqian-root]")];
  return Promise.all(roots.map((root) => enhance(root, options)));
}
