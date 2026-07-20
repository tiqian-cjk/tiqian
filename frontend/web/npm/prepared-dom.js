import {
  LAYOUT_REVISION,
  RENDER_REVISION,
  SNAPSHOT_SCHEMA,
} from "./snapshot-schema.js";
import { normalizeSnapshotSemantics } from "./snapshot-source.js";

const SPACING_EPSILON = 0.01;
const RENDER_FLOW_EPSILON_PX = 0.01;
const DEFAULT_LOCALE = "zh-Hans";
const LINE_MARKER_SELECTOR = "[data-tq-line-flow-width]";
const ROOT_SELECTOR = "tiqian-prose, [data-tiqian-root]";
const VALUE_STYLE_SCOPE_ATTRIBUTE = "data-tq-value-style-scope";
const VALUE_STYLE_ELEMENT_ATTRIBUTE = "data-tq-prepared-value-styles";
const SNAPSHOT_STYLE_OWNER = Object.freeze({});
const preparedStyleStates = new WeakMap();
const preparedStyleRootsByHost = new WeakMap();
let nextPreparedStyleScope = 1;

export const PREPARED_DOM_BRIDGE_NAME = "__TiqianPreparedDomRenderer";

function preparedPlan(value) {
  return typeof value === "string" ? JSON.parse(value) : value;
}

function preparedLocale(value) {
  if (typeof value === "string") return value;
  return String(value?.locale ?? DEFAULT_LOCALE);
}

