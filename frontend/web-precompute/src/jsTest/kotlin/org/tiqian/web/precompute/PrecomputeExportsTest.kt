@file:OptIn(kotlin.js.ExperimentalWasmJsInterop::class)

package org.tiqian.web.precompute

import kotlin.JsFun
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals

class PrecomputeExportsTest {
    @Test
    fun realLayoutPipelineUsesAndReleasesSynchronousNodeFontHandles() {
        installFixtureBackend()

        val json = precomputePlainParagraph(
            fontSessionId = "fixture-session",
            text = "中文中文",
            maxWidthPx = 36.0,
            fontFamilies = "Fixture CJK",
            fontSizePx = 18.0,
            lineHeightPx = 27.0,
            locale = "zh-Hans",
            fontWeight = 400,
            italic = false,
            firstLineIndentIc = 0.0,
            lineLengthGridEnabled = true,
        )

        assertContains(json, "\"layoutRevision\":\"tiqian-layout-v2\"")
        assertContains(json, "\"rangeStart\":0,\"rangeEnd\":2")
        assertContains(json, "\"rangeStart\":2,\"rangeEnd\":4")
        assertEquals("中|文|中|文", fixtureMetricSelectionTexts())
        assertEquals(0, fixtureHandleCount())
    }

    @Test
    fun unavailableMidlineEllipsisRollsBackToSourceEllipsis() {
        installEllipsisFallbackBackend()

        val json = precomputePlainParagraph(
            fontSessionId = "fixture-session",
            text = "……",
            maxWidthPx = 72.0,
            fontFamilies = "Fixture CJK",
            fontSizePx = 18.0,
            lineHeightPx = 27.0,
            locale = "zh-Hans",
            fontWeight = 400,
            italic = false,
            firstLineIndentIc = 0.0,
            lineLengthGridEnabled = true,
        )

        assertContains(json, "\"source\":\"……\",\"display\":\"……\"")
        assertEquals("⋯⋯←……|……←……", ellipsisFixtureShapeCalls())
        assertEquals(0, fixtureHandleCount())
    }
}

@JsFun(
    """() => {
      let nextHandle = 1;
      const shapes = new Map();
      const metrics = new Map();
      const metricSelectionTexts = [];
      globalThis.__tqPrecomputeFixtureHandles = { shapes, metrics, metricSelectionTexts };
      globalThis.__TiqianFontBackend = {
        shape(_session, displayText, _families, fontSize) {
          const handle = nextHandle++;
          const glyphs = [];
          let index = 0;
          for (const _point of displayText) {
            glyphs.push({
              id: 100 + index,
              advance: fontSize,
              x: index * fontSize,
              y: 0,
              bounds: [0, -fontSize * 0.88, fontSize, fontSize * 0.12],
            });
            index += 1;
          }
          shapes.set(handle, { glyphs, advance: glyphs.length * fontSize });
          return handle;
        },
        shapeGlyphCount: (handle) => shapes.get(handle).glyphs.length,
        shapeGlyphId: (handle, index) => shapes.get(handle).glyphs[index].id,
        shapeGlyphAdvance: (handle, index) => shapes.get(handle).glyphs[index].advance,
        shapeGlyphX: (handle, index) => shapes.get(handle).glyphs[index].x,
        shapeGlyphY: (handle, index) => shapes.get(handle).glyphs[index].y,
        shapeGlyphBound: (handle, index, edge) => shapes.get(handle).glyphs[index].bounds[edge],
        shapeAdvance: (handle) => shapes.get(handle).advance,
        shapeFaceId: () => "Fixture CJK",
        shapeFontInstanceId: () => "fixture-sha:0:wght=400",
        shapeScript: () => "Hani",
        shapeFeatureCount: () => 0,
        shapeFeature: () => "",
        shapeUnsafeBreakCount: () => 0,
        releaseShape: (handle) => shapes.delete(handle),
        metrics(_session, _families, fontSize, _fontWeight, _italic, _role, faceSelectionText) {
          const handle = nextHandle++;
          metricSelectionTexts.push(faceSelectionText);
          metrics.set(handle, [fontSize * 1.04, fontSize * 0.28, 0, fontSize * 0.88, fontSize * 0.12]);
          return handle;
        },
        metricValue: (handle, index) => metrics.get(handle)[index],
        releaseMetrics: (handle) => metrics.delete(handle),
      };
    }""",
)
private external fun installFixtureBackend()

@JsFun(
    """() => {
      let nextHandle = 1;
      const shapes = new Map();
      const metrics = new Map();
      const shapeCalls = [];
      globalThis.__tqPrecomputeFixtureHandles = { shapes, metrics, shapeCalls };
      globalThis.__TiqianFontBackend = {
        shape(_session, displayText, _families, fontSize, _weight, _italic, _locale, _role, sourceText) {
          const handle = nextHandle++;
          const missing = String(displayText).includes("⋯");
          const glyphs = [];
          let index = 0;
          for (const _point of displayText) {
            glyphs.push({
              id: missing ? 0 : 100 + index,
              advance: fontSize,
              x: index * fontSize,
              y: 0,
              bounds: [0, -fontSize * 0.88, fontSize, fontSize * 0.12],
            });
            index += 1;
          }
          shapeCalls.push(`${'$'}{displayText}←${'$'}{sourceText}`);
          shapes.set(handle, { glyphs, advance: glyphs.length * fontSize });
          return handle;
        },
        shapeGlyphCount: (handle) => shapes.get(handle).glyphs.length,
        shapeGlyphId: (handle, index) => shapes.get(handle).glyphs[index].id,
        shapeGlyphAdvance: (handle, index) => shapes.get(handle).glyphs[index].advance,
        shapeGlyphX: (handle, index) => shapes.get(handle).glyphs[index].x,
        shapeGlyphY: (handle, index) => shapes.get(handle).glyphs[index].y,
        shapeGlyphBound: (handle, index, edge) => shapes.get(handle).glyphs[index].bounds[edge],
        shapeAdvance: (handle) => shapes.get(handle).advance,
        shapeFaceId: () => "Fixture CJK",
        shapeFontInstanceId: () => "fixture-sha:0:wght=400",
        shapeScript: () => "Hani",
        shapeFeatureCount: () => 0,
        shapeFeature: () => "",
        shapeUnsafeBreakCount: () => 0,
        releaseShape: (handle) => shapes.delete(handle),
        metrics(_session, _families, fontSize) {
          const handle = nextHandle++;
          metrics.set(handle, [fontSize * 1.04, fontSize * 0.28, 0, fontSize * 0.88, fontSize * 0.12]);
          return handle;
        },
        metricValue: (handle, index) => metrics.get(handle)[index],
        releaseMetrics: (handle) => metrics.delete(handle),
      };
    }""",
)
private external fun installEllipsisFallbackBackend()

@JsFun("() => globalThis.__tqPrecomputeFixtureHandles.shapes.size + globalThis.__tqPrecomputeFixtureHandles.metrics.size")
private external fun fixtureHandleCount(): Int

@JsFun("() => globalThis.__tqPrecomputeFixtureHandles.metricSelectionTexts.join('|')")
private external fun fixtureMetricSelectionTexts(): String

@JsFun("() => globalThis.__tqPrecomputeFixtureHandles.shapeCalls.join('|')")
private external fun ellipsisFixtureShapeCalls(): String
