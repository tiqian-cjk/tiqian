package org.tiqian.test;

import org.tiqian.core.*;

@:dataClass
class LayoutFixture {
    public final id:String;
    public final text:String;
    public final constraints:LayoutConstraints;
    public final notes:String;
    public final lineHeight:Null<Float>;
    public final decorations:Array<DecorationSpan>;
    public final rubySpans:Array<RubySpan>;
    public final rubyLineHeightMode:RubyLineHeightMode;
    public final firstLineIndentEm:Null<Float>;
    public final pinBasicNoHang:Bool;
    public final useEnglishHyphenation:Bool;
    public final lineLengthGrid:LineLengthGrid;
    public final lineBreakSpans:Array<LineBreakSpan>;

    public function new(id:String, text:String, constraints:LayoutConstraints, notes:String, ?lineHeight:Null<Float>, ?decorations:Array<DecorationSpan>,
            ?rubySpans:Array<RubySpan>, ?rubyLineHeightMode:RubyLineHeightMode, ?firstLineIndentEm:Null<Float>, ?pinBasicNoHang:Bool,
            ?useEnglishHyphenation:Bool, ?lineLengthGrid:LineLengthGrid, ?lineBreakSpans:Array<LineBreakSpan>) {
        this.id = id;
        this.text = text;
        this.constraints = constraints;
        this.notes = notes;
        this.lineHeight = lineHeight;
        this.decorations = decorations == null ? [] : decorations;
        this.rubySpans = rubySpans == null ? [] : rubySpans;
        this.rubyLineHeightMode = rubyLineHeightMode == null ? RubyLineHeightMode.PerLine : rubyLineHeightMode;
        this.firstLineIndentEm = firstLineIndentEm;
        this.pinBasicNoHang = pinBasicNoHang == null ? false : pinBasicNoHang;
        this.useEnglishHyphenation = useEnglishHyphenation == null ? false : useEnglishHyphenation;
        this.lineLengthGrid = lineLengthGrid == null ? new LineLengthGrid() : lineLengthGrid;
        this.lineBreakSpans = lineBreakSpans == null ? [] : lineBreakSpans;
    }
}