function escapeText(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function escapeAttribute(value) {
  return escapeText(value).replaceAll('"', "&quot;");
}

function cssString(value) {
  return `"${String(value).replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
}

function px(value) {
  const normalized = Math.abs(value) < 0.000001 ? 0 : value;
  return `${Number(normalized.toFixed(5))}px`;
}

function snapshotValueStyleClass(index) {
  return `tqv-${index.toString(36)}`;
}

function runtimeValueStyleClass(index) {
  return `tqvr-${index.toString(36)}`;
}

function createPreparedStyleState(root) {
  const documentObject = root?.ownerDocument ?? globalThis.document;
  const parent = documentObject?.head ?? documentObject?.documentElement ?? documentObject?.body;
  if (!documentObject?.createElement || !parent?.appendChild || !root?.setAttribute) return null;
  const styleElement = documentObject.createElement("style");
  const scope = `tqv${nextPreparedStyleScope++}`;
  styleElement.setAttribute(VALUE_STYLE_ELEMENT_ATTRIBUTE, scope);
  const originalScope = root.getAttribute(VALUE_STYLE_SCOPE_ATTRIBUTE);
  root.setAttribute(VALUE_STYLE_SCOPE_ATTRIBUTE, scope);
  parent.appendChild(styleElement);
  const state = {
    root,
    scope,
    styleElement,
    originalScope,
    declarations: [],
    indexes: new Map(),
    owners: new Map(),
    dirty: false,
  };
  preparedStyleStates.set(root, state);
  return state;
}

function preparedStyleState(root) {
  return preparedStyleStates.get(root) ?? createPreparedStyleState(root);
}

function registerPreparedValueStyle(state, declaration) {
  const existing = state.indexes.get(declaration);
  if (existing != null) return existing;
  const index = state.declarations.length;
  state.declarations.push(declaration);
  state.indexes.set(declaration, index);
  state.dirty = true;
  return index;
}

function syncPreparedValueStyles(state) {
  if (!state.dirty) return;
  const rootScope = `[${VALUE_STYLE_SCOPE_ATTRIBUTE}="${state.scope}"]`;
  const snapshotValuesActive = state.owners.has(SNAPSHOT_STYLE_OWNER);
  const runtimeValuesActive = Array.from(state.owners.keys()).some((owner) =>
    owner !== SNAPSHOT_STYLE_OWNER);
  state.styleElement.textContent = state.declarations.map((declaration, index) => {
    // PreparedValueNamespaceIsolation: build-time snapshot CSS remains live in
    // the document so it can restore exact first-paint nodes. Runtime lowering
    // must use a distinct class namespace; otherwise the same compact index can
    // combine unrelated important properties (for example snapshot
    // letter-spacing plus runtime margin-right) even when the scoped runtime
    // rule has higher specificity.
    const snapshotRule = snapshotValuesActive
      ? `${rootScope} [data-tq-rendered="true"] .${snapshotValueStyleClass(index)}{${declaration}}`
      : "";
    const runtimeRule = runtimeValuesActive
      ? `${rootScope}[${VALUE_STYLE_SCOPE_ATTRIBUTE}] [data-tq-rendered="true"] .${runtimeValueStyleClass(index)}{${declaration}}`
      : "";
    return snapshotRule + runtimeRule;
  }).join("");
  state.dirty = false;
}

function removePreparedStyleState(state) {
  preparedStyleStates.delete(state.root);
  for (const owner of state.owners.keys()) {
    if (owner !== SNAPSHOT_STYLE_OWNER) preparedStyleRootsByHost.delete(owner);
  }
  state.styleElement.remove?.();
  if (state.styleElement.parentNode) state.styleElement.parentNode.removeChild(state.styleElement);
  if (state.originalScope == null) state.root.removeAttribute(VALUE_STYLE_SCOPE_ATTRIBUTE);
  else state.root.setAttribute(VALUE_STYLE_SCOPE_ATTRIBUTE, state.originalScope);
}

/** Installs the compact snapshot's dynamic declarations before DOM adoption. */
export function installPreparedValueStyles(root, declarations, renderFontFamilies = []) {
  if (!Array.isArray(declarations)) throw new Error("InvalidPreparedValueStyles");
  if (!Array.isArray(renderFontFamilies) || renderFontFamilies.some((family) =>
    typeof family !== "string" || !family.trim())) throw new Error("InvalidPreparedRenderFontFamilies");
  releasePreparedValueStyleRoot(root);
  if (declarations.length === 0) return false;
  const state = preparedStyleState(root);
  if (!state) throw new Error("PreparedValueStyleHostUnavailable");
  try {
    const indexes = declarations.map((declaration, expectedIndex) => {
      if (typeof declaration !== "string" || !declaration) {
        throw new Error("InvalidPreparedValueStyleDeclaration");
      }
      const index = registerPreparedValueStyle(state, declaration);
      if (index !== expectedIndex) throw new Error("DuplicatePreparedValueStyleDeclaration");
      return index;
    });
    state.owners.set(SNAPSHOT_STYLE_OWNER, new Set(indexes));
    syncPreparedValueStyles(state);
    return true;
  } catch (error) {
    removePreparedStyleState(state);
    throw error;
  }
}

/**
 * Kept as an internal compatibility hook. Host-compatible replay inherits the
 * existing font-family, so installing a package-owned family style is a no-op.
 */
export function installPreparedRenderFontStyle(root, renderFontFamilies) {
  if (!Array.isArray(renderFontFamilies) || renderFontFamilies.length === 0 ||
      renderFontFamilies.some((family) => typeof family !== "string" || !family.trim())) {
    throw new Error("InvalidPreparedRenderFontFamilies");
  }
  return false;
}

export function releasePreparedRenderFontStyle(root) {
  return false;
}

export function releasePreparedParagraphStyles(host) {
  const root = preparedStyleRootsByHost.get(host);
  if (!root) return false;
  preparedStyleRootsByHost.delete(host);
  const state = preparedStyleStates.get(root);
  if (!state) return false;
  state.owners.delete(host);
  if (state.owners.size === 0) removePreparedStyleState(state);
  return true;
}

export function releasePreparedValueStyleRoot(root) {
  const state = preparedStyleStates.get(root);
  if (!state) return false;
  removePreparedStyleState(state);
  return true;
}

function applyDynamicStyles(attributes, styles, styleClassFor) {
  if (styles.length === 0) return;
  const declaration = styles.join(";");
  if (styleClassFor) {
    const generatedClass = styleClassFor(declaration);
    attributes.class = attributes.class ? `${attributes.class} ${generatedClass}` : generatedClass;
  } else {
    attributes.style = declaration;
  }
}

function renderedElement(tag, attributes = {}, text = null, voidElement = false) {
  const entries = Object.entries(attributes)
    .filter(([, value]) => value != null)
    .map(([name, value]) => [name, String(value)])
    .sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0);
  const serializedAttributes = entries.map(([name, value]) =>
    value === "" ? name : `${name}="${escapeAttribute(value)}"`).join(" ");
  const opening = `<${tag}${serializedAttributes ? ` ${serializedAttributes}` : ""}>`;
  const children = text == null ? [] : [["#", String(text)]];
  return {
    html: voidElement ? opening : `${opening}${text == null ? "" : escapeText(text)}</${tag}>`,
    artifact: [tag, entries, children],
  };
}

function renderedContainer(tag, attributes = {}) {
  const entries = Object.entries(attributes)
    .filter(([, value]) => value != null)
    .map(([name, value]) => [name, String(value)])
    .sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0);
  const children = [];
  return {
    children,
    get html() {
      const serializedAttributes = entries.map(([name, value]) =>
        value === "" ? name : `${name}="${escapeAttribute(value)}"`).join(" ");
      return `<${tag}${serializedAttributes ? ` ${serializedAttributes}` : ""}>` +
        `${children.map((child) => child.html).join("")}</${tag}>`;
    },
    get artifact() {
      return [tag, entries, children.map((child) => child.artifact)];
    },
  };
}

function renderedText(value) {
  const text = String(value);
  return {
    html: escapeText(text),
    // CanonicalSnapshotTextNode: this must be byte-for-byte the same shape as
    // precomputed.js derives from the browser-parsed template DOM. A synthetic
    // `#text` element wrapper made every sparse/native Text node snapshot miss
    // with SnapshotArtifactDigestMismatch.
    artifact: ["#", text],
  };
}

