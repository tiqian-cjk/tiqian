import assert from "node:assert/strict";
import test from "node:test";

import {
  PREPARED_DOM_BRIDGE_NAME,
  installPreparedDomRendererBridge,
  installPreparedRenderFontStyle,
  installPreparedValueStyles,
  releasePreparedParagraphStyles,
  releasePreparedRenderFontStyle,
  releasePreparedValueStyleRoot,
  renderPreparedParagraphArtifact,
  renderPreparedParagraphInto,
} from "./prepared-dom.js";

function fixturePlan() {
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

function twoLineFixture(firstEndReason) {
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
    querySelectorAll(selector) {
      assert.equal(selector, "[data-tq-line-flow-width]");
      return Array.from(
        { length: this.innerHTML.match(/data-tq-line-flow-width=/gu)?.length ?? 0 },
        (_, index) => ({ index }),
      );
    },
  };
}

function styleBackedHost() {
  const head = {
    childNodes: [],
    appendChild(node) {
      this.childNodes.push(node);
      node.parentNode = this;
      return node;
    },
    removeChild(node) {
      this.childNodes.splice(this.childNodes.indexOf(node), 1);
      node.parentNode = null;
      return node;
    },
  };
  const documentObject = {
    head,
    createElement(tagName) {
      assert.equal(tagName, "style");
      return {
        attributes: new Map(),
        parentNode: null,
        textContent: "",
        setAttribute(name, value) {
          this.attributes.set(name, String(value));
        },
      };
    },
  };
  const attributes = new Map();
  const root = {
    ownerDocument: documentObject,
    getAttribute: (name) => attributes.get(name) ?? null,
    setAttribute: (name, value) => attributes.set(name, String(value)),
    removeAttribute: (name) => attributes.delete(name),
  };
  const host = {
    ...fakeHost(),
    ownerDocument: documentObject,
    closest: () => root,
  };
  return { host, root, head, attributes };
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
        tagName: "a",
        attributes: { href: "/article", class: "host-link" },
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
    semantics: [{ start: 0, end: 2, tagName: "code", attributes: {} }],
    inlineBoxes: [{ start: 0, end: 2, inlineStartPx: 6.2, inlineEndPx: 6.2 }],
  });

  assert.match(rendered.html, /data-tq-line-flow-width="48\.4"/u);
  assert.match(rendered.html, /<code data-tq-source-semantic="true">/u);
});

test("browser replay installs the same canonical HTML and returns its line markers", () => {
  const planJson = JSON.stringify(fixturePlan());
  const expected = renderPreparedParagraphArtifact(planJson, "zh-Hans");
  const host = fakeHost();
  const rendered = renderPreparedParagraphInto(host, planJson, "zh-Hans");

  assert.equal(host.innerHTML, expected.html);
  assert.equal(rendered.html, expected.html);
  assert.equal(rendered.markers.length, expected.markerCount);
});

test("browser replay preserves controlled inline semantics supplied by a Worker plan", () => {
  const host = fakeHost();
  renderPreparedParagraphInto(host, fixturePlan(), "zh-Hans", {
    sourceText: "中文",
    semantics: [{ start: 0, end: 2, tagName: "strong", attributes: [] }],
  });

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
    }],
    liveSemanticElements: [sourceElement],
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
    }, {
      start: 0,
      end: 2,
      tagName: "spoiler",
      sourceIndex: 1,
      order: 0,
    }],
    liveSemanticElements: [{ tagName: "EM", cloneNode() {} }, {
      tagName: "SPOILER",
      cloneNode() {},
    }],
  });

  assert.match(
    rendered.html,
    /data-tq-live-semantic-index="1"[^>]*><span data-tq-live-semantic-index="0"/u,
  );
});

test("browser replay moves dynamic prepared values into one root-scoped stylesheet", () => {
  const { host, head, attributes } = styleBackedHost();
  const rendered = renderPreparedParagraphInto(host, fixturePlan(), "zh-Hans");

  assert.doesNotMatch(rendered.html, / style=/u);
  assert.match(rendered.html, /class="tq-line tqvr-0"/u);
  assert.equal(head.childNodes.length, 1);
  assert.match(head.childNodes[0].textContent, /--tq-line-height:27px!important/u);
  assert.match(
    head.childNodes[0].textContent,
    /\[data-tq-value-style-scope\] \[data-tq-rendered="true"\] \.tqvr-0/u,
  );
  assert.ok(attributes.has("data-tq-value-style-scope"));

  assert.equal(releasePreparedParagraphStyles(host), true);
  assert.equal(head.childNodes.length, 0);
  assert.equal(attributes.has("data-tq-value-style-scope"), false);
});

