package ink.duo3.tiqian.test

import ink.duo3.tiqian.core.DecorationKind
import ink.duo3.tiqian.core.DecorationSpan
import ink.duo3.tiqian.core.LayoutConstraints
import ink.duo3.tiqian.core.TextAlign
import ink.duo3.tiqian.core.TextRange

data class LayoutFixture(
    val id: String,
    val text: String,
    val constraints: LayoutConstraints,
    val notes: String,
    val textAlign: TextAlign = TextAlign.Start,
    val lineHeight: Float? = null,
    val decorations: List<DecorationSpan> = emptyList(),
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
            text = "咖啡馆比咖啡更早地改变了城里人的作息与谈吐。",
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
            text = "咖啡（coffee）在十七世纪经威尼斯传入欧洲。最初它被当作药物出售，价格高得吓人，真正" +
            "让它流行起来的是随后遍地开花的咖啡馆——读报、辩论、下棋、写作——城市生活忽然多出一个公" +
            "共客厅。意大利人做出了 espresso，维也纳人往杯里加奶油，土耳其人坚持连渣同煮……" +
            "每座城市都相信自己手里那一杯才是正统。有人说：「先有咖啡馆，后有启蒙运动」。这话说得夸张" +
            "，但也不算太离谱。",
            constraints = LayoutConstraints(maxWidth = 320f),
            notes = "Real-text stress test: ~200 chars of authentic Chinese with Latin words, fullwidth/halfwidth brackets, em-dash pair, ellipsis, Chinese quotes, and multiple comma-stop sequences. Triggers multi-line greedy + justification + adjacent punctuation compression simultaneously.",
            textAlign = TextAlign.Justify,
        ),
        LayoutFixture(
            id = "emphasis-marks",
            // 他0强1调2：3豆4子5新6鲜7最8要9紧10，11烘12焙13其14次15。16
            text = "他强调：豆子新鲜最要紧，烘焙其次。",
            constraints = LayoutConstraints(maxWidth = 128f),
            notes = "CLREQ emphasis dots (着重号): span covers 豆子新鲜最要紧，烘焙其次 " +
                "including the comma — Han text gets a dot anchor, punctuation is " +
                "skipped per CLREQ. Narrow measure wraps the span across lines; " +
                "lineHeight 25.6px (1.6×16) leaves room for the dots below the em box.",
            lineHeight = 25.6f,
            decorations = listOf(
                DecorationSpan(range = TextRange(4, 16), kind = DecorationKind.Emphasis),
            ),
        ),
        LayoutFixture(
            id = "mourning-frame",
            // 悼0念1：2王3小4明5同6志7、8张9大10同11同12志13。14
            text = "悼念：王小明同志、张大同同志。",
            constraints = LayoutConstraints(maxWidth = 72f),
            notes = "示亡号 (mourning frames) around 王小明 and 张大同. maxWidth 72 " +
                "would naturally break inside 王小明 — MourningSpanKeptUnbroken moves " +
                "the break to the span start instead. Frame rects derive from raw ink " +
                "metrics; lineHeight 28.8 keeps frames clear of neighbouring lines.",
            lineHeight = 28.8f,
            decorations = listOf(
                DecorationSpan(range = TextRange(3, 6), kind = DecorationKind.Mourning),
                DecorationSpan(range = TextRange(9, 12), kind = DecorationKind.Mourning),
            ),
        ),
    )
}