function preparedSpacing(display, naturalWidth, trailingGap) {
  if (Math.abs(trailingGap) < SPACING_EPSILON) return { kind: "none", px: 0 };
  // NegativeSingleCellFlowAdvance: browsers clamp the border-box width of a
  // one-character inline span at zero when negative letter-spacing exceeds the
  // glyph advance. Preserve the selectable source glyph at its natural width
  // and carry the overtake in margin-right, which is also how multi-character
  // overlap is represented. The line sentinel still verifies the total flow.
  if (display.length === 1 && naturalWidth + trailingGap >= 0) {
    return { kind: "letter", px: trailingGap };
  }
  if (trailingGap < 0) return { kind: "overlap", px: trailingGap };
  // MultiCharacterSelectableGapCarrier: this is one layout gap after the whole
  // shaping cluster, not tracking distributed through the word. A dedicated
  // selectable carrier preserves the uninterrupted shaping run and owns the
  // full flow advance; splitting off the final grapheme would break kerning.
  return { kind: "trailing-letter", px: trailingGap };
}

function preparedFeatureSignature(run) {
  return Array.from(run.openTypeFeatures ?? [], String).join(",");
}

function preparedRenderFontSignature(run) {
  return Array.from(run.renderFontFamilies ?? [], String).join("\u001f");
}

function canMergePreparedRun(left, right) {
  if (left.rangeEnd !== right.rangeStart ||
      left.semanticSignature !== right.semanticSignature ||
      left.shapingBoundary || right.shapingBoundary ||
      preparedFeatureSignature(left) !== preparedFeatureSignature(right) ||
      preparedRenderFontSignature(left) !== preparedRenderFontSignature(right)) {
    return false;
  }
  if (left.spacing.kind === "none" && right.spacing.kind === "none") return true;
  return left.spacing.kind === "letter" && right.spacing.kind === "letter" &&
    Math.abs(left.spacing.px - right.spacing.px) < SPACING_EPSILON;
}

function mergePreparedRun(left, right) {
  left.rangeEnd = right.rangeEnd;
  left.source += right.source;
  left.display += right.display;
  left.naturalWidth += right.naturalWidth;
  left.trailingGap += right.trailingGap;
}

