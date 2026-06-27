package org.tiqian.shaping.android

import android.graphics.fonts.Font
import java.util.IdentityHashMap
import java.util.LinkedHashMap

/**
 * Process-local bridge from Android TextRunShaper's concrete [Font] objects
 * to opaque keys stored on core Glyphs. Core/layout never interprets the key;
 * Android renderers use it only to draw the exact glyph ids produced during
 * shaping with Canvas.drawGlyphs. The bridge is intentionally bounded: if an
 * old key is evicted before rendering, the renderer falls back to contextual
 * string drawing for that cluster instead of retaining every platform Font for
 * the process lifetime.
 */
object AndroidPositionedGlyphFontRegistry {
    private const val MaxRetainedFonts = 512

    private val lock = Any()
    private val keyByFont = IdentityHashMap<Font, String>()
    private val fontByKey = object : LinkedHashMap<String, Font>(16, 0.75f, true) {}
    private var nextId = 1

    fun keyFor(font: Font): String = synchronized(lock) {
        keyByFont[font]?.also { key ->
            fontByKey[key] = font
            return@synchronized key
        }
        "android-font-${nextId++}".also { key ->
            keyByFont[font] = key
            fontByKey[key] = font
            trimLocked()
        }
    }

    fun fontFor(key: String): Font? = synchronized(lock) {
        fontByKey[key]
    }

    private fun trimLocked() {
        while (fontByKey.size > MaxRetainedFonts) {
            val entries = fontByKey.entries.iterator()
            if (!entries.hasNext()) return
            val (key, font) = entries.next()
            entries.remove()
            if (keyByFont[font] == key) {
                keyByFont.remove(font)
            }
        }
    }

    internal val maxRetainedFontCountForTesting: Int
        get() = MaxRetainedFonts

    internal fun retainedFontCountForTesting(): Int = synchronized(lock) {
        fontByKey.size
    }

    internal fun clearForTesting() = synchronized(lock) {
        keyByFont.clear()
        fontByKey.clear()
        nextId = 1
    }
}
