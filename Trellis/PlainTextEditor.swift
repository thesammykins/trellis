import AppKit
import SwiftUI

@MainActor
struct PlainTextEditor: NSViewRepresentable {
    @Binding private var text: String
    let label: String
    let focusOnAppear: Bool

    init(text: Binding<String>, label: String = "Text", focusOnAppear: Bool = false) {
        _text = text
        self.label = label
        self.focusOnAppear = focusOnAppear
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = InitialFocusTextView()
        textView.focusOnAttach = focusOnAppear
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.enabledTextCheckingTypes = 0
        textView.setAccessibilityLabel(label)
        textView.delegate = context.coordinator
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.setAccessibilityLabel(label)
        guard textView.string != text else { return }

        let selection = preservedSelection(textView.selectedRanges, in: text)
        context.coordinator.isReplacingText = true
        textView.string = text
        textView.selectedRanges = selection
        context.coordinator.isReplacingText = false
    }

    private func preservedSelection(_ selections: [NSValue], in text: String) -> [NSValue] {
        let length = (text as NSString).length
        return selections.map { value in
            let range = value.rangeValue
            let location = min(range.location == NSNotFound ? length : range.location, length)
            let selectedLength = min(range.length, length - location)
            return NSValue(range: NSRange(location: location, length: selectedLength))
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isReplacingText = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isReplacingText,
                  let textView = notification.object as? NSTextView
            else { return }
            text.wrappedValue = textView.string
        }
    }
}

@MainActor
private final class InitialFocusTextView: NSTextView {
    var focusOnAttach = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if focusOnAttach, let window, window.isKeyWindow {
            focusOnAttach = false
            window.makeFirstResponder(self)
        }
    }
}
