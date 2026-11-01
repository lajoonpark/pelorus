import SwiftUI
import AppKit
import RadialCore

/// First run, four steps.
///
/// This is the first thing anyone sees of the app, so it shows the instrument rather than
/// describing it: the live compass sits beside the words and answers the pointer from the first
/// frame.
///
/// The look step lets a new user choose between the clean compass and the worn one while
/// watching it change, so the setting is a decision made at the start rather than one found later.
///
/// The Safari step exists because Safari import genuinely needs Full Disk Access and that is
/// the kind of permission request people abandon an app over. So it is offered as an explicit
/// choice, with the cost of skipping it stated plainly: the app is complete without it.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    @State private var tracker = PointerTracker()

    var body: some View {
        ZStack {
            LeatherBackground(tracker: tracker)

            HStack(spacing: 0) {
                art
                    .frame(width: 400)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .padding(.top, 30)
        }
        .frame(width: 960, height: 620)
        .onAppear { tracker.start() }
        .onDisappear { tracker.stop() }
        .motion(Motion.springSoft, value: model.step)
    }

    // MARK: - Art

    @ViewBuilder
    private var art: some View {
        ZStack {
            switch model.step {
            case .welcome, .look, .ready:
                // The same instrument on both ends: first as a demonstration, last as the real
                // thing, with your own slots on it if you have any. The look step keeps the
                // welcome step's compass rather than opening a new one, so flipping the switch
                // changes the object you are already looking at.
                LiveCompass(
                    bookmarks: model.dialBookmarks,
                    page: 0,
                    paging: RadialPaging(total: model.dialBookmarks.count),
                    showsNumbers: true,
                    radius: 200
                )
                .id(model.step == .ready ? 1 : 0)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            case .safari:
                VStack(spacing: 22) {
                    BrassBadge(symbol: "safari.fill", size: 132)
                    Text("OPTIONAL")
                        .font(Palette.mono(11, .semibold))
                        .tracking(2.2)
                        .foregroundStyle(Palette.boneFaint)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Text(model.step.eyebrow)
                .font(Palette.mono(11, .semibold))
                .tracking(1.8)
                .foregroundStyle(Palette.signal)

            Text(model.step.title)
                .font(Palette.display(46, .semibold))
                .tracking(-0.9)
                .foregroundStyle(Palette.bone)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .id(model.step)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 14)),
                    removal: .opacity
                ))

            Group {
                switch model.step {
                case .welcome: welcomeCopy
                case .look: lookCopy
                case .safari: safariCopy
                case .ready: readyCopy
                }
            }
            .id(model.step)
            .transition(.opacity)
            .padding(.top, 20)

            actions
                .padding(.top, 34)

            Spacer(minLength: 0)

            footer
        }
        .padding(.leading, 20)
        .padding(.trailing, 56)
        .padding(.bottom, 26)
    }

    private var welcomeCopy: some View {
        VStack(alignment: .leading, spacing: 18) {
            paragraph("Every bookmark you actually use, on one ring, at your cursor. Press the shortcut anywhere and the dial appears where your pointer already is, so nothing moves.")
            HStack(spacing: 14) {
                HotkeyKeycaps(displayName: model.hotkeyDisplay)
                Text("opens the dial")
                    .font(Palette.display(16, .regular))
                    .foregroundStyle(Palette.boneDim)
            }
            paragraph("Then press 1–9, or click a wedge. Esc closes it without opening anything. Try hovering the compass.", dim: true)
        }
    }

    private var lookCopy: some View {
        VStack(alignment: .leading, spacing: 20) {
            paragraph("It is a century-old instrument either way. Clean is softly aged brass and paper. Worn adds what a life in a pocket does: scratches, dents, chipped plating and a little rust.")
            BrassSegmented(
                options: [false, true],
                title: { $0 ? "Worn" : "Clean" },
                selection: Binding(get: { model.worn }, set: { model.setWorn($0) })
            )
            paragraph("Pick whichever you like the look of; the compass on the left changes as you do. You can change it later in Settings, under Worn brass.", dim: true)
        }
    }

    private var safariCopy: some View {
        VStack(alignment: .leading, spacing: 18) {
            paragraph("Safari stores bookmarks in a system-protected file. Reading it needs Full Disk Access. You can grant it now, or skip it and never think about it again.")
            VStack(alignment: .leading, spacing: 6) {
                Text("Full Disk Access is optional")
                    .font(Palette.display(16, .semibold))
                    .foregroundStyle(Palette.bone)
                Text("Adding links by hand, reordering, the shortcut, and every setting work exactly the same without it. It only switches on the Import tab.")
                    .font(Palette.display(14.5, .regular))
                    .lineSpacing(2)
                    .foregroundStyle(Palette.boneDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 16)
            .overlay(alignment: .leading) {
                Capsule().fill(Palette.signal).frame(width: 3)
            }
        }
    }

    private var readyCopy: some View {
        VStack(alignment: .leading, spacing: 20) {
            paragraph(model.hasBookmarks
                ? "Your dial is ready. Press the shortcut anywhere to open it, then a number to fire a slot."
                : "Your dial is ready and empty, which is fine. Add links in the main window, or import from Safari later if you change your mind."
            )
            HStack(spacing: 22) {
                tip("Esc", "closes")
                tip("← →", "turn the page")
                tip("1–9", "open a slot")
            }
        }
    }

    private func tip(_ key: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            KeyCap(text: key)
            Text(label)
                .font(Palette.display(14, .regular))
                .foregroundStyle(Palette.boneFaint)
        }
    }

    private func paragraph(_ text: String, dim: Bool = false) -> some View {
        Text(text)
            .font(Palette.display(17.5, .regular))
            .lineSpacing(4)
            .foregroundStyle(dim ? Palette.boneFaint : Palette.boneDim)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 12) {
            switch model.step {
            case .welcome:
                Button("Show me the dial") { model.advance() }
                    .buttonStyle(SignalButtonStyle(size: 16))
                Button("Skip") { model.finish() }
                    .buttonStyle(QuietButtonStyle(tint: Palette.boneDim, size: 16))
            case .look:
                Button("Continue") { model.advance() }
                    .buttonStyle(SignalButtonStyle(size: 16))
            case .safari:
                Button("Open Full Disk Access") { model.requestFullDiskAccess() }
                    .buttonStyle(SignalButtonStyle(size: 16))
                Button("Not now") { model.advance() }
                    .buttonStyle(QuietButtonStyle(size: 16))
            case .ready:
                Button("Start using it") { model.finish() }
                    .buttonStyle(SignalButtonStyle(size: 16))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            StepPips(step: model.step)
            Text(model.step.footerHint)
                .font(Palette.display(13.5, .regular))
                .foregroundStyle(Palette.boneFaint)
            Spacer()
            if model.step != .welcome {
                Button("Back") { model.goBack() }
                    .buttonStyle(QuietButtonStyle(tint: Palette.boneDim, size: 13))
            }
        }
    }
}