function renderRun(run, styleClassFor) {
  const featureSignature = preparedFeatureSignature(run);
  const renderFontFamilies = Array.from(run.renderFontFamilies ?? [], String);
  const needsElement = run.shapingBoundary || featureSignature ||
    renderFontFamilies.length > 0 || run.source !== run.display || run.spacing.kind !== "none";
  if (!needsElement) return renderedText(run.display);
  const attributes = {
    "data-tq-advance": String(
      run.spacing.kind === "letter" || run.spacing.kind === "trailing-letter"
        ? run.naturalWidth + run.trailingGap
        : run.naturalWidth,
    ),
    "data-tq-geometry": "true",
    "data-tq-x": String(run.drawX),
  };
  if (run.shapingBoundary || featureSignature) {
    attributes["data-tq-shaping-boundary"] = "";
  }
  if (featureSignature) {
    if (featureSignature !== "pwid,palt") throw new Error("UnsupportedPreparedOpenTypeFeatures");
    attributes["data-tq-open-type-features"] = featureSignature;
  }
  if (run.source !== run.display) attributes["data-tq-src"] = run.source;
  const styles = [];
  if (renderFontFamilies.length > 0) {
    attributes["data-tq-render-font-projection"] = "true";
    styles.push(`font-family:${renderFontFamilies.map(cssString).join(",")}!important`);
  }
  if (run.spacing.kind === "letter") {
    styles.push(`letter-spacing:${px(run.spacing.px)}!important`);
  } else if (run.spacing.kind === "overlap") {
    styles.push(`margin-right:${px(run.spacing.px)}!important`);
  }
  applyDynamicStyles(attributes, styles, styleClassFor);
  if (run.spacing.kind === "trailing-letter") {
    const container = renderedContainer("span", attributes);
    container.children.push(renderedText(run.display));
    const carrierAttributes = {
      "aria-hidden": "true",
      "data-tq-copy-ignore": "true",
      "data-tq-geometry": "true",
      "data-tq-spacing-carrier": "true",
    };
    applyDynamicStyles(
      carrierAttributes,
      [
        "display:inline-block!important",
        `inline-size:${px(run.spacing.px)}!important`,
        "height:0!important",
        "line-height:0!important",
        `letter-spacing:${px(run.spacing.px)}!important`,
        "overflow:hidden!important",
        "vertical-align:baseline!important",
        "white-space:pre!important",
      ],
      styleClassFor,
    );
    container.children.push(renderedElement("span", carrierAttributes, "\u00A0"));
    return container;
  }
  return renderedElement("span", attributes, run.display);
}

/**
 * Lowers the canonical prepared-layout wire format to the sparse DOM wire used
 * by both build-time snapshots and browser runtime rendering.
 */
