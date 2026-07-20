package org.tiqian.clreq

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * CLREQ 第六节行首行尾禁则四档（[KinsokuLevel]）的逐档收紧验证。
 * 命名与原文对齐：不处理 / 基本处理(最推荐) / GB 法 / 严格处理。
 */
class KinsokuLevelTest {
    private fun start(char: Char, level: KinsokuLevel) =
        ClreqPunctuationPolicies.forbiddenAtLineStart(char, level)

    private fun end(char: Char, level: KinsokuLevel) =
        ClreqPunctuationPolicies.forbiddenAtLineEnd(char, level)

    @Test
    fun noneForbidsNothing() {
        for (c in listOf('。', '，', '、', '”', '）', '·', '／', '—', '…', '“', '（')) {
            assertFalse(start(c, KinsokuLevel.None), "$c start@None")
            assertFalse(end(c, KinsokuLevel.None), "$c end@None")
        }
    }

    @Test
    fun basicForbidsPauseStopsClosingConnectorsAtStartAndOpeningAtEnd() {
        // 点号、结束引号/括号、连接号、间隔号、分隔号 不得居行首.
        for (c in listOf('。', '，', '、', '：', '；', '！', '？', '”', '）', '】', '·', '～', '／')) {
            assertTrue(start(c, KinsokuLevel.Basic), "$c start@Basic")
        }
        // 开始引号/括号 不得居行尾.
        for (c in listOf('“', '（', '《', '「', '【')) {
            assertTrue(end(c, KinsokuLevel.Basic), "$c end@Basic")
        }
        // 破折号、省略号 在基本处理下可居行首；分隔号 可居行尾.
        assertFalse(start('—', KinsokuLevel.Basic))
        assertFalse(start('…', KinsokuLevel.Basic))
        assertFalse(end('／', KinsokuLevel.Basic))
    }

    @Test
    fun gbStyleAddsSeparatorAtLineEnd() {
        // GB 法 = 基本处理 + 分隔号也不得居行尾.
        assertFalse(end('／', KinsokuLevel.Basic))
        assertTrue(end('／', KinsokuLevel.GbStyle))
        // 破折号、省略号 仍可居行首（GB 法尚未追加该禁则）.
        assertFalse(start('—', KinsokuLevel.GbStyle))
        assertFalse(start('…', KinsokuLevel.GbStyle))
    }

    @Test
    fun strictAddsDashAndEllipsisAtLineStart() {
        // 严格处理 = GB 法 + 破折号、省略号不得居行首.
        assertFalse(start('—', KinsokuLevel.GbStyle))
        assertTrue(start('—', KinsokuLevel.Strict))
        assertTrue(start('…', KinsokuLevel.Strict))
        assertTrue(start('⋯', KinsokuLevel.Strict))
        // 仍保留 GB 法的分隔号行尾禁则.
        assertTrue(end('／', KinsokuLevel.Strict))
    }

    @Test
    fun profileDefaultsToMeasureAdaptive() {
        assertTrue(ClreqProfile.MainlandHorizontal.kinsokuMode is KinsokuMode.MeasureAdaptive)
    }

    @Test
    fun cjkBracketVariantsClassifyAsOpeningAndClosing() {
        for (c in listOf('【', '〔', '〖', '〘', '〚')) {
            assertEquals(PunctuationClass.Opening, ClreqPunctuationPolicies.classify(c), "$c")
        }
        for (c in listOf('】', '〕', '〗', '〙', '〛')) {
            assertEquals(PunctuationClass.Closing, ClreqPunctuationPolicies.classify(c), "$c")
        }
    }

    @Test
    fun exposesUnambiguousAsciiPointMarksWithoutGuessingQuotesOrConnectors() {
        for (c in listOf(',', '.', ':', ';', '!', '?')) {
            assertTrue(ClreqPunctuationPolicies.isAsciiPointMark(c), "$c point mark")
        }
        for (c in listOf('"', '\'', '-', '/', '~', '%')) {
            assertFalse(ClreqPunctuationPolicies.isAsciiPointMark(c), "$c excluded")
        }
    }

    @Test
    fun measureAdaptiveResolvesPerLineWidth() {
        val m = KinsokuMode.MeasureAdaptive()
        // < 14 字：基本处理 + 悬挂.
        m.resolve(10f).let {
            assertEquals(KinsokuLevel.Basic, it.level)
            assertEquals(HangingPunctuationStyle.PauseStops, it.hanging)
        }
        // 14–24 字：基本处理，无悬挂.
        m.resolve(20f).let {
            assertEquals(KinsokuLevel.Basic, it.level)
            assertEquals(HangingPunctuationStyle.Disabled, it.hanging)
        }
        // > 24 字：GB 法.
        assertEquals(KinsokuLevel.GbStyle, m.resolve(28f).level)
        // > 32 字：严格处理.
        assertEquals(KinsokuLevel.Strict, m.resolve(40f).level)
    }
}
