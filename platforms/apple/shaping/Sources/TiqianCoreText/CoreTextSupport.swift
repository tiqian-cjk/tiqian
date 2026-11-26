import CoreGraphics
import CoreText
import Foundation

/// Shared Core Text helpers for the shaping adapter (`CoreTextShaper`, `CoreTextFontMetricsResolver`)
/// and the frontend renderer (`CoreTextLayoutRenderer` in the `Tiqian` module).
///
/// Fonts and shaped lines are cached for the process lifetime: measuring and drawing a cluster both
/// call `line(text:font:vertical:language:openTypeFeatures:)` with the same arguments and therefore
/// replay the same `CTLine` (AGENTS.md implementation constraint 5, 测量与绘制同源). Every cache is
/// guarded by one lock, so the engine may lay out on a background thread while the view draws on
/// the main thread.
public enum CoreTextSupport {
    public static let defaultCJKFamily = "PingFang SC"
    public static let defaultLatinFamily = "Helvetica Neue"

    /// `CoreTextSyntheticObliqueShear`: horizontal shear for `italic` (ADR 0030 Amendment
    /// 2026-08-17). tan⁻¹ 0.105 ≈ 6°, the design slant of 得意黑 / Smiley Sans, unified across
    /// platforms. A horizontal shear keeps the horizontal advance, so measure and draw agree, and
    /// it slants families without an italic face (PingFang SC).
    public static let obliqueShear: CGFloat = 0.105

    /// `CoreTextLineCacheLimit`: maximum cached shaped lines before oldest-insertion eviction.
    static let maxLineCacheEntries = 4096

    /// Size-independent (per-em) metric ratios of one resolved font. Multiply by the point size.
    public struct MetricRatios: Equatable {
        public let ascent: Double
        public let descent: Double
        public let leading: Double
        public let typoAscent: Double?
        public let typoDescent: Double?

        public init(ascent: Double, descent: Double, leading: Double, typoAscent: Double?, typoDescent: Double?) {
            self.ascent = ascent
            self.descent = descent
            self.leading = leading
            self.typoAscent = typoAscent
            self.typoDescent = typoDescent
        }
    }

    /// One parsed OpenType feature request from the shaping contract's `tag` / `tag=value` syntax.
    struct OpenTypeFeature: Equatable {
        let tag: String
        let value: Int
        var canonical: String { "\(tag)=\(value)" }
    }

    private struct FontKey: Hashable {
        let family: String
        let size: Double
        let weight: Int
        let italic: Bool
    }

    private struct LineKey: Hashable {
        let text: [UInt16]
        let font: ObjectIdentifier
        let vertical: Bool
        let language: String?
        let openTypeFeatures: [String]
    }

    private static let lock = NSLock()
    private static var fontCache: [FontKey: CTFont] = [:]
    private static var resolvedRunFontCache: [ObjectIdentifier: CTFont] = [:]
    private static var ratioCache: [ObjectIdentifier: MetricRatios] = [:]
    private static var lineCache = InsertionOrderedCache<LineKey, CTLine>(maxEntries: maxLineCacheEntries)

    /// The cached font for `family` at `size` with OpenType `weight` (400 = regular; Core Text picks
    /// the closest available weight) and optional synthetic-oblique `italic`.
    public static func font(family: String, size: Double, weight: Int = 400, italic: Bool = false) -> CTFont {
        let key = FontKey(family: family, size: size, weight: weight, italic: italic)
        lock.lock()
        defer { lock.unlock() }
        if let cached = fontCache[key] { return cached }
        let created = (351...449).contains(weight) && !italic
            ? createPlain(family: family, size: size)
            : createStyled(family: family, size: size, weight: weight, italic: italic)
        fontCache[key] = created
        return created
    }

    /// The font Core Text actually resolved for `run`, which may be a fallback face.
    public static func runFont(of run: CTRun) -> CTFont? {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let value = attributes[kCTFontAttributeName as String] else { return nil }
        let object = value as CFTypeRef
        guard CFGetTypeID(object) == CTFontGetTypeID() else { return nil }
        return (object as! CTFont)
    }

    /// The glyph runs of a shaped line.
    public static func glyphRuns(of line: CTLine) -> [CTRun] {
        CTLineGetGlyphRuns(line) as? [CTRun] ?? []
    }

    /// `CoreTextFallbackFaceMetrics`: the face Core Text selects for `text` when `font` cannot cover
    /// it. Metrics read this face so line boxes align with the face that is actually drawn. The
    /// returned font is retained by the process cache, so its identity stays a valid cache key.
    public static func resolvedRunFont(text: [UInt16], font: CTFont, language: String? = nil) -> CTFont {
        if text.isEmpty { return font }
        guard
            let line = line(text: text, font: font, language: language),
            let run = glyphRuns(of: line).first,
            let resolved = runFont(of: run)
        else { return font }
        if CFEqual(resolved, font) { return font }
        lock.lock()
        defer { lock.unlock() }
        let id = ObjectIdentifier(resolved)
        if let cached = resolvedRunFontCache[id] { return cached }
        resolvedRunFontCache[id] = resolved
        return resolved
    }

    /// The cached shaped `CTLine` for `text` in `font`, optionally with vertical forms, a language
    /// for `locl` glyph selection, and explicit OpenType features. Returns nil when a feature string
    /// does not parse, so a requested glyph-selection policy is never measured without the feature.
    public static func line(
        text: [UInt16],
        font: CTFont,
        vertical: Bool = false,
        language: String? = nil,
        openTypeFeatures: [String] = [],
    ) -> CTLine? {
        guard let features = canonicalOpenTypeFeatures(openTypeFeatures) else { return nil }
        let key = LineKey(
            text: text,
            font: ObjectIdentifier(font),
            vertical: vertical,
            language: language,
            openTypeFeatures: features,
        )
        lock.lock()
        defer { lock.unlock() }
        if let cached = lineCache.value(for: key) { return cached }
        let created = createLine(text: text, font: font, vertical: vertical, language: language, openTypeFeatures: features)
        lineCache.insert(created, for: key)
        return created
    }

