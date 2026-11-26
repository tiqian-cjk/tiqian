import CoreGraphics
import CoreText
import TiqianCoreText
import TiqianEngine

/// Draws a Tiqian `LayoutResult` into a `CGContext` with `CTFontDrawGlyphs` (ADR 0047).
///
/// Base text replays each positioned cluster (after line breaking) through the shared
/// `CoreTextSupport.line(...)` entry the shaper measured with. Positions come from
/// `LayoutResult.positionedClusters()` (per-cluster `drawX` and line baseline). On top of the base
/// text the renderer paints the engine-computed decoration geometry: 着重号 dots, 专名号 / 书名号 /
/// 示亡号 lines, link underlines, synthetic line-end hyphens, and 拼音 / 注音 annotations.
///
/// Rich text (ADR 0030): each cluster is drawn with the face its `TextSpan` selects and clusters
/// inside a `ColorSpan` are filled with that color; other text inherits the context fill color.
///
/// Coordinates: `LayoutResult` is top-left / y-down, the context is y-up, so a layout y maps to
/// `canvasHeight - y`. The renderer never sets a base fill color.
final class CoreTextLayoutRenderer {
    /// `WavyBookTitleGeometry`: 书名号甲式 wave half-length and amplitude in em, shared with the
    /// Compose and Android renderers.
    static let wavyHalfWaveEm = 0.20
    static let wavyAmplitudeEm = 0.06
    static let wavyEndpointEpsilon = 0.01
    /// `InterlinearSkipInkClearance`: horizontal clearance between an underline gap and glyph ink.
    static let skipInkClearanceEm: Float = 0.10
    static let skipInkClearanceMax: Float = 13

    private let cjkFamily: String
    private let latinFamily: String

    init(
        cjkFamily: String = CoreTextSupport.defaultCJKFamily,
        latinFamily: String = CoreTextSupport.defaultLatinFamily,
    ) {
        self.cjkFamily = cjkFamily
        self.latinFamily = latinFamily
    }

    func draw(
        _ result: LayoutResult,
        in context: CGContext,
        canvasHeight: Double,
        spans: [TextSpan] = [],
        colorSpans: [ColorSpan] = [],
        richTextSpans: [RichTextSpan] = [],
    ) throws {
        guard canvasHeight > 0 else { return }
        let fontSize = Double(result.input.textStyle.fontSize)
        let surface = Surface(context: context, canvasHeight: canvasHeight)
        drawBaseText(result, surface, spans: spans, colorSpans: colorSpans)
        drawLineEndHyphens(result, surface, colorSpans: colorSpans)
        drawEmphasisDots(result, surface, colorSpans: colorSpans)
        drawDecorationSegments(result, surface, fontSize: fontSize, colorSpans: colorSpans)
        try drawLinkUnderlines(result, surface, spans: spans, colorSpans: colorSpans, richTextSpans: richTextSpans)
        drawRuby(result, surface)
        drawBopomofo(result, surface)
    }

    /// The target context with its layout-to-Core-Graphics y mapping.
    private struct Surface {
        let context: CGContext
        let canvasHeight: Double

        func y(_ layoutY: Double) -> Double { canvasHeight - layoutY }
    }

    // MARK: - Base text

    private func drawBaseText(_ result: LayoutResult, _ surface: Surface, spans: [TextSpan], colorSpans: [ColorSpan]) {
        let baseStyle = result.input.textStyle
        var featuresByClusterRange: [TextRange: [String]] = [:]
        for run in result.glyphRuns {
            let features = run.openTypeFeatures.map { String(engineText: $0) }
            for glyph in run.glyphs { featuresByClusterRange[glyph.clusterRange] = features }
        }
        for positioned in result.positionedClusters() {
            let index = Int(positioned.clusterIndex)
            guard index >= 0, index < result.clusters.count else { continue }
            let cluster = result.clusters[index]
            if cluster.displayText.isEmpty { continue }
            // The face the shaper measured this cluster with: the span family, else the role default
            // from the engine's font decision and the shared `usesLatinFace` rule.
            let style = Self.style(at: cluster.range.start, in: spans) ?? baseStyle
            let family = style.fontFamilies.first.map { String(engineText: $0) }
                ?? (result.usesLatinFace(at: cluster.range) ? latinFamily : cjkFamily)
            let font = CoreTextSupport.font(
                family: family,
                size: Double(style.fontSize),
                weight: Int(style.fontWeight),
                italic: style.italic,
            )
            withFill(surface, Self.color(at: cluster.range.start, in: colorSpans)) {
                drawShapedText(
                    surface,
                    font: font,
                    text: cluster.displayText,
                    penX: Double(positioned.drawX),
                    baselineY: Double(positioned.baseline + cluster.baselineShift),
                    language: String(engineText: style.locale),
                    openTypeFeatures: featuresByClusterRange[cluster.range] ?? [],
                )
            }
        }
    }

