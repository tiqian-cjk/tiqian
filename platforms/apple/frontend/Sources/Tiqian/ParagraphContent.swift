import TiqianCoreText
import TiqianEngine

/// A rich-text paragraph built fluently. Sizes are relative (`sizeEm`, 1.0 = body size) and colors
/// are `0xAARRGGBB` values (nil inherits the view's text color), so the same content lays out at
/// any body size. Ruby and the CLREQ decorations (着重号 / 专名号 / 书名号 / 示亡号) attach to the
/// base text as the engine models them.
public final class ParagraphContent {
    var pieces: [Piece] = []
    private(set) var localeTag = "zh-Hans"

    public init() {}

    /// Plain body text.
    @discardableResult
    public func text(_ s: String) -> ParagraphContent {
        pieces.append(.text(s))
        return self
    }

    /// One source run with any combination of style, color, ruby, decorations and link target.
    /// `s` is appended once; every aspect becomes an independent engine span over that range.
    @discardableResult
    public func piece(
        _ s: String,
        bold: Bool = false,
        italic: Bool = false,
        sizeEm: Float = 1,
        family: String? = nil,
        argb: UInt32? = nil,
        rubyReading: String? = nil,
        rubyBopomofo: Bool = false,
        decorations: [Decoration] = [],
        locale: String? = nil,
        rubyLocale: String? = nil,
        linkTarget: String? = nil,
    ) -> ParagraphContent {
        pieces.append(.run(Run(
            text: s,
            bold: bold,
            italic: italic,
            sizeEm: sizeEm,
            family: family,
            argb: argb,
            rubyReading: rubyReading,
            rubyBopomofo: rubyBopomofo,
            decorations: decorations,
            locale: locale,
            rubyLocale: rubyLocale,
            linkTarget: linkTarget,
        )))
        return self
    }

    /// 拼音 above the base characters.
    @discardableResult
    public func pinyin(_ base: String, reading: String) -> ParagraphContent {
        piece(base, rubyReading: reading)
    }

    /// 注音 (ㄅㄆㄇ) beside the base characters; the reading defaults to `zh-TW`.
    @discardableResult
    public func bopomofo(_ base: String, reading: String) -> ParagraphContent {
        piece(base, rubyReading: reading, rubyBopomofo: true)
    }

    /// BCP 47 locale of the base paragraph (default `zh-Hans`; annotations keep their own locale).
    @discardableResult
    public func locale(_ bcp47: String) -> ParagraphContent {
        localeTag = bcp47
        return self
    }

    enum Piece {
        case text(String)
        case run(Run)
    }

    struct Run {
        let text: String
        let bold: Bool
        let italic: Bool
        let sizeEm: Float
        let family: String?
        let argb: UInt32?
        let rubyReading: String?
        let rubyBopomofo: Bool
        let decorations: [Decoration]
        let locale: String?
        let rubyLocale: String?
        let linkTarget: String?
    }
}

/// A CLREQ decoration over a source run.
public enum Decoration: CaseIterable {
    /// 着重号: dots under (horizontal) each base character.
    case emphasis
    /// 专名号: a straight line under the run.
    case properNoun
    /// 书名号甲式: a wavy line under the run.
    case bookTitle
    /// 示亡号: a frame around the run.
    case mourning

    var engineKind: DecorationKind {
        switch self {
        case .emphasis: .emphasis
        case .properNoun: .properNoun
        case .bookTitle: .bookTitle
        case .mourning: .mourning
        }
    }
}

/// A paragraph lowered from authored pieces to the engine's span model.
struct LoweredParagraph {
    let text: [UInt16]
    let spans: [TextSpan]
    let colorSpans: [ColorSpan]
    let rubySpans: [RubySpan]
    let decorations: [DecorationSpan]
    let richTextSpans: [RichTextSpan]
    let sourceBoundaries: [Int32]
    let locale: String
}

extension ParagraphContent {
    /// `RubyBopomofoDefaultLocale`: 注音 readings default to `zh-TW` without changing the base
    /// paragraph's `zh-Hans` locale.
    static let bopomofoDefaultLocale = "zh-TW"

    /// Lowers the pieces to engine spans, turning relative `sizeEm` into points at `baseSize`.
    func lowered(baseSize: Float) throws -> LoweredParagraph {
        var text: [UInt16] = []
        var spans: [TextSpan] = []
        var colors: [ColorSpan] = []
        var rubies: [RubySpan] = []
        var decorations: [DecorationSpan] = []
        var richText: [RichTextSpan] = []
        var boundaries = Set<Int32>()
        for piece in pieces {
            switch piece {
            case let .text(s):
                text += s.engineText
            case let .run(run):
                let start = Int32(text.count)
                text += run.text.engineText
                let end = Int32(text.count)
                let range = try TextRange(start, end)
                let styled = run.bold || run.italic || run.sizeEm != 1 || run.family != nil || run.locale != nil
                if styled {
                    spans.append(TextSpan(range, TextStyle(
                        (run.family.map { [$0.engineText] } ?? []).boringArray,
                        baseSize * run.sizeEm,
                        (run.locale ?? localeTag).engineText,
                        run.bold ? 700 : 400,
                        run.italic,
                    )))
                    boundaries.formUnion([start, end])
                }
                if let argb = run.argb {
                    colors.append(ColorSpan(start, end, Int32(bitPattern: argb)))
                    boundaries.formUnion([start, end])
                }
                if let reading = run.rubyReading {
                    let locale = run.rubyLocale ?? (run.rubyBopomofo ? Self.bopomofoDefaultLocale : nil)
                    rubies.append(RubySpan(
                        range,
                        reading.engineText,
                        BoringArray(),
                        run.rubyBopomofo ? .bopomofo : .pinyin,
                        locale?.engineText,
                    ))
                    boundaries.formUnion([start, end])
                }
                for kind in run.decorations {
                    decorations.append(DecorationSpan(range, kind.engineKind))
                    boundaries.formUnion([start, end])
                }
                if let target = run.linkTarget {
                    richText.append(RichTextSpan(range, Link(target.engineText)))
                    boundaries.formUnion([start, end])
                }
            }
        }
        return LoweredParagraph(
            text: text,
            spans: spans,
            colorSpans: colors,
            rubySpans: rubies,
            decorations: decorations,
            richTextSpans: richText,
            sourceBoundaries: boundaries.sorted(),
            locale: localeTag,
        )
    }
}
