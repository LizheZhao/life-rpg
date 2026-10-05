import LifeRPGCore
import SwiftUI
import UIKit

/// A `UITextView` that reports a backspace pressed on nothing, which no delegate method does: the
/// editor reads it as "delete this prompt".
final class JournalUITextView: UITextView {
    var onBackspaceWhenEmpty: (() -> Void)?

    override func deleteBackward() {
        if text.isEmpty, markedTextRange == nil, let onBackspaceWhenEmpty {
            onBackspaceWhenEmpty()
            return
        }
        super.deleteBackward()
    }
}

/// The text of one block: a text block's words or a prompt's answer. One `UITextView` per block,
/// as tall as its text (the page's `ScrollView` scrolls, not the view), because SwiftUI's own
/// editors cannot report or set a cursor on iOS 17.
///
/// The model owns the text. A keystroke is reported (`textChanged`) and never written back into the
/// view being typed in, which would move its cursor; `updateUIView` sets the text only when the
/// model's differs from the view's, which is a split, a removed question or a new block.
struct JournalTextField: UIViewRepresentable {
    let blockID: UUID
    let text: String
    /// An answer: return at its end starts free text below it, and backspace on nothing deletes the
    /// prompt. A text block has neither.
    let isAnswer: Bool
    let focus: JournalEditorModel.FocusRequest?
    let model: JournalEditorModel

    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.legibilityWeight) private var legibility

    private var style: LR.Typography { .journalBody }
    private var font: UIFont {
        let spec = style.spec
        return LRFonts.uiFont(spec.family, weight: spec.weight + (legibility == .bold ? 100 : 0),
                              size: style.pointSize(dynamicType: dynamicType))
    }

    private var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style.spec.lineSpacing
        return [.font: font, .foregroundColor: LR.Color.ui(Palette.ink), .paragraphStyle: paragraph]
    }

    func makeCoordinator() -> Coordinator { Coordinator(blockID: blockID, model: model) }

    func makeUIView(context: Context) -> JournalUITextView {
        let view = JournalUITextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.tintColor = LR.Color.ui(Palette.trendDeep)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.accessibilityIdentifier = blockID.uuidString
        return view
    }

    func updateUIView(_ view: JournalUITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isAnswer = isAnswer
        view.onBackspaceWhenEmpty = isAnswer ? { [model, blockID] in model.backspaceAtStartOfEmptyAnswer(blockID) } : nil
        let attributes = attributes
        view.typingAttributes = attributes
        if view.text != text || coordinator.pointSize != font.pointSize {
            coordinator.pointSize = font.pointSize
            coordinator.applying = true
            view.attributedText = NSAttributedString(string: text, attributes: attributes)
            coordinator.applying = false
        }
        if let focus, focus.focus.blockID == blockID, focus.serial != coordinator.appliedSerial {
            coordinator.appliedSerial = focus.serial
            coordinator.focus(view, on: focus, attempts: 8)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: JournalUITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let fitted = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(max(fitted.height, font.lineHeight + style.spec.lineSpacing)))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        let blockID: UUID
        let model: JournalEditorModel
        var isAnswer = false
        /// True while the text is being set from the model, so the delegate does not report it back.
        var applying = false
        var appliedSerial = 0
        var pointSize: CGFloat = 0

        init(blockID: UUID, model: JournalEditorModel) {
            self.blockID = blockID
            self.model = model
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !applying else { return }
            model.textChanged(blockID, to: textView.text)
            keepCaretVisible(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !applying, textView.isFirstResponder else { return }
            let range = textView.selectedRange
            model.cursorMoved(blockID, toCharacterOffset:
                JournalCursor.characterOffset(forUTF16Offset: range.location, in: textView.text))
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            // Return with the caret at the very end of an answer: free text starts below.
            if isAnswer, replacement == "\n", range.length == 0, range.location == textView.text.utf16.count,
               textView.markedTextRange == nil {
                model.returnAtEndOfAnswer(blockID)
                return false
            }
            return true
        }

        /// Puts the cursor where the model said, once the view is in a window (a block made by the
        /// same edit is not attached yet when its first update runs).
        func focus(_ view: JournalUITextView, on request: JournalEditorModel.FocusRequest, attempts: Int) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                guard view.window != nil, view.becomeFirstResponder() else {
                    if attempts > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak view] in
                            guard let self, let view else { return }
                            self.focus(view, on: request, attempts: attempts - 1)
                        }
                    }
                    return
                }
                let utf16 = JournalCursor.utf16Offset(forCharacterOffset: request.focus.offset, in: view.text)
                view.selectedRange = NSRange(location: utf16, length: 0)
                model.focusApplied(request)
                keepCaretVisible(view)
            }
        }

        /// The page's `ScrollView` is the view's scroll view; the caret is scrolled clear of the
        /// header and the prompt bar after the layout that the keystroke caused.
        private func keepCaretVisible(_ textView: UITextView) {
            DispatchQueue.main.async { [weak textView] in
                guard let textView, textView.isFirstResponder, let end = textView.selectedTextRange?.end else { return }
                var ancestor = textView.superview
                while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
                guard let scroll = ancestor as? UIScrollView else { return }
                let caret = textView.convert(textView.caretRect(for: end), to: scroll)
                scroll.scrollRectToVisible(caret.insetBy(dx: 0, dy: -32), animated: false)
            }
        }
    }
}