export function renderPreparedParagraphArtifact(
  planOrJson,
  typographyOrLocale = DEFAULT_LOCALE,
  options = {},
) {
  const plan = preparedPlan(planOrJson);
  const locale = preparedLocale(typographyOrLocale);
  const styleClassFor = typeof options.styleClassFor === "function" ? options.styleClassFor : null;
  if (plan?.schema !== SNAPSHOT_SCHEMA || plan?.layoutRevision !== LAYOUT_REVISION) {
    throw new Error("UnsupportedPreparedLayoutRevision");
  }
  const paragraphHeight = Number(plan.height);
  if (!Number.isFinite(paragraphHeight) || paragraphHeight < 0 || !Array.isArray(plan.lines)) {
    throw new Error("InvalidPreparedParagraphGeometry");
  }
  const sourceText = plan.lines.flatMap((line) => line.cells).map((cell) => cell.source).join("");
  const semantics = normalizeSnapshotSemantics(options.sourceText ?? sourceText, options.semantics ?? []);
  const renderTextSpans = Array.from(options.renderTextSpans ?? [], (span) => {
    const start = Number(span?.start);
    const end = Number(span?.end);
    const fontFamilies = Array.from(span?.fontFamilies ?? [], String)
      .map((family) => family.trim())
      .filter(Boolean);
    if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || end <= start ||
        end > (options.sourceText ?? sourceText).length || fontFamilies.length === 0) {
      throw new Error("InvalidPreparedRenderTextSpan");
    }
    return { start, end, fontFamilies };
  });
  const inlineBoxes = Array.from(options.inlineBoxes ?? []);
  const inlineStartByOffset = new Map();
  const inlineEndByOffset = new Map();
  for (const box of inlineBoxes) {
    inlineStartByOffset.set(box.start, (inlineStartByOffset.get(box.start) ?? 0) + Number(box.inlineStartPx));
    inlineEndByOffset.set(box.end, (inlineEndByOffset.get(box.end) ?? 0) + Number(box.inlineEndPx));
  }
  const semanticSpansFor = (rangeStart, rangeEnd) => semantics.filter((span) =>
    rangeStart >= span.start && rangeEnd <= span.end);
  const semanticSpansCrossing = (offset) => semantics.filter((span) =>
    offset > span.start && offset < span.end);
  const renderFontFamiliesFor = (rangeStart, rangeEnd) => {
    const owners = renderTextSpans.filter((span) =>
      rangeStart >= span.start && rangeEnd <= span.end);
    if (owners.length === 0) return [];
    const signature = JSON.stringify(owners[0].fontFamilies);
    if (owners.some((span) => JSON.stringify(span.fontFamilies) !== signature)) {
      throw new Error("ConflictingPreparedRenderTextSpan");
    }
    return owners[0].fontFamilies;
  };
  const nodes = [];
  let activeSemantics = [];
  let activeContainers = [];
  const semanticContainerFor = (semanticPath) => {
    const commonLimit = Math.min(activeSemantics.length, semanticPath.length);
    let common = 0;
    while (common < commonLimit && activeSemantics[common] === semanticPath[common]) common += 1;
    activeSemantics = activeSemantics.slice(0, common);
    activeContainers = activeContainers.slice(0, common);
    let container = activeContainers.at(-1)?.children ?? nodes;
    for (let index = common; index < semanticPath.length; index += 1) {
      const semantic = semanticPath[index];
      const wrapper = renderedContainer(semantic.tagName, {
        ...Object.fromEntries(semantic.attributes),
        "data-tq-source-semantic": "true",
      });
      container.push(wrapper);
      activeSemantics.push(semantic);
      activeContainers.push(wrapper);
      container = wrapper.children;
    }
    return container;
  };
  for (let lineIndex = 0; lineIndex < plan.lines.length; lineIndex += 1) {
    const line = plan.lines[lineIndex];
    const height = line.bottom - line.top;
    const first = line.cells[0];
    const flowStart = first ? first.drawX - first.leadingLayoutAdvance : 0;
    const firstInlineStart = first ? inlineStartByOffset.get(first.rangeStart) ?? 0 : 0;
    if (first && Math.abs(first.leadingLayoutAdvance - firstInlineStart) > RENDER_FLOW_EPSILON_PX) {
      throw new Error(`SnapshotRenderFlowMismatch:line=${lineIndex};leading-layout-advance`);
    }
    const cells = line.cells.map((cell, index) => {
      const next = line.cells[index + 1];
      const trailingInlineEdge = inlineEndByOffset.get(cell.rangeEnd) ?? 0;
      const nextLeadingInlineEdge = next ? inlineStartByOffset.get(next.rangeStart) ?? 0 : 0;
      const trailingGap = next
        ? next.drawX - cell.drawX - cell.naturalWidth - trailingInlineEdge - nextLeadingInlineEdge
        : line.hyphenAdvance > 0
          ? 0
          : line.indent + line.visualWidth - cell.drawX - cell.naturalWidth - trailingInlineEdge;
      return {
        rangeStart: cell.rangeStart,
        rangeEnd: cell.rangeEnd,
        source: cell.source,
        display: cell.display,
        drawX: cell.drawX,
        naturalWidth: cell.naturalWidth,
        shapingBoundary: cell.shapingBoundary === true,
        openTypeFeatures: cell.openTypeFeatures,
        renderFontFamilies: renderFontFamiliesFor(cell.rangeStart, cell.rangeEnd),
        trailingGap,
        spacing: preparedSpacing(cell.display, cell.naturalWidth, trailingGap),
        semanticPath: semanticSpansFor(cell.rangeStart, cell.rangeEnd),
      };
    });
    for (const cell of cells) cell.semanticSignature = JSON.stringify(cell.semanticPath);
    const runs = [];
    for (const cell of cells) {
      const pending = runs.at(-1);
      if (pending && canMergePreparedRun(pending, cell)) mergePreparedRun(pending, cell);
      else runs.push({ ...cell, spacing: { ...cell.spacing } });
    }
    const last = line.cells.at(-1);
    const flowEnd = last
      ? last.drawX + last.naturalWidth + (inlineEndByOffset.get(last.rangeEnd) ?? 0)
      : 0;
    const hyphenLeadingGap = line.hyphenAdvance > 0
      ? line.indent + line.visualWidth - flowEnd
      : 0;
    const inlineEdgeWidth = line.cells.reduce((sum, cell) =>
      sum + (inlineStartByOffset.get(cell.rangeStart) ?? 0) +
        (inlineEndByOffset.get(cell.rangeEnd) ?? 0), 0);
    const expectedFlowWidth = flowStart + inlineEdgeWidth + runs.reduce(
      (sum, run) => sum + run.naturalWidth + run.trailingGap,
      0,
    ) + hyphenLeadingGap + line.hyphenAdvance;
    const coreLineWidth = line.indent + line.visualWidth + line.hyphenAdvance;
    if (Math.abs(expectedFlowWidth - coreLineWidth) > RENDER_FLOW_EPSILON_PX) {
      throw new Error(`SnapshotRenderFlowMismatch:line=${lineIndex}`);
    }
    const markerStyles = [
      `--tq-line-height:${px(height)}!important`,
      `--tq-line-baseline-offset:${px(-(line.bottom - line.baseline))}!important`,
    ];
    if (Math.abs(flowStart) >= SPACING_EPSILON) {
      markerStyles.push(`--tq-line-flow-start:${px(flowStart)}!important`);
    }
    const markerAttributes = {
      "aria-hidden": "true",
      class: "tq-line",
      "data-tq-copy-ignore": "true",
      "data-tq-geometry": "true",
      "data-tq-line-empty": String(line.cells.length === 0),
      "data-tq-line-end": line.endReason,
      "data-tq-line-top": String(line.top),
      "data-tq-line-bottom": String(line.bottom),
      "data-tq-line-baseline": String(line.baseline),
      "data-tq-line-flow-width": String(expectedFlowWidth),
      "data-tq-line-index": String(lineIndex),
      "data-tq-line-range": `${line.rangeStart}-${line.rangeEnd}`,
      "data-tq-line-shift": Math.abs(flowStart) >= SPACING_EPSILON ? "true" : null,
      "data-tq-line-width": String(coreLineWidth),
      "data-tq-paragraph-height": String(paragraphHeight),
    };
    applyDynamicStyles(markerAttributes, markerStyles, styleClassFor);
    semanticContainerFor(activeSemantics).push(renderedElement("span", markerAttributes));

    for (const run of runs) {
      semanticContainerFor(run.semanticPath).push(renderRun(run, styleClassFor));
    }

    if (line.hyphenAdvance > 0) {
      const hyphenAttributes = {
        "aria-hidden": "true",
        "data-tq-advance": String(line.hyphenAdvance),
        "data-tq-copy-ignore": "true",
        "data-tq-engine-hyphen": "true",
        "data-tq-geometry": "true",
        "data-tq-x": String(line.indent + line.visualWidth),
        lang: locale,
      };
      applyDynamicStyles(
        hyphenAttributes,
        Math.abs(hyphenLeadingGap) >= SPACING_EPSILON
          ? [`margin-left:${px(hyphenLeadingGap)}!important`]
          : [],
        styleClassFor,
      );
      semanticContainerFor(activeSemantics).push(renderedElement("span", hyphenAttributes, "-"));
    }
    const boundaryContainer = semanticContainerFor(semanticSpansCrossing(line.rangeEnd));
    boundaryContainer.push(renderedElement("span", {
      "aria-hidden": "true",
      "data-tq-copy-ignore": "true",
      "data-tq-geometry": "true",
      "data-tq-line-end-sentinel": String(lineIndex),
    }));
    if (line.endReason === "MandatoryBreak") {
      boundaryContainer.push(renderedElement("span", {
        "data-tq-geometry": "true",
        "data-tq-hard-break": "true",
        "data-tq-src": "\n",
      }));
    }
    if (lineIndex < plan.lines.length - 1) {
      const breakAttributes = {
        "data-tq-engine-break": line.endReason,
      };
      if (line.endReason !== "MandatoryBreak") {
        // AccessibilitySoftWrapExclusion: only MandatoryBreak represents a
        // source newline. Other BRs replay visual geometry and stay out of AX
        // and source-faithful copy semantics.
        breakAttributes["aria-hidden"] = "true";
        breakAttributes["data-tq-copy-ignore"] = "true";
      }
      boundaryContainer.push(renderedElement("br", breakAttributes, null, true));
    }
  }
  semanticContainerFor([]);
  if (plan.lines.length > 0) {
    // ParagraphSelectionEndSentinel mirrors the runtime DOM renderer. The
    // zero-width character keeps Chromium's cross-block selection terminator
    // outside compressed closing-punctuation letter spacing, while remaining
    // absent from copy, accessibility, and layout width.
    nodes.push(renderedElement("span", {
      "aria-hidden": "true",
      "data-tq-copy-ignore": "true",
      "data-tq-selection-end": "true",
    }, "\u200B"));
  }
  return Object.freeze({
    html: nodes.map((node) => node.html).join(""),
    artifact: nodes.map((node) => node.artifact),
    markerCount: plan.lines.length,
  });
}

