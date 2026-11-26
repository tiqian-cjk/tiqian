import CoreGraphics
import CoreText
import TiqianEngine

/// Core Text shaping adapter (ADR 0046), the Apple peer of `SkiaTextShaper` / `AwtTextShaper`.
///
/// Contract: shape the layout-decided `ShapingInput.displayText` with one resolved font and return
/// one cluster plus one glyph run with real advances and glyph-local ink bounds. Font fallback,
/// CLREQ substitution and punctuation decisions stay in the engine. Shaping goes through
/// `CoreTextSupport.line(...)`, the same entry the renderer replays, including the paragraph
/// language and explicit OpenType features such as `fwid=1`.
public final class CoreTextShaper: TextShaper {
    /// `ShapingDecisionInfo.capabilityIssue` value recorded when Core Text cannot apply a requested
    /// OpenType feature and the run is shaped without it.
    public static let openTypeFeatureUnavailable = "CoreTextOpenTypeFeatureUnavailable"

    private let cjkFamily: String
    private let latinFamily: String

    public init(
        cjkFamily: String = CoreTextSupport.defaultCJKFamily,
        latinFamily: String = CoreTextSupport.defaultLatinFamily,
    ) {
        self.cjkFamily = cjkFamily
        self.latinFamily = latinFamily
    }

    public func shape(_ input: ShapingInput) throws -> ShapingResult {
        let sourceText = Array(input.text[Int(input.range.start)..<Int(input.range.end)])
        let displayText = input.displayText
        let fontKey = input.fontDecision.candidate.key
        let family = resolveFamily(input)

        // Per-span weight and italic (rich text, ADR 0030): runs are measured with the face they
        // are drawn with.
        let font = CoreTextSupport.font(
            family: family,
            size: Double(input.style.fontSize),
            weight: Int(input.style.fontWeight),
            italic: input.style.italic,
        )
        if displayText.isEmpty {
            return degenerate(input, sourceText: sourceText, reason: "CoreTextShaper:empty")
        }

        let language = String(engineText: input.style.locale)
        let requested = input.openTypeFeatures.map { String(engineText: $0) }
        let canonical = CoreTextSupport.canonicalOpenTypeFeatures(requested)
        var capabilityIssue = canonical == nil ? Self.openTypeFeatureUnavailable : nil
        var appliedFeatures = canonical ?? []
        var shaped = shapeLine(displayText, font: font, language: language, openTypeFeatures: appliedFeatures)
        if shaped == nil, !appliedFeatures.isEmpty {
            // A feature Core Text cannot instantiate is an explicit capability degrade: record it,
            // shape without the feature, and let the GlyphRun carry the applied (empty) feature set
            // so the renderer replays exactly this fallback.
            capabilityIssue = Self.openTypeFeatureUnavailable
            appliedFeatures = []
            shaped = shapeLine(displayText, font: font, language: language, openTypeFeatures: appliedFeatures)
        }
        guard let shaped else {
            return degenerate(
                input,
                sourceText: sourceText,
                reason: "CoreTextShaper:font-unavailable",
                capabilityIssue: capabilityIssue,
            )
        }

        let advance = shaped.advance
        let count = shaped.glyphIDs.count
        var glyphs: [Glyph] = []
        glyphs.reserveCapacity(count)
        for index in 0..<count {
            let startX = shaped.xs[index]
            let endX = index + 1 < count ? shaped.xs[index + 1] : advance
            let glyphAdvance = shaped.verticalForms ? advance / Float(count) : max(endX - startX, 0)
            glyphs.append(try Glyph(
                shaped.glyphIDs[index],
                input.range,
                glyphAdvance,
                startX,
                shaped.ys[index],
                nil,
                shaped.bounds[index],
            ))
        }
        let cluster = Cluster(input.range, sourceText, fontKey, advance, displayText)
        let run = GlyphRun(
            input.range,
            fontKey,
            glyphs.readOnlyArray,
            advance,
            appliedFeatures.map(\.engineText).readOnlyArray,
        )
        let featureEvidence = appliedFeatures.isEmpty
            ? nil
            : "CoreTextFontDescriptor:\(appliedFeatures.joined(separator: ","))".engineText
        let decision = ShapingDecisionInfo(
            input.range,
            sourceText,
            displayText,
            fontKey,
            Int32(count),
            advance,
            ShapingSource.coreText.rawValue.engineText,
            "CoreTextShaper:\(family)".engineText,
            Int32(glyphs.filter { $0.bounds == nil }.count),
            Int32(shaped.glyphIDs.filter { $0 == 0 }.count),
            nil,
            nil,
            input.style.locale,
            nil,
            featureEvidence,
            capabilityIssue?.engineText,
        )
        return ShapingResult([cluster].readOnlyArray, [run].readOnlyArray, [decision].readOnlyArray)
    }