    /// Draws the synthetic line-end hyphen of Western auto-hyphenation (ADR 0029). The engine
    /// reserves `LineBox.hyphenAdvance` after `indent + visualWidth` and leaves drawing to the
    /// frontend; the renderer shapes "-" in the Latin face at the body size, the character the
    /// engine measured.
    private func drawLineEndHyphens(_ result: LayoutResult, _ surface: Surface, colorSpans: [ColorSpan]) {
        let style = result.input.textStyle
        let font = CoreTextSupport.font(
            family: latinFamily,
            size: Double(style.fontSize),
            weight: Int(style.fontWeight),
            italic: style.italic,
        )
        for line in result.lines where line.hyphenAdvance > 0 {
            // The hyphen takes the color of the cluster it follows.
            let anchor = result.clusters[Int(line.clusterRange.last)].range.start
            withFill(surface, Self.color(at: anchor, in: colorSpans)) {
                drawShapedText(
                    surface,
                    font: font,
                    text: "-".engineText,
                    penX: Double(line.indent + line.visualWidth),
                    baselineY: Double(line.baseline),
                )
            }
        }
    }

    /// The last `TextSpan` covering `offset` (later spans win), or nil.
    static func style(at offset: Int32, in spans: [TextSpan]) -> TextStyle? {
        spans.last { offset >= $0.range.start && offset < $0.range.end }?.style
    }

    /// The ARGB of the last `ColorSpan` covering `offset`, or nil to inherit the context fill color.
    static func color(at offset: Int32, in colorSpans: [ColorSpan]) -> UInt32? {
        colorSpans.last { offset >= $0.start && offset < $0.end }.map { UInt32(bitPattern: $0.argb) }
    }

    private func withFill(_ surface: Surface, _ argb: UInt32?, _ draw: () -> Void) {
        guard let argb else {
            draw()
            return
        }
        surface.context.saveGState()
        surface.context.setFillColor(
            red: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: CGFloat((argb >> 24) & 0xFF) / 255,
        )
        draw()
        surface.context.restoreGState()
    }

    /// Shapes `text` with `font` and draws it with its pen at (`penX`, baseline `baselineY`) in
    /// layout space. Each Core Text run draws with its own font, so a character the base font
    /// lacks draws with the fallback face Core Text selected.
    private func drawShapedText(
        _ surface: Surface,
        font: CTFont,
        text: [UInt16],
        penX: Double,
        baselineY: Double,
        vertical: Bool = false,
        language: String? = nil,
        openTypeFeatures: [String] = [],
    ) {
        guard let line = CoreTextSupport.line(
            text: text,
            font: font,
            vertical: vertical,
            language: language,
            openTypeFeatures: openTypeFeatures,
        ) else { return }
        let penY = surface.y(baselineY)
        for run in CoreTextSupport.glyphRuns(of: line) {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let runFont = CoreTextSupport.runFont(of: run) ?? font
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            // CTRun positions are already y-up and baseline-relative.
            for index in 0..<count {
                positions[index].x += penX
                positions[index].y += penY
            }
            CTFontDrawGlyphs(runFont, glyphs, positions, count, surface.context)
        }
    }

    // MARK: - Annotations (拼音 / 注音)

    private func drawRuby(_ result: LayoutResult, _ surface: Surface) {
        for ruby in result.debug.rubyDecisions where !ruby.text.isEmpty {
            // Re-shape the reading with its resolved font instead of replaying stored glyph ids: a
            // reading that triggered a Core Text fallback face carries ids of that face. The weight
            // is the engine-computed annotation weight (ADR 0032).
            let family = ruby.fontFamilies.first.map { String(engineText: $0) } ?? latinFamily
            let font = CoreTextSupport.font(family: family, size: Double(ruby.fontSize), weight: Int(ruby.fontWeight))
            drawShapedText(
                surface,
                font: font,
                text: ruby.text,
                penX: Double(ruby.centerX - ruby.width / 2),
                baselineY: Double(ruby.baselineY),
                language: String(engineText: ruby.locale),
            )
        }
    }

