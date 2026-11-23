import '@tiqian/web-component/auto';
import { registerTiqianProse } from '@tiqian/web-component/element';
import { createEnhanceContext } from '@tiqian/core/src/engine/context/enhance-context.js';

interface MetricsEventDetail {
  durationMs?: number;
}

declare global {
  var __tiqianOneShot: ((root: Element, options?: Record<string, unknown>) => Promise<void>) | undefined;
  var __tiqianRegister: typeof registerTiqianProse | undefined;
}

// One-shot replay entry for the demo/web tests: parcel bundles module
// instances so the page cannot re-import them by URL, and the retired document
// event channel (ADR 0053 C1) no longer accepts replays. Tests replay captured
// root options through this public surface. Replaces the retired enhance() verb
// (wc-s6 scope 9): options apply through the factory, and mount returns the
// completion promise covering the one-time work, runtime loading included.
globalThis.__tiqianOneShot = (root: Element, options?: Record<string, unknown>): Promise<void> =>
  createEnhanceContext(root, options).mount();

// Explicit registration entry point for programmatic hosts. The /auto entry
// already registers <tiqian-prose> with default options on import, but tests
// and controlled environments can call this directly for parameterized setup.
globalThis.__tiqianRegister = registerTiqianProse;

// Fixed Benchmark HUD Controls
const slider: HTMLInputElement | null = document.getElementById('width-slider') as HTMLInputElement | null;
const widthVal: HTMLElement | null = document.getElementById('width-val');
const pageWrapper: HTMLElement | null = document.querySelector('.page-wrapper');
const relayoutMsVal: HTMLElement | null = document.getElementById('relayout-ms-val');
const fpsVal: HTMLElement | null = document.getElementById('fps-val');

// 1. Fluid Width Slider
if (slider && pageWrapper && widthVal) {
  slider.addEventListener('input', (e: Event): void => {
    const target: HTMLInputElement = e.target as HTMLInputElement;
    const width: number = Number(target.value);
    widthVal.textContent = width + 'px';
    pageWrapper.style.maxWidth = width + 'px';
  });
}

// 2. Monitor Tiqian Relayout Latency
function handleMetrics(e: Event): void {
  const customEvent: CustomEvent<MetricsEventDetail> = e as CustomEvent<MetricsEventDetail>;
  if (customEvent.detail && typeof customEvent.detail.durationMs === 'number' && relayoutMsVal) {
    relayoutMsVal.textContent = customEvent.detail.durationMs.toFixed(1) + 'ms';
  }
}
document.addEventListener('tiqian:relayout-ready', handleMetrics);
document.addEventListener('tiqian:ready', handleMetrics);

// 3. Live 60 FPS Monitor
let frameCount: number = 0;
let lastTime: number = performance.now();
function updateFps(): void {
  frameCount++;
  const now: number = performance.now();
  if (now - lastTime >= 500) {
    const fps: number = Math.round((frameCount * 1000) / (now - lastTime));
    if (fpsVal) fpsVal.textContent = fps + ' FPS';
    frameCount = 0;
    lastTime = now;
  }
  requestAnimationFrame(updateFps);
}
requestAnimationFrame(updateFps);
