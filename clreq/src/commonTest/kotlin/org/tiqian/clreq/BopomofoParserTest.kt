package org.tiqian.clreq

import kotlin.test.Test
import kotlin.test.assertEquals

/** 注音 tone parsing (ADR 0033): engine derives tone + symbols from the reading. */
class BopomofoParserTest {

    @Test
    fun yinpingHasNoMark() {
        val r = BopomofoParser.parse("ㄓㄨㄥ")
        assertEquals(listOf("ㄓ", "ㄨ", "ㄥ"), r.symbols)
        assertEquals(BopomofoTone.Yinping, r.tone)
    }

    @Test
    fun suffixMarksAreToneAndStripped() {
        assertEquals(BopomofoReading(listOf("ㄔ", "ㄤ"), BopomofoTone.Yangping), BopomofoParser.parse("ㄔㄤˊ"))
        assertEquals(BopomofoReading(listOf("ㄋ", "ㄧ"), BopomofoTone.Shang), BopomofoParser.parse("ㄋㄧˇ"))
        assertEquals(BopomofoReading(listOf("ㄑ", "ㄩ"), BopomofoTone.Qu), BopomofoParser.parse("ㄑㄩˋ"))
        // explicit 阴平 macron is stripped too
        assertEquals(BopomofoReading(listOf("ㄇ", "ㄚ"), BopomofoTone.Yinping), BopomofoParser.parse("ㄇㄚˉ"))
    }

    @Test
    fun neutralToneIsPrefixed() {
        val r = BopomofoParser.parse("˙ㄉㄜ")
        assertEquals(listOf("ㄉ", "ㄜ"), r.symbols)
        assertEquals(BopomofoTone.Neutral, r.tone)
    }

    @Test
    fun singleSymbol() {
        assertEquals(BopomofoReading(listOf("ㄦ"), BopomofoTone.Yangping), BopomofoParser.parse("ㄦˊ"))
    }
}
