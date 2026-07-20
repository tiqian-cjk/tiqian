package org.tiqian.clreq

/**
 * 注音 声调 (ADR 0033). The author writes only the reading string; the engine
 * derives the tone — manual tone tagging would be a disaster.
 */
enum class BopomofoTone {
    /** 阴平 (1声) — no mark drawn, but reserves the same调号 space as the others. */
    Yinping,

    /** 阳平 (2声) `ˊ` — 平上去 group, drawn upper-right of the last symbol. */
    Yangping,

    /** 上声 (3声) `ˇ` — 平上去 group. */
    Shang,

    /** 去声 (4声) `ˋ` — 平上去 group. */
    Qu,

    /** 轻声 `˙` — prefixed, drawn at the top of the symbol column. */
    Neutral,

    /** 入声 (方音) — drawn lower-right. Geometry supported; v1 parser does not emit it. */
    Ru,
}

/** A parsed 注音 reading: 1–3 ㄅㄆㄇ symbols + the tone (ADR 0033). */
data class BopomofoReading(
    val symbols: List<String>,
    val tone: BopomofoTone,
)

/**
 * Parses a 注音 string into symbols + tone:
 * - leading `˙`(U+02D9) ⇒ 轻声 (rest are symbols);
 * - trailing `ˊ`/`ˇ`/`ˋ` ⇒ 阳平/上/去 (stripped); trailing `ˉ`(U+02C9) ⇒ explicit 阴平;
 * - otherwise ⇒ 阴平 (no mark).
 *
 * Each remaining char (U+3105–U+312F bopomofo) is one symbol — readings carry ≤3.
 * 入声 (方音) is not parsed in v1 (Mandarin 注音 has none).
 */
object BopomofoParser {
    private const val NEUTRAL = '˙' // ˙ 轻声
    private const val YANGPING = 'ˊ' // ˊ
    private const val SHANG = 'ˇ' // ˇ
    private const val QU = 'ˋ' // ˋ
    private const val YINPING_MACRON = 'ˉ' // ˉ explicit 阴平

    fun parse(reading: String): BopomofoReading {
        if (reading.isEmpty()) return BopomofoReading(emptyList(), BopomofoTone.Yinping)
        if (reading[0] == NEUTRAL) {
            return BopomofoReading(symbolsOf(reading.substring(1)), BopomofoTone.Neutral)
        }
        val tone = when (reading.last()) {
            YANGPING -> BopomofoTone.Yangping
            SHANG -> BopomofoTone.Shang
            QU -> BopomofoTone.Qu
            else -> BopomofoTone.Yinping
        }
        val hasSuffixMark = reading.last() in charArrayOf(YANGPING, SHANG, QU, YINPING_MACRON)
        val body = if (hasSuffixMark) reading.dropLast(1) else reading
        return BopomofoReading(symbolsOf(body), tone)
    }

    private fun symbolsOf(body: String): List<String> = body.map { it.toString() }
}