    /// Parses `tag` / `tag=value` feature strings into the canonical `tag=value` form used by the
    /// font descriptor and the line cache key, or nil when any entry is invalid.
    static func canonicalOpenTypeFeatures(_ features: [String]) -> [String]? {
        var canonical: [String] = []
        for feature in features {
            guard let parsed = parseOpenTypeFeature(feature) else { return nil }
            canonical.append(parsed.canonical)
        }
        return canonical
    }

    static func parseOpenTypeFeature(_ value: String) -> OpenTypeFeature? {
        let parts = value.split(separator: "=", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let tag = String(parts[0])
        let setting: Int
        if parts.count == 2 {
            guard let parsed = Int(parts[1]) else { return nil }
            setting = parsed
        } else {
            setting = 1
        }
        let printableASCII = tag.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }
        guard tag.unicodeScalars.count == 4, printableASCII, setting >= 0 else { return nil }
        return OpenTypeFeature(tag: tag, value: setting)
    }

    /// Cached metric ratios for the exact resolved `font`; `compute` runs at most once per font.
    public static func ratios(for font: CTFont, compute: () -> MetricRatios) -> MetricRatios {
        let id = ObjectIdentifier(font)
        lock.lock()
        if let cached = ratioCache[id] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let computed = compute()
        lock.lock()
        ratioCache[id] = computed
        lock.unlock()
        return computed
    }

    private static func createLine(
        text: [UInt16],
        font: CTFont,
        vertical: Bool,
        language: String?,
        openTypeFeatures: [String],
    ) -> CTLine {
        let lineFont = openTypeFeatures.isEmpty ? font : fontWithOpenTypeFeatures(font, openTypeFeatures)
        // Built from UTF-16 code units so the line's string indices equal engine source offsets.
        let string = text.withUnsafeBufferPointer { buffer in
            CFStringCreateWithCharacters(nil, buffer.baseAddress, buffer.count)!
        }
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): lineFont,
        ]
        if vertical {
            attributes[NSAttributedString.Key(kCTVerticalFormsAttributeName as String)] = kCFBooleanTrue
        }
        // Language drives `locl` glyph selection (SC vs TC forms). It is part of the one shared
        // line entry, so the shaper and the renderer select the same glyphs.
        if let language {
            attributes[NSAttributedString.Key(kCTLanguageAttributeName as String)] = language as CFString
        }
        let attributed = NSAttributedString(string: string as String, attributes: attributes)
        return CTLineCreateWithAttributedString(attributed as CFAttributedString)
    }

    /// Applies explicit OpenType features through Core Text's font-descriptor feature settings.
    private static func fontWithOpenTypeFeatures(_ font: CTFont, _ features: [String]) -> CTFont {
        let settings: [[String: Any]] = features.compactMap(parseOpenTypeFeature).map { feature in
            [
                kCTFontOpenTypeFeatureTag as String: feature.tag as CFString,
                kCTFontOpenTypeFeatureValue as String: feature.value as CFNumber,
            ]
        }
        let attributes = [kCTFontFeatureSettingsAttribute as String: settings] as CFDictionary
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes)
        return CTFontCreateCopyWithAttributes(font, 0, nil, descriptor)
    }

    private static func createPlain(family: String, size: Double) -> CTFont {
        let attributes = [kCTFontFamilyNameAttribute as String: family as CFString] as CFDictionary
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    /// `CoreTextWeightTraitAnchors`: OpenType weight (100-900) to the Core Text normalized weight
    /// trait (-1...1), using Apple's system weight anchors.
    static func weightTrait(_ weight: Int) -> Double {
        switch weight {
        case ...150: -0.80
        case ...250: -0.60
        case ...350: -0.40
        case ..<500: 0.0
        case ..<600: 0.23
        case ..<700: 0.30
        case ..<800: 0.40
        case ..<900: 0.56
        default: 0.62
        }
    }

    /// A `family` font at `size` carrying `weight` through the weight trait, and a synthetic oblique
    /// transform when `italic`.
    private static func createStyled(family: String, size: Double, weight: Int, italic: Bool) -> CTFont {
        let traits = [kCTFontWeightTrait as String: weightTrait(weight) as CFNumber]
        let attributes = [
            kCTFontFamilyNameAttribute as String: family as CFString,
            kCTFontTraitsAttribute as String: traits as CFDictionary,
        ] as CFDictionary
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes)
        guard italic else { return CTFontCreateWithFontDescriptor(descriptor, size, nil) }
        var matrix = CGAffineTransform(a: 1, b: 0, c: obliqueShear, d: 1, tx: 0, ty: 0)
        return CTFontCreateWithFontDescriptor(descriptor, size, &matrix)
    }
}

/// Bounded map with oldest-insertion eviction and no reordering on access.
struct InsertionOrderedCache<Key: Hashable, Value> {
    private let maxEntries: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []
    private var head = 0

    init(maxEntries: Int) {
        precondition(maxEntries > 0, "maxEntries must be positive")
        self.maxEntries = maxEntries
    }

    func value(for key: Key) -> Value? { values[key] }

    mutating func insert(_ value: Value, for key: Key) {
        if values[key] == nil {
            if values.count >= maxEntries {
                values.removeValue(forKey: order[head])
                head += 1
                if head > maxEntries {
                    order.removeFirst(head)
                    head = 0
                }
            }
            order.append(key)
        }
        values[key] = value
    }
}
