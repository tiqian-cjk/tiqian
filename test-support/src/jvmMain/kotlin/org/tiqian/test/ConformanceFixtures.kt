package org.tiqian.test

import java.io.File
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSpan
import org.tiqian.core.LastLineAlignment
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LineBreakPolicy
import org.tiqian.core.LineBreakSpan
import org.tiqian.core.LineLengthGrid
import org.tiqian.core.RubyKind
import org.tiqian.core.RubyLineHeightMode
import org.tiqian.core.RubySpan
import org.tiqian.core.TextRange

/**
 * Language-neutral conformance fixture wire format (the JSON files under `conformance/fixtures`).
 * The JSON files are the single source of truth shared with non-Kotlin engine
 * implementations; this loader maps them onto [LayoutFixture]. Schema changes go
 * through `conformance/SPEC.md` and a reviewed dump diff, like any golden change.
 */
@Serializable
data class ConformanceFixtureDto(
    val schema: Int,
    val id: String,
    val text: String,
    val maxWidth: Float,
    val maxHeight: Float? = null,
    val maxLines: Int? = null,
    val notes: String = "",
    val lineHeight: Float? = null,
    val decorations: List<SpanDto> = emptyList(),
    val rubySpans: List<RubyDto> = emptyList(),
    val rubyLineHeightMode: String = RubyLineHeightMode.PerLine.name,
    val firstLineIndentEm: Float? = 0f,
    /** Mirrors [LayoutFixture.firstLineIndentEm]'s null contract explicitly in JSON. */
    val firstLineIndentDefault: Boolean = false,
    val pinBasicNoHang: Boolean = false,
    val useEnglishHyphenation: Boolean = false,
    val lineLengthGridEnabled: Boolean = true,
    val lineLengthGridBodyAlignment: String? = null,
    val lineBreakSpans: List<LineBreakSpanDto> = emptyList(),
)

@Serializable
data class SpanDto(val start: Int, val end: Int, val kind: String)

@Serializable
data class RubyDto(
    val start: Int,
    val end: Int,
    val text: String,
    val fontFamilies: List<String> = emptyList(),
    val kind: String = RubyKind.Pinyin.name,
    val locale: String? = null,
    val localeExplicit: Boolean = false,
)

@Serializable
data class LineBreakSpanDto(val start: Int, val end: Int, val policy: String)

object ConformanceFixtures {
    const val SCHEMA_VERSION: Int = 1

    private val json = Json {
        prettyPrint = true
        prettyPrintIndent = "  "
        encodeDefaults = false
    }

    fun defaultDirectory(): File = File("../conformance/fixtures")

    fun loadAll(directory: File = defaultDirectory()): List<LayoutFixture> {
        val files = directory.listFiles { file -> file.extension == "json" }
            ?.sortedBy { it.name }
            ?: error("Conformance fixture directory not found: ${directory.absolutePath}")
        check(files.isNotEmpty()) { "No conformance fixtures in ${directory.absolutePath}" }
        return files.map { file ->
            val dto = json.decodeFromString<ConformanceFixtureDto>(file.readText())
            check(dto.schema == SCHEMA_VERSION) {
                "${file.name}: schema ${dto.schema} != supported $SCHEMA_VERSION"
            }
            dto.toFixture()
        }
    }

    fun export(fixtures: List<LayoutFixture>, directory: File) {
        directory.mkdirs()
        for (fixture in fixtures) {
            File(directory, "${fixture.id}.json")
                .writeText(json.encodeToString(fixture.toDto()) + "\n")
        }
    }

    private fun ConformanceFixtureDto.toFixture(): LayoutFixture = LayoutFixture(
        id = id,
        text = text,
        constraints = LayoutConstraints(
            maxWidth = maxWidth,
            maxHeight = maxHeight ?: Float.POSITIVE_INFINITY,
            maxLines = maxLines ?: Int.MAX_VALUE,
        ),
        notes = notes,
        lineHeight = lineHeight,
        decorations = decorations.map {
            DecorationSpan(TextRange(it.start, it.end), DecorationKind.valueOf(it.kind))
        },
        rubySpans = rubySpans.map { ruby ->
            val kind = RubyKind.valueOf(ruby.kind)
            if (ruby.localeExplicit) {
                RubySpan(TextRange(ruby.start, ruby.end), ruby.text, ruby.fontFamilies, kind, ruby.locale)
            } else {
                RubySpan(TextRange(ruby.start, ruby.end), ruby.text, ruby.fontFamilies, kind)
            }
        },
        rubyLineHeightMode = RubyLineHeightMode.valueOf(rubyLineHeightMode),
        firstLineIndentEm = if (firstLineIndentDefault) null else firstLineIndentEm,
        pinBasicNoHang = pinBasicNoHang,
        useEnglishHyphenation = useEnglishHyphenation,
        lineLengthGrid = LineLengthGrid(
            enabled = lineLengthGridEnabled,
            bodyAlignment = lineLengthGridBodyAlignment?.let(LastLineAlignment::valueOf),
        ),
        lineBreakSpans = lineBreakSpans.map {
            LineBreakSpan(TextRange(it.start, it.end), LineBreakPolicy.valueOf(it.policy))
        },
    )

    private fun LayoutFixture.toDto(): ConformanceFixtureDto = ConformanceFixtureDto(
        schema = SCHEMA_VERSION,
        id = id,
        text = text,
        maxWidth = constraints.maxWidth,
        maxHeight = constraints.maxHeight.takeIf { it != Float.POSITIVE_INFINITY },
        maxLines = constraints.maxLines.takeIf { it != Int.MAX_VALUE },
        notes = notes,
        lineHeight = lineHeight,
        decorations = decorations.map { SpanDto(it.range.start, it.range.end, it.kind.name) },
        rubySpans = rubySpans.map { ruby ->
            val defaultLocale = if (ruby.kind == RubyKind.Bopomofo) "zh-TW" else null
            RubyDto(
                start = ruby.baseRange.start,
                end = ruby.baseRange.end,
                text = ruby.text,
                fontFamilies = ruby.fontFamilies,
                kind = ruby.kind.name,
                locale = ruby.locale,
                localeExplicit = ruby.locale != defaultLocale,
            )
        },
        rubyLineHeightMode = rubyLineHeightMode.name,
        firstLineIndentEm = firstLineIndentEm ?: 0f,
        firstLineIndentDefault = firstLineIndentEm == null,
        pinBasicNoHang = pinBasicNoHang,
        useEnglishHyphenation = useEnglishHyphenation,
        lineLengthGridEnabled = lineLengthGrid.enabled,
        lineLengthGridBodyAlignment = lineLengthGrid.bodyAlignment?.name,
        lineBreakSpans = lineBreakSpans.map {
            LineBreakSpanDto(it.range.start, it.range.end, it.policy.name)
        },
    )
}
