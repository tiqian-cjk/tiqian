#if os(iOS)
import UIKit
import Tiqian

/// Integer-backed UIKit text positions. Offsets are UTF-16, matching NSString, the engine text and
/// Tiqian's source ranges.
final class CJKTextPosition: UITextPosition {
    let offset: Int

    init(_ offset: Int) {
        self.offset = offset
    }
}

final class CJKTextRange: UITextRange {
    let lower: CJKTextPosition
    let upper: CJKTextPosition

    init(start: Int, end: Int) {
        lower = CJKTextPosition(min(start, end))
        upper = CJKTextPosition(max(start, end))
    }

    override var start: UITextPosition { lower }
    override var end: UITextPosition { upper }
    override var isEmpty: Bool { lower.offset == upper.offset }
}

/// UIKit-owned selection chrome consumes these annotations. The rectangles themselves come from
/// `Document.selectionBoxes`, so highlights and handles replay Tiqian's occupied cluster geometry.
final class CJKNativeSelectionRect: UITextSelectionRect {
    private let selectionRect: CGRect
    private let includesStart: Bool
    private let includesEnd: Bool

    init(rect: CGRect, containsStart: Bool, containsEnd: Bool) {
        selectionRect = rect
        includesStart = containsStart
        includesEnd = containsEnd
    }

    override var rect: CGRect { selectionRect }
    override var writingDirection: NSWritingDirection { .leftToRight }
    override var containsStart: Bool { includesStart }
    override var containsEnd: Bool { includesEnd }
    override var isVertical: Bool { false }
}

extension CJKCanvas {
    private var textLength: Int { textInputSource.utf16.count }

    override var canBecomeFirstResponder: Bool { true }

    var hasText: Bool { textLength > 0 }
    var isEditable: Bool { false }
    var textInputView: UIView { self }

    var selectedTextRange: UITextRange? {
        get {
            guard let range = textSelectionRange else { return nil }
            return CJKTextRange(start: range.location, end: NSMaxRange(range))
        }
        set {
            let normalized: NSRange?
            if let range = newValue as? CJKTextRange {
                if range.isEmpty {
                    let caret = normalizedOffset(range.lower.offset, forward: true)
                    normalized = NSRange(location: caret, length: 0)
                } else {
                    let start = normalizedOffset(range.lower.offset, forward: false)
                    let end = normalizedOffset(range.upper.offset, forward: true)
                    normalized = NSRange(location: start, length: max(0, end - start))
                }
            } else {
                normalized = nil
            }
            guard normalized != textSelectionRange else { return }
            inputDelegate?.selectionWillChange(self)
            textSelectionRange = normalized
            inputDelegate?.selectionDidChange(self)
            setNeedsLayout()
        }
    }

    var markedTextRange: UITextRange? { nil }
    var markedTextStyle: [NSAttributedString.Key: Any]? {
        get { nil }
        set { }
    }

    var beginningOfDocument: UITextPosition { CJKTextPosition(0) }
    var endOfDocument: UITextPosition { CJKTextPosition(textLength) }

    func text(in range: UITextRange) -> String? {
        guard let range = range as? CJKTextRange, let document = selectionDocument else { return nil }
        return document.textInRange(
            start: range.lower.offset,
            end: range.upper.offset
        )
    }

