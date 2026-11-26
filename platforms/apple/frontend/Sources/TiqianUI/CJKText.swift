#if os(macOS)
import SwiftUI
import AppKit
import Tiqian

/// A reusable SwiftUI view that typesets and scrolls a CJK document with the Tiqian engine — the
/// Apple peer of Compose's `CjkText`. Content is native `AttributedString` wrapped in [CJKBlock]s;
/// the view owns a `Typesetter` (from [fontSize]), lowers the blocks, lays out at the current
/// width, and scrolls. It exposes no `Tiqian`-prefixed engine types.
///
public struct CJKText: NSViewRepresentable {
    @Environment(\.openURL) private var openURL
    public let blocks: [CJKBlock]
    public let fontSize: Float

    public init(_ blocks: [CJKBlock], fontSize: Float) {
        self.blocks = blocks
        self.fontSize = fontSize
    }

    public func makeNSView(context: Context) -> CJKTextView {
        let textView = CJKTextView(blocks, fontSize: fontSize)
        textView.onOpenURL = { url in openURL(url) }
        return textView
    }

    public func updateNSView(_ textView: CJKTextView, context: Context) {
        textView.onOpenURL = { url in openURL(url) }
        textView.setContent(blocks, fontSize: fontSize)
    }
}

/// AppKit-native CJK text view. AppKit consumers use this directly; `CJKText` is its SwiftUI
/// adapter. Both Apple platforms expose the same content initializer and update method.
public final class CJKTextView: NSScrollView {
    /// Native embedding hook. SwiftUI's `CJKText` wires this to the environment `OpenURLAction`;
    /// an AppKit host may override it, otherwise links open through `NSWorkspace`.
    public var onOpenURL: ((URL) -> Void)? {
        get { (documentView as? CJKCanvas)?.onOpenURL }
        set { (documentView as? CJKCanvas)?.onOpenURL = newValue }
    }

    public convenience init(_ blocks: [CJKBlock], fontSize: Float) {
        self.init(frame: .zero)
        setContent(blocks, fontSize: fontSize)
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        initialize()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        initialize()
    }

    private func initialize() {
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        documentView = CJKCanvas()
    }

    public func setContent(_ blocks: [CJKBlock], fontSize: Float) {
        (documentView as? CJKCanvas)?.configure(blocks: blocks, fontSize: fontSize)
    }

    /// A full engine relayout is O(paragraphs), so the canvas skips relayout during live resize and
    /// flushes the one deferred reflow when the drag ends.
    public override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        (documentView as? CJKCanvas)?.flushDeferredResize()
    }
}

/// The scroll view's document view. It is **flipped** (top-left origin) so the scroll view shows the
/// first line first; `CoreTextLayoutRenderer` expects a y-up context, so `draw(_:)` flips the
/// CGContext back to y-up before drawing — the two flips cancel.
final class CJKCanvas: NSView, NSUserInterfaceValidations {
    private let padding: CGFloat = 28

    private var blocks: [CJKBlock] = []
    private var fontSize: Float = 18
    private var typesetter = Typesetter(fontSize: 18, cjkFamily: "PingFang SC", latinFamily: "Helvetica Neue")
    private var builder: DocBuilder?        // AttributedString lowered ONCE per (blocks, fontSize)
    // Qualified as `Tiqian.Document`: bare `Document` is ambiguous in an Xcode app build where
    // SwiftUI also exports a `Document` symbol (a clean-room build hit "'Document' is ambiguous").
    private var document: Tiqian.Document?
    private var laidOutBucket: CGFloat = -1 // grid-column bucket the current document was laid out at
    private var deferredResize = false      // a live resize crossed a bucket; reflow when it settles
    private var selectionRange = NSRange(location: 0, length: 0)
    private var selectionAnchor: Int?
    private var pressedLinkTarget: String?
    private var linkMouseDownPoint: NSPoint?
    var onOpenURL: ((URL) -> Void)?

    override var isFlipped: Bool { true }

