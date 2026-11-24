import assert from "node:assert/strict";
import test from "node:test";

import {
  installPreparedValueStyles,
  releasePreparedParagraphStyles,
  releasePreparedValueStyleRoot,
  renderPreparedParagraphArtifact,
  renderPreparedParagraphInto,
} from "@tiqian/core/src/sampler/snapshot/prepared-dom.js";
import { createEnhanceContext } from "@tiqian/core/src/engine/context/enhance-context.js";
import { probe } from "./runtime-host.js";

type TestPlan = Exclude<Parameters<typeof renderPreparedParagraphArtifact>[0], string>;
type Host = Parameters<typeof renderPreparedParagraphInto>[0];

interface QueryMatch {
  index: number;
}

function fixturePlan(): TestPlan {
  return {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    lines: [{
      rangeStart: 0,
      rangeEnd: 2,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: 36,
      hyphenAdvance: 0,
      endReason: "ParagraphEnd",
      cells: [{
        rangeStart: 0,
        rangeEnd: 1,
        source: "中",
        display: "中",
        drawX: 0,
        naturalWidth: 18,
        leadingLayoutAdvance: 0,
      }, {
        rangeStart: 1,
        rangeEnd: 2,
        source: "文",
        display: "文",
        drawX: 18,
        naturalWidth: 18,
        leadingLayoutAdvance: 0,
      }],
    }],
  };
}

function twoLineFixture(firstEndReason: string) {
  return {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 54,
    lines: [
      {
        rangeStart: 0,
        rangeEnd: 1,
        top: 0,
        bottom: 27,
        baseline: 20,
        indent: 0,
        visualWidth: 18,
        hyphenAdvance: 0,
        endReason: firstEndReason,
        cells: [{
          rangeStart: 0,
          rangeEnd: 1,
          source: "中",
          display: "中",
          drawX: 0,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
        }],
      },
      {
        rangeStart: firstEndReason === "MandatoryBreak" ? 2 : 1,
        rangeEnd: firstEndReason === "MandatoryBreak" ? 3 : 2,
        top: 27,
        bottom: 54,
        baseline: 47,
        indent: 0,
        visualWidth: 18,
        hyphenAdvance: 0,
        endReason: "ParagraphEnd",
        cells: [{
          rangeStart: firstEndReason === "MandatoryBreak" ? 2 : 1,
          rangeEnd: firstEndReason === "MandatoryBreak" ? 3 : 2,
          source: "文",
          display: "文",
          drawX: 0,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
        }],
      },
    ],
  };
}

function articleFixture(lineCount = 25, cellsPerLine = 40) {
  return {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: lineCount * 27,
    lines: Array.from({ length: lineCount }, (_, lineIndex) => {
      const rangeStart = lineIndex * cellsPerLine;
      return {
        rangeStart,
        rangeEnd: rangeStart + cellsPerLine,
        top: lineIndex * 27,
        bottom: (lineIndex + 1) * 27,
        baseline: lineIndex * 27 + 20,
        indent: 0,
        visualWidth: cellsPerLine * 18,
        hyphenAdvance: 0,
        endReason: lineIndex === lineCount - 1 ? "ParagraphEnd" : "AutoWrap",
        cells: Array.from({ length: cellsPerLine }, (_, cellIndex) => ({
          rangeStart: rangeStart + cellIndex,
          rangeEnd: rangeStart + cellIndex + 1,
          source: "中",
          display: "中",
          drawX: cellIndex * 18,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
        })),
      };
    }),
  };
}

function fakeHost() {
  return {
    innerHTML: "",
    querySelectorAll(selector: string): QueryMatch[] {
      if (selector !== "[data-tq-line-flow-width]") return [];
      return Array.from(
        { length: this.innerHTML.match(/data-tq-line-flow-width=/gu)?.length ?? 0 },
        (_, index) => ({ index }),
      );
    },
  };
}

function inlineObjectPlan({ trailingMargin = false } = {}) {
  return {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    lines: [{
      rangeStart: 0,
      rangeEnd: 2,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: trailingMargin ? 38 : 36,
      hyphenAdvance: 0,
      endReason: "ParagraphEnd",
      cells: [
        {
          rangeStart: 0,
          rangeEnd: 1,
          source: "\uFFFC",
          display: "\uFFFC",
          drawX: 0,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
          inlineObject: 18,
        },
        {
          rangeStart: 1,
          rangeEnd: 2,
          source: "字",
          display: "字",
          drawX: trailingMargin ? 20 : 18,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
        },
      ],
    }],
  };
}

type StyleSetPropertyFn = (name: string, value: string, priority: string) => void;
type SetAttributeFn = (name: string, value: string) => void;
type CloneNodeFn = (deep: boolean) => FakeInlineElement;
interface FakeInlineStyleWrapper {
  setProperty: StyleSetPropertyFn;
}

interface FakeInlineElement {
  tagName: string;
  attributes: Map<string, string>;
  cloneCalls: boolean[];
  styleProperties: [string, string, string][];
  style: FakeInlineStyleWrapper;
  setAttribute: SetAttributeFn;
  cloneNode: CloneNodeFn;
}

function fakeInlineElement(tagName: string): FakeInlineElement {
  const element: FakeInlineElement = {
    tagName,
    attributes: new Map(),
    cloneCalls: [],
    styleProperties: [],
    style: {
      setProperty(name: string, value: string, priority: string) {
        element.styleProperties.push([name, value, priority]);
      },
    },
    setAttribute(name: string, value: string) {
      element.attributes.set(name, String(value));
    },
    cloneNode(deep: boolean) {
      element.cloneCalls.push(deep);
      const copy = fakeInlineElement(tagName);
      copy.attributes = new Map(element.attributes);
      return copy;
    },
  };
  return element;
}

interface InlinePlaceholder {
  openingTag: string;
  getAttribute(name: string): string | null;
  replaceWith(clone: FakeInlineElement): void;
}

interface SwapHost {
  innerHTML: string;
  swapped: FakeInlineElement[];
  querySelectorAll(selector: string): Array<QueryMatch | InlinePlaceholder>;
}

function swapHost(): SwapHost {
  const host: SwapHost = {
    innerHTML: "",
    swapped: [],
    querySelectorAll(selector: string) {
      if (selector === "[data-tq-line-flow-width]") {
        return Array.from(
          { length: this.innerHTML.match(/data-tq-line-flow-width=/gu)?.length ?? 0 },
          (_, index) => ({ index }),
        );
      }
      if (selector !== '[data-tq-inline-object="pending"]') return [];
      const placeholders: InlinePlaceholder[] = [];
      const pattern = /<span\b[^>]*\bdata-tq-inline-object="pending"[^>]*><\/span>/gu;
      for (const match of this.innerHTML.matchAll(pattern)) {
        const openingTag = match[0];
        placeholders.push({
          openingTag,
          getAttribute(name: string) {
            const found = openingTag.match(new RegExp(`${name}="([^"]*)"`, "u"));
            return found ? found[1] : null;
          },
          replaceWith(clone: FakeInlineElement) {
            const serialized = `<${clone.tagName}` +
              Array.from(clone.attributes).sort(([left], [right]) => left.localeCompare(right))
                .map(([name, value]) => ` ${name}="${value}"`).join("") + ">";
            host.innerHTML = host.innerHTML.replace(openingTag, serialized);
            host.swapped.push(clone);
          },
        });
      }
      return placeholders;
    },
  };
  return host;
}

