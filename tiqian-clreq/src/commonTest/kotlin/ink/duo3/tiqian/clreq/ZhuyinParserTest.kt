package ink.duo3.tiqian.clreq

import kotlin.test.Test
import kotlin.test.assertEquals

/** 注音 tone parsing (ADR 0033): engine derives tone + symbols from the reading. */
class ZhuyinParserTest {

    @Test
    fun yinpingHasNoMark() {
        val r = ZhuyinParser.parse("ㄓㄨㄥ")
        assertEquals(listOf("ㄓ", "ㄨ", "ㄥ"), r.symbols)
        assertEquals(ZhuyinTone.Yinping, r.tone)
    }

    @Test
    fun suffixMarksAreToneAndStripped() {
        assertEquals(ZhuyinReading(listOf("ㄔ", "ㄤ"), ZhuyinTone.Yangping), ZhuyinParser.parse("ㄔㄤˊ"))
        assertEquals(ZhuyinReading(listOf("ㄋ", "ㄧ"), ZhuyinTone.Shang), ZhuyinParser.parse("ㄋㄧˇ"))
        assertEquals(ZhuyinReading(listOf("ㄑ", "ㄩ"), ZhuyinTone.Qu), ZhuyinParser.parse("ㄑㄩˋ"))
        // explicit 阴平 macron is stripped too
        assertEquals(ZhuyinReading(listOf("ㄇ", "ㄚ"), ZhuyinTone.Yinping), ZhuyinParser.parse("ㄇㄚˉ"))
    }

    @Test
    fun neutralToneIsPrefixed() {
        val r = ZhuyinParser.parse("˙ㄉㄜ")
        assertEquals(listOf("ㄉ", "ㄜ"), r.symbols)
        assertEquals(ZhuyinTone.Neutral, r.tone)
    }

    @Test
    fun singleSymbol() {
        assertEquals(ZhuyinReading(listOf("ㄦ"), ZhuyinTone.Yangping), ZhuyinParser.parse("ㄦˊ"))
    }
}