    /// 注音: each placement draws as a Core Text vertical run. The engine records the
    /// horizontal-baseline origin that Skia / Android replay; a Core Text vertical run's pen is the
    /// top centre of the ideographic box, so the ㄅㄆㄇ symbol origin derives from the box. Tone
    /// marks are positioned from each platform's own ink, so their `drawX` / `baselineY` replay as-is.
    private func drawBopomofo(_ result: LayoutResult, _ surface: Surface) {
        for decision in result.debug.bopomofoDecisions {
            let family = decision.fontFamilies.first.map { String(engineText: $0) } ?? cjkFamily
            let language = String(engineText: decision.locale)
            for placement in decision.placements where !placement.text.isEmpty {
                let font = CoreTextSupport.font(
                    family: family,
                    size: Double(placement.fontSize),
                    weight: Int(decision.fontWeight),
                )
                let isSymbol = placement.role == .symbol
                drawShapedText(
                    surface,
                    font: font,
                    text: placement.text,
                    penX: Double(isSymbol ? placement.left + placement.width / 2 : placement.drawX),
                    baselineY: Double(isSymbol ? placement.top : placement.baselineY),
                    vertical: true,
                    language: language,
                    openTypeFeatures: ["vert=1"],
                )
            }
        }
    }

    // MARK: - 着重号 / 专名号 / 书名号 / 示亡号

    private func drawEmphasisDots(_ result: LayoutResult, _ surface: Surface, colorSpans: [ColorSpan]) {
        for decoration in result.debug.decorationDecisions where decoration.applied && decoration.dotDiameter > 0 {
            let radius = Double(decoration.dotDiameter) / 2
            let centerX = Double(decoration.anchorX)
            let centerY = surface.y(Double(decoration.anchorY))
            withFill(surface, Self.color(at: decoration.clusterRange.start, in: colorSpans)) {
                surface.context.fillEllipse(in: CGRect(
                    x: centerX - radius,
                    y: centerY - radius,
                    width: radius * 2,
                    height: radius * 2,
                ))
            }
        }
    }

    private func drawDecorationSegments(_ result: LayoutResult, _ surface: Surface, fontSize: Double, colorSpans: [ColorSpan]) {
        let stroke = max(fontSize / 16, 1)
        let skipClearance = max(Float(stroke), min(Float(fontSize) * Self.skipInkClearanceEm, Self.skipInkClearanceMax))
        for segment in result.debug.decorationSegments {
            let kind = String(engineText: segment.kind)
            withFill(surface, Self.color(at: segment.sourceRange.start, in: colorSpans)) {
                switch kind {
                case DecorationKind.properNoun.rawValue, DecorationKind.bookTitle.rawValue:
                    let skips = result.coreTextInkSkipIntervals(
                        lineIndex: segment.lineIndex,
                        bandTop: segment.top - Float(stroke),
                        bandBottom: segment.top + Float(stroke),
                    )
                    keptIntervals(
                        left: Double(segment.left),
                        right: Double(segment.right),
                        skips: skips,
                        clearance: Double(skipClearance),
                    ) { left, right in
                        if kind == DecorationKind.properNoun.rawValue {
                            horizontalLine(surface, left: left, right: right, y: Double(segment.top), stroke: stroke)
                        } else {
                            wavyLine(surface, left: left, right: right, y: Double(segment.top), stroke: stroke, fontSize: fontSize)
                        }
                    }
                default:
                    // 示亡号 frame; continuation edges (openStart / openEnd) stay undrawn.
                    let left = Double(segment.left), right = Double(segment.right)
                    let top = Double(segment.top), bottom = Double(segment.bottom)
                    horizontalLine(surface, left: left, right: right, y: top, stroke: stroke)
                    horizontalLine(surface, left: left, right: right, y: bottom, stroke: stroke)
                    if !segment.openStart { verticalLine(surface, x: left, top: top, bottom: bottom, stroke: stroke) }
                    if !segment.openEnd { verticalLine(surface, x: right, top: top, bottom: bottom, stroke: stroke) }
                }
            }
        }
    }