interface LiveSemanticClone {
  styleProperties?: [string, string, string][];
  attributes: Map<string, string>;
  tagName: string;
}

interface LiveSemanticPlaceholder {
  getAttribute(name: string): string | null;
  firstChild: null;
  replaceWith(clone: LiveSemanticClone): void;
}

interface LiveSemanticHost {
  innerHTML: string;
  querySelectorAll(selector: string): Array<QueryMatch | LiveSemanticPlaceholder>;
}

function liveSemanticHost(): LiveSemanticHost {
  const host: LiveSemanticHost = {
    innerHTML: "",
    querySelectorAll(selector: string) {
      if (selector === "[data-tq-line-flow-width]") {
        return Array.from(
          { length: this.innerHTML.match(/data-tq-line-flow-width=/gu)?.length ?? 0 },
          (_, index) => ({ index }),
        );
      }
      if (selector === "[data-tq-live-semantic-index]") {
        const placeholders: LiveSemanticPlaceholder[] = [];
        const pattern = /<span\b[^>]*\bdata-tq-live-semantic-index="(\d+)"[^>]*>([\s\S]*?)<\/span>/gu;
        for (const match of this.innerHTML.matchAll(pattern)) {
          const fullMatch = match[0];
          const sourceIndex = match[1];
          const innerContent = match[2];
          placeholders.push({
            getAttribute(name: string) {
              if (name === "data-tq-live-semantic-index") return sourceIndex;
              return null;
            },
            firstChild: null,
            replaceWith(clone: LiveSemanticClone) {
              const styleAttr = clone.styleProperties?.length
                ? ` style="${clone.styleProperties.map(([k, v, p]) => `${k}:${v}${p ? "!" + p : ""}`).join(";")}"`
                : "";
              const attrs = Array.from(clone.attributes.entries())
                .sort(([a], [b]) => a.localeCompare(b))
                .map(([k, v]) => ` ${k}="${v}"`)
                .join("");
              const serialized = `<${clone.tagName.toLowerCase()}${attrs}${styleAttr}>${innerContent}</${clone.tagName.toLowerCase()}>`;
              host.innerHTML = host.innerHTML.replace(fullMatch, serialized);
            },
          });
        }
        return placeholders;
      }
      return [];
    },
  };
  return host;
}

interface MockNode {
  textContent: string;
  parentNode: MockNode | null;
}

type NodeAppendFn = (node: MockNode) => MockNode;
type NodeRemoveFn = (node: MockNode) => MockNode;

interface MockHead extends MockNode {
  childNodes: MockNode[];
  appendChild: NodeAppendFn;
  removeChild: NodeRemoveFn;
}

interface MockStyleElement extends MockNode {
  attributes: Map<string, string>;
  setAttribute(name: string, value: string): void;
}

interface MockDocument {
  head: MockHead;
  createElement(tagName: string): MockStyleElement;
}

interface MockRoot {
  ownerDocument: MockDocument;
  getAttribute(name: string): string | null;
  setAttribute(name: string, value: string): void;
  removeAttribute(name: string): void;
}

function styleBackedHost() {
  const head: MockHead = {
    textContent: "",
    parentNode: null,
    childNodes: [],
    appendChild(node: MockNode) {
      this.childNodes.push(node);
      node.parentNode = this;
      return node;
    },
    removeChild(node: MockNode) {
      this.childNodes.splice(this.childNodes.indexOf(node), 1);
      node.parentNode = null;
      return node;
    },
  };
  const documentObject: MockDocument = {
    head,
    createElement(tagName: string) {
      assert.equal(tagName, "style");
      return {
        attributes: new Map(),
        parentNode: null as MockNode | null,
        textContent: "",
        setAttribute(name: string, value: string) {
          this.attributes.set(name, String(value));
        },
      };
    },
  };
  const attributes = new Map<string, string>();
  const root: MockRoot = {
    ownerDocument: documentObject,
    getAttribute: (name: string) => attributes.get(name) ?? null,
    setAttribute: (name: string, value: string) => attributes.set(name, String(value)),
    removeAttribute: (name: string) => attributes.delete(name),
  };
  const host = {
    ...fakeHost(),
    ownerDocument: documentObject,
    closest: () => root,
  };
  return { host, root, head, attributes, documentObject };
}

test("shared prepared DOM lowering keeps plain text native and the wire deterministic", () => {
  const plan = fixturePlan();
  const fromObject = renderPreparedParagraphArtifact(plan, { locale: "zh-Hans" });
  const fromJson = renderPreparedParagraphArtifact(JSON.stringify(plan), "zh-Hans");

  assert.deepEqual(fromJson, fromObject);
  assert.equal(fromObject.markerCount, 1);
  assert.equal(fromObject.html.match(/data-tq-shaping-boundary/gu)?.length ?? 0, 0);
  assert.match(fromObject.html, /data-tq-line-flow-width="36"/u);
  assert.equal(fromObject.artifact.filter(([tag]) => tag === "span").length, 3);
  assert.equal(fromObject.artifact.filter(([tag]) => tag === "#").length, 1);
  assert.match(fromObject.html, /<\/span>中文<span/u);
});

test("prepared semantic links remain one native element across engine soft wraps", () => {
  const rendered = renderPreparedParagraphArtifact(
    twoLineFixture("AutoWrap"),
    { locale: "zh-Hans" },
    {
      sourceText: "中文",
      semantics: [{
        start: 0,
        end: 2,
        sourceIndex: 0,
        tagName: "a",
        attributes: [["href", "/article"], ["class", "host-link"]],
      }],
    },
  );

  assert.equal(rendered.html.match(/<a\b/gu)?.length, 1);
  assert.match(rendered.html, /<a class="host-link" data-tq-source-semantic="true" href="\/article">/u);
  assert.match(rendered.html, /<br[^>]*data-tq-engine-break="AutoWrap"[^>]*><span[^>]*data-tq-line-index="1"/u);
  assert.equal(rendered.artifact.filter(([tag]) => tag === "a").length, 1);
  assert.equal(rendered.artifact[1][0], "a");
});

