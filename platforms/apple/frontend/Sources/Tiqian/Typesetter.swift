import CoreGraphics
import TiqianCoreText
import TiqianEngine

/// The entry point for typesetting CJK text with the Core Text pipeline. Construct one per body
/// font size (it owns the engine and the renderer, which share the Core Text caches), then either
/// lay out plain text into a `Paragraph` or author a multi-block `Document` through
/// `documentBuilder()`.
///
/// Every CLREQ rule (避头尾, 两端对齐, 中西文间距, 标点挤压) runs inside the engine's layout with
/// real Core Text measurements. The caller owns the content; this type owns the typesetting.
public final class Typesetter {
    let fontSize: Float
    let engine: ParagraphLayoutEngine
    let renderer: CoreTextLayoutRenderer

    public init(
        fontSize: Float = 18,
        cjkFamily: String = CoreTextSupport.defaultCJKFamily,
        latinFamily: String = CoreTextSupport.defaultLatinFamily,
    ) {
        self.fontSize = fontSize
        // The same families reach the engine (measure) and the renderer (draw).
        engine = appleParagraphEngine(cjkFamily: cjkFamily, latinFamily: latinFamily)
        renderer = CoreTextLayoutRenderer(cjkFamily: cjkFamily, latinFamily: latinFamily)
    }

    /// Lays plain `text` out into a column `width` points wide.
    public func layout(_ text: String, width: Float) -> Paragraph {
        let result = EngineInvariant.call("ParagraphLayoutEngine.layout") {
            try engine.layout(LayoutInput(
                TiqianTextContent(text.engineText),
                TextStyle(BoringArray(), fontSize),
                ParagraphStyle(),
                try LayoutConstraints(width),
            ))
        }
        return Paragraph(result: result, renderer: renderer)
    }

    /// A new document builder bound to this typesetter's engine, renderer and body font size.
    public func documentBuilder() -> DocBuilder {
        DocBuilder(typesetter: self)
    }

    func layout(_ input: LayoutInput) -> LayoutResult {
        EngineInvariant.call("ParagraphLayoutEngine.layout") { try engine.layout(input) }
    }
}

/// One laid-out paragraph. Read `height` to size the view, then `draw(in:canvasHeight:)`.
public final class Paragraph {
    let result: LayoutResult
    private let renderer: CoreTextLayoutRenderer

    init(result: LayoutResult, renderer: CoreTextLayoutRenderer) {
        self.result = result
        self.renderer = renderer
    }

    /// Total laid-out height in points.
    public var height: Double { Double(result.size.height) }

    /// Total laid-out width in points.
    public var width: Double { Double(result.size.width) }

    /// Number of lines at the requested width.
    public var lineCount: Int { result.lines.count }

    /// Draws into a y-up `context` whose height is `canvasHeight`. Text inherits the context's
    /// current fill color.
    public func draw(in context: CGContext, canvasHeight: Double) {
        EngineInvariant.call("CoreTextLayoutRenderer.draw") {
            try renderer.draw(result, in: context, canvasHeight: canvasHeight)
        }
    }
}
