const ROOT_SELECTOR = "tiqian-prose, [data-tiqian-root]";
const PARAGRAPH_SELECTOR = "p, li";
const GESTURE_GRACE_MS = 350;
const MOMENTUM_CONTINUATION_MS = 1500;
const MIN_SCROLL_CORRECTION_PX = 0.5;

/**
 * ProgressiveViewportAnchorCompensation: a progressive commit replaces
 * paragraph content whose height differs from what the reader is looking at,
 * which silently moves their place in the article. The coordinator brackets
 * every slice with capture/compensate so the paragraph nearest the viewport
 * center keeps its on-screen position. Both reads happen in the same task as
 * the DOM mutation: transforms from entrance animations are identical on both
 * sides and cancel out, so only real layout displacement is corrected. This is
 * a viewport transition policy — the layout truth in LayoutResult is untouched.
 */

function clockNow() {
  const value = globalThis.performance?.now?.();
  return Number.isFinite(value) ? value : Date.now();
}

function viewportHeight(root) {
  const view = root.ownerDocument?.defaultView ?? globalThis.window;
  const value = view?.visualViewport?.height ?? view?.innerHeight ?? globalThis.innerHeight;
  return Number.isFinite(Number(value)) ? Number(value) : 0;
}

function readRect(element) {
  const rect = element?.getBoundingClientRect?.();
  if (!rect || !Number.isFinite(Number(rect.top))) return null;
  const top = Number(rect.top);
  const bottom = Number.isFinite(Number(rect.bottom)) ? Number(rect.bottom) : top;
  return { top, bottom };
}

// GestureGraceYield: a scroll correction delivered mid-gesture halts iOS
// momentum and fights the user's hand. Input tracking is document-wide and
// shared by every root; compensation simply skips while a gesture is live.
// MomentumScrollContinuation: iOS momentum fires no touch events after the
// finger lifts, only scroll events. A scroll arriving shortly after a real
// gesture extends the grace; an isolated scroll (including our own
// correction) does not.
let gestureTrackerInstalled = false;
let lastGestureAt = Number.NEGATIVE_INFINITY;

function installGestureTracker(root) {
  if (gestureTrackerInstalled) return;
  const view = root.ownerDocument?.defaultView ?? globalThis.window;
  if (typeof view?.addEventListener !== "function") return;
  gestureTrackerInstalled = true;
  const passiveCapture = { capture: true, passive: true };
  const markGesture = () => {
    lastGestureAt = clockNow();
  };
  for (const type of ["pointerdown", "touchstart", "touchmove", "wheel", "keydown"]) {
    view.addEventListener(type, markGesture, passiveCapture);
  }
  view.addEventListener("scroll", () => {
    const now = clockNow();
    if (now - lastGestureAt < MOMENTUM_CONTINUATION_MS) lastGestureAt = now;
  }, passiveCapture);
}

function gestureIsActive() {
  return clockNow() - lastGestureAt < GESTURE_GRACE_MS;
}

function belongsToRoot(node, root) {
  if (typeof node.closest !== "function") return true;
  return node.closest(ROOT_SELECTOR) === root;
}

// ViewportCenterParagraphAnchor: the paragraph whose top sits nearest the
// viewport center is the one the reader is most likely reading; paragraphs
// above it absorb the height changes that would move it. The root itself is
// the fallback when no paragraph intersects the viewport.
function chooseAnchor(root) {
  const paragraphs = root.querySelectorAll?.(PARAGRAPH_SELECTOR) ?? [];
  const height = viewportHeight(root);
  const center = height > 0 ? height / 2 : 0;
  let selected = null;
  let selectedDistance = Infinity;
  for (let index = 0; index < paragraphs.length; index += 1) {
    const paragraph = paragraphs[index];
    if (!belongsToRoot(paragraph, root)) continue;
    const rect = readRect(paragraph);
    if (!rect) continue;
    if (height > 0 && (rect.bottom <= 0 || rect.top >= height)) continue;
    const distance = Math.abs(rect.top - center);
    if (distance < selectedDistance) {
      selected = { node: paragraph, top: rect.top };
      selectedDistance = distance;
    }
  }
  if (selected) return selected;
  const rootRect = readRect(root);
  return rootRect ? { node: root, top: rootRect.top } : null;
}

function computedStyle(element) {
  const view = element?.ownerDocument?.defaultView ?? globalThis.window;
  const getter = view?.getComputedStyle ?? globalThis.getComputedStyle;
  if (typeof getter !== "function") return null;
  try {
    return getter.call(view, element);
  } catch {
    return null;
  }
}

function scrollableOverflow(value) {
  return /^(auto|overlay|scroll)$/u.test(String(value ?? "").trim().toLowerCase());
}

function scrollOwner(root) {
  for (let element = root; element; element = element.parentElement) {
    const style = computedStyle(element);
    if (!style) continue;
    if (!scrollableOverflow(style.overflowY || style.overflow)) continue;
    if (element.scrollHeight > element.clientHeight) {
      return { element, view: root.ownerDocument?.defaultView ?? globalThis.window };
    }
  }
  return { element: null, view: root.ownerDocument?.defaultView ?? globalThis.window };
}

