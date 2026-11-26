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
/// The renderer resolves all of this into a `CoreTextDisplayList` once per result; `draw` builds the
/// list and replays it, and `Document` keeps the list to replay it on later draws. Coordinates:
/// `LayoutResult` is top-left / y-down, the context is y-up, so a layout y maps to
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
        try displayList(for: result, spans: spans, colorSpans: colorSpans, richTextSpans: richTextSpans)
            .replay(in: context, canvasHeight: canvasHeight)
    }

    /// Resolves every primitive of `result` in paint order: base text, line-end hyphens, 着重号 dots,
    /// interlinear decorations, link underlines, 拼音, 注音.
    func displayList(
        for result: LayoutResult,
        spans: [TextSpan] = [],
        colorSpans: [ColorSpan] = [],
        richTextSpans: [RichTextSpan] = [],
    ) throws -> CoreTextDisplayList {
        var builder = DisplayListBuilder(
            result: result,
            spans: spans,
            colorSpans: colorSpans,
            cjkFamily: cjkFamily,
            latinFamily: latinFamily,
        )
        builder.appendBaseText()
        builder.appendLineEndHyphens()
        builder.appendEmphasisDots()
        builder.appendDecorationSegments()
        try builder.appendLinkUnderlines(richTextSpans)
        builder.appendRuby()
        builder.appendBopomofo()
        return builder.list
    }

    /// The last `TextSpan` covering `offset` (later spans win), or nil.
    static func style(at offset: Int32, in spans: [TextSpan]) -> TextStyle? {
        spans.last { offset >= $0.range.start && offset < $0.range.end }?.style
    }

    /// The ARGB of the last `ColorSpan` covering `offset`, or nil to inherit the context fill color.
    static func color(at offset: Int32, in colorSpans: [ColorSpan]) -> UInt32? {
        colorSpans.last { offset >= $0.start && offset < $0.end }.map { UInt32(bitPattern: $0.argb) }
    }
}

/// Source-offset lookups for one paragraph, built once instead of scanning spans per cluster.
/// Each table stores, per UTF-16 offset, the index of the entry that the corresponding linear rule
/// selects; offsets outside the source text fall back to the linear rule.
private struct SourceIndex {
    private let spans: [TextSpan]
    private let colorSpans: [ColorSpan]
    private let styleByOffset: [Int]
    private let colorByOffset: [Int]
    /// The first `debug.fontDecisions` entry covering each offset.
    private let fontDecisionByOffset: [Int]
    private let result: LayoutResult

    init(result: LayoutResult, spans: [TextSpan], colorSpans: [ColorSpan]) {
        let length = result.input.content.text.count
        self.result = result
        self.spans = spans
        self.colorSpans = colorSpans
        // Later spans win, so paint in order and let later entries overwrite.
        var styles = [Int](repeating: -1, count: length)
        for (index, span) in spans.enumerated() {
            Self.paint(&styles, Int(span.range.start), Int(span.range.end), index)
        }
        var colors = [Int](repeating: -1, count: length)
        for (index, span) in colorSpans.enumerated() {
            Self.paint(&colors, Int(span.start), Int(span.end), index)
        }
        // The first decision wins, so paint in reverse order.
        var decisions = [Int](repeating: -1, count: length)
        let fontDecisions = result.presentation.fontDecisions
        for index in fontDecisions.indices.reversed() {
            let range = fontDecisions[index].range
            Self.paint(&decisions, Int(range.start), Int(range.end), index)
        }
        styleByOffset = styles
        colorByOffset = colors
        fontDecisionByOffset = decisions
    }

    private static func paint(_ table: inout [Int], _ start: Int, _ end: Int, _ value: Int) {
        let lower = max(start, 0)
        let upper = min(end, table.count)
        guard lower < upper else { return }
        for offset in lower..<upper { table[offset] = value }
    }

    func style(at offset: Int32) -> TextStyle? {
        guard offset >= 0, Int(offset) < styleByOffset.count else {
            return CoreTextLayoutRenderer.style(at: offset, in: spans)
        }
        let index = styleByOffset[Int(offset)]
        return index >= 0 ? spans[index].style : nil
    }

