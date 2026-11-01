import SwiftUI
import AppKit
import RadialCore

/// Records a shortcut by listening to the next key press.
///
/// Implemented as a local `NSView` event monitor rather than a text field so modifier-only
/// and special keys (space, F-keys, arrows) can all be captured, which a text field cannot do.
struct HotkeyRecorder: NSViewRepresentable {

    @Binding var isRecording: Bool
    var current: HotkeySpec
    var onCapture: (HotkeySpec) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = onCapture
        view.onStop = { isRecording = false }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onCapture = onCapture
        view.onStop = { isRecording = false }
        view.isRecording = isRecording
        if isRecording {
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        }
    }

    final class RecorderView: NSView {
        var onCapture: ((HotkeySpec) -> Void)?
        var onStop: (() -> Void)?
        var isRecording = false {
            didSet {
                if isRecording != oldValue { needsDisplay = true }
            }
        }

        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }
        override var isFlipped: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }
            if event.keyCode == 53 { // escape cancels recording
                isRecording = false
                onStop?()
                return
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let spec = HotkeySpec(
                keyCode: UInt32(event.keyCode),
                command: flags.contains(.command),
                option: flags.contains(.option),
                control: flags.contains(.control),
                shift: flags.contains(.shift)
            )
            isRecording = false
            onCapture?(spec)
            onStop?()
        }

        override func flagsChanged(with event: NSEvent) {
            // Show progress while the user holds modifiers, but never capture a modifier alone.
            guard isRecording else { return }
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            guard isRecording else { return }
            let label = "Press a shortcut…"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Palette.nsDisplay(12, .medium),
                .foregroundColor: Palette.nsSignal,
            ]
            let size = label.size(withAttributes: attributes)
            label.draw(
                at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                withAttributes: attributes
            )
        }
    }
}