test("prepared semantic inline boxes reserve host padding in the same flow", () => {
  const plan = fixturePlan();
  plan.lines[0].visualWidth = 48.4;
  plan.lines[0].cells[0].drawX = 6.2;
  plan.lines[0].cells[0].leadingLayoutAdvance = 6.2;
  plan.lines[0].cells[1].drawX = 24.2;
  const rendered = renderPreparedParagraphArtifact(plan, { locale: "zh-Hans" }, {
    sourceText: "中文",
    semantics: [{ start: 0, end: 2, sourceIndex: 0, tagName: "code", attributes: [] }],
    inlineBoxes: [{ start: 0, end: 2, inlineStartPx: 6.2, inlineEndPx: 6.2 }],
  });

  assert.match(rendered.html, /data-tq-line-flow-width="48\.4"/u);
  assert.match(rendered.html, /<code data-tq-source-semantic="true">/u);
});

test("browser replay installs the same canonical HTML and returns its line markers", () => {
  const planJson = JSON.stringify(fixturePlan());
  const expected = renderPreparedParagraphArtifact(planJson, "zh-Hans");
  const host = fakeHost();
  const rendered = renderPreparedParagraphInto(probe<Host>(host), planJson, "zh-Hans", {}, createEnhanceContext(probe<Element>(host)));

  assert.equal(host.innerHTML, expected.html);
  assert.equal(rendered.html, expected.html);
  assert.equal(rendered.markers.length, expected.markerCount);
});

test("browser replay preserves controlled inline semantics supplied by a Worker plan", () => {
  const host = fakeHost();
  renderPreparedParagraphInto(probe<Host>(host), fixturePlan(), "zh-Hans", {
    sourceText: "中文",
    semantics: [{ start: 0, end: 2, sourceIndex: 0, tagName: "strong", attributes: [] }],
  }, createEnhanceContext(probe<Element>(host)));

  assert.match(host.innerHTML, /<strong data-tq-source-semantic="true">中文<\/strong>/u);
});

test("live Worker replay lowers semantic placeholders without serializing host behavior", () => {
  const sourceElement = {
    tagName: "SPOILER",
    cloneNode() {},
  };
  const rendered = renderPreparedParagraphArtifact(fixturePlan(), "zh-Hans", {
    sourceText: "中文",
    semanticReplay: "live-source",
    semantics: [{
      start: 0,
      end: 2,
      tagName: "spoiler",
      sourceIndex: 0,
      attributes: [],
    }],
    liveSemanticElements: probe<Element[]>([sourceElement]),
  });

  assert.equal(rendered.liveSemanticCount, 1);
  assert.match(rendered.html, /data-tq-live-semantic-index="0"/u);
  assert.doesNotMatch(rendered.html, /<spoiler|onclick=|padding:4px/u);
});

test("live Worker replay nests equal-range placeholders in source hierarchy order", () => {
  const rendered = renderPreparedParagraphArtifact(fixturePlan(), "zh-Hans", {
    sourceText: "中文",
    semanticReplay: "live-source",
    semantics: [{
      start: 0,
      end: 2,
      tagName: "em",
      sourceIndex: 0,
      order: 1,
      attributes: [],
    }, {
      start: 0,
      end: 2,
      tagName: "spoiler",
      sourceIndex: 1,
      order: 0,
      attributes: [],
    }],
    liveSemanticElements: probe<Element[]>([{ tagName: "EM", cloneNode() {} }, {
      tagName: "SPOILER",
      cloneNode() {},
    }]),
  });

  assert.match(
    rendered.html,
    /data-tq-live-semantic-index="1"[^>]*><span data-tq-live-semantic-index="0"/u,
  );
});

test("browser replay moves dynamic prepared values into one root-scoped stylesheet", () => {
  const { host, head, attributes } = styleBackedHost();
  const context = createEnhanceContext(probe<Element>(host));
  const rendered = renderPreparedParagraphInto(probe<Host>(host), fixturePlan(), "zh-Hans", {}, context);

  assert.doesNotMatch(rendered.html, / style=/u);
  const runtimeClass = rendered.html.match(/class="tq-line (tqvr-[0-9a-z]+)"/u)?.[1];
  assert.ok(runtimeClass, "the line marker must carry a runtime value class");
  assert.equal(head.childNodes.length, 1);
  assert.match(head.childNodes[0].textContent, /--tq-line-height:27px!important/u);
  assert.match(
    head.childNodes[0].textContent,
    new RegExp(`\\[data-tq-value-style-scope\\] \\[data-tq-rendered="true"\\] \\.${runtimeClass}\\{--tq-line-height:27px!important`, "u"),
  );
  assert.ok(attributes.has("data-tq-value-style-scope"));

  const second = styleBackedHost();
  const secondRendered = renderPreparedParagraphInto(probe<Host>(second.host), fixturePlan(), "zh-Hans", {}, createEnhanceContext(probe<Element>(second.host)));
  const secondClass = secondRendered.html.match(/class="tq-line (tqvr-[0-9a-z]+)"/u)?.[1];
  assert.equal(secondClass, runtimeClass);

  assert.equal(releasePreparedParagraphStyles(probe<Element>(host), context), true);
  assert.equal(head.childNodes.length, 0);
  assert.equal(attributes.has("data-tq-value-style-scope"), false);
});

test("runtime value classes cannot inherit unrelated snapshot declarations", () => {
  const { host, root, head } = styleBackedHost();
  const context = createEnhanceContext(probe<Element>(root));
  assert.equal(
    installPreparedValueStyles(
      probe<Element>(root),
      context,
      ["letter-spacing:-1.79285px!important"],
      ["Tiqian Fixture Sans"],
    ),
    true,
  );

  const rendered = renderPreparedParagraphInto(probe<Host>(host), fixturePlan(), "zh-Hans", {}, context);
  const runtimeClass = rendered.html.match(/class="tq-line (tqvr-[0-9a-z]+)"/u)?.[1];
  assert.ok(runtimeClass, "the line marker must carry a runtime value class");
  assert.doesNotMatch(rendered.html, /class="[^"]*tqv-[0-9a-z]/u);
  assert.match(
    head.childNodes[0].textContent,
    /\.tqv-0\{letter-spacing:-1\.79285px!important\}/u,
  );
  assert.match(
    head.childNodes[0].textContent,
    new RegExp(`\\.${runtimeClass}\\{--tq-line-height:27px!important`, "u"),
  );
  assert.notEqual(runtimeClass, "tqv-0");
});

test("snapshot host families never become root projection variables", () => {
  const { root, head, attributes } = styleBackedHost();
  const context = createEnhanceContext(probe<Element>(root));

  assert.equal(installPreparedValueStyles(probe<Element>(root), context, [], ["Snapshot Sans"]), false);
  assert.equal(head.childNodes.length, 0);
  assert.equal(releasePreparedValueStyleRoot(probe<Element>(root), context), false);
  assert.equal(head.childNodes.length, 0);
  assert.equal(attributes.has("data-tq-value-style-scope"), false);
});