    func color(at offset: Int32) -> UInt32? {
        guard offset >= 0, Int(offset) < colorByOffset.count else {
            return CoreTextLayoutRenderer.color(at: offset, in: colorSpans)
        }
        let index = colorByOffset[Int(offset)]
        return index >= 0 ? UInt32(bitPattern: colorSpans[index].argb) : nil
    }

    /// Same answer as `LayoutResult.usesLatinFace(at:)`. A decision containing a non-empty range
    /// covers its first offset, so the first decision covering `range.start` is the first decision
    /// containing the range whenever it also reaches `range.end`. Empty ranges and every other case
    /// use the linear rule.
    func usesLatinFace(at range: TextRange) -> Bool {
        let start = Int(range.start)
        if range.start < range.end, start >= 0, start < fontDecisionByOffset.count, fontDecisionByOffset[start] >= 0 {
            let decision = result.presentation.fontDecisions[fontDecisionByOffset[start]]
            if range.end <= decision.range.end { return fontRoleNameUsesLatinFace(decision.role) }
        }
        return result.usesLatinFace(at: range)
    }
}

/// Appends a paragraph's primitives to a display list. Stored coordinates are y-up from the
/// layout top (layout y maps to -y); see `CoreTextDisplayList`.
private struct DisplayListBuilder {
    let result: LayoutResult
    let spans: [TextSpan]
    let cjkFamily: String
    let latinFamily: String
    let positioned: [PositionedCluster]
    let source: SourceIndex
    let inkIndex: CoreTextInkIndex
    var list = CoreTextDisplayList()

    init(result: LayoutResult, spans: [TextSpan], colorSpans: [ColorSpan], cjkFamily: String, latinFamily: String) {
        self.result = result
        self.spans = spans
        self.cjkFamily = cjkFamily
        self.latinFamily = latinFamily
        positioned = Array(result.positionedClusters())
        source = SourceIndex(result: result, spans: spans, colorSpans: colorSpans)
        inkIndex = CoreTextInkIndex(result: result, positioned: positioned)
    }

    private var fontSize: Double { Double(result.input.textStyle.fontSize) }

    // MARK: - Base text

    mutating func appendBaseText() {
        let baseStyle = result.input.textStyle
        var featuresByClusterRange: [TextRange: [String]] = [:]
        for run in result.glyphRuns {
            let features = run.openTypeFeatures.map { String(engineText: $0) }
            for glyph in run.glyphs { featuresByClusterRange[glyph.clusterRange] = features }
        }
        for cluster in positioned {
            let index = Int(cluster.clusterIndex)
            guard index >= 0, index < result.clusters.count else { continue }
            let shaped = result.clusters[index]
            if shaped.displayText.isEmpty { continue }
            // The face the shaper measured this cluster with: the span family, else the role default
            // from the engine's font decision and the shared `usesLatinFace` rule.
            let style = source.style(at: shaped.range.start) ?? baseStyle
            let family = style.fontFamilies.first.map { String(engineText: $0) }
                ?? (source.usesLatinFace(at: shaped.range) ? latinFamily : cjkFamily)
            let font = CoreTextSupport.font(
                family: family,
                size: Double(style.fontSize),
                weight: Int(style.fontWeight),
                italic: style.italic,
            )
            appendText(
                font: font,
                text: shaped.displayText,
                penX: Double(cluster.drawX),
                baselineY: Double(cluster.baseline + shaped.baselineShift),
                language: String(engineText: style.locale),
                openTypeFeatures: featuresByClusterRange[shaped.range] ?? [],
                argb: source.color(at: shaped.range.start),
            )
        }
    }

