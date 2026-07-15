import { stableStringify } from "./snapshot-schema.js";

const SAFE_SEMANTIC_TAGS = new Set([
  "a", "abbr", "b", "bdi", "bdo", "cite", "code", "data", "del", "dfn", "em",
  "i", "ins", "kbd", "mark", "q", "s", "samp", "small", "span", "strong", "sub",
  "sup", "time", "u", "var",
]);
const INTERNAL_ATTRIBUTE_PREFIX = "data-tq-";
const ATTRIBUTE_NAME = /^[A-Za-z_:][A-Za-z0-9_.:-]*$/u;
const COLLAPSIBLE_WHITESPACE = /[ \t\n\r\f]/u;

function normalizedAttributes(value) {
  const entries = Array.isArray(value)
    ? value
    : value && typeof value === "object"
      ? Object.entries(value)
      : [];
  const attributes = [];
  for (const item of entries) {
    if (!Array.isArray(item) || item.length !== 2) throw new Error("InvalidSnapshotSemanticAttributes");
    const name = String(item[0]).trim().toLowerCase();
    const attributeValue = String(item[1]);
    if (!ATTRIBUTE_NAME.test(name) || name.startsWith("on") ||
        name.startsWith(INTERNAL_ATTRIBUTE_PREFIX) || name === "style") {
      throw new Error(`UnsupportedSnapshotSemanticAttribute:${name}`);
    }
    if (name === "href" && /^\s*javascript:/iu.test(attributeValue)) {
      throw new Error("UnsafeSnapshotSemanticHref");
    }
    attributes.push([name, attributeValue]);
  }
  attributes.sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0);
  if (new Set(attributes.map(([name]) => name)).size !== attributes.length) {
    throw new Error("DuplicateSnapshotSemanticAttribute");
  }
  return attributes;
}

function assertUtf16Boundary(text, offset) {
  if (!Number.isSafeInteger(offset) || offset < 0 || offset > text.length) {
    throw new Error("InvalidSnapshotSemanticRange");
  }
  if (offset > 0 && offset < text.length &&
      /[\uD800-\uDBFF]/u.test(text[offset - 1]) && /[\uDC00-\uDFFF]/u.test(text[offset])) {
    throw new Error("SnapshotSemanticRangeSplitsSurrogatePair");
  }
}

/** Canonical controlled inline semantics shared by precompute and adoption. */
export function normalizeSnapshotSemantics(textValue, value = []) {
  const text = String(textValue);
  if (!Array.isArray(value)) throw new Error("InvalidSnapshotSemantics");
  const semantics = value.map((span, order) => {
    const start = Number(span?.start);
    const end = Number(span?.end);
    assertUtf16Boundary(text, start);
    assertUtf16Boundary(text, end);
    if (end <= start) throw new Error("InvalidSnapshotSemanticRange");
    const tagName = String(span?.tagName ?? "").trim().toLowerCase();
    if (!SAFE_SEMANTIC_TAGS.has(tagName)) {
      throw new Error(`UnsupportedSnapshotSemanticTag:${tagName}`);
    }
    return Object.freeze({
      start,
      end,
      tagName,
      attributes: Object.freeze(normalizedAttributes(span?.attributes)),
      order: Number.isSafeInteger(span?.order) ? Number(span.order) : order,
    });
  }).sort((left, right) =>
    left.start - right.start || right.end - left.end || left.order - right.order);

  const stack = [];
  for (const span of semantics) {
    while (stack.length > 0 && span.start >= stack.at(-1).end) stack.pop();
    const parent = stack.at(-1);
    if (parent && span.end > parent.end) throw new Error("CrossingSnapshotSemanticRanges");
    stack.push(span);
  }
  return Object.freeze(semantics.map(({ order: _order, ...span }) => Object.freeze(span)));
}

export function snapshotSourceArtifact(textValue, semanticsValue = []) {
  const text = String(textValue);
  const semantics = normalizeSnapshotSemantics(text, semanticsValue);
  return Object.freeze({ text, semantics });
}

export function snapshotSourceArtifactString(textValue, semanticsValue = []) {
  return stableStringify(snapshotSourceArtifact(textValue, semanticsValue));
}

function exactRangeContract(spans, semantic, predicate) {
  return Array.isArray(spans) && spans.some((span) =>
    Number(span?.start) === semantic.start && Number(span?.end) === semantic.end && predicate(span));
}

