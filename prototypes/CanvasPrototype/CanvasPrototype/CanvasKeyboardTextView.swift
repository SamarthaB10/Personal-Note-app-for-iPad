import UIKit

/// A text box editor that accepts keyboard input and refuses Pencil Scribble.
final class CanvasKeyboardTextView: UITextView, UITextViewDelegate, UIScribbleInteractionDelegate {
    var onTextChange: ((String) -> Void)?
    var onEditingEnd: (() -> Void)?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        delegate = self
        isEditable = true
        isSelectable = true
        isScrollEnabled = false
        backgroundColor = .white
        textContainerInset = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        layer.borderWidth = 1
        layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.65).cgColor
        layer.cornerRadius = 4
        accessibilityLabel = "Text box"
        addInteraction(UIScribbleInteraction(delegate: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
        false
    }

    func textViewDidChange(_ textView: UITextView) {
        onTextChange?(textView.text ?? "")
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        onEditingEnd?()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let containsPencil = event?.allTouches?.contains(where: { $0.type == .pencil }) ?? false
        guard !containsPencil else { return false }
        return super.point(inside: point, with: event)
    }
}