function applyScrollDelta(root, delta) {
  const owner = scrollOwner(root);
  if (owner.element) {
    const current = Number(owner.element.scrollTop);
    if (!Number.isFinite(current)) return false;
    owner.element.scrollTop = current + delta;
    return true;
  }
  if (typeof owner.view?.scrollBy === "function") {
    owner.view.scrollBy(0, delta);
    return true;
  }
  const scrollingElement = root.ownerDocument?.scrollingElement;
  if (scrollingElement) {
    const current = Number(scrollingElement.scrollTop);
    if (!Number.isFinite(current)) return false;
    scrollingElement.scrollTop = current + delta;
    return true;
  }
  return false;
}

function scrollOffset(root) {
  const owner = scrollOwner(root);
  if (owner.element) {
    const value = Number(owner.element.scrollTop);
    return Number.isFinite(value) ? value : 0;
  }
  const value = Number(
    owner.view?.scrollY ?? root.ownerDocument?.scrollingElement?.scrollTop,
  );
  return Number.isFinite(value) ? value : 0;
}

/**
 * Reads the anchor immediately before a slice mutates the DOM. Returns null
 * when there is nothing to protect: the reader is actively scrolling, the
 * scroller sits at its very top (CSS scroll anchoring suppresses adjustments
 * at offset zero, and so does this policy, so a page enhancing during load
 * never scrolls away from the article start), or the root is entirely below
 * the viewport, where its height changes cannot move visible content. A root
 * entirely above the viewport anchors on its own bottom edge: every height
 * change inside it displaces the viewport by exactly that edge's movement.
 */
export function captureViewportAnchor(root) {
  installGestureTracker(root);
  holdNativeScrollAnchoring(root);
  if (gestureIsActive()) return null;
  if (!(scrollOffset(root) > 0)) return null;
  const rect = readRect(root);
  if (!rect) return null;
  const height = viewportHeight(root);
  if (height > 0 && rect.top >= height) return null;
  if (height > 0 && rect.bottom <= 0) {
    return { node: root, top: rect.bottom, edge: "bottom" };
  }
  return chooseAnchor(root);
}

/**
 * Re-reads the anchor after the slice committed and cancels its displacement
 * in the nearest scrollable ancestor (or the window). Must run in the same
 * task as the capture; a frame boundary in between would let animations and
 * user scrolling pollute the delta.
 */
export function compensateViewportAnchor(root, anchor) {
  if (!anchor || anchor.node.isConnected === false) return false;
  const rect = readRect(anchor.node);
  if (!rect) return false;
  const delta = (anchor.edge === "bottom" ? rect.bottom : rect.top) - anchor.top;
  if (!Number.isFinite(delta) || Math.abs(delta) < MIN_SCROLL_CORRECTION_PX) return false;
  return applyScrollDelta(root, delta);
}

const heldOwnerByRoot = new WeakMap();
const ownerHolds = new WeakMap();

/**
 * NativeAnchoringHandover: two anchoring systems must never share one
 * scroller. While a layout job is committing slices, the browser's own scroll
 * anchoring sees engine paragraph swaps as anchor-node destruction and can
 * re-anchor wildly (hundreds of pixels per frame when an entrance animation
 * runs alongside). For exactly the job window this module owns the scroller:
 * `overflow-anchor: none` on the nearest scrollable ancestor (or the root
 * element for the viewport), reference-counted across roots that share it and
 * restored as soon as the last job ends, so ordinary host content keeps
 * native anchoring at all other times.
 */
export function holdNativeScrollAnchoring(root) {
  if (heldOwnerByRoot.has(root)) return;
  const owner = scrollOwner(root).element ?? root.ownerDocument?.documentElement;
  const style = owner?.style;
  if (typeof style?.setProperty !== "function") return;
  heldOwnerByRoot.set(root, owner);
  const hold = ownerHolds.get(owner) ?? { count: 0, saved: null };
  if (hold.count === 0) {
    hold.saved = {
      value: style.getPropertyValue?.("overflow-anchor") ?? "",
      priority: style.getPropertyPriority?.("overflow-anchor") ?? "",
    };
    style.setProperty("overflow-anchor", "none");
  }
  hold.count += 1;
  ownerHolds.set(owner, hold);
}

export function releaseNativeScrollAnchoring(root) {
  const owner = heldOwnerByRoot.get(root);
  if (!owner) return;
  heldOwnerByRoot.delete(root);
  const hold = ownerHolds.get(owner);
  if (!hold) return;
  hold.count -= 1;
  if (hold.count > 0) return;
  ownerHolds.delete(owner);
  const style = owner.style;
  if (typeof style?.setProperty !== "function" || !hold.saved) return;
  if (hold.saved.value) {
    style.setProperty("overflow-anchor", hold.saved.value, hold.saved.priority);
  } else {
    style.removeProperty?.("overflow-anchor");
  }
}