    /// The family to shape with: the span's first explicit family, then a concrete family named by
    /// the font decision, then the role default. A candidate family equal to its key is a logical
    /// key such as `cjk-primary`, not an installed family.
    private func resolveFamily(_ input: ShapingInput) -> String {
        if let first = input.style.fontFamilies.first { return String(engineText: first) }
        let candidate = input.fontDecision.candidate
        if candidate.family != candidate.key { return String(engineText: candidate.family) }
        return input.fontDecision.role.usesLatinFace() ? latinFamily : cjkFamily
    }

    private struct Shaped {
        var glyphIDs: [Int32] = []
        var xs: [Float] = []
        var ys: [Float] = []
        var bounds: [Rect?] = []
        var advance: Float = 0
        var verticalForms = false
    }

    private func shapeLine(_ displayText: [UInt16], font: CTFont, language: String, openTypeFeatures: [String]) -> Shaped? {
        let verticalForms = openTypeFeatures.contains("vert=1")
        guard let line = CoreTextSupport.line(
            text: displayText,
            font: font,
            vertical: verticalForms,
            language: language,
            openTypeFeatures: openTypeFeatures,
        ) else { return nil }
        var shaped = Shaped()
        shaped.verticalForms = verticalForms
        shaped.advance = Float(CTLineGetTypographicBounds(line, nil, nil, nil))
        for run in CoreTextSupport.glyphRuns(of: line) {
            collect(run, fallbackFont: font, into: &shaped)
        }
        return shaped
    }

    private func collect(_ run: CTRun, fallbackFont: CTFont, into shaped: inout Shaped) {
        let count = CTRunGetGlyphCount(run)
        guard count > 0 else { return }
        let runFont = CoreTextSupport.runFont(of: run) ?? fallbackFont
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        var rects = [CGRect](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
        CTFontGetBoundingRectsForGlyphs(runFont, .horizontal, glyphs, &rects, count)
        for index in 0..<count {
            shaped.glyphIDs.append(Int32(glyphs[index]))
            shaped.xs.append(Float(positions[index].x))
            shaped.ys.append(Float(-positions[index].y))
            shaped.bounds.append(Self.glyphLocalRect(rects[index]))
        }
    }

    /// Core Graphics bounding rect (+y up, baseline-relative) to engine `Rect` (+y down, negative
    /// top above the baseline). Empty ink (spaces) has no bounds.
    static func glyphLocalRect(_ rect: CGRect) -> Rect? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        return Rect(
            Float(rect.origin.x),
            Float(-(rect.origin.y + rect.height)),
            Float(rect.origin.x + rect.width),
            Float(-rect.origin.y),
        )
    }

    private func degenerate(
        _ input: ShapingInput,
        sourceText: [UInt16],
        reason: String,
        capabilityIssue: String? = nil,
    ) -> ShapingResult {
        let fontKey = input.fontDecision.candidate.key
        let cluster = Cluster(input.range, sourceText, fontKey, 0, input.displayText)
        let run = GlyphRun(input.range, fontKey, ReadOnlyArray(), 0)
        let decision = ShapingDecisionInfo(
            input.range,
            sourceText,
            input.displayText,
            fontKey,
            0,
            0,
            ShapingSource.coreText.rawValue.engineText,
            reason.engineText,
            0,
            0,
            nil,
            nil,
            input.style.locale,
            nil,
            nil,
            capabilityIssue?.engineText,
        )
        return ShapingResult([cluster].readOnlyArray, [run].readOnlyArray, [decision].readOnlyArray)
    }
}
