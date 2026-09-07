import AppKit
import SwiftUI

@MainActor
struct PlainTextEditor: NSViewRepresentable {
    @Binding private var text: String
    let label: String
    let focusOnAppear: Bool
    let usesSystemFont: Bool
    let accessibilityHelp: String?
    let focusRequest: UUID?
    let onFocusConsumed: ((UUID) -> Void)?
    let onSubmit: (() -> Void)?
    let onReference: ((NSRange) -> Void)?
    let selectionRequest: NSRange?

    init(text: Binding<String>, label: String = "Text", focusOnAppear: Bool = false,
         usesSystemFont: Bool = false,
         accessibilityHelp: String? = nil,
         focusRequest: UUID? = nil, onFocusConsumed: ((UUID) -> Void)? = nil,
         onSubmit: (() -> Void)? = nil, onReference: ((NSRange) -> Void)? = nil,
         selectionRequest: NSRange? = nil) {
        _text = text
        self.label = label
        self.focusOnAppear = focusOnAppear
        self.usesSystemFont = usesSystemFont
        self.accessibilityHelp = accessibilityHelp
        self.focusRequest = focusRequest
        self.onFocusConsumed = onFocusConsumed
        self.onSubmit = onSubmit
        self.onReference = onReference
        self.selectionRequest = selectionRequest
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = InitialFocusTextView()
        textView.focusOnAttach = focusOnAppear
        textView.onSubmit = onSubmit
        textView.onReference = onReference
        textView.string = text
        textView.font = usesSystemFont
            ? .systemFont(ofSize: NSFont.systemFontSize)
            : .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
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
        textView.setAccessibilityHelp(accessibilityHelp)
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
        textView.setAccessibilityHelp(accessibilityHelp)
        if let selectionRequest, context.coordinator.selectionRequest != selectionRequest {
            context.coordinator.selectionRequest = selectionRequest
            DispatchQueue.main.async { [weak textView] in
                guard let textView, NSMaxRange(selectionRequest) <= (textView.string as NSString).length else { return }
                textView.setSelectedRange(selectionRequest)
            }
        } else if selectionRequest == nil { context.coordinator.selectionRequest = nil }
        if let textView = textView as? InitialFocusTextView {
            textView.onSubmit = onSubmit
            textView.onReference = onReference
            if focusRequest != context.coordinator.focusRequest {
                context.coordinator.focusRequest = focusRequest
                if let focusRequest {
                    DispatchQueue.main.async { [weak textView] in
                        guard let textView, let window = textView.window, window.isKeyWindow else { return }
                        window.makeFirstResponder(textView)
                        onFocusConsumed?(focusRequest)
                    }
                }
            }
        }
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
        var focusRequest: UUID?
        var selectionRequest: NSRange?

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
    var onSubmit: (() -> Void)?
    var onReference: ((NSRange) -> Void)?

    override func keyDown(with event: NSEvent) {
        let insertion = selectedRange()
        if event.characters == "@", !hasMarkedText(), let onReference,
           insertion.length == 0,
           insertion.location == 0 || (string as NSString).substring(with: NSRange(location: insertion.location - 1, length: 1)).rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            super.keyDown(with: event)
            onReference(NSRange(location: insertion.location, length: 1))
            return
        }
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, !event.modifierFlags.contains(.shift), !hasMarkedText(), let onSubmit {
            onSubmit()
            return
        }
        super.keyDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if focusOnAttach, let window, window.isKeyWindow {
            focusOnAttach = false
            window.makeFirstResponder(self)
        }
    }
}
