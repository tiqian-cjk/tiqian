package org.tiqian.shaping.android.nativefont

import android.annotation.TargetApi
import android.graphics.Typeface
import android.graphics.fonts.Font
import android.graphics.fonts.FontStyle
import android.graphics.text.PositionedGlyphs
import android.graphics.text.TextRunShaper
import android.os.Build
import android.text.TextPaint
import org.tiqian.font.FontRole
import org.tiqian.shaping.ReplayableFontFaceRequest
import java.io.File
import java.util.Locale

/**
 * API 31+ system-default face oracle.
 *
 * Android does not expose Minikin's active family/fallback graph. Asking the
 * platform to shape the concrete selection text and reading the resulting
 * Font is the public source of truth. The native backend then replays that
 * exact file/index/axis instance with HarfBuzz and FreeType.
 */
@TargetApi(31)
internal object AndroidPlatformFontOracle {
    fun select(request: ReplayableFontFaceRequest): PlatformFontSelection {
        val selectionText = platformFaceProbeText(request)
        val paint = TextPaint().apply {
            isAntiAlias = true
            textSize = request.fontSize
            textLocale = Locale.forLanguageTag(request.locale)
            typeface = requestedTypeface(request)
        }
        val shaped = TextRunShaper.shapeTextRun(
            selectionText,
            0,
            selectionText.length,
            0,
            selectionText.length,
            0f,
            0f,
            false,
            paint,
        )
        val instances = (0 until shaped.glyphCount())
            .map { index -> shaped.platformInstance(index) }
            .distinctBy(PlatformGlyphInstance::instanceKey)
        check(instances.isNotEmpty()) {
            "PlatformFontSelectionEmpty: role=${request.role}; " +
                "requestText=${request.selectionText}; probeText=$selectionText"
        }
        // PlatformMultiFaceStringDrawDegrade: the platform legitimately itemizes some runs
        // across more than one physical face (a CJK base plus a combining mark its face lacks,
        // Thai/Arabic and other non-CJK scripts, or a Latin word crossing a fallback boundary).
        // No single controlled-byte face can replay those, so we keep the base (first) face for
        // metrics, record the platform-measured run advance, and flag the selection so the layout
        // backend defers this segment's measurement and drawing to the platform text stack.
        val spansMultipleFaces = instances.size > 1
        val instance = instances.first()
        val degradedRunAdvance = if (spansMultipleFaces) {
            paint.getRunAdvance(selectionText, 0, selectionText.length, 0, selectionText.length, false, selectionText.length)
        } else {
            0f
        }
        val font = instance.font
        return PlatformFontSelection(
            font = font,
            source = font.source(),
            collectionIndex = font.ttcIndex,
            variationAxes = instance.variationAxes,
            weight = if (instance.fakeBold) request.weight else instance.effectiveWeight,
            italic = instance.effectiveItalic || instance.fakeItalic,
            syntheticBold = instance.fakeBold,
            syntheticItalic = instance.fakeItalic,
            spansMultipleFaces = spansMultipleFaces,
            degradedRunAdvance = degradedRunAdvance,
            aliases = buildSet {
                addAll(request.preferredFamilies.filter(String::isNotBlank))
                font.file?.nameWithoutExtension?.takeIf(String::isNotBlank)?.let(::add)
                when (request.role) {
                    FontRole.LatinText, FontRole.CjkText, FontRole.CjkPunctuation -> {
                        add("sans")
                        add("sans-serif")
                    }
                    FontRole.Emoji -> add("emoji")
                    else -> add("system-default")
                }
            },
        )
    }

    fun bootstrapCatalogOrNull(): AndroidFontCatalog? = runCatching {
        val probes = listOf(
            FontRole.CjkText to "中",
            FontRole.CjkPunctuation to "。",
            FontRole.LatinText to "A",
        )
        val selections = probes.map { (role, text) ->
            role to select(
                ReplayableFontFaceRequest(
                    role = role,
                    preferredFamilies = mutableListOf(),
                    fontSize = 32f,
                    weight = 400,
                    italic = false,
                    locale = "zh-Hans",
                    selectionText = text,
                ),
            )
        }
        val specs = selections
            .groupBy { (_, selection) -> selection.instanceKey }
            .values
            .mapIndexed { index, group ->
                val selection = group.first().second
                AndroidFontFaceSpec(
                    source = selection.source,
                    collectionIndex = selection.collectionIndex,
                    familyKey = "platform-default-$index",
                    familyAliases = group.flatMapTo(linkedSetOf()) { it.second.aliases },
                    roles = group.mapTo(linkedSetOf()) { it.first },
                    weight = selection.weight,
                    italic = selection.italic,
                    variationAxes = selection.variationAxes,
                )
            }
        AndroidFontCatalog(
            faceSpecs = specs,
            sourceKind = "AndroidPlatformTextRunOracleApi31",
        )
    }.getOrNull()