test("runtime value classes cannot inherit unrelated snapshot declarations", () => {
  const { host, root, head } = styleBackedHost();
  assert.equal(
    installPreparedValueStyles(
      root,
      ["letter-spacing:-1.79285px!important"],
      ["Tiqian Fixture Sans"],
    ),
    true,
  );

  const rendered = renderPreparedParagraphInto(host, fixturePlan(), "zh-Hans");
  assert.match(rendered.html, /class="tq-line tqvr-1"/u);
  assert.doesNotMatch(rendered.html, /class="[^"]*tqv-1/u);
  assert.match(
    head.childNodes[0].textContent,
    /\.tqv-0\{letter-spacing:-1\.79285px!important\}/u,
  );
  assert.match(
    head.childNodes[0].textContent,
    /\.tqvr-1\{--tq-line-height:27px!important/u,
  );
});

test("host-compatible runtime families do not allocate a projection stylesheet", () => {
  const { root, head, attributes } = styleBackedHost();

  assert.equal(installPreparedRenderFontStyle(root, ["Fixture Sans"]), false);
  assert.equal(head.childNodes.length, 0);
  assert.equal(attributes.has("data-tq-value-style-scope"), false);

  assert.equal(releasePreparedRenderFontStyle(root), false);
  assert.equal(head.childNodes.length, 0);
  assert.equal(attributes.has("data-tq-value-style-scope"), false);
});

