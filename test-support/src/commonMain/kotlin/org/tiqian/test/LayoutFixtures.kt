package org.tiqian.test

import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LineLengthGrid
import org.tiqian.core.LineBreakPolicy
import org.tiqian.core.LineBreakSpan
import org.tiqian.core.RubyKind
import org.tiqian.core.RubyLineHeightMode
import org.tiqian.core.RubySpan
import org.tiqian.core.TextRange

data class LayoutFixture(
    val id: String,
    val text: String,
    val constraints: LayoutConstraints,
    val notes: String,
    val lineHeight: Float? = null,
    val decorations: List<DecorationSpan> = emptyList(),
    val rubySpans: List<RubySpan> = emptyList(),
    val rubyLineHeightMode: RubyLineHeightMode = RubyLineHeightMode.PerLine,
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
     * syllable points with a displayed hyphen (`LineEndHangingHyphen`, ADR 0029).
     * Default off — the deterministic stub has no hyphenator.
     */
    val useEnglishHyphenation: Boolean = false,
    /** Disable the default integer-`ic` measure for fixtures that need an exact width. */
    val lineLengthGrid: LineLengthGrid = LineLengthGrid(),
    val lineBreakSpans: List<LineBreakSpan> = emptyList(),
)