    /** Import actual platform instances for a host family without disguising synthetic styles as real faces. */
    fun styleCatalogOrNull(): AndroidFontCatalog? = runCatching {
        val weightRanges = mutableMapOf<Pair<String, Int>, ClosedFloatingPointRange<Float>?>()
        val specs = listOf(FontRole.CjkText to "中", FontRole.LatinText to "A").flatMap { (role, probe) ->
            (100..900 step 100).flatMap { weight ->
                listOf(false, true).mapNotNull { italic ->
                    val selection = select(ReplayableFontFaceRequest(
                        role = role, preferredFamilies = mutableListOf("sans-serif"), fontSize = 32f,
                        weight = weight, italic = italic, locale = "zh-Hans", selectionText = probe,
                    ))
                    if (selection.syntheticBold || selection.syntheticItalic || selection.spansMultipleFaces) return@mapNotNull null
                    val font = selection.font
                    val key = (font.file?.absolutePath ?: "buffer:${font.sourceIdentifier}") to selection.collectionIndex
                    val weightRange = if (key in weightRanges) weightRanges[key] else {
                        physicalWeightRange(font).also { weightRanges[key] = it }
                    }
                    val physicalWeight = weightRange?.let { selection.weight.toFloat().coerceIn(it).toInt() }
                        ?: font.style.weight
                    val physicalAxes = selection.variationAxes - "wght" +
                        if (weightRange == null) emptyMap() else mapOf("wght" to physicalWeight.toFloat())
                    AndroidFontFaceSpec(
                        source = selection.source, collectionIndex = selection.collectionIndex,
                        familyKey = "platform-styles-${role.name}", familyAliases = selection.aliases,
                        roles = if (role == FontRole.CjkText) setOf(role, FontRole.CjkPunctuation) else setOf(role),
                        weight = physicalWeight, italic = selection.italic, variationAxes = physicalAxes,
                    )
                }
            }
        }.distinctBy { listOf(it.familyKey, it.source.label, it.collectionIndex, it.weight, it.italic, it.variationAxes) }
        check(specs.any { FontRole.CjkText in it.roles } && specs.any { FontRole.LatinText in it.roles })
        AndroidFontCatalog(faceSpecs = specs, sourceKind = "AndroidPlatformStyleInstancesApi31")
    }.getOrNull()

    /** Inspect the selected TTC face through the same FreeType bridge used for replay. */
    private fun physicalWeightRange(font: Font): ClosedFloatingPointRange<Float>? {
        val buffer = font.buffer.duplicate().apply { position(0) }
        val source = NativeFontBridge.nativeRegisterBufferSource(buffer, buffer.remaining().toLong())
        check(source != 0L) { "Cannot inspect the platform font source" }
        try {
            val face = NativeFontBridge.nativeCreateFace(source, font.ttcIndex, intArrayOf(), floatArrayOf())
            check(face != 0L) { "Cannot inspect the platform font face" }
            try {
                return NativeFontFace(face, NativeFontBridge.nativeUnitsPerEm(face)).axisRange("wght")
            } finally {
                NativeFontBridge.nativeReleaseFace(face)
            }
        } finally {
            NativeFontBridge.nativeReleaseSource(source)
        }
    }

    private fun requestedTypeface(request: ReplayableFontFaceRequest): Typeface {
        val family = request.preferredFamilies.firstOrNull(String::isNotBlank)
        return if (family == null) {
            Typeface.create(Typeface.DEFAULT, request.weight, request.italic)
        } else {
            Typeface.create(
                Typeface.create(family, Typeface.NORMAL),
                request.weight,
                request.italic,
            )
        }
    }

}

/**
 * Shared curly quotes and em dashes have glyphs in both Latin and CJK system fonts. Once the
 * paragraph classifier has assigned [FontRole.CjkPunctuation], probing the isolated mark would
 * discard that decision and let Android's Latin primary face win merely because it also covers
 * the code point. `CjkPunctuationHanFaceAnchor` therefore selects the concrete CJK face with the
 * same Han probe as [FontRole.CjkText]; the selected bytes then shape the original punctuation.
 */
internal fun platformFaceProbeText(request: ReplayableFontFaceRequest): String =
    when (request.role) {
        FontRole.CjkPunctuation -> "中"
        else -> request.selectionText.ifEmpty {
            when (request.role) {
                FontRole.CjkText -> "中"
                FontRole.LatinText -> "A"
                FontRole.Symbol -> "∑"
                FontRole.Emoji -> "😀"
                FontRole.Unknown -> "�"
                FontRole.CjkPunctuation -> error("handled above")
            }
        }
    }