class EarlyLayoutFixtures {
    public static final all:Array<LayoutFixture> = [
        new LayoutFixture("basic-pause-stop", "中文，中文。", new LayoutConstraints(160), "Covers pause/stop punctuation glue.", null, [], [],
            RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("ellipsis-and-dash", "中文……English——中文。", new LayoutConstraints(220), "Covers CJK ellipsis and dash fallback decisions.", null, [],
            [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("nested-quotes", "他说：“你好，世界。”", new LayoutConstraints(180), "Covers opening/closing punctuation and repair planning.", null, [], [],
            RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("adjacent-punctuation-spacing", "他说：“你好，世界。”！！", new LayoutConstraints(220),
            "Shows punctuation atoms and adjacent punctuation spacing compression.", null, [], [], RubyLineHeightMode.PerLine, 0, false, false,
            new LineLengthGrid(), []),
        new LayoutFixture("contextual-curly-quotes", "中‘that’s’中’，‘", new LayoutConstraints(192),
            "NonCjkInWordApostrophe keeps the apostrophe in that’s on the Western run while the surrounding single quotes retain CJK punctuation geometry; the trailing ’，‘ sequence exercises both adjacent-punctuation compression boundaries.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("mixed-script-quote-paragraph-language", "“Json是谁？”", new LayoutConstraints(192),
            "A quote-only Chinese paragraph begins with a Latin identifier; full content evidence is mixed, so ParagraphLanguageQuoteContext keeps the pair on CJK punctuation geometry.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("adjacent-curly-quote-list-context", "中文“对A”“波霸”；中文“欧派”“double”“double may”呢", new LayoutConstraints(320),
            "PairedPunctuationOuterScriptContext evaluates ordinary text at the enclosing level and excludes every quoted sibling, so Latin content in one item cannot switch a following CJK-context quote pair to proportional Latin geometry.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("mi10s-adjacent-curly-quote-wrap", "所以这个和 “骑ji” “说shui”“斜xiá”不一样，港台是从众的，大陆读音大多数源自韵书。", new LayoutConstraints(160),
            "Mi 10s dogfood regression: PairedPunctuationOuterScriptContext gives the adjacent ‘斜xiá’ pair its enclosing Chinese prose context, while Uax14WesternPunctuationBoundary keeps Western closing/opening punctuation attached even when a shared code point uses a Latin face.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("mi10s-western-bracket-citation-wrap", "史力军,姚晨,杨国玉,等.常见有机化合物中文词汇的读音详解[J].化学教育(中英文), 2023, 44(10):21-38.",
            new LayoutConstraints(272),
            "Mi 10s dogfood regression: WesternBracketCjkInterChar lets proportional ASCII parentheses touching Chinese share tier-3 equal expansion without changing their Latin face; BibliographicNumericLocatorBreak exposes clean volume(issue):page-range boundaries while each digit run and the page range remain intact.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(false), []),
        new LayoutFixture("bibliographic-numeric-locator-break", "中文中文中文44(10):21-38.", new LayoutConstraints(224),
            "BibliographicNumericLocatorBreak lets the preceding Chinese line take 44(10): and wraps before the intact page range 21-38.; the volume and issue digit runs remain cohesive and no synthetic hyphen is added.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(false), []),
        new LayoutFixture("unmatched-curly-quotes", "’90s James’； “truncated；中文“未闭", new LayoutConstraints(240),
            "UnmatchedQuoteSurroundingScriptContext keeps leading elisions, trailing possessives, and spaced truncated Latin quotations proportional while an unspaced truncated quote in Chinese remains CJK punctuation.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("fallback-roles", "提椠……Hello——世界。", new LayoutConstraints(240),
            "Covers cluster font role classification for CJK text, CJK punctuation, and Latin words.", null, [], [], RubyLineHeightMode.PerLine, 0, false,
            false, new LineLengthGrid(), []),
        new LayoutFixture("greedy-multi-line", "咖啡馆比咖啡更早地改变了城里人的作息与谈吐。", new LayoutConstraints(144),
            "Exercises greedy multi-line breaking with width tight enough to trigger several breaks.", null, [], [], RubyLineHeightMode.PerLine, 0, false,
            false, new LineLengthGrid(), []),
        new LayoutFixture("kinsoku-carry-previous", "提椠中文中文中文。", new LayoutConstraints(64),
            "Forces a kinsoku CarryPrevious repair: greedy break would put 。 at line start, so the engine pulls the preceding character down.", null, [], [],
            RubyLineHeightMode.PerLine, 0, true, false, new LineLengthGrid(), []),
        new LayoutFixture("kinsoku-push-in", "中文中。", new LayoutConstraints(60),
            "Forces PushIn: greedy would put 。 at line start, then line-end punctuation glue shrinks enough to keep it on the previous line.", null, [], [],
            RubyLineHeightMode.PerLine, 0, true, false, new LineLengthGrid(), []),
        new LayoutFixture("lookahead-future-push-in", "中文中文中文。", new LayoutConstraints(60),
            "Forces a PushIn repair inside lookahead's future lines; lookahead should score that cheap repair instead of adding an earlier break.", null, [],
            [], RubyLineHeightMode.PerLine, 0, true, false, new LineLengthGrid(), []),
        new LayoutFixture("lookahead-avoids-repair", "中文中文中文。", new LayoutConstraints(48),
            "At width 48 greedy ends up with a CarryPrevious repair on the last line; lookahead shifts the first break earlier to avoid the conflict entirely.",
            null, [], [], RubyLineHeightMode.PerLine, 0, true, false, new LineLengthGrid(), []),
        new LayoutFixture("justify-cjk-paragraph", "中文中文中文中文中文中文", new LayoutConstraints(100),
            "Justification fills the small deficit on the first line by adding CjkInterChar glue between adjacent CJK clusters.", null, [], [],
            RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("justify-mixed-paragraph", "中文Hello中文，世界。", new LayoutConstraints(144),
            "Justification uses CjkLatinSpace at the CJK↔Latin boundary plus PunctuationGlue if a spacing reduction landed on the line.", null, [], [],
            RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("justify-unbreakable-number-symbol", "中文50℃中文中文中文Example", new LayoutConstraints(128),
            "CLREQ stretch prohibition: the inseparable 50|℃ boundary stays closed while other legal gaps justify the line.", null, [], [],
            RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(false), []),
        new LayoutFixture("ascii-brackets-in-cjk", "中文段落(English)和[mixed]说明。", new LayoutConstraints(240),
            "ASCII (, ), [, ] do not share code points with the CJK fullwidth forms （）【】, so they always classify as Latin. (English) and [mixed] cluster as Latin runs and render in latin-primary even when surrounded by CJK content.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("ascii-point-mark-in-cjk", "中文中文,中文", new LayoutConstraints(64),
            "AttachedAsciiPointMarkKinsoku: a directly attached ASCII comma keeps its Latin face and proportional advance, but cannot start a wrapped Chinese line. The structured contextual-kinsoku decision explains the exception without creating CJK punctuation glue.",
            null, [], [], RubyLineHeightMode.PerLine, 0, true, false, new LineLengthGrid(), []),
        new LayoutFixture("ascii-point-mark-impossible-measure", "中,文", new LayoutConstraints(15),
            "AttachedAsciiPointMarkImpossibleMeasureHang: when even the preceding character plus its attached Latin comma cannot fit, the applied contextual fallback hangs the comma instead of accepting it at line start. The ordinary profile hanging policy remains disabled.",
            null, [], [], RubyLineHeightMode.PerLine, 0, true, false, new LineLengthGrid(), []),
        new LayoutFixture("real-paragraph-1",
            "咖啡（coffee）在十七世纪经威尼斯传入欧洲。最初它被当作药物出售，价格高得吓人，真正让它流行起来的是随后遍地开花的咖啡馆——读报、辩论、下棋、写作——城市生活忽然多出一个公共客厅。意大利人做出了 espresso，维也纳人往杯里加奶油，土耳其人坚持连渣同煮……每座城市都相信自己手里那一杯才是正统。有人说：「先有咖啡馆，后有启蒙运动」。这话说得夸张，但也不算太离谱。",
            new LayoutConstraints(320),
            "Real-text stress test: ~200 chars of authentic Chinese with Latin words, fullwidth/halfwidth brackets, em-dash pair, ellipsis, Chinese quotes, and multiple comma-stop sequences. Triggers multi-line greedy + justification + adjacent punctuation compression simultaneously. Uses the standard 2em 段首缩进 like real body text.",
            null, [], [], RubyLineHeightMode.PerLine, 2, false, false, new LineLengthGrid(), []),
        new LayoutFixture("latin-word-wrap", "他引用了一句话：The quick brown fox jumps over the lazy dog，然后继续讲。", new LayoutConstraints(240),
            "LatinWordSegmentation: the English sentence wraps at word boundaries instead of overflowing as one unbreakable cluster; spaces collapse at line edges; word spaces stretch under justify.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("emphasis-marks", "他强调：豆子新鲜最要紧，烘焙其次。", new LayoutConstraints(128),
            "CLREQ emphasis dots (着重号): span covers 豆子新鲜最要紧，烘焙其次 including the comma — Han text gets a dot anchor, punctuation is skipped per CLREQ. Narrow measure wraps the span across lines; lineHeight 25.6px (1.6×16) leaves room for the dots below the em box.",
            25.6, [new DecorationSpan(new TextRange(4, 16), DecorationKind.Emphasis),], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(),
            []),
        new LayoutFixture("ruby-line-height", "甲乙丙丁戊己庚辛壬癸子丑", new LayoutConstraints(64),
            "ConditionalRubyLineHeight: an 18px line leaves only 2px above the 16px base face, so the 8px pinyin box adds the 6px deficit only before its annotated line in the default PerLine mode.",
            18, [], [new RubySpan(new TextRange(4, 5), "wù")], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("bopomofo-tone-em-box", "好", new LayoutConstraints(64),
            "BopomofoToneSharedAnnotationEmSizing: the ordinary tone mark shares the 0.3em annotation size; its 5×5 slot only positions it, and glyph ink does not rescale it.",
            null, [], [new RubySpan(new TextRange(0, 1), "ㄏㄠˇ", RubyKind.Bopomofo),], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("first-line-indent", "咖啡的风味因产地而各异，烘焙的深浅同样会改变口感与香气。", new LayoutConstraints(200),
            "段首缩进: first line indents 2em (CLREQ standard) — its usable measure shrinks to maxWidth-2em and the LineBox carries the indent; later lines use the full measure. Justify targets the indented measure on line 0.",
            null, [], [], RubyLineHeightMode.PerLine, 2, false, false, new LineLengthGrid(), []),
        new LayoutFixture("latin-camelcase", "用PowerPoint做", new LayoutConstraints(128),
            "CamelCaseBreak: a camelCase token wraps at its hump (Power|Point) with NO hyphen — the capital signals the break. All-caps abbreviations (NASA) and single Title-case words are NOT treated this way.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("latin-existing-hyphen", "out-of-the-way", new LayoutConstraints(128),
            "ExistingHyphenBreak (CY/T 154-2017 §9.3): a hyphenated compound wraps AT its existing '-' (no new hyphen, no synthetic 短横线 atom). Keeps ≥2 letters each side (§9.4).",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("latin-hard-break", "中Network", new LayoutConstraints(64),
            "LatinForcedHyphenBreak (ADR 0029): with NO hyphenator (default), an over-long Latin word still hard-breaks at character boundaries with a hanging hyphen, keeping 前二后三 — 'Ne' head, 'ork' tail.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("latin-opaque-url-token", "链接 https://example.com/path/to/abc123def456ghi789", new LayoutConstraints(160),
            "LatinOpaqueTokenBreak (ADR 0029): URL / identifier-like Latin runs break at clean separator or character boundaries without adding a synthetic hyphen.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("zero-width-space-soft-break", "A.\u200B.\u200B.Complete？AaFont？", new LayoutConstraints(96),
            "UAX #14 ZW: U+200B is a source-faithful zero-width soft break control. It is not shaped, never creates a blank visual line, and does not weaken the visible-zero-advance capability guard.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("western-hyphenation", "请运行 internationalization 命令", new LayoutConstraints(160),
            "LineEndHangingHyphen (ADR 0029): the long English word is split at en-US syllable points so it wraps inside the measure; a hyphen is reserved inside the line when possible, and only hangs when it cannot fit. The 'hyphen=' line tag marks where. Needs the injected English hyphenator.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, true, new LineLengthGrid(), []),
        new LayoutFixture("progressive-technical-inline", "中文 internationalization 命令", new LayoutConstraints(160),
            "ProgressiveTechnicalBreak: semantic link/code text uses structural, letter-digit, camel, then syllable boundaries without a displayed hyphen. Ordinary paragraph opportunities remain first; only an otherwise unfillable auto-wrapped technical line uses explicit grapheme tracking.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, true, new LineLengthGrid(),
            [new LineBreakSpan(new TextRange(3, 23), LineBreakPolicy.ProgressiveTechnical),]),
        new LayoutFixture("progressive-technical-hash-fill", "deadbeefcafebabefeedfaceabcdefabcdef", new LayoutConstraints(173),
            "ExplicitEmergencyGraphemeTracking: a standalone technical hash skips syllable classification, hard-breaks at source graphemes, and exactly fills every non-last line. The final line remains naturally aligned.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, true, new LineLengthGrid(false),
            [new LineBreakSpan(new TextRange(0, 36), LineBreakPolicy.ProgressiveTechnical),]),
        new LayoutFixture("progressive-technical-alpha-numeric", "Machine2Machine", new LayoutConstraints(76),
            "TechnicalAlphaNumericTransitionBreak: the real-font report selects Machine2|Machine at the letter-digit structural boundary; the cut stays clean and adds no hyphen.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, true, new LineLengthGrid(false),
            [new LineBreakSpan(new TextRange(0, 15), LineBreakPolicy.ProgressiveTechnical),]),
        new LayoutFixture("progressive-technical-current-line-emergency",
            "Swift 这边是我最有体感的。JSONDecoder 慢是个老问题，SR-6252[36] 那个 issue 里挖出的根因是底层走 NSJSONSerialization 再桥接回 Objective-C，swift_dynamicCast 吃掉大量时间。",
            new LayoutConstraints(579),
            "CurrentLineTechnicalTierRejection: a technical token is reconsidered against the current line's stretch, regardless of whether the complete token fits a full measure. A clean tier that needs unbounded tracking is rejected; the hierarchy continues to a rightmost Emergency cut before terminal technical tracking is allowed.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(false),
            [
                new LineBreakSpan(new TextRange(16, 27), LineBreakPolicy.ProgressiveTechnical),
                new LineBreakSpan(new TextRange(67, 86), LineBreakPolicy.ProgressiveTechnical),
                new LineBreakSpan(new TextRange(104, 121), LineBreakPolicy.ProgressiveTechnical),
            ]),
        new LayoutFixture("adaptive-short-line-indent", "提椠是一个面向中文正文的排版引擎", new LayoutConstraints(160),
            "MeasureAdaptiveFirstLineIndent: with no explicit indent and a short measure (10 字 < 14), the段首缩进 default narrows to 1 字 (not 2). The firstindent decision line records measure/threshold/source.",
            null, [], [], RubyLineHeightMode.PerLine, null, false, false, new LineLengthGrid(), []),
        new LayoutFixture("mandatory-single-newline", "第一行\n第二行", new LayoutConstraints(160),
            "ADR 0037: a single source newline is a mandatory break, zero-width and unshaped.", null, [], [], RubyLineHeightMode.PerLine, 0, false, false,
            new LineLengthGrid(), []),
        new LayoutFixture("mandatory-blank-lines", "甲\n\n乙\n", new LayoutConstraints(160),
            "ADR 0037: consecutive and trailing mandatory breaks preserve blank lines.", null, [], [], RubyLineHeightMode.PerLine, 0, false, false,
            new LineLengthGrid(), []),
        new LayoutFixture("mandatory-leading-trailing-newline", "\n开头和结尾\n", new LayoutConstraints(160),
            "ADR 0037: leading and trailing mandatory breaks produce visible empty lines.", null, [], [], RubyLineHeightMode.PerLine, 0, false, false,
            new LineLengthGrid(), []),
        new LayoutFixture("mandatory-crlf", "甲\r\n乙", new LayoutConstraints(160), "ADR 0037: CRLF is one mandatory break cluster, not two blank lines.", null,
            [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("mandatory-wraps-long-line", "中文中文中文中文中文\n尾行", new LayoutConstraints(64),
            "ADR 0037: long source lines still auto-wrap before the mandatory break; mandatory-break lines are not justified.", null, [], [],
            RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("indent-opening-quote", "“好咖啡要趁热喝。”他说完便把杯子推了过来，让大家依次尝一口。", new LayoutConstraints(192),
            "段首缩进 composed with an opening quote at paragraph start: the additive model's line-start leading-glue trim halves the quote (CLREQ 缩减该符号始侧二分之一个汉字大小的空白) — visual blank before the quote ink is exactly the 2em indent.",
            null, [], [], RubyLineHeightMode.PerLine, 2, false, false, new LineLengthGrid(), []),
        new LayoutFixture("line-end-kinsoku", "中文中文（中文）中文", new LayoutConstraints(80),
            "CLREQ 行尾禁则 (Basic): 开括号不得居行尾. maxWidth 80 (5字) would end line 0 on （ — the break retreats so （ starts line 1 (CarryNext, cascade-free). Pinned Fixed(Basic) so the measure doesn't auto-escalate.",
            null, [], [], RubyLineHeightMode.PerLine, 0, true, false, new LineLengthGrid(), []),
        new LayoutFixture("interlinear-lines", "屈原写下离骚，顾炎武王夫之并称。", new LayoutConstraints(224),
            "行间线 (ADR 0024): 专名号 underlines 屈原/顾炎武/王夫之, 书名号甲式 wavy line under 离骚. 顾炎武 and 王夫之 are adjacent — AdjacentInterlinearLineShortening pulls each adjacent edge back 1/16em so the two marks read separately. No explicit lineHeight: InterlinearMarkLineSpacingFloor raises the line height to 1.5em.",
            null, [
                new DecorationSpan(new TextRange(0, 2), DecorationKind.ProperNoun),
                new DecorationSpan(new TextRange(4, 6), DecorationKind.BookTitle),
                new DecorationSpan(new TextRange(7, 10), DecorationKind.ProperNoun),
                new DecorationSpan(new TextRange(10, 13), DecorationKind.ProperNoun),
            ],
            [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("mourning-frame", "悼念：王小明同志、张大同同志。", new LayoutConstraints(72),
            "示亡号 (mourning frames) around 王小明 and 张大同. maxWidth 72 would naturally break inside 王小明 — MourningSpanKeptUnbroken moves the break to the span start instead. Frame rects hug the font-declared character face; the InterlinearMarkLineSpacingFloor (0.5em) keeps frames clear of neighbouring lines without an explicit lineHeight.",
            null, [
                new DecorationSpan(new TextRange(3, 6), DecorationKind.Mourning),
                new DecorationSpan(new TextRange(9, 12), DecorationKind.Mourning),
            ],
            [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("contextual-dash-ellipsis", "中文—下句；等…真。 English — next; ellipsis… / slash. A——B; Wait……what? 中文—English\n——中文\n……",
            new LayoutConstraints(1024),
            "ContextualDashEllipsisRoleResolution uses surrounding strong script, not mark count: single CJK marks retain CJK geometry while repeated Western marks stay on the Latin face in their own clusters (ContextualDashEllipsisRunSegmentation). The tail exercises conflicting-surrounding-script (中文—English), mandatory-break truncation with only-right evidence (——中文), and the no-context paragraph-language fallback (……).",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("parenthetical-dash-pairs", "他彻夜想Jessica——Jessica是他的前女友——睡不着觉。地点——北京，时间——明天。", new LayoutConstraints(1024),
            "ParentheticalDashPairContext: the Jessica insertion pair resolves jointly from the outer context (conflict -> paragraph language -> CJK two-em dashes) even though the first run sits between Latin words; the second sentence's runs are separated by a comma, stay independent, and resolve from their own surroundings.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
        new LayoutFixture("quote-digit-boundaries", "中文 le“t”ters 中1“1”2文；中Ａ“Ｂ”Ｃ文。尾号是“1‘2’3”，用时1’30”。", new LayoutConstraints(1024),
            "Non-CJK word-internal quote boundaries: le“t”ters keeps NonCjkWordInternalQuotePair on the Latin face; digit (中1“1”2文) and fullwidth (中Ａ“Ｂ”Ｃ文) boundaries stay excluded and resolve CJK; the digit-bounded single pair in “1‘2’3” inherits the enclosing CJK quotation; the unmatched marks in 1’30” resolve as NumericPrimeUnmatchedQuote on the Latin face.",
            null, [], [], RubyLineHeightMode.PerLine, 0, false, false, new LineLengthGrid(), []),
    ];
}