/** Inline code is snapshot-safe only when the host publishes its full metric contract. */
export function snapshotSemanticMetricContractIssue(
  semanticsValue,
  textSpansValue,
  inlineBoxesValue,
) {
  const codeSpans = Array.from(semanticsValue ?? []).filter((span) => span.tagName === "code");
  for (const semantic of codeSpans) {
    const hasTextStyle = exactRangeContract(textSpansValue, semantic, (span) =>
      Array.isArray(span.fontFamilies) && span.fontFamilies.length > 0 &&
      Number.isFinite(Number(span.fontSizePx)) &&
      Number.isSafeInteger(Number(span.fontWeight)) &&
      typeof span.italic === "boolean" &&
      Number.isFinite(Number(span.baselineShiftPx)));
    if (!hasTextStyle) return "InlineCodeFontContractUnavailable";
    const hasInlineBox = exactRangeContract(inlineBoxesValue, semantic, (box) =>
      Number.isFinite(Number(box.inlineStartPx)) && Number.isFinite(Number(box.inlineEndPx)));
    if (!hasInlineBox) return "InlineCodeBoxContractUnavailable";
  }
  return null;
}

function projectedNormalFlow(rawText, rawSemantics) {
  const text = String(rawText);
  const projected = [];
  const boundaryMap = new Array(text.length + 1).fill(0);
  let pendingStart = -1;
  let pendingEnd = -1;

  const resolvePending = (emit) => {
    if (pendingStart < 0) return;
    const before = projected.length;
    if (emit && projected.length > 0 && projected.at(-1) !== "\n") projected.push(" ");
    const after = projected.length;
    boundaryMap[pendingStart] = before;
    for (let boundary = pendingStart + 1; boundary <= pendingEnd; boundary += 1) {
      boundaryMap[boundary] = after;
    }
    pendingStart = -1;
    pendingEnd = -1;
  };

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (character === "\n" && rawSemantics.hardBreakOffsets.has(index)) {
      resolvePending(false);
      boundaryMap[index] = projected.length;
      projected.push("\n");
      boundaryMap[index + 1] = projected.length;
    } else if (COLLAPSIBLE_WHITESPACE.test(character)) {
      if (pendingStart < 0) {
        pendingStart = index;
        boundaryMap[index] = projected.length;
      }
      pendingEnd = index + 1;
    } else {
      resolvePending(true);
      boundaryMap[index] = projected.length;
      projected.push(character);
      boundaryMap[index + 1] = projected.length;
    }
  }
  resolvePending(false);
  boundaryMap[text.length] = projected.length;
  return snapshotSourceArtifact(
    projected.join(""),
    rawSemantics.spans.map((span) => ({
      ...span,
      start: boundaryMap[span.start],
      end: boundaryMap[span.end],
    })).filter((span) => span.end > span.start),
  );
}

/**
 * Canonicalizes a native, normal-flow paragraph before inert snapshot adoption.
 * Geometry generated by Tiqian is intentionally not accepted by this path.
 */
export function snapshotSourceArtifactFromDom(paragraph) {
  const rawText = [];
  const spans = [];
  const hardBreakOffsets = new Set();
  let order = 0;
  let rawLength = 0;

  const appendNode = (node) => {
    if (node.nodeType === 3) {
      const value = String(node.textContent ?? "");
      rawText.push(value);
      rawLength += value.length;
      return;
    }
    if (node.nodeType !== 1) return;
    const tagName = String(node.tagName ?? "").toLowerCase();
    if (tagName === "br") {
      hardBreakOffsets.add(rawLength);
      rawText.push("\n");
      rawLength += 1;
      return;
    }
    if (!SAFE_SEMANTIC_TAGS.has(tagName)) throw new Error(`UnsupportedSnapshotSemanticTag:${tagName}`);
    const start = rawLength;
    const sourceOrder = order++;
    for (const child of Array.from(node.childNodes ?? [])) appendNode(child);
    const end = rawLength;
    if (end <= start) return;
    spans.push({
      start,
      end,
      tagName,
      attributes: Array.from(node.attributes ?? [], (attribute) => (
        Array.isArray(attribute)
          ? [String(attribute[0]), String(attribute[1])]
          : [String(attribute.name), String(attribute.value)]
      )),
      order: sourceOrder,
    });
  };

  for (const child of Array.from(paragraph.childNodes ?? [])) appendNode(child);
  return projectedNormalFlow(rawText.join(""), { spans, hardBreakOffsets });
}