test("prepared semantic font runs replay their explicit host-family projection", () => {
  const valueStyles: string[] = [];
  const rendered = renderPreparedParagraphArtifact(fixturePlan(), "zh-Hans", {
    sourceText: "中文",
    styleClassFor: (value: string) => {
      valueStyles.push(value);
      return `tqv-${valueStyles.length - 1}`;
    },
    renderTextSpans: [{
      start: 0,
      end: 2,
      fontFamilies: ["Tiqian Exact Mono"],
    }],
  });

  assert.match(rendered.html, /class="tqv-[^"]+"[^>]*>中文<\/span>/u);
  assert.match(rendered.html, /data-tq-render-font-projection="true"/u);
  assert.ok(valueStyles.some((value) =>
    value.includes('font-family:"Tiqian Exact Mono"!important')));
});

test("prepared positive spacing participates in native selection instead of using margin", () => {
  const plan = fixturePlan();
  plan.lines[0].cells[1].drawX = 20;
  plan.lines[0].visualWidth = 38;

  const lowered = renderPreparedParagraphArtifact(plan, "zh-Hans");

  assert.match(lowered.html, /inline-size:2px!important/u);
  assert.doesNotMatch(lowered.html, /margin-right:2px!important/u);
  assert.match(lowered.html, /data-tq-advance="20"/u);
  assert.match(lowered.html, /<\/span>文<span/u);
});

test("a single-cell overlap preserves its glyph width and carries negative flow in margin", () => {
  const plan = fixturePlan() as TestPlan & { sourceText?: string };
  plan.sourceText = " 中";
  plan.lines[0].rangeEnd = 2;
  plan.lines[0].visualWidth = 17;
  plan.lines[0].cells = [{
    rangeStart: 0,
    rangeEnd: 1,
    source: " ",
    display: " ",
    drawX: 0,
    naturalWidth: 4,
    leadingLayoutAdvance: 0,
  }, {
    rangeStart: 1,
    rangeEnd: 2,
    source: "中",
    display: "中",
    drawX: -1,
    naturalWidth: 18,
    leadingLayoutAdvance: 0,
  }];

  const lowered = renderPreparedParagraphArtifact(plan, "zh-Hans");

  assert.match(lowered.html, /margin-right:-5px!important/u);
  assert.match(lowered.html, /data-tq-advance="4"/u);
  assert.doesNotMatch(lowered.html, /letter-spacing:-5px!important/u);
});

test("a multi-character cluster preserves shaping and carries selectable trailing space", () => {
  const plan = fixturePlan();
  plan.lines[0].rangeEnd = 4;
  plan.lines[0].visualWidth = 51;
  plan.lines[0].cells = [{
    rangeStart: 0,
    rangeEnd: 3,
    source: "App",
    display: "App",
    drawX: 0,
    naturalWidth: 30,
    leadingLayoutAdvance: 0,
  }, {
    rangeStart: 3,
    rangeEnd: 4,
    source: "中",
    display: "中",
    drawX: 33,
    naturalWidth: 18,
    leadingLayoutAdvance: 0,
  }];

  const lowered = renderPreparedParagraphArtifact(plan, "zh-Hans");
  assert.match(lowered.html, /word-spacing:3px!important/u);
  assert.match(lowered.html, /inline-size:3px!important/u);
  assert.match(lowered.html, /height:0!important/u);
  assert.match(lowered.html, /line-height:0!important/u);
  assert.match(lowered.html, /data-tq-advance="33"/u);
  assert.match(lowered.html, />App<span[^>]*data-tq-spacing-carrier="true"[^>]*> <\/span><\/span>/u);
  assert.doesNotMatch(lowered.html, /letter-spacing:1px!important/u);
});

test("independently shaped multi-character cells remain separate browser shaping runs", () => {
  const plan = fixturePlan();
  plan.lines[0].rangeEnd = 13;
  plan.lines[0].visualWidth = 103;
  plan.lines[0].cells = [{
    rangeStart: 0,
    rangeEnd: 8,
    source: "https://",
    display: "https://",
    drawX: 0,
    naturalWidth: 61,
    leadingLayoutAdvance: 0,
    shapingBoundary: true,
  }, {
    rangeStart: 8,
    rangeEnd: 13,
    source: "a.com",
    display: "a.com",
    drawX: 61,
    naturalWidth: 42,
    leadingLayoutAdvance: 0,
    shapingBoundary: true,
  }];

  const lowered = renderPreparedParagraphArtifact(plan, "zh-Hans");
  assert.equal(lowered.html.match(/data-tq-shaping-boundary/gu)?.length, 2);
  assert.match(lowered.html, /data-tq-advance="61"/u);
  assert.match(lowered.html, /data-tq-advance="42"/u);
  assert.doesNotMatch(lowered.html, />https:\/\/a\.com<\/span>/u);
});

test("visual soft wraps stay out of accessibility and copy semantics", () => {
  const lowered = renderPreparedParagraphArtifact(twoLineFixture("AutoWrap"), "zh-Hans");
  const lineBreak = lowered.artifact.find(([tag]) => tag === "br");

  assert.ok(lineBreak);
  assert.deepEqual(Object.fromEntries(lineBreak[1] as readonly [string, string][]), {
    "aria-hidden": "true",
    "data-tq-copy-ignore": "true",
    "data-tq-engine-break": "AutoWrap",
  });
  assert.doesNotMatch(lowered.html, /data-tq-hard-break/u);
});

test("mandatory breaks retain source newline semantics", () => {
  const lowered = renderPreparedParagraphArtifact(twoLineFixture("MandatoryBreak"), "zh-Hans");
  const lineBreak = lowered.artifact.find(([tag]) => tag === "br");

  assert.ok(lineBreak);
  assert.deepEqual(Object.fromEntries(lineBreak[1] as readonly [string, string][]), {
    "data-tq-engine-break": "MandatoryBreak",
  });
  assert.match(lowered.html, /data-tq-hard-break="true"/u);
  assert.match(lowered.html, /data-tq-src="\n"/u);
});

test("prepared DOM carries only the supported proportional quote feature signature", () => {
  const plan = fixturePlan();
  plan.lines[0].cells[0].source = "\u2019";
  plan.lines[0].cells[0].display = "\u2019";
  plan.lines[0].cells[0].openTypeFeatures = ["pwid", "palt"];

  const lowered = renderPreparedParagraphArtifact(plan, "zh-Hans");
  const featureRun = lowered.artifact.find(([, attributes]) =>
    Object.fromEntries(attributes as readonly [string, string][])["data-tq-open-type-features"] != null);

  assert.ok(featureRun);
  assert.equal(
    Object.fromEntries(featureRun![1] as readonly [string, string][])["data-tq-open-type-features"],
    "pwid,palt",
  );
  assert.match(lowered.html, /data-tq-open-type-features="pwid,palt"/u);

  plan.lines[0].cells[0].openTypeFeatures = ["fwid"];
  const fullWidth = renderPreparedParagraphArtifact(plan, "zh-Hans");
  assert.match(fullWidth.html, /data-tq-open-type-features="fwid"/u);

  plan.lines[0].cells[0].openTypeFeatures = ["pwid"];
  assert.throws(
    () => renderPreparedParagraphArtifact(plan, "zh-Hans"),
    /UnsupportedPreparedOpenTypeFeatures/u,
  );
});

