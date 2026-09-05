package org.tiqian.core;

@:dataClass
class ParagraphStyle {
    // Alignment of the paragraph's LAST line only. CLREQ:「与西文排版不同，
    // 中文排版特别是书籍正文排版极少使用左齐右不齐，原则上应该进行两端
    // 对齐」— justification is the baseline behaviour, not an option: every
    // non-last line is always justified (挤压/拉伸已使行长一致). The only
    // degree of freedom is the last line — start (default), centered, or
    // end-aligned (落款、引文出处等特殊用法). A single-line paragraph is its
    // `CjkBodyLineHeightDefault` (1.5em — 中文正文 leading). A value overrides
    // no-overlap minimum (字面 + any [InterlinearMarkLineSpacingFloor]) — a line
    // To set 1.5× of a 16px font, pass `24f`, not `1.5f`.
    // （CLREQ「段首缩排以两个汉字的空间为标准」，窄行缩一字）。The indent
    // ADR 0018 sets the default 净空 in em between the lower edge of the marked 字面 and the 着重号.
    // The explicit 段首缩进 override uses `ic` (字身框, ADR 0034), and `0.ic` disables it.
    // A null value means that no explicit value is specified, so firstLineIndentPolicy resolves it from the 行长.
    // The opening punctuation rule reduces the leading space required by CLREQ.
    // The 段落缩排 value applies to every line, uses `ic`, and combines with the first-line value.
    // It is added to the first-line value relative to the paragraph inset, so a negative value can express 凸排.
    // Each line's effective inset is the paragraph inset plus its first-line part, with a lower bound of zero.
    // The default 段首缩进 policy applies only when the explicit first-line value is null.
    // The 行长 grid quantizes the available width to an integer multiple of 字号.
    // The 拼音 ruby 行高 policy first uses existing leading to contain the 注文.
    // When the existing space is sufficient, both modes leave the 行盒 unchanged.
    // PerLine adds height only to lines carrying 拼音; UniformParagraph applies the same increment to every line.
    // The right-side 注音 path does not use this policy.
    // An inline object that exceeds the 正文 face keeps a minimum 净空 from visible content on the adjacent line.
    // The object first uses space supplied by the 正文 行高, and the line must retain clearance between upper and lower 墨迹.
    // Only the missing part of the intrusion plus this 净空 is added; the default is 0.1em and zero disables it.
    // The 着重号 dot keeps an explicit 净空 from the lower edge of the marked 字面, measured in em.
    // CLREQ places the 着重号 at the bottom in 横排 but does not set the exact distance from the 字面.
    // The distance is a style value, and the engine positions the dot from each cluster's real 字面 metrics.
    // A larger 行高 provides more room but does not move the 着重号; the default comes from DEFAULT_EMPHASIS_DOT_GAP_EM.
    // The MeasureAdaptiveFirstLineIndent policy changes 段首缩进 with the available line length.
    // A 窄行, where the measure is below shortBelowEm 字, uses shortEm; a 宽行 uses longEm.
    // In a 窄栏, a two 字 缩进 can occupy too much of the line, so 多栏 layouts often use one 字.
    // The threshold is 14 字 and is independent of the 悬挂 threshold used by MeasureAdaptiveKinsoku.
    // These policies answer different questions: 悬挂 concerns the placement of a whole glyph, while 缩进 concerns the amount of inset.
    // The policy remains active with KinsokuMode.Fixed and does not depend on a 悬挂 signal.
    // A fixed 段首缩进 is selected with ParagraphStyle.firstLineIndent and can include zero to disable it.
    // The 行长 grid floors the available width to an integer multiple of 字号 so the 正文 occupies complete 字格 cells.
    // Responsive containers rarely have a width that is an exact multiple of 字号, so the remaining slack is placed by bodyAlignment.
    // The quantized 正文 block can be aligned inside the container by Start, Center, or End.
    // Known pixel-aligned widths and non-CJK text can set enabled to false and use the original maxWidth.
    // The 正文 block alignment controls the quantized remainder; the 双齐 paragraph still uses lastLineAlignment for its last line.
    // The default body alignment follows ParagraphStyle.lastLineAlignment and can be overridden independently.
    public static final DEFAULT_EMPHASIS_DOT_GAP_EM:Float = 0.1;
    public static final DEFAULT_INLINE_OBJECT_MINIMUM_CLEARANCE_EM:Float = 0.1;

    public final lastLineAlignment:LastLineAlignment;
    public final writingMode:WritingMode;
    public final lineHeight:Null<Float>;
    public final firstLineIndent:Null<Ic>;
    public final blockIndent:Ic;
    public final firstLineIndentPolicy:MeasureAdaptiveFirstLineIndent;
    public final lineLengthGrid:LineLengthGrid;
    public final rubyLineHeightMode:RubyLineHeightMode;
    public final inlineObjectMinimumClearanceEm:Float;
    public final emphasisDotGapEm:Float;

    public function new(?lastLineAlignment:Null<LastLineAlignment>, ?writingMode:Null<WritingMode>, ?lineHeight:Null<Float>, ?firstLineIndent:Null<Ic>,
            ?blockIndent:Null<Ic>, ?firstLineIndentPolicy:Null<MeasureAdaptiveFirstLineIndent>, ?lineLengthGrid:Null<LineLengthGrid>,
            ?rubyLineHeightMode:Null<RubyLineHeightMode>, ?inlineObjectMinimumClearanceEm:Null<Float>, ?emphasisDotGapEm:Null<Float>) {
        this.lastLineAlignment = lastLineAlignment == null ? LastLineAlignment.Start : lastLineAlignment;
        this.writingMode = writingMode == null ? WritingMode.HorizontalTb : writingMode;
        this.lineHeight = lineHeight == null ? null : lineHeight;
        this.firstLineIndent = firstLineIndent == null ? null : firstLineIndent;
        this.blockIndent = blockIndent == null ? Ic.Zero : blockIndent;
        this.firstLineIndentPolicy = firstLineIndentPolicy == null ? new MeasureAdaptiveFirstLineIndent() : firstLineIndentPolicy;
        this.lineLengthGrid = lineLengthGrid == null ? new LineLengthGrid() : lineLengthGrid;
        this.rubyLineHeightMode = rubyLineHeightMode == null ? RubyLineHeightMode.PerLine : rubyLineHeightMode;
        this.inlineObjectMinimumClearanceEm = inlineObjectMinimumClearanceEm == null ? ParagraphStyle.DEFAULT_INLINE_OBJECT_MINIMUM_CLEARANCE_EM : inlineObjectMinimumClearanceEm;
        this.emphasisDotGapEm = emphasisDotGapEm == null ? ParagraphStyle.DEFAULT_EMPHASIS_DOT_GAP_EM : emphasisDotGapEm;
    }
}
