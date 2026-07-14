const BLOCK_ELEMENTS = new Set([
  "ADDRESS",
  "ARTICLE",
  "ASIDE",
  "BLOCKQUOTE",
  "DD",
  "DIV",
  "DL",
  "DT",
  "FIELDSET",
  "FIGCAPTION",
  "FIGURE",
  "FOOTER",
  "FORM",
  "H1",
  "H2",
  "H3",
  "H4",
  "H5",
  "H6",
  "HEADER",
  "HR",
  "LI",
  "MAIN",
  "NAV",
  "OL",
  "P",
  "PRE",
  "SECTION",
  "TABLE",
  "TR",
  "UL",
]);

const ENGINE_FLOW_STYLE_PROPERTIES = [
  "white-space-collapse",
  "overflow-wrap",
  "text-autospace",
  "text-spacing-trim",
  "text-wrap-mode",
  "-webkit-hyphens",
  "hyphens",
  "word-break",
];

function clipboardTextForChildren(parent) {
  const children = Array.from(parent.childNodes ?? []);
  const containsBlock = children.some(
    (child) => child.nodeType === 1 && BLOCK_ELEMENTS.has(child.tagName),
  );
  let result = "";
  let previous = null;
  for (const child of children) {
    if (containsBlock && child.nodeType === 3 && !child.data?.trim()) continue;
    const item = clipboardTextForNode(child);
    if (
      previous && (previous.block || item.block) && result && item.text &&
      !result.endsWith("\n") && !item.text.startsWith("\n")
    ) result += "\n";
    result += item.text;
    previous = item;
  }
  return result;
}

function clipboardTextForNode(node) {
  if (node.nodeType === 3) return { block: false, text: node.data ?? "" };
  if (node.nodeType !== 1) return { block: false, text: "" };
  if (node.tagName === "BR") return { block: false, text: "\n" };
  return {
    block: BLOCK_ELEMENTS.has(node.tagName),
    text: clipboardTextForChildren(node),
  };
}

function stripEngineStyles(element, rendered, sourceSemantic) {
  if (!element.style || (!rendered && !sourceSemantic)) return;
  for (const property of ENGINE_FLOW_STYLE_PROPERTIES) element.style.removeProperty(property);
  if (rendered) element.style.removeProperty("position");
  if (!element.getAttribute("style")?.trim()) element.removeAttribute("style");
}

/**
 * `SourceFaithfulSemanticClipboard`: remove Tiqian's paint-only DOM, restore
 * source substitutions and hard breaks, then serialize block-aware plain text
 * plus host-owned semantic HTML. Visual soft wraps never enter either payload.
 */
export function createTiqianClipboardPayload(fragment, documentObject = globalThis.document) {
  if (!fragment?.querySelectorAll || !documentObject?.createElement) {
    return { text: "", html: "" };
  }

  fragment.querySelectorAll("[data-tq-copy-ignore]").forEach((element) => element.remove());
  fragment.querySelectorAll("[data-tq-src]").forEach((element) => {
    if (element.hasAttribute("data-tq-hard-break")) {
      // PartialRangeMandatoryBreak: Range.cloneContents() may contain only the
      // hidden source marker, only the semantic BR, or both. Prefer the BR when
      // both survived; otherwise materialize the missing half as one BR.
      const semanticBreak = element.nextElementSibling;
      if (semanticBreak?.matches?.("br[data-tq-engine-break='MandatoryBreak']")) {
        element.remove();
      } else {
        element.replaceWith(documentObject.createElement("br"));
      }
    } else {
      element.replaceWith(documentObject.createTextNode(element.getAttribute("data-tq-src") ?? ""));
    }
  });
  fragment.querySelectorAll(
    "[data-tq-engine-break]:not([data-tq-engine-break='MandatoryBreak'])",
  ).forEach((element) => element.remove());

  Array.from(fragment.querySelectorAll("[data-tq-geometry]"))
    .reverse()
    .forEach((element) => element.replaceWith(...Array.from(element.childNodes)));

  fragment.querySelectorAll("*").forEach((element) => {
    const rendered = element.hasAttribute("data-tq-rendered");
    const sourceSemantic = element.hasAttribute("data-tq-source-semantic");
    const cjkStrong = element.hasAttribute("data-tq-cjk-emphasis");
    stripEngineStyles(element, rendered, sourceSemantic);
    if (cjkStrong) {
      element.style?.removeProperty("font-weight");
      if (!element.getAttribute("style")?.trim()) element.removeAttribute("style");
    }
    Array.from(element.attributes).forEach((attribute) => {
      if (attribute.name.startsWith("data-tq-")) element.removeAttribute(attribute.name);
    });
  });

  const wrapper = documentObject.createElement("div");
  wrapper.appendChild(fragment);
  return {
    text: clipboardTextForChildren(wrapper),
    html: wrapper.innerHTML,
  };
}

export function installTiqianCopyHandler(documentObject = globalThis.document) {
  if (!documentObject || globalThis.__tiqianCopyHandlerInstalled) return;
  globalThis.__tiqianCopyHandlerInstalled = true;
  documentObject.addEventListener("copy", (event) => {
    const selection = globalThis.window?.getSelection?.();
    if (!selection || selection.isCollapsed || selection.rangeCount === 0) return;
    const range = selection.getRangeAt(0);
    const renderedAncestor = (node) => {
      const element = node?.nodeType === 1 ? node : node?.parentElement;
      return element?.closest?.("[data-tq-rendered]") ?? null;
    };
    let touchesRendered = Boolean(
      renderedAncestor(range.startContainer) || renderedAncestor(range.endContainer),
    );
    if (!touchesRendered) {
      const common = range.commonAncestorContainer;
      const commonElement = common?.nodeType === 1 ? common : common?.parentElement;
      const candidates = commonElement?.querySelectorAll
        ? Array.from(commonElement.querySelectorAll("[data-tq-rendered]"))
        : [];
      if (commonElement?.matches?.("[data-tq-rendered]")) candidates.unshift(commonElement);
      touchesRendered = candidates.some((candidate) => {
        try {
          return range.intersectsNode(candidate);
        } catch {
          return false;
        }
      });
    }
    if (!touchesRendered) return;
    const payload = createTiqianClipboardPayload(range.cloneContents(), documentObject);
    if ((payload.text || payload.html) && event.clipboardData) {
      event.clipboardData.setData("text/plain", payload.text);
      if (payload.html) event.clipboardData.setData("text/html", payload.html);
      event.preventDefault();
    }
  });
}

globalThis.__TiqianCreateClipboardPayload = createTiqianClipboardPayload;
globalThis.__TiqianInstallCopyHandler = installTiqianCopyHandler;