test("canonical prepared nodes keep repeated reset declarations in shared CSS", () => {
  const lowered = renderPreparedParagraphArtifact(twoLineFixture("MandatoryBreak"), "zh-Hans");
  const marker = lowered.artifact.find(([, attributes]) =>
    Array.isArray(attributes) && Object.fromEntries(attributes as readonly [string, string][])["data-tq-line-flow-width"] != null);
  const sentinel = lowered.artifact.find(([, attributes]) =>
    Array.isArray(attributes) && Object.fromEntries(attributes as readonly [string, string][])["data-tq-line-end-sentinel"] != null);
  const selectionEnd = lowered.artifact.find(([, attributes]) =>
    Array.isArray(attributes) && Object.fromEntries(attributes as readonly [string, string][])["data-tq-selection-end"] != null);
  const hardBreak = lowered.artifact.find(([, attributes]) =>
    Array.isArray(attributes) && Object.fromEntries(attributes as readonly [string, string][])["data-tq-hard-break"] != null);
  const lineBreak = lowered.artifact.find(([tag]) => tag === "br");

  assert.equal(
    Object.fromEntries(marker![1] as readonly [string, string][]).style,
    "--tq-line-height:27px!important;--tq-line-baseline-offset:-7px!important",
  );
  assert.equal(Object.hasOwn(Object.fromEntries(sentinel![1] as readonly [string, string][]) as Record<string, unknown>, "style"), false);
  assert.deepEqual(selectionEnd![2], [["#", "\u200B"]]);
  assert.equal(Object.fromEntries(selectionEnd![1] as readonly [string, string][])["data-tq-copy-ignore"], "true");
  assert.equal(Object.hasOwn(Object.fromEntries(selectionEnd![1] as readonly [string, string][]) as Record<string, unknown>, "style"), false);
  assert.equal(Object.hasOwn(Object.fromEntries(hardBreak![1] as readonly [string, string][]) as Record<string, unknown>, "style"), false);
  assert.equal(Object.hasOwn(Object.fromEntries(lineBreak![1] as readonly [string, string][]) as Record<string, unknown>, "style"), false);
  assert.doesNotMatch(
    lowered.html,
    /(?:all:unset|display:inline-block|pointer-events:none|overflow:hidden)/u,
  );
});

test("article-sized prepared markup keeps inline style payload to dynamic line variables", () => {
  const lineCount = 25;
  const lowered = renderPreparedParagraphArtifact(articleFixture(lineCount), "zh-Hans");
  const inlineStyles = Array.from(
    lowered.html.matchAll(/ style="([^"]*)"/gu),
    (match) => match[1],
  );
  const inlineStyleBytes = inlineStyles.reduce(
    (sum, style) => sum + Buffer.byteLength(style),
    0,
  );

  assert.equal(inlineStyles.length, lineCount);
  assert.ok(
    inlineStyleBytes / lineCount < 80,
    `inline styles grew to ${inlineStyleBytes / lineCount} bytes/line`,
  );
  assert.ok(inlineStyles.every((style) => style.split(";").every((declaration) =>
    declaration.startsWith("--tq-line-"))));
});

test("evidenceFreePlanStaysLean", () => {
  const plan = fixturePlan();
  const html = renderPreparedParagraphArtifact(plan, "zh-Hans").html;
  assert.ok(!html.includes("data-tq-dash-"));
  assert.ok(!html.includes("data-tq-punctuation-"));
  assert.ok(!html.includes("data-tq-inline-object"));
  assert.ok(!html.includes("<svg"));
  assert.ok(!html.includes("font-size:"));
});

test("dashEvidenceAttributesRender", () => {
  const plan = {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    lines: [{
      rangeStart: 0,
      rangeEnd: 1,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: 18,
      hyphenAdvance: 0,
      endReason: "ParagraphEnd",
      cells: [{
        rangeStart: 0,
        rangeEnd: 1,
        source: "\u2014",
        display: "\u2014",
        drawX: 0,
        naturalWidth: 18,
        leadingLayoutAdvance: 0,
        dashStrategy: "ReplaceEmDash",
        shapingLanguage: "zh-Hans",
        resolvedFace: "FaceA",
        glyphIds: "71,72",
        shapingEvidence: "ShapingReason",
        renderFontFamily: "Han Face",
      }],
    }],
  };
  const html = renderPreparedParagraphArtifact(plan, "zh-Hans").html;
  assert.ok(html.includes('data-tq-dash-strategy="ReplaceEmDash"'));
  assert.ok(html.includes('data-tq-dash-advance="18"'));
  assert.ok(html.includes('data-tq-dash-font-family="Han Face"'));
  assert.ok(html.includes('data-tq-dash-face="FaceA"'));
  assert.ok(html.includes('data-tq-dash-glyph-ids="71,72"'));
  assert.ok(html.includes('data-tq-dash-evidence="ShapingReason"'));
  assert.ok(html.includes('lang="zh-Hans"'));
  assert.ok(html.includes('font-family:&quot;Han Face&quot;') || html.includes('font-family:"Han Face"'));
  assert.ok(html.includes('data-tq-render-font-projection="true"'));
});

test("dashRunIsolatesAndPunctuationAttributesRender", () => {
  const plan = {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    lines: [{
      rangeStart: 0,
      rangeEnd: 3,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: 54,
      hyphenAdvance: 0,
      endReason: "ParagraphEnd",
      cells: [
        {
          rangeStart: 0,
          rangeEnd: 1,
          source: "前",
          display: "前",
          drawX: 0,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
        },
        {
          rangeStart: 1,
          rangeEnd: 2,
          source: "\u2014",
          display: "\u2014",
          drawX: 18,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
          dashStrategy: "ReplaceEmDash",
          punctuationInkFloor: 2.5,
          punctuationBodyWidth: 16,
        },
        {
          rangeStart: 2,
          rangeEnd: 3,
          source: "后",
          display: "后",
          drawX: 36,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
        },
      ],
    }],
  };
  const artifact = renderPreparedParagraphArtifact(plan, "zh-Hans");
  const html = artifact.html;
  assert.ok(html.includes('data-tq-punctuation-ink-floor="2.5"'));
  assert.ok(html.includes('data-tq-punctuation-body-width="16"'));
  assert.ok(html.includes("前<span"));
  assert.ok(html.includes("</span>后"));
});