@TargetApi(31)
internal data class PlatformFontSelection(
    val font: Font,
    val source: AndroidFontSource,
    val collectionIndex: Int,
    val variationAxes: Map<String, Float>,
    val weight: Int,
    val italic: Boolean,
    val syntheticBold: Boolean,
    val syntheticItalic: Boolean,
    /** True when the platform shaped the probe run across more than one physical face. */
    val spansMultipleFaces: Boolean = false,
    /** Platform-measured run advance for the degrade path; only meaningful when [spansMultipleFaces]. */
    val degradedRunAdvance: Float = 0f,
    val aliases: Set<String>,
) {
    val instanceKey: String = buildString {
        append(font.sourceIdentifier)
        append(':')
        append(font.file?.absolutePath)
        append(':')
        append(collectionIndex)
        append(':')
        append(variationAxes.entries.joinToString(",") { (tag, value) -> "$tag=${value.toRawBits()}" })
        append(":syntheticBold=")
        append(syntheticBold)
        append(":syntheticItalic=")
        append(syntheticItalic)
    }
}

@TargetApi(31)
private fun PositionedGlyphs.platformInstance(index: Int): PlatformGlyphInstance {
    val font = getFont(index)
    val overrides = if (Build.VERSION.SDK_INT >= 35) styleOverrides(index) else PlatformStyleOverrides()
    return PlatformGlyphInstance(
        font = font,
        variationAxes = applyPlatformStyleOverrides(font.effectiveVariationAxes(), overrides),
        effectiveWeight = (overrides.weight ?: font.style.weight.toFloat()).toInt().coerceIn(1, 1000),
        effectiveItalic = overrides.italic?.let { it > 0f }
            ?: (font.style.slant == FontStyle.FONT_SLANT_ITALIC),
        fakeBold = overrides.fakeBold,
        fakeItalic = overrides.fakeItalic,
    )
}

@TargetApi(35)
private fun PositionedGlyphs.styleOverrides(index: Int): PlatformStyleOverrides {
    fun valueOrNull(value: Float): Float? = value.takeUnless { it == PositionedGlyphs.NO_OVERRIDE }
    return PlatformStyleOverrides(
        weight = valueOrNull(getWeightOverride(index)),
        italic = valueOrNull(getItalicOverride(index)),
        fakeBold = getFakeBold(index),
        fakeItalic = getFakeItalic(index),
    )
}

internal data class PlatformStyleOverrides(
    val weight: Float? = null,
    val italic: Float? = null,
    val fakeBold: Boolean = false,
    val fakeItalic: Boolean = false,
)

internal fun applyPlatformStyleOverrides(
    fontAxes: Map<String, Float>,
    overrides: PlatformStyleOverrides,
): Map<String, Float> = fontAxes.toMutableMap().apply {
    overrides.weight?.let { this["wght"] = it }
    overrides.italic?.let { this["ital"] = it }
}.toSortedMap()

@TargetApi(31)
private data class PlatformGlyphInstance(
    val font: Font,
    val variationAxes: Map<String, Float>,
    val effectiveWeight: Int,
    val effectiveItalic: Boolean,
    val fakeBold: Boolean,
    val fakeItalic: Boolean,
) {
    val instanceKey: String = buildString {
        append(font.sourceIdentifier)
        append(':')
        append(font.file?.absolutePath)
        append(':')
        append(font.ttcIndex)
        append(':')
        append(variationAxes.entries.joinToString(",") { (tag, value) -> "$tag=${value.toRawBits()}" })
        append(":fakeBold=")
        append(fakeBold)
        append(":fakeItalic=")
        append(fakeItalic)
    }

}

@TargetApi(31)
private fun Font.source(): AndroidFontSource {
    file?.takeIf(File::isFile)?.let { file ->
        return AndroidFontSource.file(file, sourceLabel())
    }
    return AndroidFontSource.directBuffer(
        buffer.duplicate().apply { position(0) },
        sourceLabel(),
    )
}

@TargetApi(31)
private fun Font.effectiveVariationAxes(): Map<String, Float> =
    axes.orEmpty().associate { axis -> axis.tag to axis.styleValue }.toSortedMap()

@TargetApi(31)
private fun Font.sourceLabel(): String = buildString {
    append("PlatformTextRun:")
    append(file?.absolutePath ?: sourceIdentifier)
    append('#')
    append(ttcIndex)
    val axes = effectiveVariationAxes()
    if (axes.isNotEmpty()) {
        append(':')
        append(axes.entries.joinToString(",") { (tag, value) -> "$tag=$value" })
    }
}
