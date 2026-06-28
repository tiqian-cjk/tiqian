package org.tiqian.test

import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.TextRange

data class LayoutFixture(
    val id: String,
    val text: String,
    val constraints: LayoutConstraints,
    val notes: String,
    val lineHeight: Float? = null,
    val decorations: List<DecorationSpan> = emptyList(),
    /**
     * Fixtures pin 0 unless they exercise 段首缩进 — the maxWidth geometry
     * of the micro fixtures above is hand-tuned to specific break points
     * and a non-zero indent would obscure what each one tests. `null` opts
     * into the `MeasureAdaptiveFirstLineIndent` default (1 字 on short lines,
     * 2 字 otherwise).
     */
    val firstLineIndentEm: Float? = 0f,
    /**
     * Repair-mechanism fixtures pin the kinsoku mode to Fixed(Basic, no hang)
     * so the MeasureAdaptive default (which enables hanging below 14 字)
     * doesn't replace the specific repair they exercise — same spirit as
     * pinning firstLineIndentEm = 0.
     */
    val pinBasicNoHang: Boolean = false,
    /**
     * Inject the bundled English hyphenator so a long Western word wraps at
     * syllable points with a hanging hyphen (`LineEndHangingHyphen`, ADR 0029).
     * Default off — the deterministic stub has no hyphenator.
     */
    val useEnglishHyphenation: Boolean = false,
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
            pinBasicNoHang = true,
        ),
        LayoutFixture(
            id = "kinsoku-push-in",
            text = "中文中。",
            constraints = LayoutConstraints(maxWidth = 60f),
            notes = "Forces PushIn: greedy would put 。 at line start, then line-end punctuation glue shrinks enough to keep it on the previous line.",
            pinBasicNoHang = true,
        ),
        LayoutFixture(
            id = "lookahead-future-push-in",
            text = "中文中文中文。",
            constraints = LayoutConstraints(maxWidth = 60f),
            notes = "Forces a PushIn repair inside lookahead's future lines; lookahead should score that cheap repair instead of adding an earlier break.",
            pinBasicNoHang = true,
        ),
        LayoutFixture(
            id = "lookahead-avoids-repair",
            text = "中文中文中文。",
            constraints = LayoutConstraints(maxWidth = 48f),
            notes = "At width 48 greedy ends up with a CarryPrevious repair on the last line; lookahead shifts the first break earlier to avoid the conflict entirely.",
            pinBasicNoHang = true,
        ),
        LayoutFixture(
            id = "justify-cjk-paragraph",
            text = "中文中文中文中文中文中文",
            constraints = LayoutConstraints(maxWidth = 100f),
            notes = "Justification fills the small deficit on the first line by adding CjkInterChar glue between adjacent CJK clusters.",
        ),
        LayoutFixture(
            id = "justify-mixed-paragraph",
            text = "中文Hello中文，世界。",
            constraints = LayoutConstraints(maxWidth = 144f),
            notes = "Justification uses CjkLatinSpace at the CJK↔Latin boundary plus PunctuationGlue if a spacing reduction landed on the line.",
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
            notes = "Real-text stress test: ~200 chars of authentic Chinese with Latin words, fullwidth/halfwidth brackets, em-dash pair, ellipsis, Chinese quotes, and multiple comma-stop sequences. Triggers multi-line greedy + justification + adjacent punctuation compression simultaneously. Uses the standard 2em 段首缩进 like real body text.",
            firstLineIndentEm = 2f,
        ),
        LayoutFixture(
            id = "latin-word-wrap",
            text = "他引用了一句话：The quick brown fox jumps over the lazy dog，然后继续讲。",
            constraints = LayoutConstraints(maxWidth = 240f),
            notes = "LatinWordSegmentation: the English sentence wraps at word " +
                "boundaries instead of overflowing as one unbreakable cluster; " +
                "spaces collapse at line edges; word spaces stretch under justify.",
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
            id = "first-line-indent",
            text = "咖啡的风味因产地而各异，烘焙的深浅同样会改变口感与香气。",
            constraints = LayoutConstraints(maxWidth = 200f),
            notes = "段首缩进: first line indents 2em (CLREQ standard) — its " +
                "usable measure shrinks to maxWidth-2em and the LineBox carries " +
                "the indent; later lines use the full measure. Justify targets " +
                "the indented measure on line 0.",
            firstLineIndentEm = 2f,
        ),
        LayoutFixture(
            id = "latin-camelcase",
            text = "用PowerPoint做",
            constraints = LayoutConstraints(maxWidth = 128f),
            notes = "CamelCaseBreak: a camelCase token wraps at its hump (Power|Point) " +
                "with NO hyphen — the capital signals the break. All-caps abbreviations " +
                "(NASA) and single Title-case words are NOT treated this way.",
        ),
        LayoutFixture(
            id = "latin-existing-hyphen",
            text = "out-of-the-way",
            constraints = LayoutConstraints(maxWidth = 128f),
            notes = "ExistingHyphenBreak (CY/T 154-2017 §9.3): a hyphenated compound " +
                "wraps AT its existing '-' (no new hyphen, no synthetic 短横线 atom). " +
                "Keeps ≥2 letters each side (§9.4).",
        ),
        LayoutFixture(
            id = "latin-hard-break",
            text = "中Network",
            constraints = LayoutConstraints(maxWidth = 64f),
            notes = "LatinForcedHyphenBreak (ADR 0029): with NO hyphenator (default), " +
                "an over-long Latin word still hard-breaks at character boundaries " +
                "with a hanging hyphen, keeping 前二后三 — 'Ne' head, 'ork' tail.",
        ),
        LayoutFixture(
            id = "western-hyphenation",
            text = "请运行 internationalization 命令",
            constraints = LayoutConstraints(maxWidth = 160f),
            notes = "LineEndHangingHyphen (ADR 0029): the long English word is " +
                "split at en-US syllable points so it wraps inside the measure; a " +
                "hyphen hangs at the line end (行尾点号悬挂-style). The 'hyphen=' " +
                "line tag marks where. Needs the injected English hyphenator.",
            useEnglishHyphenation = true,
        ),
        LayoutFixture(
            id = "adaptive-short-line-indent",
            text = "提椠是一个面向中文正文的排版引擎",
            constraints = LayoutConstraints(maxWidth = 160f),
            notes = "MeasureAdaptiveFirstLineIndent: with no explicit indent and a " +
                "short measure (10 字 < 14), the段首缩进 default narrows to 1 字 " +
                "(not 2). The firstindent decision line records measure/threshold/source.",
            firstLineIndentEm = null,
        ),
        LayoutFixture(
            id = "mandatory-single-newline",
            text = "第一行\n第二行",
            constraints = LayoutConstraints(maxWidth = 160f),
            notes = "ADR 0037: a single source newline is a mandatory break, zero-width and unshaped.",
        ),
        LayoutFixture(
            id = "mandatory-blank-lines",
            text = "甲\n\n乙\n",
            constraints = LayoutConstraints(maxWidth = 160f),
            notes = "ADR 0037: consecutive and trailing mandatory breaks preserve blank lines.",
        ),
        LayoutFixture(
            id = "mandatory-leading-trailing-newline",
            text = "\n开头和结尾\n",
            constraints = LayoutConstraints(maxWidth = 160f),
            notes = "ADR 0037: leading and trailing mandatory breaks produce visible empty lines.",
        ),
        LayoutFixture(
            id = "mandatory-crlf",
            text = "甲\r\n乙",
            constraints = LayoutConstraints(maxWidth = 160f),
            notes = "ADR 0037: CRLF is one mandatory break cluster, not two blank lines.",
        ),
        LayoutFixture(
            id = "mandatory-wraps-long-line",
            text = "中文中文中文中文中文\n尾行",
            constraints = LayoutConstraints(maxWidth = 64f),
            notes = "ADR 0037: long source lines still auto-wrap before the mandatory break; mandatory-break lines are not justified.",
        ),
        LayoutFixture(
            id = "indent-opening-quote",
            text = "“好咖啡要趁热喝。”他说完便把杯子推了过来，让大家依次尝一口。",
            constraints = LayoutConstraints(maxWidth = 192f),
            notes = "段首缩进 composed with an opening quote at paragraph start: " +
                "the additive model's line-start leading-glue trim halves the " +
                "quote (CLREQ 缩减该符号始侧二分之一个汉字大小的空白) — visual " +
                "blank before the quote ink is exactly the 2em indent.",
            firstLineIndentEm = 2f,
        ),
        LayoutFixture(
            id = "line-end-kinsoku",
            // 中0文1中2文3（4中5文6）7中8文9
            text = "中文中文（中文）中文",
            constraints = LayoutConstraints(maxWidth = 80f),
            notes = "CLREQ 行尾禁则 (Basic): 开括号不得居行尾. maxWidth 80 (5字) " +
                "would end line 0 on （ — the break retreats so （ starts line 1 " +
                "(CarryNext, cascade-free). Pinned Fixed(Basic) so the measure " +
                "doesn't auto-escalate.",
            pinBasicNoHang = true,
        ),
        LayoutFixture(
            id = "interlinear-lines",
            // 屈0原1写2下3离4骚5，6顾7炎8武9王10夫11之12并13称14。15
            text = "屈原写下离骚，顾炎武王夫之并称。",
            constraints = LayoutConstraints(maxWidth = 224f),
            notes = "行间线 (ADR 0024): 专名号 underlines 屈原/顾炎武/王夫之, " +
                "书名号甲式 wavy line under 离骚. 顾炎武 and 王夫之 are adjacent — " +
                "AdjacentInterlinearLineShortening pulls each adjacent edge back " +
                "1/16em so the two marks read separately. No explicit lineHeight: " +
                "InterlinearMarkLineSpacingFloor raises the line height to 1.5em.",
            decorations = listOf(
                DecorationSpan(range = TextRange(0, 2), kind = DecorationKind.ProperNoun),
                DecorationSpan(range = TextRange(4, 6), kind = DecorationKind.BookTitle),
                DecorationSpan(range = TextRange(7, 10), kind = DecorationKind.ProperNoun),
                DecorationSpan(range = TextRange(10, 13), kind = DecorationKind.ProperNoun),
            ),
        ),
        LayoutFixture(
            id = "mourning-frame",
            // 悼0念1：2王3小4明5同6志7、8张9大10同11同12志13。14
            text = "悼念：王小明同志、张大同同志。",
            constraints = LayoutConstraints(maxWidth = 72f),
            notes = "示亡号 (mourning frames) around 王小明 and 张大同. maxWidth 72 " +
                "would naturally break inside 王小明 — MourningSpanKeptUnbroken moves " +
                "the break to the span start instead. Frame rects hug the font-declared " +
                "character face; the InterlinearMarkLineSpacingFloor (0.5em) keeps " +
                "frames clear of neighbouring lines without an explicit lineHeight.",
            decorations = listOf(
                DecorationSpan(range = TextRange(3, 6), kind = DecorationKind.Mourning),
                DecorationSpan(range = TextRange(9, 12), kind = DecorationKind.Mourning),
            ),
        ),
    )
}