test("styleDeltaSplitsRunsAndEmitsPaint", () => {
  const plan = {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    lines: [{
      rangeStart: 0,
      rangeEnd: 3,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: 54,
      hyphenAdvance: 0,
      endReason: "ParagraphEnd",
      cells: [
        {
          rangeStart: 0,
          rangeEnd: 1,
          source: "甲",
          display: "甲",
          drawX: 0,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
        },
        {
          rangeStart: 1,
          rangeEnd: 2,
          source: "乙",
          display: "乙",
          drawX: 18,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
          style: { fontSize: 12, fontWeight: 700 },
        },
        {
          rangeStart: 2,
          rangeEnd: 3,
          source: "丙",
          display: "丙",
          drawX: 36,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
        },
      ],
    }],
  };
  const html = renderPreparedParagraphArtifact(plan, "zh-Hans").html;
  assert.ok(html.includes("font-size:12px!important"));
  assert.ok(html.includes("font-weight:700!important"));
  assert.ok(html.includes("甲<span"));
  assert.ok(html.includes("</span>丙"));
});

test("latinEmphasisItalicEffect", () => {
  const ranges: [number, number][] = [[0, 1]];
  const italicPlan = {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    emphasisRanges: ranges,
    lines: [{
      rangeStart: 0,
      rangeEnd: 1,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: 10,
      hyphenAdvance: 0,
      endReason: "ParagraphEnd",
      cells: [{
        rangeStart: 0,
        rangeEnd: 1,
        source: "A",
        display: "A",
        drawX: 0,
        naturalWidth: 10,
        leadingLayoutAdvance: 0,
        latin: true,
      }],
    }],
  };
  const italicHtml = renderPreparedParagraphArtifact(italicPlan, "zh-Hans").html;
  assert.ok(italicHtml.includes("font-style:italic!important"));

  const nonItalicPlan = {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    emphasisRanges: ranges,
    lines: [{
      rangeStart: 1,
      rangeEnd: 2,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: 10,
      hyphenAdvance: 0,
      endReason: "ParagraphEnd",
      cells: [{
        rangeStart: 1,
        rangeEnd: 2,
        source: "B",
        display: "B",
        drawX: 0,
        naturalWidth: 10,
        leadingLayoutAdvance: 0,
        latin: true,
      }],
    }],
  };
  const nonItalicHtml = renderPreparedParagraphArtifact(nonItalicPlan, "zh-Hans").html;
  assert.ok(!nonItalicHtml.includes("font-style:italic!important"));
});

test("inlineObjectPlaceholderKeepsFlow", () => {
  const plan = {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    lines: [{
      rangeStart: 0,
      rangeEnd: 2,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: 36,
      hyphenAdvance: 0,
      endReason: "ParagraphEnd",
      cells: [
        {
          rangeStart: 0,
          rangeEnd: 1,
          source: "\uFFFC",
          display: "\uFFFC",
          drawX: 0,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
          inlineObject: 18,
        },
        {
          rangeStart: 1,
          rangeEnd: 2,
          source: "字",
          display: "字",
          drawX: 18,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
        },
      ],
    }],
  };
  const artifact = renderPreparedParagraphArtifact(plan, "zh-Hans");
  const html = artifact.html;
  assert.ok(html.includes('data-tq-inline-object="pending"'));
  assert.ok(html.includes('data-tq-object-range="0-1"'));
  assert.ok(html.includes("inline-size:18px!important"));
});

test("inlineObjectPlaceholderCarriesTrailingMarginAttribute", () => {
  const withMargin = renderPreparedParagraphArtifact(inlineObjectPlan({ trailingMargin: true }));
  assert.ok(withMargin.html.includes('data-tq-object-trailing-margin="2"'));
  assert.ok(withMargin.html.includes("margin-right:2px!important"));

  const withoutMargin = renderPreparedParagraphArtifact(inlineObjectPlan());
  assert.doesNotMatch(withoutMargin.html, /data-tq-object-trailing-margin/u);
  assert.doesNotMatch(withoutMargin.html, /margin-right:/u);
});

test("inlineObjectCloneSwapReplacesPlaceholdersWithDeepClones", () => {
  const host = swapHost();
  const element = fakeInlineElement("IMG");
  const rendered = renderPreparedParagraphInto(probe<Host>(host), inlineObjectPlan({ trailingMargin: true }), "zh-Hans", {
    inlineObjects: [{ start: 0, end: 1, element: probe<Element>(element), marginRight: 4.5 }],
  }, createEnhanceContext(probe<Element>(host)));

  assert.deepEqual(element.cloneCalls, [true]);
  assert.equal(host.swapped.length, 1);
  const clone = host.swapped[0];
  assert.notEqual(clone, element);
  assert.equal(clone.attributes.get("data-tq-inline-object"), "true");
  assert.equal(clone.attributes.get("data-tq-object-range"), "0-1");
  assert.deepEqual(clone.styleProperties, [["margin-right", "6.5px", "important"]]);
  assert.doesNotMatch(host.innerHTML, /data-tq-inline-object="pending"/u);
  assert.match(host.innerHTML, /<IMG[^>]*data-tq-inline-object="true"/u);
  assert.equal(rendered.html, host.innerHTML);
  assert.equal(rendered.markers.length, 1);
});

test("inlineObjectCloneSwapSkipsMarginWithoutTrailingGap", () => {
  const host = swapHost();
  renderPreparedParagraphInto(probe<Host>(host), inlineObjectPlan(), "zh-Hans", {
    inlineObjects: [{ start: 0, end: 1, element: probe<Element>(fakeInlineElement("IMG")), marginRight: 4.5 }],
  }, createEnhanceContext(probe<Element>(host)));

  assert.equal(host.swapped.length, 1);
  assert.deepEqual(host.swapped[0].styleProperties, []);
  assert.equal(host.swapped[0].attributes.get("data-tq-inline-object"), "true");
});

test("inlineObjectCloneSwapThrowsWithoutSource", () => {
  const host = swapHost();
  assert.throws(
    () => renderPreparedParagraphInto(probe<Host>(host), inlineObjectPlan(), "zh-Hans", {}, createEnhanceContext(probe<Element>(host))),
    /InlineObjectSourceUnavailable:0-1/u,
  );
});

test("inlineObjectCloneSwapThrowsOnDuplicateRanges", () => {
  const host = swapHost();
  const entry = { start: 0, end: 1, element: probe<Element>(fakeInlineElement("IMG")) };
  assert.throws(
    () => renderPreparedParagraphInto(probe<Host>(host), inlineObjectPlan(), "zh-Hans", {
      inlineObjects: [entry, entry],
    }, createEnhanceContext(probe<Element>(host))),
    /ConflictingInlineObjectRange:0-1/u,
  );
});

test("inlineObjectCloneSwapIgnoresEntriesWithoutPlaceholders", () => {
  const host = swapHost();
  const rendered = renderPreparedParagraphInto(probe<Host>(host), fixturePlan(), "zh-Hans", {
    inlineObjects: [{ start: 0, end: 1, element: probe<Element>(fakeInlineElement("IMG")) }],
  }, createEnhanceContext(probe<Element>(host)));

  assert.equal(host.swapped.length, 0);
  assert.equal(rendered.markers.length, rendered.html.match(/data-tq-line-flow-width=/gu)!.length);
});