    /// `AppleNativeLinkUnderline`: native `AttributedString.link` ranges stay semantic `Link` spans.
    /// The renderer draws their solid underline from the same source boxes, punctuation-glue trim
    /// and recorded glyph ink that the other frontends use.
    private func drawLinkUnderlines(
        _ result: LayoutResult,
        _ surface: Surface,
        spans: [TextSpan],
        colorSpans: [ColorSpan],
        richTextSpans: [RichTextSpan],
    ) throws {
        let underlines = richTextSpans
            .filter { $0.role is Link }
            .map { RichTextSpan($0.range, Underline.instance, $0.paint) }
        guard !underlines.isEmpty else { return }
        let occupied = try result.positionedRichTextSegments(underlines.readOnlyArray)
        let segments = result.richTextDecorationSegments(ReadOnlyArray(occupied))
        let stroke = max(result.input.textStyle.fontSize / 16, 1)
        for segment in segments {
            let style = Self.style(at: segment.range.start, in: spans) ?? result.input.textStyle
            let lineY = try result.richTextDecorationLineY(segment, stroke)
            let skipClearance = max(stroke, min(style.fontSize * Self.skipInkClearanceEm, Self.skipInkClearanceMax))
            let skips = result.coreTextInkSkipIntervals(
                lineIndex: segment.lineIndex,
                bandTop: lineY - stroke,
                bandBottom: lineY + stroke,
            )
            let argb = segment.span.paint.argb.map { UInt32(bitPattern: $0) }
                ?? Self.color(at: segment.range.start, in: colorSpans)
            withFill(surface, argb) {
                keptIntervals(
                    left: Double(segment.left),
                    right: Double(segment.right),
                    skips: skips,
                    clearance: Double(skipClearance),
                ) { left, right in
                    horizontalLine(surface, left: left, right: right, y: Double(lineY), stroke: Double(stroke))
                }
            }
        }
    }

    private func horizontalLine(_ surface: Surface, left: Double, right: Double, y: Double, stroke: Double) {
        surface.context.fill(CGRect(x: left, y: surface.y(y) - stroke / 2, width: right - left, height: stroke))
    }

    private func verticalLine(_ surface: Surface, x: Double, top: Double, bottom: Double, stroke: Double) {
        let cgTop = surface.y(top)
        let cgBottom = surface.y(bottom)
        let low = min(cgTop, cgBottom)
        surface.context.fill(CGRect(x: x - stroke / 2, y: low, width: stroke, height: max(cgTop, cgBottom) - low))
    }

    /// 书名号甲式 wave of quadratic Bézier arcs. Core Graphics converts the stroked path into an
    /// outline and fills it with the current fill color, so dark mode and rich-text colors need no
    /// separate stroke-color state.
    private func wavyLine(_ surface: Surface, left: Double, right: Double, y: Double, stroke: Double, fontSize: Double) {
        guard right > left else { return }
        let halfWave = max(fontSize * Self.wavyHalfWaveEm, 1)
        let amplitude = fontSize * Self.wavyAmplitudeEm
        let baseY = surface.y(y)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left, y: baseY))
        var x = left
        var up = true
        while x < right - Self.wavyEndpointEpsilon {
            let nextX = min(x + halfWave, right)
            let controlY = baseY + (up ? amplitude * 2 : -amplitude * 2)
            path.addQuadCurve(to: CGPoint(x: nextX, y: baseY), control: CGPoint(x: (x + nextX) / 2, y: controlY))
            x = nextX
            up.toggle()
        }
        surface.context.addPath(path)
        surface.context.setLineWidth(stroke)
        surface.context.replacePathWithStrokedPath()
        surface.context.fillPath()
    }
}

extension LayoutResult {
    /// Whether the cluster at `range` draws in the Latin face, from the engine's own font decision
    /// (`debug.fontDecisions`) and the shared `fontRoleNameUsesLatinFace` rule that shaping and
    /// metrics use. Mirrors the Compose frontend's `LayoutResultReplayIndex`.
    func usesLatinFace(at range: TextRange) -> Bool {
        let role = debug.fontDecisions.first { range.start >= $0.range.start && range.end <= $0.range.end }?.role
        return fontRoleNameUsesLatinFace(role)
    }
}