export function renderPreparedParagraph(planOrJson, typographyOrLocale = DEFAULT_LOCALE) {
  return renderPreparedParagraphArtifact(planOrJson, typographyOrLocale).html;
}

/**
 * Replays the canonical markup in a browser host. `innerHTML` deliberately uses
 * the browser HTML parser, matching the DOM produced when the same string is
 * delivered inside an SSR snapshot template.
 */
export function renderPreparedParagraphInto(
  host,
  planOrJson,
  typographyOrLocale = DEFAULT_LOCALE,
  options = {},
) {
  if (host == null || !("innerHTML" in Object(host)) || typeof host.querySelectorAll !== "function") {
    throw new Error("InvalidPreparedParagraphHost");
  }
  const root = host.closest?.(ROOT_SELECTOR) ?? host;
  const state = preparedStyleState(root);
  const usedStyles = new Set();
  let lowered;
  try {
    lowered = renderPreparedParagraphArtifact(planOrJson, typographyOrLocale, {
      ...options,
      styleClassFor: state
        ? (declaration) => {
          const index = registerPreparedValueStyle(state, declaration);
          usedStyles.add(index);
          return runtimeValueStyleClass(index);
        }
        : null,
    });
  } catch (error) {
    if (state?.owners.size === 0) removePreparedStyleState(state);
    throw error;
  }
  if (state) {
    state.owners.set(host, usedStyles);
    state.dirty = true;
    preparedStyleRootsByHost.set(host, root);
    syncPreparedValueStyles(state);
  }
  host.innerHTML = lowered.html;
  const markers = Array.from(host.querySelectorAll(LINE_MARKER_SELECTOR));
  if (markers.length !== lowered.markerCount) {
    throw new Error(
      `PreparedDomMarkerCountMismatch:expected=${lowered.markerCount};actual=${markers.length}`,
    );
  }
  return Object.freeze({ html: lowered.html, markers });
}

export function installPreparedDomRendererBridge(target = globalThis) {
  const bridge = Object.freeze({
    schema: SNAPSHOT_SCHEMA,
    layoutRevision: LAYOUT_REVISION,
    renderRevision: RENDER_REVISION,
    lower: renderPreparedParagraphArtifact,
    render: renderPreparedParagraphInto,
    release: releasePreparedParagraphStyles,
    releaseRoot: releasePreparedValueStyleRoot,
  });
  Object.defineProperty(target, PREPARED_DOM_BRIDGE_NAME, {
    configurable: true,
    enumerable: false,
    value: bridge,
    writable: false,
  });
  return bridge;
}

installPreparedDomRendererBridge();
