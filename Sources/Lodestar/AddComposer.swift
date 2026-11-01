import SwiftUI
import AppKit
import RadialCore

/// Adding a link: a floating button that opens into the form, instead of a form that is always
/// on screen. Most of the time you are not adding anything, so the window should not look as if
/// you were.
struct AddComposer: View {
    @ObservedObject var model: BookmarkListModel
    @Binding var isOpen: Bool
    /// Called after a link lands, so the window can show it on the dial.
    var onAdded: () -> Void

    @State private var title = ""
    @State private var link = ""
    @State private var errorText: String?
    @State private var clipboard: String?
    @State private var hovering = false

    @FocusState private var linkFocused: Bool

    private let closedSize: CGFloat = 60
    private let openWidth: CGFloat = 700
    private let openHeight: CGFloat = 84

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if isOpen, errorText == nil, link.isEmpty, let clipboard {
                clipboardChip(clipboard)
                    .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
            }
            composer
        }
        .onChange(of: isOpen) { _, nowOpen in
            if nowOpen {
                clipboard = clipboardLink()
                // After the morph has made room, so the caret does not land in a moving field.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { linkFocused = true }
            } else {
                errorText = nil
                linkFocused = false
            }
        }
    }

    // MARK: - Shape

    private var composer: some View {
        let radius: CGFloat = isOpen ? 24 : closedSize / 2
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack(alignment: .leading) {
            shape
                .fill(isOpen ? Palette.voidRaised : Palette.signal)
                .overlay(
                    shape.fill(LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .opacity(isOpen ? 0 : 1)
                )
                .overlay(shape.strokeBorder(isOpen ? Palette.rimStrong : Color.white.opacity(0.3), lineWidth: 1))
                .shadow(
                    color: isOpen ? Color.black.opacity(0.6) : Palette.signal.opacity(hovering ? 0.55 : 0.35),
                    radius: isOpen ? 36 : (hovering ? 22 : 14),
                    y: isOpen ? 20 : 10
                )

            if isOpen {
                form
                    .padding(.leading, closedSize + 6)
                    .padding(.trailing, 14)
                    .transition(.opacity.combined(with: .offset(x: 16)))
            }

            Button {
                withAnimation(Motion.springSoft) { isOpen.toggle() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isOpen ? Palette.bone : Palette.signalInk)
                    .rotationEffect(.degrees(isOpen ? 135 : 0))
                    .frame(width: closedSize, height: closedSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isOpen ? "Close" : "Add a bookmark (⌘N)")
            .accessibilityLabel(isOpen ? "Close" : "Add a bookmark")
        }
        .frame(width: isOpen ? openWidth : closedSize, height: isOpen ? openHeight : closedSize)
        .scaleEffect(hovering && !isOpen ? 1.1 : 1)
        .onHover { hovering = $0 }
        .motion(Motion.snap, value: hovering)
        .onExitCommand {
            withAnimation(Motion.springSoft) { isOpen = false }
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                field {
                    TextField("", text: $title, prompt: hint("Name (optional)"))
                        .textFieldStyle(.plain)
                        .font(Palette.display(16, .regular))
                }
                .frame(width: 160)

                field {
                    HStack(spacing: 0) {
                        Text("https://")
                            .font(Palette.mono(13))
                            .foregroundStyle(Palette.boneFaint)
                        TextField("", text: $link, prompt: hint("paste a link, or type a domain"))
                            .textFieldStyle(.plain)
                            .font(Palette.display(16, .regular))
                            .focused($linkFocused)
                            .onSubmit(commit)
                    }
                }

                Button("Add bookmark", action: commit)
                    .buttonStyle(SignalButtonStyle(isEnabled: canCommit, size: 14))
                    .disabled(!canCommit)
            }
            if let errorText {
                Text(errorText)
                    .font(Palette.display(12.5, .medium))
                    .foregroundStyle(Palette.alarm)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(Palette.bone)
        .motion(Motion.spring, value: errorText)
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.void))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.rim, lineWidth: 1))
    }

    private func clipboardChip(_ host: String) -> some View {
        Button {
            link = host
            clipboard = nil
            linkFocused = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .semibold))
                Text("Add")
                Text(host)
                    .font(Palette.mono(13))
                    .foregroundStyle(Palette.signal)
                Text("from clipboard?")
            }
            .font(Palette.display(15, .regular))
            .foregroundStyle(Palette.bone)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Palette.voidRaised))
            .overlay(Capsule().strokeBorder(Palette.signal.opacity(0.5), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.5), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .liftOnHover(2)
    }

    // MARK: - Actions

    private var canCommit: Bool {
        !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commit() {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let error = model.add(title: title, url: trimmed) {
            errorText = error
            return
        }
        title = ""
        link = ""
        errorText = nil
        withAnimation(Motion.springSoft) { isOpen = false }
        onAdded()
    }

    /// The host of a link on the clipboard, if there is one worth offering.
    private func clipboardLink() -> String? {
        guard let raw = NSPasteboard.general.string(forType: .string),
              let url = Bookmark.normalizedURL(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host
        else { return nil }
        let name = host.replacingOccurrences(of: "www.", with: "")
        // Already on the dial: offering it again would only produce an error.
        if model.bookmarks.contains(where: { $0.host == name || $0.url == url.absoluteString }) { return nil }
        return name
    }
}
