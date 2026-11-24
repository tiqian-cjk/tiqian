import { strict as assert } from "node:assert";
import test from "node:test";

import type { FakeElement } from "./snapshot-dom-fixtures.js";

import {
  cleanupMounted,
  computedStyleValue,
  copySelection,
  cssPx,
  elementWidth,
  loadHostRuntime,
  mount,
  preparedValueStyleProperty,
  probe,
  testOptions,
} from "./runtime-host.js";

const enginePunctuationFeatureStyle = `
  <style>
    [data-tq-rendered="true"] {
      font-feature-settings: "halt" 0, "chws" 0, "palt" 0 !important;
    }
    [data-tq-rendered="true"] span[data-tq-open-type-features="pwid,palt"] {
      font-feature-settings: "halt" 0, "chws" 0, "palt" 1 !important;
    }
  </style>
`;

function lastTextLeaf(paragraph: FakeElement) {
  const leaves = Array.from(paragraph.querySelectorAll("[data-tq-geometry]"))
    .filter((element) => !element.hasAttribute("data-tq-copy-ignore") && element.textContent.length > 0);
  return leaves.length === 0 ? null : leaves[leaves.length - 1];
}

function geometryLeafWithText(paragraph: FakeElement, text: string) {
  return Array.from(paragraph.querySelectorAll("[data-tq-geometry]"))
    .find((element) => element.textContent === text) || null;
}

function textNodeCharacterWidths(element: FakeElement) {
  const node = element.firstChild;
  if (!node || node.nodeType !== 3) return "";
  const widths = [];
  for (let index = 0; index < node.textContent.length; index += 1) {
    const range = globalThis.document.createRange();
    range.setStart(probe<Node>(node), index);
    range.setEnd(probe<Node>(node), index + 1);
    widths.push(range.getBoundingClientRect().width);
  }
  return widths.join(",");
}