test("inlineObjectCloneSwapClonesAreIndependentOfSource", () => {
  const host = swapHost();
  const element = fakeInlineElement("IMG");
  renderPreparedParagraphInto(probe<Host>(host), inlineObjectPlan(), "zh-Hans", {
    inlineObjects: [{ start: 0, end: 1, element: probe<Element>(element) }],
  }, createEnhanceContext(probe<Element>(host)));
  element.setAttribute("data-tq-late", "1");

  assert.equal(host.swapped[0].attributes.has("data-tq-late"), false);
});

// This fixture deliberately omits RubyAnnotation.ascent so the renderer falls
// back to the ratio-derived ascent (top:-3px); the planAscent test below
// supplies ascent: 7 and asserts the direct value instead. TestPlan requires
// ascent, so the fixture type drops that one field and the call widens once.
interface BaseRangeStartOverride {
  baseRangeStart?: number;
}
type RatioAscentPlan = Omit<TestPlan, "rubyDecisions"> & {
  rubyDecisions: Array<Omit<NonNullable<TestPlan["rubyDecisions"]>[number], "ascent"> & BaseRangeStartOverride>;
};

test("rubyAnnotationSpanUsesRatioAscent", () => {
  const plan: RatioAscentPlan = {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    rubyDecisions: [{
      baseRangeStart: 0,
      baseRangeEnd: 1,
      text: "B\u011Bij\u012Bng",
      fontSize: 10,
      fontWeight: 500,
      centerX: 9,
      baselineY: 5,
      fontFamilies: ["Ruby Face"],
    }],
    lines: [{
      rangeStart: 0,
      rangeEnd: 1,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: 18,
      hyphenAdvance: 0,
      endReason: "ParagraphEnd",
      cells: [{
        rangeStart: 0,
        rangeEnd: 1,
        source: "京",
        display: "京",
        drawX: 0,
        naturalWidth: 18,
        leadingLayoutAdvance: 0,
      }],
    }],
  };
  const html = renderPreparedParagraphArtifact(plan as TestPlan, "zh-Hans").html;
  assert.ok(html.includes('data-tq-src="\uFF08B\u011Bij\u012Bng\uFF09"'));
  assert.ok(html.includes("left:9px!important"));
  assert.ok(html.includes("top:-3px!important"));
  assert.ok(html.includes("transform:translateX(-50%)!important"));
  assert.ok(html.includes("font-weight:500!important"));
});

test("rubyAnnotationSpanUsesPlanAscent", () => {
  const plan = {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    rubyDecisions: [{
      baseRangeStart: 0,
      baseRangeEnd: 1,
      text: "B\u011Bij\u012Bng",
      fontSize: 10,
      ascent: 7,
      fontWeight: 500,
      centerX: 9,
      baselineY: 5,
      fontFamilies: ["Ruby Face"],
    }],
    lines: [{
      rangeStart: 0,
      rangeEnd: 1,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: 18,
      hyphenAdvance: 0,
      endReason: "ParagraphEnd",
      cells: [{
        rangeStart: 0,
        rangeEnd: 1,
        source: "京",
        display: "京",
        drawX: 0,
        naturalWidth: 18,
        leadingLayoutAdvance: 0,
      }],
    }],
  };
  const html = renderPreparedParagraphArtifact(plan as TestPlan, "zh-Hans").html;
  assert.ok(html.includes("top:-2px!important"));
  assert.ok(!html.includes("top:-3px!important"));
});

test("bopomofoAnnotationSpanOccupiesSlack", () => {
  const plan = {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    bopomofoDecisions: [{
      baseRangeStart: 0,
      baseRangeEnd: 1,
      text: "ㄓˇ",
      fontWeight: 500,
      fontFamilies: ["Bopomofo Face"],
      placements: [
        {
          role: "Symbol",
          text: "ㄓ",
          left: 0,
          top: 2,
          width: 6,
          height: 8,
        },
        {
          role: "Tone",
          text: "ˇ",
          left: 6,
          top: 2,
          width: 4,
          height: 8,
        },
      ],
    }],
    lines: [{
      rangeStart: 0,
      rangeEnd: 1,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: 24,
      hyphenAdvance: 0,
      endReason: "ParagraphEnd",
      cells: [{
        rangeStart: 0,
        rangeEnd: 1,
        source: "只",
        display: "只",
        drawX: 0,
        naturalWidth: 18,
        advance: 24,
        leadingLayoutAdvance: 0,
      }],
    }],
  };
  const html = renderPreparedParagraphArtifact(plan as TestPlan, "zh-Hans").html;
  assert.ok(html.includes("width:6px!important"));
  assert.ok(html.includes('data-tq-src="（ㄓˇ）"'));
  assert.ok(html.includes("writing-mode:vertical-rl!important"));
  const expectedToneFontSize = Number((4 * 0.82 / (0.644 + (0.682 - 0.644) * (1 / 3))).toFixed(5));
  assert.ok(html.includes(`font-size:${expectedToneFontSize}px!important`));
});

test("interlinearAndDotOverlaysRender", () => {
  const plan = {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    fontSize: 20,
    overlayWidth: 120,
    height: 27,
    decorationSegments: [
      { kind: "ProperNoun", left: 0, top: 20, right: 60 },
      { kind: "BookTitle", left: 60, top: 20, right: 120 },
    ],
    emphasisDots: [
      { anchorX: 10, anchorY: 25, dotDiameter: 5 },
    ],
    lines: [{
      rangeStart: 0,
      rangeEnd: 1,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: 18,
      hyphenAdvance: 0,
      endReason: "ParagraphEnd",
      cells: [{
        rangeStart: 0,
        rangeEnd: 1,
        source: "中",
        display: "中",
        drawX: 0,
        naturalWidth: 18,
        leadingLayoutAdvance: 0,
      }],
    }],
  };
  const html = renderPreparedParagraphArtifact(plan as TestPlan, "zh-Hans").html;
  const svgMatches = html.match(/<svg/gu) ?? [];
  assert.equal(svgMatches.length, 2);
  assert.ok(html.includes("--tq-overlay-width:120px;--tq-overlay-height:27px"));
  assert.ok(html.includes('data-tq-decoration-line="true"'));
  assert.ok(html.includes('x1="0"'));
  assert.ok(html.includes('d="M 60 20'));
  assert.ok(html.includes(" Q "));
  assert.ok(html.includes('data-tq-decoration-dot="true"'));
  assert.ok(html.includes('r="2.5"'));
});