// MARK: - Chrome

/// One brass pip per step: the current step stretches into a lit capsule.
private struct StepPips: View {
    let step: OnboardingStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { candidate in
                let current = candidate == step
                Capsule()
                    .fill(current ? Palette.signal : (candidate.rawValue < step.rawValue ? Palette.signal.opacity(0.45) : Palette.rimStrong))
                    .frame(width: current ? 26 : 8, height: 8)
                    .shadow(color: Palette.signal.opacity(current ? 0.6 : 0), radius: 6)
            }
        }
        .motion(Motion.spring, value: step)
    }
}

// MARK: - Step model

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case look
    case safari
    case ready

    var windowTitle: String {
        switch self {
        case .welcome: return "Welcome to Lodestar"
        case .look: return "Choose a look"
        case .safari: return "Safari import"
        case .ready: return "You are all set"
        }
    }

    var eyebrow: String {
        switch self {
        case .welcome: return "STEP 1 OF 4"
        case .look: return "STEP 2 OF 4"
        case .safari: return "STEP 3 OF 4 · OPTIONAL"
        case .ready: return "STEP 4 OF 4"
        }
    }

    var title: String {
        switch self {
        case .welcome: return "Nine things,\none gesture."
        case .look: return "How worn should\nit look?"
        case .safari: return "Bring your Safari\nbookmarks along"
        case .ready: return "Your dial is ready"
        }
    }

    var footerHint: String {
        switch self {
        case .welcome: return "You can reopen this tour from the menu bar at any time."
        case .look: return "Purely cosmetic. Nothing else changes."
        case .safari: return "Nothing here is required to start using the app."
        case .ready: return "Reopen this tour from the menu bar any time."
        }
    }
}

final class OnboardingModel: ObservableObject {
    @Published private(set) var step: OnboardingStep = .welcome
    @Published private(set) var hasBookmarks: Bool
    @Published private(set) var worn: Bool

    let hotkeyDisplay: String
    private let environment: AppEnvironment

    /// Stand-ins for a first run with nothing on the dial, so the compass has something to show.
    /// Never saved: they exist only on this screen.
    private static let demo: [Bookmark] = [
        ("Mail", "mail.example.com"), ("Calendar", "calendar.example.com"),
        ("Notes", "notes.example.com"), ("Music", "music.example.com"),
        ("News", "news.example.com"), ("Maps", "maps.example.com"),
        ("Photos", "photos.example.com"), ("Docs", "docs.example.com"),
    ].map { Bookmark(title: $0.0, url: "https://\($0.1)") }

    /// Your own first page when you have one, the demonstration page when you do not.
    var dialBookmarks: [Bookmark] {
        let real = Array(environment.store.bookmarks.prefix(RadialLayout.maxSlicesPerPage))
        return real.isEmpty ? OnboardingModel.demo : real
    }
    var onFinish: (() -> Void)?

    init(environment: AppEnvironment, hotkey: HotkeySpec, hasBookmarks: Bool) {
        self.environment = environment
        self.hotkeyDisplay = hotkey.displayName
        self.hasBookmarks = hasBookmarks
        self.worn = environment.preferences.compassWorn
    }

    /// Applies the look straight away, so the compass beside the words answers the choice.
    func setWorn(_ value: Bool) {
        environment.updatePreferences { $0.compassWorn = value }
        CompassTheme.isWorn = value
        worn = value
    }

    func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        step = next
    }

    func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Opens the right System Settings pane and moves on, so the user is never stuck on it.
    func requestFullDiskAccess() {
        openFullDiskAccessSettings()
        advance()
    }

    private func openFullDiskAccessSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    func finish() {
        environment.updatePreferences {
            $0.hasCompletedOnboarding = true
        }
        onFinish?()
    }
}
