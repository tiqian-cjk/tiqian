package ink.duo3.tiqian.test

import ink.duo3.tiqian.core.LayoutConstraints
import ink.duo3.tiqian.core.TextAlign

data class LayoutFixture(
    val id: String,
    val text: String,
    val constraints: LayoutConstraints,
    val notes: String,
    val textAlign: TextAlign = TextAlign.Start,
)

object EarlyLayoutFixtures {
    val all: List<LayoutFixture> = listOf(
        LayoutFixture(
            id = "basic-pause-stop",
            text = "中文，中文。",
            constraints = LayoutConstraints(maxWidth = 160f),
            notes = "Covers pause/stop punctuation glue.",
        ),
        LayoutFixture(
            id = "ellipsis-and-dash",
            text = "中文……English——中文。",
            constraints = LayoutConstraints(maxWidth = 220f),
            notes = "Covers CJK ellipsis and dash fallback decisions.",
        ),
        LayoutFixture(
            id = "nested-quotes",
            text = "他说：“你好，世界。”",
            constraints = LayoutConstraints(maxWidth = 180f),
            notes = "Covers opening/closing punctuation and repair planning.",
        ),
        LayoutFixture(
            id = "adjacent-punctuation-spacing",
            text = "他说：“你好，世界。”！！",
            constraints = LayoutConstraints(maxWidth = 220f),
            notes = "Shows punctuation atoms and adjacent punctuation spacing compression.",
        ),
        LayoutFixture(
            id = "fallback-roles",
            text = "提椠……Hello——世界。",
            constraints = LayoutConstraints(maxWidth = 240f),
            notes = "Covers cluster font role classification for CJK text, CJK punctuation, and Latin words.",
        ),
        LayoutFixture(
            id = "greedy-multi-line",
            text = "提椠是一个面向中文正文的排版引擎，用于测试断行。",
            constraints = LayoutConstraints(maxWidth = 144f),
            notes = "Exercises greedy multi-line breaking with width tight enough to trigger several breaks.",
        ),
        LayoutFixture(
            id = "kinsoku-carry-previous",
            text = "提椠中文中文中文。",
            constraints = LayoutConstraints(maxWidth = 64f),
            notes = "Forces a kinsoku CarryPrevious repair: greedy break would put 。 at line start, so the engine pulls the preceding character down.",
        ),
        LayoutFixture(
            id = "kinsoku-push-in",
            text = "中文中。",
            constraints = LayoutConstraints(maxWidth = 60f),
            notes = "Forces PushIn: greedy would put 。 at line start, then line-end punctuation glue shrinks enough to keep it on the previous line.",
        ),
        LayoutFixture(
            id = "lookahead-future-push-in",
            text = "中文中文中文。",
            constraints = LayoutConstraints(maxWidth = 60f),
            notes = "Forces a PushIn repair inside lookahead's future lines; lookahead should score that cheap repair instead of adding an earlier break.",
        ),
        LayoutFixture(
            id = "lookahead-avoids-repair",
            text = "中文中文中文。",
            constraints = LayoutConstraints(maxWidth = 48f),
            notes = "At width 48 greedy ends up with a CarryPrevious repair on the last line; lookahead shifts the first break earlier to avoid the conflict entirely.",
        ),
        LayoutFixture(
            id = "justify-cjk-paragraph",
            text = "中文中文中文中文中文中文",
            constraints = LayoutConstraints(maxWidth = 100f),
            notes = "Justification fills the small deficit on the first line by adding CjkInterChar glue between adjacent CJK clusters. textAlign=Justify.",
            textAlign = TextAlign.Justify,
        ),
        LayoutFixture(
            id = "justify-mixed-paragraph",
            text = "中文Hello中文，世界。",
            constraints = LayoutConstraints(maxWidth = 144f),
            notes = "Justification uses CjkLatinSpace at the CJK↔Latin boundary plus PunctuationGlue if a spacing reduction landed on the line. textAlign=Justify.",
            textAlign = TextAlign.Justify,
        ),
        LayoutFixture(
            id = "ascii-brackets-in-cjk",
            text = "中文段落(English)和[mixed]说明。",
            constraints = LayoutConstraints(maxWidth = 240f),
            notes = "ASCII (, ), [, ] do not share code points with the CJK fullwidth forms （）【】, so they always classify as Latin. (English) and [mixed] cluster as Latin runs and render in latin-primary even when surrounded by CJK content.",
        ),
        LayoutFixture(
            id = "real-paragraph-1",
            text = "提椠（Tiqian）是一个面向中文正文的 CJK 段落排版引擎。第一阶段的目标不是复刻浏览器级文本系统，而是在 shaping 之后、绘制之前的薄薄一层里——字体 fallback、CJK 度量、标点 atom、避头尾修复、两端对齐——做出一个可观察、可调试、可扩展的物理模型。换句话说，「功能可以窄，模型必须真」。第一阶段并不试图同时覆盖竖排、JLREQ、ruby、纵中横、编辑器、IME……这些不是被遗忘，而是被故意推后到模型稳定之后。",
            constraints = LayoutConstraints(maxWidth = 320f),
            notes = "Real-text stress test: ~200 chars of authentic Chinese with Latin words, fullwidth/halfwidth brackets, em-dash pair, ellipsis, Chinese quotes, and multiple comma-stop sequences. Triggers multi-line greedy + justification + adjacent punctuation compression simultaneously.",
            textAlign = TextAlign.Justify,
        ),
    )
}