function assertEnginePunctuationFeatureLock(element: FakeElement, proportionalQuote = false) {
  const features = computedStyleValue(element, "font-feature-settings");
  assert.ok(/["']halt["']\s+0/.test(features), features);
  assert.ok(/["']chws["']\s+0/.test(features), features);
  const palt = /["']palt["'](?:\s+(-?\d+))?/.exec(features);
  assert.ok(palt, features);
  const paltValue = palt[1] === undefined || palt[1] === "" ? "1" : palt[1];
  assert.equal(proportionalQuote ? "1" : "0", paltValue, features);
}

test("rendererSourceFidelity_expandsCjkContextCurlyQuotesButKeepsLatinPairsProportional", async (t) => {
  t.after(cleanupMounted);
  const TiqianWeb = await loadHostRuntime();
  const root = mount(`
    <div data-tiqian-root="true" style="width: 600px">
      <p style="font-family: Arial, sans-serif; font-size: 20px; line-height: 32px"><span class="cjk-quotes">中“文”中</span></p>
      <p style="font-family: Arial, sans-serif; font-size: 20px; line-height: 32px"><span class="latin-quotes">A“A”A</span></p>
    </div>
  `);

  assert.equal(TiqianWeb.enhance(probe<Element>(root)), 2);

  const cjk = root.querySelector(".cjk-quotes[data-tq-source-semantic]");
  const latin = root.querySelector(".latin-quotes[data-tq-source-semantic]");
  assert.ok(cjk);
  assert.ok(latin);
  // Three Han glyphs + two context-CJK quote boxes = 5em. The same
  // source quote codepoints in Latin prose retain the face's narrow
  // proportional advances instead of being globally widened.
  assert.ok(Math.abs(elementWidth(cjk) - 100.0) <= 1.0);
  assert.ok(elementWidth(latin) < 80.0, `Latin quote pair was widened: ${elementWidth(latin)}px`);
  assert.equal(copySelection(cjk), "中“文”中");
  assert.equal(copySelection(latin), "A“A”A");
});

test("rendererSourceFidelity_preservesOneNativeLinkAcrossEngineOwnedLines", async (t) => {
  t.after(cleanupMounted);
  const TiqianWeb = await loadHostRuntime();
  const root = mount(`
    <div data-tiqian-root="true" style="width: 120px">
      <p><a class="host-link" href="/target/" target="_self" rel="author" title="Host title" style="color: rgb(10, 11, 12); text-decoration-style: dotted; transition: text-decoration-color 200ms">一段足够长而且确定会跨过许多视觉行的链接文字</a>。<a class="other-link" href="/other/">其他</a></p>
    </div>
  `);

  const count = TiqianWeb.enhance(probe<Element>(root), testOptions());

  assert.equal(count, 1);
  const links = root.querySelectorAll("p a.host-link[href='/target/']");
  assert.equal(links.length, 1, "one source link must remain one DOM link across soft wraps");
  const link = links[0];
  assert.equal(link.parentElement, root.querySelector("p"), "top-level source link must stay a direct child");
  assert.equal(link.getAttribute("target"), "_self");
  assert.equal(link.getAttribute("rel"), "author");
  assert.equal(link.getAttribute("title"), "Host title");
  assert.equal(link.style.getPropertyValue("color"), "rgb(10, 11, 12)");
  assert.equal(link.style.getPropertyValue("text-decoration-style"), "dotted");
  assert.equal(link.style.getPropertyValue("transition"), "text-decoration-color 200ms");
  assert.equal(link.getAttribute("data-tq-link-group"), null);
  assert.ok(link.querySelectorAll("br[data-tq-engine-break]").length > 1);
  assert.equal(link.textContent, "一段足够长而且确定会跨过许多视觉行的链接文字");

  TiqianWeb.refresh(probe<Element>(root), false);
  const refreshedLinks = root.querySelectorAll("p a.host-link[href='/target/']");
  assert.equal(refreshedLinks.length, 1);
  assert.equal(refreshedLinks[0].getAttribute("data-tq-link-group"), null);
});

test("rendererSourceFidelity_keepsOneLinkAcrossConsecutiveEmptyHardBreakLines", async (t) => {
  t.after(cleanupMounted);
  const TiqianWeb = await loadHostRuntime();
  const root = mount(`
    <div data-tiqian-root="true" style="width: 320px">
      <p><a class="host-link" href="/target/">甲<br><br>乙</a></p>
    </div>
  `);

  assert.equal(TiqianWeb.enhance(probe<Element>(root), testOptions()), 1);

  const paragraph = root.querySelector("p")!;
  const links = paragraph.querySelectorAll("a.host-link[href='/target/']");
  assert.equal(links.length, 1);
  const link = links[0];
  assert.equal(link.querySelectorAll("[data-tq-hard-break]").length, 2);
  assert.equal(link.querySelectorAll("br[data-tq-engine-break='MandatoryBreak']").length, 2);
  assert.equal(copySelection(paragraph), "甲\n\n乙");
});

test("rendererSourceFidelity_keepsSemanticLinkContinuousAcrossGeometryFragments", async (t) => {
  t.after(cleanupMounted);
  const TiqianWeb = await loadHostRuntime();
  const root = mount(`
    <div data-tiqian-root="true" style="width: 700px">
      <p style="font-size: 18px; line-height: 30px">对比（来自<a class="host-link" href="/pull/4479">添加windows-reactor的PR</a>）：</p>
    </div>
  `);

  assert.equal(TiqianWeb.enhance(probe<Element>(root), testOptions()), 1);

  const paragraph = root.querySelector("p")!;
  const links = paragraph.querySelectorAll("a.host-link[href='/pull/4479']");
  assert.equal(links.length, 1, "one source link must stay one semantic wrapper per line");
  const link = links[0];
  assert.equal(copySelection(link), "添加windows-reactor的PR");
  assert.ok(link.children.length > 1, "geometry fragments should live inside the host link");
});

test("rendererSourceFidelity_keepsInlineBoxAsOneNativeElementAcrossEngineLines", async (t) => {
  t.after(cleanupMounted);
  const TiqianWeb = await loadHostRuntime();
  const root = mount(`
    <div data-tiqian-root="true" style="width: 90px">
      <p>前<spoiler style="padding-left: 4px; padding-right: 4px; border: 1px solid">一段足够长并且必然跨行的语义内容</spoiler>后。</p>
    </div>
  `);

  assert.equal(TiqianWeb.enhance(probe<Element>(root), testOptions()), 1);

  const inline = root.querySelectorAll("p spoiler");
  assert.equal(inline.length, 1);
  const spoiler = inline[0];
  assert.ok(spoiler.querySelectorAll("br[data-tq-engine-break]").length > 1);
  assert.equal(computedStyleValue(spoiler, "padding-left"), "4px");
  assert.equal(computedStyleValue(spoiler, "padding-right"), "4px");
  assert.equal(spoiler.getAttribute("data-tq-inline-open-start"), null);
  assert.equal(spoiler.getAttribute("data-tq-inline-open-end"), null);
});

test("rendererSourceFidelity_engineGeometrySpansAreNeutralToHostSpanRules", async (t) => {
  t.after(cleanupMounted);
  const TiqianWeb = await loadHostRuntime();
  const root = mount(`
    <div class="host" data-tiqian-root="true" style="width: 320px">
      <style>
        .host p span { display: block !important; padding: 19px !important; font-size: 40px !important; }
        [data-tq-rendered="true"] span[data-tq-geometry="true"] {
          all: unset !important;
          display: inline !important;
          text-spacing-trim: space-all !important;
        }
      </style>
      <p style="font-size: 18px; line-height: 30px">引擎生成的几何节点不能继承宿主对真实 span 的盒模型。</p>
    </div>
  `);

  assert.equal(TiqianWeb.enhance(probe<Element>(root), testOptions()), 1);

  const paragraph = root.querySelector("p")!;
  assert.equal(paragraph.querySelector(".tq-flow"), null);
  const run = paragraph.querySelector(":scope > [data-tq-geometry]:not(.tq-line)");
  assert.ok(run);
  assert.equal(computedStyleValue(run, "display"), "inline");
  assert.equal(cssPx(computedStyleValue(run, "padding-left")), 0);
  assert.equal(cssPx(computedStyleValue(run, "font-size")), 18);
});

test("rendererSourceFidelity_engineAnnotationsAreNeutralToHostSpanAndSvgRules", async (t) => {
  t.after(cleanupMounted);
  const TiqianWeb = await loadHostRuntime();
  const root = mount(`
    <div class="host" data-tiqian-root="true" style="width: 320px">
      <style>
        [data-tq-rendered="true"] svg[data-tq-geometry="true"] {
          all: unset !important;
          display: block !important;
        }
        [data-tq-rendered="true"] svg[data-tq-geometry="true"] circle[data-tq-decoration-dot] {
          fill: var(--tq-decoration-color) !important;
        }
        .host p span { display: block !important; padding: 19px !important; }
        .host p svg { display: none !important; }
        .host p svg circle { fill: rgb(255, 0, 255) !important; }
      </style>
      <p style="color: rgb(1, 2, 3)">前<strong>强调</strong>后。</p>
    </div>
  `);

  assert.equal(
    TiqianWeb.enhance(probe<Element>(root), { ...testOptions(), strongAsEmphasisMarks: true }),
    1,
  );

  const paragraph = root.querySelector("p")!;
  const svg = paragraph.querySelector("svg[data-tq-geometry]");
  const circle = paragraph.querySelector("circle");
  assert.ok(svg);
  assert.ok(circle);
  assert.equal(computedStyleValue(svg, "display"), "block");
  assert.equal(computedStyleValue(circle, "fill"), "rgb(1, 2, 3)");
});

test("rendererSourceFidelity_emitsFinalAndLatinAdjacentPunctuationSpacingWithoutClippingInk", async (t) => {
  t.after(cleanupMounted);
  const TiqianWeb = await loadHostRuntime();
  const root = mount(`
    <div data-tiqian-root="true" style="width: 220px">
      <p style="font-size: 18px; line-height: 30px">你想要开发一个小软件（单文件），那么你现在应该选择C++（MFC）、Rust（Winio）。</p>
    </div>
  `);

  assert.equal(TiqianWeb.enhance(probe<Element>(root), testOptions()), 1);

  const paragraph = root.querySelector("p")!;
  const lines = paragraph.querySelectorAll(".tq-line");
  assert.ok(lines.length > 1);
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    assert.ok(preparedValueStyleProperty(line, "--tq-line-height").length > 0);
    assert.ok(preparedValueStyleProperty(line, "--tq-line-baseline-offset").length > 0);
    assert.equal(line.style.getPropertyValue("display"), "");
    assert.equal(line.style.getPropertyValue("width"), "");
    assert.equal(line.style.getPropertyValue("height"), "");
    assert.equal(line.style.getPropertyValue("line-height"), "");
    assert.equal(line.style.getPropertyValue("vertical-align"), "");
    assert.equal(line.style.getPropertyValue("overflow"), "");
    assert.equal(line.style.getPropertyValue("pointer-events"), "");
    assert.ok(line.getAttribute("data-tq-line-width") !== null);
  }

  const last = lastTextLeaf(paragraph);
  assert.ok(last);
  assert.ok(
    cssPx(computedStyleValue(last, "margin-right")) < -0.1,
    `expected final-cluster compression: ${paragraph.innerHTML}`,
  );
});

test("rendererSourceFidelity_browserPunctuationTrimDoesNotDoubleCompressClosingCommaOpeningSequence", async (t) => {
  t.after(cleanupMounted);
  const TiqianWeb = await loadHostRuntime();
  const source = "前句「甲」、「乙」后句。";
  const root = mount(`
    <div data-tiqian-root="true" style="width: 700px">
      ${enginePunctuationFeatureStyle}
      <style>
        [data-tq-rendered="true"] [data-tq-geometry] {
          text-spacing-trim: space-all !important;
        }
      </style>
      <p style="font-size: 18px; line-height: 30px">${source}</p>
    </div>
  `);

  assert.equal(TiqianWeb.enhance(probe<Element>(root), testOptions()), 1);

  const paragraph = root.querySelector("p")!;
  assertEnginePunctuationFeatureLock(paragraph);
  let totalAdvance = 0;
  for (const punctuation of ["」", "、"]) {
    const run = geometryLeafWithText(paragraph, punctuation);
    assert.ok(run);
    assert.equal(computedStyleValue(run, "text-spacing-trim"), "space-all");
    assertEnginePunctuationFeatureLock(run);
    const width = Number.parseFloat(textNodeCharacterWidths(run));
    assert.ok(Math.abs(width - 18) < 0.75, `unexpected glyph width for ${punctuation}: ${width}`);
    totalAdvance += width + cssPx(computedStyleValue(run, "margin-right"));
  }
  assert.ok(Math.abs(totalAdvance - 18) < 0.75, `closing-comma advance: ${totalAdvance}`);
  assert.equal(copySelection(paragraph), source);
});