    /// The synthetic line-end hyphen of Western auto-hyphenation (ADR 0029). The engine reserves
    /// `LineBox.hyphenAdvance` after `indent + visualWidth` and leaves drawing to the frontend; the
    /// renderer shapes "-" in the Latin face at the body size, the character the engine measured.
    mutating func appendLineEndHyphens() {
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
            appendText(
                font: font,
                text: "-".engineText,
                penX: Double(line.indent + line.visualWidth),
                baselineY: Double(line.baseline),
                argb: source.color(at: anchor),
            )
        }
    }

    /// Shapes `text` with `font` through the shared line cache and records its glyph runs with the
    /// pen at (`penX`, baseline `baselineY`) in layout space. Each Core Text run keeps its own font,
    /// so a character the base font lacks draws with the fallback face Core Text selected.
    private mutating func appendText(
        font: CTFont,
        text: [UInt16],
        penX: Double,
        baselineY: Double,
        vertical: Bool = false,
        language: String? = nil,
        openTypeFeatures: [String] = [],
        argb: UInt32? = nil,
    ) {
        guard let line = CoreTextSupport.line(
            text: text,
            font: font,
            vertical: vertical,
            language: language,
            openTypeFeatures: openTypeFeatures,
        ) else { return }
        var runs: [CoreTextDisplayList.GlyphRunOp] = []
        for run in CoreTextSupport.glyphRuns(of: line) {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            // CTRun positions are y-up and baseline-relative.
            for index in 0..<count {
                positions[index].x += penX
                positions[index].y -= baselineY
            }
            runs.append(.init(font: CoreTextSupport.runFont(of: run) ?? font, glyphs: glyphs, positions: positions))
        }
        if !runs.isEmpty { list.append(.glyphs(runs), argb: argb) }
    }

    // MARK: - Annotations (拼音 / 注音)

    mutating func appendRuby() {
        for ruby in result.presentation.rubyDecisions where !ruby.text.isEmpty {
            // Re-shape the reading with its resolved font instead of replaying stored glyph ids: a
            // reading that triggered a Core Text fallback face carries ids of that face. The weight
            // is the engine-computed annotation weight (ADR 0032).
            let family = ruby.fontFamilies.first.map { String(engineText: $0) } ?? latinFamily
            let font = CoreTextSupport.font(family: family, size: Double(ruby.fontSize), weight: Int(ruby.fontWeight))
            appendText(
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
    mutating func appendBopomofo() {
        for decision in result.presentation.bopomofoDecisions {
            let family = decision.fontFamilies.first.map { String(engineText: $0) } ?? cjkFamily
            let language = String(engineText: decision.locale)
            for placement in decision.placements where !placement.text.isEmpty {
                let font = CoreTextSupport.font(
                    family: family,
                    size: Double(placement.fontSize),
                    weight: Int(decision.fontWeight),
                )
                let isSymbol = placement.role == .symbol
                appendText(
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

    mutating func appendEmphasisDots() {
        for decoration in result.presentation.decorationDecisions where decoration.applied && decoration.dotDiameter > 0 {
            let radius = Double(decoration.dotDiameter) / 2
            let centerX = Double(decoration.anchorX)
            let centerY = -Double(decoration.anchorY)
            list.append(
                .fillEllipse(CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2)),
                argb: source.color(at: decoration.clusterRange.start),
            )
        }
    }

    mutating func appendDecorationSegments() {
        let fontSize = fontSize
        let stroke = max(fontSize / 16, 1)
        let skipClearance = max(
            Float(stroke),
            min(Float(fontSize) * CoreTextLayoutRenderer.skipInkClearanceEm, CoreTextLayoutRenderer.skipInkClearanceMax),
        )
        for segment in result.presentation.decorationSegments {
            let kind = String(engineText: segment.kind)
            let argb = source.color(at: segment.sourceRange.start)
            switch kind {
            case DecorationKind.properNoun.rawValue, DecorationKind.bookTitle.rawValue:
                let skips = inkIndex.intervals(
                    lineIndex: segment.lineIndex,
                    bandTop: segment.top - Float(stroke),
                    bandBottom: segment.top + Float(stroke),
                )
                var kept: [(Double, Double)] = []
                keptIntervals(
                    left: Double(segment.left),
                    right: Double(segment.right),
                    skips: skips,
                    clearance: Double(skipClearance),
                ) { kept.append(($0, $1)) }
                for (left, right) in kept {
                    if kind == DecorationKind.properNoun.rawValue {
                        appendHorizontalLine(left: left, right: right, y: Double(segment.top), stroke: stroke, argb: argb)
                    } else {
                        appendWavyLine(left: left, right: right, y: Double(segment.top), stroke: stroke, argb: argb)
                    }
                }
            default:
                // 示亡号 frame; continuation edges (openStart / openEnd) stay undrawn.
                let left = Double(segment.left), right = Double(segment.right)
                let top = Double(segment.top), bottom = Double(segment.bottom)
                appendHorizontalLine(left: left, right: right, y: top, stroke: stroke, argb: argb)
                appendHorizontalLine(left: left, right: right, y: bottom, stroke: stroke, argb: argb)
                if !segment.openStart { appendVerticalLine(x: left, top: top, bottom: bottom, stroke: stroke, argb: argb) }
                if !segment.openEnd { appendVerticalLine(x: right, top: top, bottom: bottom, stroke: stroke, argb: argb) }
            }
        }
    }

    /// `AppleNativeLinkUnderline`: native `AttributedString.link` ranges stay semantic `Link` spans.
    /// The renderer draws their solid underline from the same source boxes, punctuation-glue trim
    /// and recorded glyph ink that the other frontends use.
    mutating func appendLinkUnderlines(_ richTextSpans: [RichTextSpan]) throws {
        let underlines = richTextSpans
            .filter { $0.role is Link }
            .map { RichTextSpan($0.range, Underline.instance, $0.paint) }
        guard !underlines.isEmpty else { return }
        let occupied = try result.positionedRichTextSegments(underlines.readOnlyArray)
        let segments = result.richTextDecorationSegments(ReadOnlyArray(occupied))
        let stroke = max(result.input.textStyle.fontSize / 16, 1)
        for segment in segments {
            let style = source.style(at: segment.range.start) ?? result.input.textStyle
            let lineY = try result.richTextDecorationLineY(segment, stroke)
            let skipClearance = max(
                stroke,
                min(style.fontSize * CoreTextLayoutRenderer.skipInkClearanceEm, CoreTextLayoutRenderer.skipInkClearanceMax),
            )
            let skips = inkIndex.intervals(lineIndex: segment.lineIndex, bandTop: lineY - stroke, bandBottom: lineY + stroke)
            let argb = segment.span.paint.argb.map { UInt32(bitPattern: $0) } ?? source.color(at: segment.range.start)
            var kept: [(Double, Double)] = []
            keptIntervals(
                left: Double(segment.left),
                right: Double(segment.right),
                skips: skips,
                clearance: Double(skipClearance),
            ) { kept.append(($0, $1)) }
            for (left, right) in kept {
                appendHorizontalLine(left: left, right: right, y: Double(lineY), stroke: Double(stroke), argb: argb)
            }
        }
    }

    private mutating func appendHorizontalLine(left: Double, right: Double, y: Double, stroke: Double, argb: UInt32?) {
        list.append(.fillRect(CGRect(x: left, y: -y - stroke / 2, width: right - left, height: stroke)), argb: argb)
    }

    private mutating func appendVerticalLine(x: Double, top: Double, bottom: Double, stroke: Double, argb: UInt32?) {
        let low = min(-top, -bottom)
        let high = max(-top, -bottom)
        list.append(.fillRect(CGRect(x: x - stroke / 2, y: low, width: stroke, height: high - low)), argb: argb)
    }

    /// 书名号甲式 wave of quadratic Bézier arcs, stored as its stroked outline so a replay fills it
    /// with the current fill color; dark mode and rich-text colors need no stroke-color state. The
    /// outline uses Core Graphics' default butt cap, miter join and miter limit 10.
    private mutating func appendWavyLine(left: Double, right: Double, y: Double, stroke: Double, argb: UInt32?) {
        guard right > left else { return }
        let halfWave = max(fontSize * CoreTextLayoutRenderer.wavyHalfWaveEm, 1)
        let amplitude = fontSize * CoreTextLayoutRenderer.wavyAmplitudeEm
        let baseY = -y
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left, y: baseY))
        var x = left
        var up = true
        while x < right - CoreTextLayoutRenderer.wavyEndpointEpsilon {
            let nextX = min(x + halfWave, right)
            let controlY = baseY + (up ? amplitude * 2 : -amplitude * 2)
            path.addQuadCurve(to: CGPoint(x: nextX, y: baseY), control: CGPoint(x: (x + nextX) / 2, y: controlY))
            x = nextX
            up.toggle()
        }
        let outline = path.copy(strokingWithWidth: stroke, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        list.append(.fillPath(outline), argb: argb)
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