    func replace(_ range: UITextRange, withText text: String) { }
    func insertText(_ text: String) { }
    func deleteBackward() { }
    func setMarkedText(_ markedText: String?, selectedRange: NSRange) { }
    func unmarkText() { }

    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        guard
            let from = fromPosition as? CJKTextPosition,
            let to = toPosition as? CJKTextPosition,
            from.offset <= to.offset
        else { return nil }
        return CJKTextRange(start: from.offset, end: to.offset)
    }

    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        guard let position = position as? CJKTextPosition else { return nil }
        let raw = position.offset + offset
        guard raw >= 0, raw <= textLength else { return nil }
        return CJKTextPosition(normalizedOffset(raw, forward: offset >= 0))
    }

    func position(
        from position: UITextPosition,
        in direction: UITextLayoutDirection,
        offset: Int
    ) -> UITextPosition? {
        guard let position = position as? CJKTextPosition else { return nil }
        if direction == .left {
            return self.position(from: position, offset: -offset)
        }
        if direction == .right {
            return self.position(from: position, offset: offset)
        }
        guard let document = selectionDocument else { return CJKTextPosition(position.offset) }
        let caret = document.caretBox(offset: position.offset)
        let targetY = direction == .up ? caret.top - 1.0 : caret.bottom + 1.0
        let target = Int(document.selectionOffset(x: caret.left, y: targetY))
        return CJKTextPosition(normalizedOffset(target, forward: direction == .down))
    }

    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        guard
            let lhs = position as? CJKTextPosition,
            let rhs = other as? CJKTextPosition
        else { return .orderedSame }
        if lhs.offset < rhs.offset { return .orderedAscending }
        if lhs.offset > rhs.offset { return .orderedDescending }
        return .orderedSame
    }

    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        guard
            let from = from as? CJKTextPosition,
            let to = toPosition as? CJKTextPosition
        else { return 0 }
        return to.offset - from.offset
    }

    func position(
        within range: UITextRange,
        farthestIn direction: UITextLayoutDirection
    ) -> UITextPosition? {
        guard let range = range as? CJKTextRange else { return nil }
        return direction == .left || direction == .up ? range.lower : range.upper
    }

    func characterRange(
        byExtending position: UITextPosition,
        in direction: UITextLayoutDirection
    ) -> UITextRange? {
        guard let position = position as? CJKTextPosition else { return nil }
        if direction == .left || direction == .up {
            guard position.offset > 0 else { return nil }
            let start = normalizedOffset(position.offset - 1, forward: false)
            return CJKTextRange(start: start, end: position.offset)
        }
        guard position.offset < textLength else { return nil }
        let end = normalizedOffset(position.offset + 1, forward: true)
        return CJKTextRange(start: position.offset, end: end)
    }

    func baseWritingDirection(
        for position: UITextPosition,
        in direction: UITextStorageDirection
    ) -> NSWritingDirection { .leftToRight }

    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) { }

    func firstRect(for range: UITextRange) -> CGRect {
        guard let range = range as? CJKTextRange else { return .zero }
        if range.isEmpty {
            return caretRect(for: range.lower)
        }
        return selectionRects(for: range).first?.rect ?? .zero
    }

    func caretRect(for position: UITextPosition) -> CGRect {
        guard
            let position = position as? CJKTextPosition,
            let document = selectionDocument
        else { return .zero }
        let box = document.caretBox(offset: position.offset)
        return platformRect(box)
    }

    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        guard
            let range = range as? CJKTextRange,
            !range.isEmpty,
            let document = selectionDocument
        else { return [] }
        let boxes = document.selectionBoxes(
            start: range.lower.offset,
            end: range.upper.offset
        )
        return boxes.enumerated().map { index, box in
            CJKNativeSelectionRect(
                rect: platformRect(box),
                containsStart: index == boxes.startIndex,
                containsEnd: index == boxes.index(before: boxes.endIndex)
            )
        }
    }

    func closestPosition(to point: CGPoint) -> UITextPosition? {
        guard let document = selectionDocument else { return CJKTextPosition(0) }
        let offset = document.selectionOffset(
            x: Double(point.x - selectionPadding),
            y: Double(point.y - selectionPadding)
        )
        return CJKTextPosition(Int(offset))
    }

    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        guard
            let hit = closestPosition(to: point) as? CJKTextPosition,
            let range = range as? CJKTextRange
        else { return nil }
        return CJKTextPosition(hit.offset.coerce(in: range.lower.offset...range.upper.offset))
    }

    func characterRange(at point: CGPoint) -> UITextRange? {
        guard let document = selectionDocument else { return nil }
        let hit = Int(document.selectionOffset(
            x: Double(point.x - selectionPadding),
            y: Double(point.y - selectionPadding)
        ))
        if let range = CJKWordTokenizer.range(
            in: document.text,
            containingUTF16Offset: hit
        ) {
            return CJKTextRange(start: range.location, end: NSMaxRange(range))
        }
        guard let range = document.selectionWord(
            x: Double(point.x - selectionPadding),
            y: Double(point.y - selectionPadding)
        ) else { return nil }
        return CJKTextRange(start: Int(range.start), end: Int(range.end))
    }

    func interactionShouldBegin(_ interaction: UITextInteraction, at point: CGPoint) -> Bool {
        selectionDocument != nil && textLength > 0
    }

    func interactionWillBegin(_ interaction: UITextInteraction) {
        becomeFirstResponder()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(copy(_:)) {
            return textSelectionRange?.length ?? 0 > 0
        }
        if action == #selector(selectAll(_:)) {
            return textLength > 0 && textSelectionRange?.length != textLength
        }
        return false
    }

    override func copy(_ sender: Any?) {
        guard let selected = selectedClipboardText, !selected.isEmpty else { return }
        UIPasteboard.general.string = selected
    }

    override func selectAll(_ sender: Any?) {
        selectedTextRange = CJKTextRange(start: 0, end: textLength)
    }

    var selectedSourceText: String? {
        guard let range = selectedTextRange else { return nil }
        return text(in: range)
    }

    var selectedClipboardText: String? {
        guard
            let range = selectedTextRange as? CJKTextRange,
            let document = selectionDocument
        else { return nil }
        return document.clipboardTextInRange(
            start: range.lower.offset,
            end: range.upper.offset
        )
    }

    /// Called whenever the engine document is replaced. Content changes reset selection; width-only
    /// reflow keeps source offsets stable and merely invalidates native selection geometry.
    func textInputDocumentDidChange() {
        let nextSource = selectionDocument?.text ?? ""
        if nextSource != textInputSource {
            inputDelegate?.textWillChange(self)
            inputDelegate?.selectionWillChange(self)
            textInputSource = nextSource
            textSelectionRange = NSRange(location: 0, length: 0)
            inputDelegate?.textDidChange(self)
            inputDelegate?.selectionDidChange(self)
        } else if let range = textSelectionRange {
            let location = min(range.location, textLength)
            let length = min(range.length, textLength - location)
            textSelectionRange = NSRange(location: location, length: length)
        }
        accessibilityValue = nextSource.isEmpty ? nil : nextSource
        setNeedsLayout()
    }

    private func normalizedOffset(_ offset: Int, forward: Bool) -> Int {
        let clamped = offset.coerce(in: 0...textLength)
        guard let document = selectionDocument else { return clamped }
        return Int(document.selectionBoundary(offset: clamped, forward: forward))
    }

    private func platformRect(_ box: SelectionBox) -> CGRect {
        CGRect(
            x: selectionPadding + CGFloat(box.left),
            y: selectionPadding + CGFloat(box.top),
            width: CGFloat(box.right - box.left),
            height: CGFloat(box.bottom - box.top)
        )
    }
}

private extension Int {
    func coerce(in range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
#endif