test("prepared semantic font runs replay their explicit host-family projection", () => {
  const valueStyles = [];
  const rendered = renderPreparedParagraphArtifact(fixturePlan(), "zh-Hans", {
    sourceText: "中文",
    styleClassFor: (value) => {
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

test("snapshot and runtime host families never become root projection variables", () => {
  const { root, head, attributes } = styleBackedHost();

  assert.equal(installPreparedValueStyles(root, [], ["Snapshot Sans"]), false);
  assert.equal(installPreparedRenderFontStyle(root, ["Runtime Sans"]), false);
  assert.equal(head.childNodes.length, 0);
  assert.equal(releasePreparedRenderFontStyle(root), false);
  assert.equal(releasePreparedValueStyleRoot(root), false);
  assert.equal(head.childNodes.length, 0);
  assert.equal(attributes.has("data-tq-value-style-scope"), false);
});

test("prepared positive spacing participates in native selection instead of using margin", () => {
  const plan = fixturePlan();
  plan.lines[0].cells[1].drawX = 20;
  plan.lines[0].visualWidth = 38;

  const lowered = renderPreparedParagraphArtifact(plan, "zh-Hans");

  assert.match(lowered.html, /letter-spacing:2px!important/u);
  assert.doesNotMatch(lowered.html, /margin-right:2px!important/u);
  assert.match(lowered.html, /data-tq-advance="20"/u);
  assert.match(lowered.html, /<\/span>文<span/u);
});

test("a single-cell overlap preserves its glyph width and carries negative flow in margin", () => {
  const plan = fixturePlan();
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
  assert.match(lowered.html, /letter-spacing:3px!important/u);
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
  assert.deepEqual(Object.fromEntries(lineBreak[1]), {
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
  assert.deepEqual(Object.fromEntries(lineBreak[1]), {
    "data-tq-engine-break": "MandatoryBreak",
  });
  assert.match(lowered.html, /data-tq-hard-break="true"/u);
  assert.match(lowered.html, /data-tq-src="\n"/u);
});

test("prepared DOM carries only the supported proportional quote feature signature", () => {
  const plan = fixturePlan();
  plan.lines[0].cells[0].source = "’";
  plan.lines[0].cells[0].display = "’";
  plan.lines[0].cells[0].openTypeFeatures = ["pwid", "palt"];

  const lowered = renderPreparedParagraphArtifact(plan, "zh-Hans");
  const featureRun = lowered.artifact.find(([, attributes]) =>
    Object.fromEntries(attributes)["data-tq-open-type-features"] != null);

  assert.ok(featureRun);
  assert.equal(
    Object.fromEntries(featureRun[1])["data-tq-open-type-features"],
    "pwid,palt",
  );
  assert.match(lowered.html, /data-tq-open-type-features="pwid,palt"/u);

  plan.lines[0].cells[0].openTypeFeatures = ["pwid"];
  assert.throws(
    () => renderPreparedParagraphArtifact(plan, "zh-Hans"),
    /UnsupportedPreparedOpenTypeFeatures/u,
  );
});

test("canonical prepared nodes keep repeated reset declarations in shared CSS", () => {
  const lowered = renderPreparedParagraphArtifact(twoLineFixture("MandatoryBreak"), "zh-Hans");
  const marker = lowered.artifact.find(([, attributes]) =>
    Array.isArray(attributes) && Object.fromEntries(attributes)["data-tq-line-flow-width"] != null);
  const sentinel = lowered.artifact.find(([, attributes]) =>
    Array.isArray(attributes) && Object.fromEntries(attributes)["data-tq-line-end-sentinel"] != null);
  const selectionEnd = lowered.artifact.find(([, attributes]) =>
    Array.isArray(attributes) && Object.fromEntries(attributes)["data-tq-selection-end"] != null);
  const hardBreak = lowered.artifact.find(([, attributes]) =>
    Array.isArray(attributes) && Object.fromEntries(attributes)["data-tq-hard-break"] != null);
  const lineBreak = lowered.artifact.find(([tag]) => tag === "br");

  assert.equal(
    Object.fromEntries(marker[1]).style,
    "--tq-line-height:27px!important;--tq-line-baseline-offset:-7px!important",
  );
  assert.equal(Object.hasOwn(Object.fromEntries(sentinel[1]), "style"), false);
  assert.deepEqual(selectionEnd[2], [["#", "\u200B"]]);
  assert.equal(Object.fromEntries(selectionEnd[1])["data-tq-copy-ignore"], "true");
  assert.equal(Object.hasOwn(Object.fromEntries(selectionEnd[1]), "style"), false);
  assert.equal(Object.hasOwn(Object.fromEntries(hardBreak[1]), "style"), false);
  assert.equal(Object.hasOwn(Object.fromEntries(lineBreak[1]), "style"), false);
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

test("global runtime bridge delegates to the canonical lowering and browser replay", () => {
  const bridge = globalThis[PREPARED_DOM_BRIDGE_NAME];
  const plan = fixturePlan();
  const expected = renderPreparedParagraphArtifact(plan, "zh-Hans");
  const host = fakeHost();

  assert.equal(bridge.layoutRevision, "tiqian-layout-v2");
  assert.equal(bridge.renderRevision, "prebroken-dom-v15");
  assert.equal(bridge.version, 1);
  assert.equal(bridge.semanticReplayRevision, 1);
  assert.deepEqual(bridge.lower(JSON.stringify(plan), "zh-Hans"), expected);
  assert.equal(bridge.render(host, plan, { locale: "zh-Hans" }).html, expected.html);
  assert.equal(host.innerHTML, expected.html);
});

test("prepared DOM bridge upgrades a configurable legacy renderer", () => {
  const target = {};
  const legacy = Object.freeze({
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v15",
    lower: () => "legacy",
    render: () => "legacy",
    release: () => false,
    releaseRoot: () => false,
  });
  Object.defineProperty(target, PREPARED_DOM_BRIDGE_NAME, {
    configurable: true,
    value: legacy,
  });

  const bridge = installPreparedDomRendererBridge(target);

  assert.notEqual(bridge, legacy);
  assert.equal(bridge.coordinatorVersion, 1);
  assert.equal(bridge.version, 1);
  assert.equal(bridge.semanticReplayRevision, 1);
  assert.equal(
    Object.getOwnPropertyDescriptor(target, PREPARED_DOM_BRIDGE_NAME).configurable,
    false,
  );
  assert.equal(bridge.lower(fixturePlan(), "zh-Hans").markerCount, 1);
});

test("cached legacy renderer cannot downgrade the prepared DOM bridge", () => {
  const target = {};
  const bridge = installPreparedDomRendererBridge(target);

  assert.throws(() => {
    Object.defineProperty(target, PREPARED_DOM_BRIDGE_NAME, {
      configurable: true,
      value: Object.freeze({
        schema: 1,
        layoutRevision: "tiqian-layout-v2",
        renderRevision: "prebroken-dom-v15",
      }),
      writable: false,
    });
  }, TypeError);
  assert.equal(target[PREPARED_DOM_BRIDGE_NAME], bridge);
  assert.equal(bridge.semanticReplayRevision, 1);
});

test("prepared DOM coordinator upgrades monotonically without unlocking the global slot", () => {
  const target = {};
  const bridge = installPreparedDomRendererBridge(target);
  const future = Object.freeze({
    version: 2,
    semanticReplayRevision: 0,
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v16",
    lower: () => "future",
    render: () => "future",
    release: () => true,
    releaseRoot: () => true,
  });

  assert.equal(bridge.install(future), bridge);
  assert.equal(bridge.version, 2);
  assert.equal(bridge.renderRevision, "prebroken-dom-v16");
  assert.equal(bridge.lower(), "future");

  installPreparedDomRendererBridge(target);
  assert.equal(bridge.version, 2);
  assert.equal(bridge.renderRevision, "prebroken-dom-v16");
  assert.equal(bridge.lower(), "future");
  assert.equal(
    Object.getOwnPropertyDescriptor(target, PREPARED_DOM_BRIDGE_NAME).configurable,
    false,
  );
});