test("planInlineEdgesTakePrecedence", () => {
  const plan = {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    inlineEdges: [{ offset: 1, inlineEnd: 4 }],
    lines: [{
      rangeStart: 0,
      rangeEnd: 2,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: 40,
      hyphenAdvance: 0,
      endReason: "ParagraphEnd",
      cells: [
        {
          rangeStart: 0,
          rangeEnd: 1,
          source: "前",
          display: "前",
          drawX: 0,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
        },
        {
          rangeStart: 1,
          rangeEnd: 2,
          source: "后",
          display: "后",
          drawX: 22,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
        },
      ],
    }],
  };
  const artifact = renderPreparedParagraphArtifact(plan as TestPlan, "zh-Hans", {
    inlineBoxes: [{ start: 1, end: 1, inlineStartPx: 0, inlineEndPx: 10 }],
  });
  assert.equal(artifact.markerCount, 1);
  assert.ok(artifact.html.includes('data-tq-line-flow-width="40"'));
});

// Both emphasis-dot tests stub getComputedStyle with fixtures that carry only
// a styleColor field; the engine reads the resolved color and nothing else.
// The parameter stays unknown because the fixtures are not real Elements.
interface StyleColorSource {
  styleColor?: string;
}
const styleColorComputedStyle = (fallback: string) => (element: unknown): CSSStyleDeclaration => {
  const styleColor = (element as StyleColorSource | null | undefined)?.styleColor;
  return probe<CSSStyleDeclaration>({ color: styleColor ?? fallback });
};

test("emphasis dot color resolves from live source spans", () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = styleColorComputedStyle("rgb(255, 0, 0)");
  try {
    const plan = {
      schema: 1,
      layoutRevision: "tiqian-layout-v2",
      fontSize: 20,
      overlayWidth: 120,
      height: 27,
      emphasisDots: [
        { anchorX: 10, anchorY: 25, dotDiameter: 5, clusterRangeStart: 0 },
      ],
      lines: [{
        rangeStart: 0,
        rangeEnd: 1,
        top: 0,
        bottom: 27,
        baseline: 20,
        indent: 0,
        visualWidth: 18,
        hyphenAdvance: 0,
        endReason: "ParagraphEnd",
        cells: [{
          rangeStart: 0,
          rangeEnd: 1,
          source: "中",
          display: "中",
          drawX: 0,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
        }],
      }],
    };
    const liveElement = { styleColor: "rgb(255, 0, 0)" };
    const host = fakeHost();
    const rendered = renderPreparedParagraphInto(probe<Host>(host), plan as TestPlan, "zh-Hans", {
      semantics: [{ start: 0, end: 1, tagName: "strong", sourceIndex: 0, order: 0, attributes: [] }],
      liveSemanticElements: probe<Element[]>([liveElement]),
    }, createEnhanceContext(probe<Element>(host)));
    assert.ok(rendered.html.includes('fill="rgb(255, 0, 0)"'));
    assert.ok(rendered.html.includes("--tq-decoration-color:rgb(255, 0, 0)"));

    const artifact = renderPreparedParagraphArtifact(plan as TestPlan, "zh-Hans");
    assert.ok(artifact.html.includes('fill="currentColor"'));
    assert.ok(artifact.html.includes("--tq-decoration-color:currentColor"));
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("emphasis dot color selects the deepest covering semantic span", () => {
  const previousGetComputedStyle = globalThis.getComputedStyle;
  globalThis.getComputedStyle = styleColorComputedStyle("currentColor");
  try {
    const plan = {
      schema: 1,
      layoutRevision: "tiqian-layout-v2",
      fontSize: 20,
      overlayWidth: 120,
      height: 27,
      emphasisDots: [
        { anchorX: 10, anchorY: 25, dotDiameter: 5, clusterRangeStart: 1 },
      ],
      lines: [{
        rangeStart: 0,
        rangeEnd: 2,
        top: 0,
        bottom: 27,
        baseline: 20,
        indent: 0,
        visualWidth: 36,
        hyphenAdvance: 0,
        endReason: "ParagraphEnd",
        cells: [{
          rangeStart: 0,
          rangeEnd: 1,
          source: "中",
          display: "中",
          drawX: 0,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
        }, {
          rangeStart: 1,
          rangeEnd: 2,
          source: "文",
          display: "文",
          drawX: 18,
          naturalWidth: 18,
          leadingLayoutAdvance: 0,
        }],
      }],
    };
    const outerElement = { styleColor: "rgb(255, 0, 0)" };
    const innerElement = { styleColor: "rgb(0, 128, 0)" };
    const host = fakeHost();
    const rendered = renderPreparedParagraphInto(probe<Host>(host), plan as TestPlan, "zh-Hans", {
      semantics: [
        { start: 0, end: 2, tagName: "em", sourceIndex: 0, order: 0, attributes: [] },
        { start: 1, end: 2, tagName: "strong", sourceIndex: 1, order: 1, attributes: [] },
      ],
      liveSemanticElements: probe<Element[]>([outerElement, innerElement]),
    }, createEnhanceContext(probe<Element>(host)));
    assert.ok(rendered.html.includes('fill="rgb(0, 128, 0)"'));
    assert.ok(rendered.html.includes("--tq-decoration-color:rgb(0, 128, 0)"));
  } finally {
    globalThis.getComputedStyle = previousGetComputedStyle;
  }
});

test("cjkStrongSemantics marks clone with data-tq-cjk-emphasis and font-weight", () => {
  const host = liveSemanticHost();
  const sourceElement = fakeInlineElement("STRONG");
  const options = {
    sourceText: "中文",
    semanticReplay: "live-source",
    semantics: [{
      start: 0,
      end: 2,
      tagName: "strong",
      sourceIndex: 0,
      attributes: [],
    }],
    liveSemanticElements: probe<Element[]>([sourceElement]),
    cjkStrongSemantics: [{ start: 0, end: 2, weight: 700 }],
  };
  const rendered = renderPreparedParagraphInto(probe<Host>(host), fixturePlan(), "zh-Hans", options, createEnhanceContext(probe<Element>(host)));
  assert.ok(rendered.html.includes('data-tq-cjk-emphasis="true"'));
  assert.ok(rendered.html.includes("font-weight:700!important"));

  const artifact = renderPreparedParagraphArtifact(fixturePlan(), "zh-Hans", {
    sourceText: "中文",
    semantics: [{ start: 0, end: 2, tagName: "strong", sourceIndex: 0, attributes: [] }],
    cjkStrongSemantics: [{ start: 0, end: 2, weight: 700 }],
  });
  assert.ok(artifact.html.includes('data-tq-cjk-emphasis="true"'));
  assert.ok(artifact.html.includes('style="font-weight:700!important"'));

  const unadornedHost = liveSemanticHost();
  const unadorned = renderPreparedParagraphInto(probe<Host>(unadornedHost), fixturePlan(), "zh-Hans", {
    sourceText: "中文",
    semanticReplay: "live-source",
    semantics: [{
      start: 0,
      end: 2,
      tagName: "strong",
      sourceIndex: 0,
      attributes: [],
    }],
    liveSemanticElements: probe<Element[]>([fakeInlineElement("STRONG")]),
  }, createEnhanceContext(probe<Element>(unadornedHost)));
  assert.equal(unadorned.html.includes("data-tq-cjk-emphasis"), false);
});
