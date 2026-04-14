import SwiftUI
import UIKit

struct SelectableTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange

    class Coordinator: NSObject, UITextViewDelegate, UIScribbleInteractionDelegate {
        var parent: SelectableTextView

        init(_ parent: SelectableTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selectedRange = textView.selectedRange
        }

        @available(iOS 14.0, *)
        func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
            false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = true
        tv.isScrollEnabled = true
        tv.backgroundColor = .clear
        tv.font = UIFont.systemFont(ofSize: 17)
        tv.isSelectable = true
        tv.delegate = context.coordinator
        if #available(iOS 14.0, *) {
            tv.addInteraction(UIScribbleInteraction(delegate: context.coordinator))
        }
        DispatchQueue.main.async {
            if tv.window != nil {
                tv.becomeFirstResponder()
            }
        }
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        let length = (text as NSString).length
        let range = selectedRange
        if range.location >= 0,
           range.length >= 0,
           range.location + range.length <= length,
           uiView.selectedRange != range {
            uiView.selectedRange = range
        }

        if !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }
}

