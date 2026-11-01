import SwiftUI
import AppKit
import RadialCore

/// The quickest way to get one link onto the dial.
///
/// The menu bar item used to lead to the manager window, which meant a full window, a reload
/// and a scroll for what is usually "paste the thing I just copied". This is a small panel
/// with the caret already blinking in the link field: paste, Return, gone.
struct QuickAddView: View {
    @ObservedObject var model: BookmarkListModel
    var onClose: () -> Void

    @State private var url = ""
    @State private var title = ""
    @State private var error: String?
    @State private var added: SlotToast?
    @State private var appeared = false
    @FocusState private var focus: Field?

    private enum Field { case link, name }

    private struct SlotToast: Equatable {
        let slot: Int
        let title: String
    }

    var body: some View {
        ZStack {
            if let added {
                confirmation(added)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                form
                    .transition(.opacity)
            }
        }
        .frame(width: 480)
        .background(
            ZStack {
                Palette.void
                RadialGradient(
                    colors: [Palette.signal.opacity(0.14), Color.clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 300
                )
            }
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LinearGradient(
                    colors: [Color.clear, added == nil ? Palette.signal : Palette.mint, Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(height: 2)
        }
        // The panel arrives the way the dial does: set down, with a little give.
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .motion(Motion.springSoft, value: added)
        .onExitCommand(perform: onClose)
        .onAppear {
            withAnimation(Motion.springSoft) { appeared = true }
            // The clipboard is the reason this panel exists, so use it before asking.
            if let pasted = QuickAddView.linkFromClipboard(), url.isEmpty {
                url = pasted
                title = QuickAddView.suggestedTitle(for: pasted)
                focus = .name
            } else {
                focus = .link
            }
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("NEXT SLOT · PAGE \(nextSlotPage)")
                    .font(Palette.mono(11, .semibold))
                    .tracking(1.8)
                    .foregroundStyle(Palette.boneFaint)
                Text("New slot")
                    .font(Palette.display(30, .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(Palette.bone)
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("LINK")
                HStack(spacing: 0) {
                    Text("https://")
                        .font(Palette.mono(13.5))
                        .foregroundStyle(Palette.boneFaint)
                    TextField("", text: $url, prompt: hint("paste a link, or type a domain"))
                        .textFieldStyle(.plain)
                        .font(Palette.mono(13.5))
                        .foregroundStyle(Palette.bone)
                        .focused($focus, equals: .link)
                        .onSubmit(commit)
                        .onChange(of: url) { _, _ in
                            if error != nil { error = nil }
                        }
                }
                .brassField(focused: focus == .link, error: error != nil)
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("DIAL LABEL")
                TextField("", text: $title, prompt: hint("Optional. Defaults to the domain"))
                    .textFieldStyle(.plain)
                    .font(Palette.display(16, .regular))
                    .foregroundStyle(Palette.bone)
                    .focused($focus, equals: .name)
                    .onSubmit(commit)
                    .brassField(focused: focus == .name)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Palette.display(13.5, .medium))
                    .foregroundStyle(Palette.alarm)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: onClose)
                    .buttonStyle(QuietButtonStyle(size: 14))
                    .keyboardShortcut(.cancelAction)
                Button("Add to dial", action: commit)
                    .buttonStyle(SignalButtonStyle(isEnabled: canCommit, size: 14))
                    .disabled(!canCommit)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(28)
        .motion(Motion.spring, value: error)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Palette.mono(10.5, .semibold))
            .tracking(1.6)
            .foregroundStyle(Palette.boneFaint)
            .padding(.leading, 2)
    }

    private var canCommit: Bool {
        Bookmark.normalizedURL(url) != nil
    }

    private var nextSlotPage: Int {
        (model.store.count) / RadialLayout.maxSlicesPerPage + 1
    }

    private func commit() {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let failure = model.add(title: title, url: trimmed) {
            error = failure
            focus = .link
            return
        }
        // `model.add` reloads, so the new count is the slot the bookmark just landed in.
        added = SlotToast(
            slot: model.store.count,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (Bookmark.normalizedURL(trimmed)?.host ?? trimmed)
                : title
        )
        // Long enough to read, short enough not to feel like a dialog.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            onClose()
        }
    }

    // MARK: - Confirmation

    private func confirmation(_ toast: SlotToast) -> some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Palette.mint.opacity(0.14))
                Circle()
                    .strokeBorder(Palette.mint.opacity(0.5), lineWidth: 1.5)
                DrawnCheck(tint: Palette.mint, lineWidth: 4)
                    .frame(width: 30, height: 30)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 5) {
                Text("SLOT \(toast.slot)")
                    .font(Palette.mono(11, .semibold))
                    .tracking(1.8)
                    .foregroundStyle(Palette.mint)
                Text(toast.title)
                    .font(Palette.display(26, .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(Palette.bone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("is on the dial")
                    .font(Palette.display(15, .regular))
                    .foregroundStyle(Palette.boneDim)
            }
            Spacer()
        }
        .padding(28)
        .frame(height: 124)
    }

    // MARK: - Clipboard

    /// Only http(s) links are worth pre-filling; a stray sentence in the clipboard would just
    /// have to be deleted.
    static func linkFromClipboard() -> String? {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return nil }
        return Bookmark.normalizedURL(raw)?.absoluteString
    }

    /// A readable default label from the URL path: "/openai/codex" becomes "Codex".
    static func suggestedTitle(for urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "" }
        let last = url.pathComponents.last { $0 != "/" && !$0.isEmpty }
        guard let last, last.count > 1, last.count <= 28 else { return "" }
        return last
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

/// Panel for the quick-add form. Sized to fit its content and centred on the pointer's screen,
/// so it behaves like a HUD rather than a document window.
final class QuickAddPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(content: NSViewController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 330),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        contentViewController = content
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = Palette.nsVoid
        appearance = NSAppearance(named: .darkAqua)
        level = .floating
        isReleasedWhenClosed = false
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
    }
}