    /// Rebuilds the (lowered) engine builder and reflows only when the content or font size actually
    /// changed. On a plain window resize the builder is reused — see `relayout()`.
    func configure(blocks: [CJKBlock], fontSize: Float) {
        var changed = false
        if fontSize != self.fontSize {
            self.fontSize = fontSize
            typesetter = Typesetter(fontSize: fontSize, cjkFamily: "PingFang SC", latinFamily: "Helvetica Neue")
            changed = true
        }
        if blocks != self.blocks {
            self.blocks = blocks
            changed = true
        }
        if changed {
            builder = blocks.isEmpty ? nil : Lowering.builder(blocks, baseSize: fontSize, typesetter: typesetter)
            laidOutBucket = -1 // force a relayout for the new content
            selectionRange = NSRange(location: 0, length: 0)
            selectionAnchor = nil
            pressedLinkTarget = nil
            linkMouseDownPoint = nil
            relayout()
            scrollToTop()
            needsDisplay = true
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        // Fires again on reattach / clip change: drop any prior observer first so observers don't
        // accumulate (each would fire a redundant relayout).
        NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: nil)
        guard let clip = superview as? NSClipView else { return }
        clip.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(viewportChanged),
            name: NSView.frameDidChangeNotification, object: clip,
        )
        relayout()
    }

    @objc private func viewportChanged() {
        // A full relayout re-runs the engine's line-break for every paragraph (~13ms for the essay), so
        // reflowing on every frame of a live window/pane drag drops frames. During a live resize just
        // remember that the viewport moved and reflow once, when `CJKTextView.viewDidEndLiveResize`
        // fires — the drag then stays smooth (the current layout is left-aligned in the new width until
        // it settles). Non-live changes (initial layout, split-view snaps, zoom) reflow immediately.
        if enclosingScrollView?.inLiveResize == true || inLiveResize {
            deferredResize = true
            return
        }
        if relayout() { needsDisplay = true }
    }

    /// Flush the one relayout deferred during a live resize (called when the drag ends).
    func flushDeferredResize() {
        guard deferredResize else { return }
        deferredResize = false
        if relayout() { needsDisplay = true }
    }

    private var viewportWidth: CGFloat { enclosingScrollView?.contentView.bounds.width ?? bounds.width }
    private var viewportHeight: CGFloat { enclosingScrollView?.contentView.bounds.height ?? bounds.height }

    /// Re-lay-out only when the grid-column *bucket* changes. The engine grids line length to whole
    /// characters (font-size units), so the layout is identical for any width within a bucket — a
    /// live horizontal drag then re-lays-out about once per character-width instead of every pixel
    /// (and height-only resizes / sub-pixel ticks reuse the current document). Returns whether the
    /// visible layout or the view size changed (so the caller only repaints when needed).
    @discardableResult
    private func relayout() -> Bool {
        let em = CGFloat(fontSize)
        let columnWidth = viewportWidth - padding * 2
        guard columnWidth > 0, em > 0, let builder else {
            let changed = document != nil || frame.size != .zero
            document = nil
            laidOutBucket = -1
            if frame.size != .zero { setFrameSize(.zero) }
            return changed
        }
        // Grid-column bucket: the engine grids line length to whole characters, so the layout — and
        // thus the content-sized frame — is identical for any width within a bucket. Nothing to do
        // until a whole column is gained/lost, so a within-bucket resize (any direction) is free.
        let bucket = (columnWidth / em).rounded(.down)
        if bucket == laidOutBucket, document != nil { return false }
        let gridWidth = bucket * em
        document = builder.layout(width: Float(gridWidth))
        laidOutBucket = bucket
        let contentHeight = (document.map { CGFloat($0.height) } ?? 0) + padding * 2
        setFrameSize(NSSize(width: gridWidth + padding * 2, height: contentHeight))
        window?.invalidateCursorRects(for: self)
        return true
    }

    private func scrollToTop() {
        scroll(NSPoint(x: 0, y: 0)) // flipped: top is y == 0
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
        for link in linkRectsForDisplay {
            addCursorRect(link.rect, cursor: .pointingHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let document else { return }
        pressedLinkTarget = event.clickCount == 1 && !event.modifierFlags.contains(.shift)
            ? linkTarget(at: point)
            : nil
        linkMouseDownPoint = point

        if event.clickCount >= 2 {
            let hit = selectionOffset(at: point)
            if let word = CJKWordTokenizer.range(
                in: document.text,
                containingUTF16Offset: hit
            ) {
                selectionAnchor = word.location
                setSelection(start: word.location, end: NSMaxRange(word))
                return
            }
            if let word = document.selectionWord(
                x: Double(point.x - padding),
                y: Double(point.y - padding)
            ) {
                selectionAnchor = Int(word.start)
                setSelection(start: Int(word.start), end: Int(word.end))
                return
            }
        }

        let offset = selectionOffset(at: point)
        if event.modifierFlags.contains(.shift), selectionRange.length > 0 {
            selectionAnchor = selectionRange.location
            setSelection(start: selectionRange.location, end: offset)
        } else {
            selectionAnchor = offset
            setSelection(start: offset, end: offset)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard selectionAnchor != nil else { return }
        autoscroll(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if let down = linkMouseDownPoint, hypot(point.x - down.x, point.y - down.y) > 3 {
            pressedLinkTarget = nil
        }
        setSelection(start: selectionAnchor ?? 0, end: selectionOffset(at: point))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            selectionAnchor = nil
            pressedLinkTarget = nil
            linkMouseDownPoint = nil
        }
        let point = convert(event.locationInWindow, from: nil)
        guard let target = pressedLinkTarget, linkTarget(at: point) == target else { return }
        openLink(target)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    @objc func copy(_ sender: Any?) {
        guard let selectedClipboardText, !selectedClipboardText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedClipboardText, forType: .string)
    }

    @objc override func selectAll(_ sender: Any?) {
        let length = document?.text.utf16.count ?? 0
        setSelection(start: 0, end: length)
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) { return selectionRange.length > 0 }
        if item.action == #selector(selectAll(_:)) {
            let length = document?.text.utf16.count ?? 0
            return length > 0 && selectionRange.length != length
        }
        return false
    }

    var selectedSourceText: String? {
        guard selectionRange.length > 0, let document else { return nil }
        return document.textInRange(
            start: selectionRange.location,
            end: NSMaxRange(selectionRange)
        )
    }

    var selectedClipboardText: String? {
        guard selectionRange.length > 0, let document else { return nil }
        return document.clipboardTextInRange(
            start: selectionRange.location,
            end: NSMaxRange(selectionRange)
        )
    }

    var selectionRectsForDisplay: [NSRect] {
        guard selectionRange.length > 0, let document else { return [] }
        return document.selectionBoxes(
            start: selectionRange.location,
            end: NSMaxRange(selectionRange)
        ).map { box in
            NSRect(
                x: padding + CGFloat(box.left),
                y: padding + CGFloat(box.top),
                width: CGFloat(box.right - box.left),
                height: CGFloat(box.bottom - box.top)
            )
        }
    }

    var linkRectsForDisplay: [(target: String, rect: NSRect)] {
        document?.linkBoxes().map { box in
            (
                box.target,
                NSRect(
                    x: padding + CGFloat(box.left),
                    y: padding + CGFloat(box.top),
                    width: CGFloat(box.right - box.left),
                    height: CGFloat(box.bottom - box.top)
                )
            )
        } ?? []
    }

    func linkTarget(at point: NSPoint) -> String? {
        document?.linkAt(
            x: Double(point.x - padding),
            y: Double(point.y - padding)
        )
    }

    @discardableResult
    func activateLink(at point: NSPoint) -> Bool {
        guard let target = linkTarget(at: point) else { return false }
        return openLink(target)
    }

    @discardableResult
    private func openLink(_ target: String) -> Bool {
        guard let url = URL(string: target) else { return false }
        if let onOpenURL {
            onOpenURL(url)
        } else {
            NSWorkspace.shared.open(url)
        }
        return true
    }

    func selectionOffset(at point: NSPoint) -> Int {
        guard let document else { return 0 }
        return Int(document.selectionOffset(
            x: Double(point.x - padding),
            y: Double(point.y - padding)
        ))
    }

    private func setSelection(start: Int, end: Int) {
        let length = document?.text.utf16.count ?? 0
        let lower = Swift.min(start, end).clamped(to: 0...length)
        let upper = Swift.max(start, end).clamped(to: lower...length)
        let next = NSRange(location: lower, length: upper - lower)
        guard next != selectionRange else { return }
        selectionRange = next
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .selectedTextChanged)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        guard let document, let ctx = NSGraphicsContext.current?.cgContext else { return }

        NSColor.selectedTextBackgroundColor.setFill()
        selectionRectsForDisplay.forEach { NSBezierPath(rect: $0).fill() }

        ctx.saveGState()
        // Flipped (y-down) view; the renderer expects y-up. Undo the flip so CTFontDrawGlyphs draws
        // upright and `canvasHeight - y` lands where it should.
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        // Base text/decorations inherit this fill color (colored spans override per cluster). Top
        // inset is folded into canvasHeight; left inset is a translate.
        NSColor.textColor.setFill()
        ctx.translateBy(x: padding, y: 0)
        // The view is flipped (y-down), so the dirty rect maps to document coordinates by removing
        // the inset; blocks outside it are skipped.
        document.draw(
            in: ctx,
            canvasHeight: Double(bounds.height) - Double(padding),
            visibleRect: dirtyRect.offsetBy(dx: -padding, dy: -padding),
        )
        ctx.restoreGState()
    }

    // Accessibility (VoiceOver): the canvas only paints glyphs, so expose the document's source text
    // as a static-text value. This is a paragraph-agnostic first version — per-paragraph elements and
    // selection semantics are follow-ups; a reader must at least be able to READ the prose aloud.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? { "正文" }
    override func accessibilityValue() -> Any? { document?.text }

    override func accessibilitySelectedText() -> String? { selectedSourceText }
    override func accessibilitySelectedTextRange() -> NSRange { selectionRange }
    override func setAccessibilitySelectedTextRange(_ range: NSRange) {
        setSelection(start: range.location, end: NSMaxRange(range))
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
#elseif os(iOS)
import SwiftUI
import UIKit
import Tiqian

/// A reusable SwiftUI view that typesets and scrolls a CJK document with the Tiqian engine — the
/// iOS peer of Compose's `CjkText` and the macOS `CJKText`. Content stays native
/// `AttributedString`; this view only owns viewport lifecycle, Core Graphics replay and scrolling.
public struct CJKText: UIViewRepresentable {
    @Environment(\.openURL) private var openURL
    public let blocks: [CJKBlock]
    public let fontSize: Float

    public init(_ blocks: [CJKBlock], fontSize: Float) {
        self.blocks = blocks
        self.fontSize = fontSize
    }

    public func makeUIView(context: Context) -> CJKTextView {
        let textView = CJKTextView(blocks, fontSize: fontSize)
        textView.onOpenURL = { url in openURL(url) }
        return textView
    }

    public func updateUIView(_ textView: CJKTextView, context: Context) {
        textView.onOpenURL = { url in openURL(url) }
        textView.setContent(blocks, fontSize: fontSize)
    }
}

/// UIKit owns scrolling and viewport changes; the canvas owns one width-bucketed engine layout.
/// Both initial presentation and rotation/split-view resizing go through `layoutSubviews`, so the
/// host never has to report its width manually or maintain a second layout model. UIKit consumers
/// use this view directly; `CJKText` is its SwiftUI adapter.
public final class CJKTextView: UIScrollView {
    private let canvas = CJKCanvas()
    private var updatingCanvasFrame = false

    /// Native embedding hook. SwiftUI's `CJKText` wires this to the environment `OpenURLAction`;
    /// a UIKit host may override it, otherwise links open through `UIApplication`.
    public var onOpenURL: ((URL) -> Void)? {
        get { canvas.onOpenURL }
        set { canvas.onOpenURL = newValue }
    }

    public convenience init(_ blocks: [CJKBlock], fontSize: Float) {
        self.init(frame: .zero)
        setContent(blocks, fontSize: fontSize)
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        initialize()
    }

    private func initialize() {
        backgroundColor = .systemBackground
        alwaysBounceVertical = true
        showsHorizontalScrollIndicator = false
        keyboardDismissMode = .interactive
        addSubview(canvas)
    }

    public func setContent(_ blocks: [CJKBlock], fontSize: Float) {
        let contentChanged = canvas.configure(blocks: blocks, fontSize: fontSize)
        setNeedsLayout()
        layoutIfNeeded()
        if contentChanged {
            setContentOffset(CGPoint(x: 0, y: -adjustedContentInset.top), animated: false)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard !updatingCanvasFrame else { return }

        let canvasSize = canvas.sizeThatFits(viewport: bounds.size)
        if canvas.frame.origin != .zero || canvas.frame.size != canvasSize || contentSize != canvasSize {
            updatingCanvasFrame = true
            canvas.frame = CGRect(origin: .zero, size: canvasSize)
            contentSize = canvasSize
            updatingCanvasFrame = false
        }
    }
}

/// The iOS drawing surface. UIKit supplies a y-down graphics context, while the shared renderer
/// consumes a native y-up context; `draw(_:)` normalizes that boundary before replaying the same
/// `Document` used on macOS.
final class CJKCanvas: UIView, UITextInput, UITextInteractionDelegate, UIGestureRecognizerDelegate {
    private let padding: CGFloat = 28

    private var blocks: [CJKBlock] = []
    private var fontSize: Float = 18
    private var typesetter = Typesetter(
        fontSize: 18,
        cjkFamily: "PingFang SC",
        latinFamily: "Helvetica Neue"
    )
    private var builder: DocBuilder?
    private var document: Tiqian.Document?
    private var laidOutBucket: CGFloat = -1

    // Stored protocol state for the native, non-editable UITextInteraction implemented in
    // CJKTextInput.swift. Geometry still comes exclusively from [document].
    weak var inputDelegate: UITextInputDelegate?
    lazy var tokenizer: UITextInputTokenizer = UITextInputStringTokenizer(textInput: self)
    var textSelectionRange: NSRange? = NSRange(location: 0, length: 0)
    var textInputSource = ""
    var nativeTextInteraction: UITextInteraction?
    var onOpenURL: ((URL) -> Void)?

    var selectionDocument: Tiqian.Document? { document }
    var selectionPadding: CGFloat { padding }

    override init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        initialize()
    }

    private func initialize() {
        isOpaque = true
        contentMode = .redraw
        backgroundColor = .systemBackground
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLabel = "正文"
        let textInteraction = UITextInteraction(for: .nonEditable)
        textInteraction.textInput = self
        textInteraction.delegate = self
        addInteraction(textInteraction)
        nativeTextInteraction = textInteraction
        let linkTap = UITapGestureRecognizer(target: self, action: #selector(activateLinkGesture(_:)))
        linkTap.cancelsTouchesInView = false
        linkTap.delegate = self
        addGestureRecognizer(linkTap)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle else { return }
        backgroundColor = .systemBackground
        setNeedsDisplay()
    }

    /// Rebuild the lowered builder only when authored content changes. Viewport-only changes
    /// keep the already-lowered builder and only rerun line breaking for a new column bucket.
    @discardableResult
    func configure(blocks: [CJKBlock], fontSize: Float) -> Bool {
        var changed = false
        if fontSize != self.fontSize {
            self.fontSize = fontSize
            typesetter = Typesetter(
                fontSize: fontSize,
                cjkFamily: "PingFang SC",
                latinFamily: "Helvetica Neue"
            )
            changed = true
        }
        if blocks != self.blocks {
            self.blocks = blocks
            changed = true
        }
        if changed {
            builder = blocks.isEmpty
                ? nil
                : Lowering.builder(blocks, baseSize: fontSize, typesetter: typesetter)
            document = nil
            laidOutBucket = -1
            accessibilityValue = nil
            setNeedsDisplay()
        }
        return changed
    }

    /// Resolve the engine document for [viewport], returning a vertically scrollable canvas size.
    /// Width is quantized exactly like the macOS frontend because Tiqian grids the measure to whole
    /// character columns; height-only UIKit layout passes therefore do not relayout the document.
    func sizeThatFits(viewport: CGSize) -> CGSize {
        let em = CGFloat(fontSize)
        let availableWidth = viewport.width - padding * 2
        guard availableWidth > 0, em > 0, let builder else {
            document = nil
            laidOutBucket = -1
            accessibilityValue = nil
            textInputDocumentDidChange()
            return viewport
        }

        let bucket = max(1, (availableWidth / em).rounded(.down))
        let gridWidth = bucket * em
        if bucket != laidOutBucket || document == nil {
            document = builder.layout(width: Float(gridWidth))
            laidOutBucket = bucket
            accessibilityValue = document?.text
            textInputDocumentDidChange()
            setNeedsDisplay()
        }

        let documentHeight = CGFloat(document?.height ?? 0) + padding * 2
        return CGSize(
            width: max(viewport.width, gridWidth + padding * 2),
            height: max(viewport.height, documentHeight)
        )
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(UIColor.systemBackground.cgColor)
        context.fill(rect)
        guard let document else { return }

        context.saveGState()
        // UIKit's current context is y-down. Restore native Core Graphics y-up coordinates before
        // calling the shared renderer, then fold the top and left insets into its existing contract.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(UIColor.label.cgColor)
        context.translateBy(x: padding, y: 0)
        // UIKit's rect is y-down from the view top, so it maps to document coordinates by removing
        // the inset; blocks outside it are skipped.
        document.draw(
            in: context,
            canvasHeight: Double(bounds.height) - Double(padding),
            visibleRect: rect.offsetBy(dx: -padding, dy: -padding),
        )
        context.restoreGState()
    }

    var linkRectsForDisplay: [(target: String, rect: CGRect)] {
        document?.linkBoxes().map { box in
            (
                box.target,
                CGRect(
                    x: padding + CGFloat(box.left),
                    y: padding + CGFloat(box.top),
                    width: CGFloat(box.right - box.left),
                    height: CGFloat(box.bottom - box.top)
                )
            )
        } ?? []
    }

    func linkTarget(at point: CGPoint) -> String? {
        document?.linkAt(
            x: Double(point.x - padding),
            y: Double(point.y - padding)
        )
    }

    @discardableResult
    func activateLink(at point: CGPoint) -> Bool {
        guard let target = linkTarget(at: point), let url = URL(string: target) else { return false }
        if let onOpenURL {
            onOpenURL(url)
        } else {
            UIApplication.shared.open(url)
        }
        return true
    }

    @objc private func activateLinkGesture(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        activateLink(at: gesture.location(in: self))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        linkTarget(at: touch.location(in: self)) != nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }

}
#endif
