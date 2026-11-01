import SwiftUI
import RadialCore

/// The manager window: one section at a time, on a leather desk.
///
/// It used to be a single page of header, add form, column headers, list and footer. Each of
/// those is now somewhere it belongs: the compass on Dial, the ledger on Library, Safari on
/// Import, preferences on Settings, and adding a link behind one floating button.
struct BookmarkManagerView: View {
    @ObservedObject var model: BookmarkListModel
    @ObservedObject var settings: SettingsModel
    @ObservedObject var router: ManagerRouter
    var onOpenDial: () -> Void = {}

    /// Held, not observed: only the views that draw the cursor's light re-render as it moves.
    @State private var tracker = PointerTracker()
    @State private var editing: Bookmark?
    @State private var composing = false

    var body: some View {
        ZStack {
            LeatherBackground(tracker: tracker)

            ZStack {
                tabContent
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: router.tab == .dial ? .center : .top
                    )
                    .id(router.tab)
                    .transition(.depth)
            }
            .padding(.top, 104)
            .padding(.bottom, 40)

            VStack {
                BrassTabBar(selection: $router.tab)
                    .padding(.top, 22)
                Spacer()
            }

            if showsComposer {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        AddComposer(model: model, isOpen: $composing) {
                            withAnimation(Motion.springSoft) { router.tab = .dial }
                        }
                    }
                }
                .padding(.trailing, 40)
                .padding(.bottom, 36)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            if let message = model.syncMessage, router.tab != .importer {
                VStack {
                    Spacer()
                    ToastView(message: message)
                        .padding(.bottom, 44)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(Palette.void)
        .motion(Motion.springSoft, value: router.tab)
        .motion(Motion.springSoft, value: showsComposer)
        .motion(Motion.spring, value: model.syncMessage)
        .sheet(item: $editing) { bookmark in
            EditBookmarkSheet(
                bookmark: bookmark,
                slot: model.slotNumber(for: bookmark),
                defaultBehavior: model.defaultOpenBehavior,
                browser: model.browser
            ) { title, url, behavior, wholeSite in
                model.update(
                    id: bookmark.id,
                    title: title,
                    url: url,
                    openBehavior: behavior,
                    matchWholeSite: wholeSite
                )
            }
        }
        .onAppear { tracker.start() }
        .onDisappear { tracker.stop() }
        .onChange(of: model.focusRequest) { _, _ in
            // A request from the menu bar ("New Bookmark…") should open the composer.
            withAnimation(Motion.springSoft) {
                router.tab = .dial
                composing = true
            }
        }
        .onChange(of: model.syncMessage) { _, message in
            guard let message else { return }
            // Toasts leave on their own; the Import tab shows its result inline instead.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                if model.syncMessage == message { model.syncMessage = nil }
            }
        }
        .onChange(of: router.tab) { _, tab in
            // The composer only lives on Dial and Library; leaving for the others closes it.
            if tab == .importer || tab == .settings { composing = false }
        }
    }

    private var showsComposer: Bool {
        router.tab == .dial || router.tab == .library
    }

    @ViewBuilder
    private var tabContent: some View {
        switch router.tab {
        case .dial:
            DialTabView(
                model: model,
                settings: settings,
                onEdit: { editing = $0 },
                onAdd: { withAnimation(Motion.springSoft) { composing = true } }
            )
        case .library:
            LibraryTabView(model: model) { bookmark in
                editing = bookmark
            }
        case .importer:
            ImportTabView(model: model) {
                withAnimation(Motion.springSoft) { router.tab = .dial }
            }
        case .settings:
            SettingsView(model: settings, previewBookmarks: model.bookmarks) {
                withAnimation(Motion.springSoft) { router.tab = .importer }
            }
        }
    }
}

// MARK: - Edit sheet

/// Title, link and how it opens, with live validation. Small enough that a sheet is the right
/// surface.
struct EditBookmarkSheet: View {
    let bookmark: Bookmark
    /// Which slot this is, shown as the sheet's eyebrow.
    var slot: Int?
    /// What Settings does with links that do not choose for themselves, so "Default" can say it.
    let defaultBehavior: OpenBehavior
    let browser: Browser
    let onSave: (String, String, OpenBehavior?, Bool) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var url: String
    @State private var behavior: OpenBehavior?
    @State private var wholeSite: Bool
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case name, link }

    init(
        bookmark: Bookmark,
        slot: Int? = nil,
        defaultBehavior: OpenBehavior,
        browser: Browser,
        onSave: @escaping (String, String, OpenBehavior?, Bool) -> String?
    ) {
        self.bookmark = bookmark
        self.slot = slot
        self.defaultBehavior = defaultBehavior
        self.browser = browser
        self.onSave = onSave
        _title = State(initialValue: bookmark.title)
        _url = State(initialValue: bookmark.url)
        _behavior = State(initialValue: bookmark.openBehavior)
        _wholeSite = State(initialValue: bookmark.matchesWholeSite)
    }

    private var isValid: Bool { Bookmark.normalizedURL(url) != nil }
    private var showsInvalid: Bool { !url.isEmpty && !isValid }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(slot.map { "SLOT \($0)" } ?? "EDIT")
                    .font(Palette.mono(11, .semibold))
                    .tracking(1.8)
                    .foregroundStyle(Palette.signal)
                Text("Edit slot")
                    .font(Palette.display(30, .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(Palette.bone)
                Text(bookmark.host.isEmpty ? bookmark.url : bookmark.host)
                    .font(Palette.mono(12.5))
                    .foregroundStyle(Palette.boneFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            field("NAME") {
                TextField("", text: $title, prompt: hint("Shown on the dial"))
                    .textFieldStyle(.plain)
                    .font(Palette.display(16, .regular))
                    .foregroundStyle(Palette.bone)
                    .focused($focus, equals: .name)
                    .brassField(focused: focus == .name)
            }

            field("LINK") {
                TextField("", text: $url, prompt: hint("https://…"))
                    .textFieldStyle(.plain)
                    .font(Palette.mono(13.5))
                    .foregroundStyle(Palette.bone)
                    .focused($focus, equals: .link)
                    .brassField(focused: focus == .link, error: showsInvalid || error != nil)
            }

            field("WHEN OPENED") {
                OpeningPicker(
                    selection: $behavior,
                    wholeSite: $wholeSite,
                    defaultBehavior: defaultBehavior,
                    browser: browser
                )
            }

            if showsInvalid {
                Text("Needs to be an http or https address.")
                    .font(Palette.display(13.5, .medium))
                    .foregroundStyle(Palette.alarm)
                    .transition(.opacity)
            }
            if let error {
                Text(error)
                    .font(Palette.display(13.5, .medium))
                    .foregroundStyle(Palette.alarm)
                    .transition(.opacity)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(QuietButtonStyle(size: 14))
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let message = onSave(title, url, behavior, wholeSite) {
                        error = message
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(SignalButtonStyle(isEnabled: isValid, size: 14))
                .disabled(!isValid)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 480)
        .background(
            ZStack {
                Palette.voidRaised
                RadialGradient(
                    colors: [Palette.signal.opacity(0.10), Color.clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 280
                )
            }
        )
        .motion(Motion.spring, value: showsInvalid)
        .motion(Motion.spring, value: error)
        .motion(Motion.spring, value: behavior)
        .onAppear { focus = .name }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Palette.mono(10.5, .semibold))
                .tracking(1.6)
                .foregroundStyle(Palette.boneFaint)
                .padding(.leading, 2)
            content()
        }
    }
}

// MARK: - Opening picker

/// The four ways a bookmark can open, all on screen at once: "Default" plus the three behaviours.
///
/// A list rather than a dropdown, because the choice is only intuitive when each option can be
/// read before it is picked, and four short rows cost less than the click that opens a menu.
/// "Default" says what it currently is, so nobody has to remember the setting it follows.
struct OpeningPicker: View {
    @Binding var selection: OpenBehavior?
    @Binding var wholeSite: Bool
    let defaultBehavior: OpenBehavior
    let browser: Browser

    private var effective: OpenBehavior { selection ?? defaultBehavior }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 4) {
                row(nil, title: "Default", detail: defaultBehavior.displayName)
                ForEach(OpenBehavior.allCases, id: \.self) { behavior in
                    row(behavior, title: behavior.displayName, detail: nil)
                }
            }

            Text(OpenPlan.honours(browser)
                 ? effective.summary
                 : "\(browser.name) can't be told what to do with its tabs, so it decides.")
                .font(Palette.display(13.5, .regular))
                .foregroundStyle(Palette.boneDim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 2)

            if effective == .reuseTab, OpenPlan.honours(browser) {
                Toggle(isOn: $wholeSite) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Any page on this site")
                            .font(Palette.display(15, .regular))
                            .foregroundStyle(Palette.bone)
                        Text("Counts a tab on the same site as open, not just this exact page.")
                            .font(Palette.display(13, .regular))
                            .foregroundStyle(Palette.boneDim)
                    }
                }
                .toggleStyle(BrassToggleStyle())
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
    }

    private func row(_ option: OpenBehavior?, title: String, detail: String?) -> some View {
        let selected = selection == option
        return Button {
            withAnimation(Motion.springSoft) { selection = option }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(selected ? Palette.signal : Palette.rimStrong, lineWidth: 1.5)
                    .background(Circle().fill(selected ? Palette.signal : Color.clear).padding(4))
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(Palette.display(15, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.bone : Palette.boneDim)
                if let detail {
                    Text("· \(detail)")
                        .font(Palette.display(13.5, .regular))
                        .foregroundStyle(Palette.boneFaint)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Palette.signal.opacity(0.10) : Palette.void)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Palette.signal.opacity(0.6) : Palette.rim, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(detail.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Mini dial

/// The window's mark: the compass, small enough to sit in a header.
///
/// Drawn from `CompassMetrics` and `RadialLayout` rather than shipped as an asset, so the mark
/// can never drift from the real instrument — and so the app has a recognisable object in its
/// window instead of a generic icon.
struct MiniDial: View {
    var filled = true
    /// Off when something else draws the needle (see `SearchingDial`).
    var showsNeedle = true

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            Canvas { context, size in
                let metrics = CompassMetrics(cardRadius: side * 0.36)
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let card = RadialLayout(
                    sliceCount: RadialLayout.maxSlicesPerPage,
                    centerRadius: metrics.hubRadius,
                    outerRadius: metrics.sectorOutset
                )

                // Case.
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: centre.x - metrics.caseRadius,
                        y: centre.y - metrics.caseRadius,
                        width: metrics.caseRadius * 2,
                        height: metrics.caseRadius * 2
                    )),
                    with: .color(CompassTheme.brassMid.swiftUI())
                )
                // Card.
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: centre.x - metrics.cardRadius,
                        y: centre.y - metrics.cardRadius,
                        width: metrics.cardRadius * 2,
                        height: metrics.cardRadius * 2
                    )),
                    with: .color(CompassTheme.paper.swiftUI())
                )

                // Wedges, with the first lit when the dial has contents.
                for index in 0..<RadialLayout.maxSlicesPerPage {
                    let lit = filled && index == 0
                    let drawn = card.drawableRange(of: index, inset: card.step * 0.05)
                    var path = Path()
                    let steps = 8
                    for step in 0...steps {
                        let angle = drawn.start + drawn.sweep * CGFloat(step) / CGFloat(steps)
                        let point = card.point(radius: metrics.sectorOutset, angle: angle)
                        let screen = CGPoint(x: centre.x + point.x, y: centre.y + point.y)
                        step == 0 ? path.move(to: screen) : path.addLine(to: screen)
                    }
                    for step in stride(from: steps, through: 0, by: -1) {
                        let angle = drawn.start + drawn.sweep * CGFloat(step) / CGFloat(steps)
                        let point = card.point(radius: metrics.sectorInset, angle: angle)
                        path.addLine(to: CGPoint(x: centre.x + point.x, y: centre.y + point.y))
                    }
                    path.closeSubpath()
                    context.fill(path, with: .color(lit
                        ? CompassTheme.vermilion.swiftUI(alpha: 0.30)
                        : CompassTheme.ink.swiftUI(alpha: 0.06)))
                    context.stroke(path, with: .color(lit
                        ? CompassTheme.vermilion.swiftUI(alpha: 0.90)
                        : CompassTheme.ink.swiftUI(alpha: 0.20)), lineWidth: 0.8)
                }

                // Needle, pointing at the first slot.
                if showsNeedle {
                    var needle = Path()
                    let tip = CGPoint(x: centre.x, y: centre.y - metrics.cardRadius * 0.60)
                    needle.move(to: tip)
                    needle.addLine(to: CGPoint(x: centre.x - side * 0.030, y: centre.y + metrics.cardRadius * 0.42))
                    needle.addLine(to: CGPoint(x: centre.x + side * 0.030, y: centre.y + metrics.cardRadius * 0.42))
                    needle.closeSubpath()
                    context.fill(needle, with: .color(CompassTheme.vermilion.swiftUI().opacity(filled ? 1 : 0.30)))
                }

                // Hub.
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: centre.x - metrics.hubRadius,
                        y: centre.y - metrics.hubRadius,
                        width: metrics.hubRadius * 2,
                        height: metrics.hubRadius * 2
                    )),
                    with: .color(CompassTheme.brassDark.swiftUI())
                )
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Slot gutter

/// The row's slot number, with the slot's *bearing* on the dial behind it.
///
/// At 26pt a wedge is unreadable — the old design drew all nine and they collapsed into a
/// smudge. What still reads at this size is a single pip at the slot's own bearing, which is
/// the one thing a plain table cannot say: where this bookmark sits.
struct SlotGutter: View {
    let slot: Int
    /// Slice index within its own page, or nil for a row with no slot.
    let sliceIndex: Int?
    var sliceCount = RadialLayout.maxSlicesPerPage
    var emphasised = false

    private var isLit: Bool { sliceIndex != nil }

    private var helpText: String {
        guard let sliceIndex else { return "No slot" }
        return "Slot \(slot) — bearing \(sliceIndex + 1) of \(sliceCount) on the dial"
    }

    var body: some View {
        ZStack {
            if let sliceIndex {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    Canvas { context, size in
                        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                        let ring = RadialLayout(
                            sliceCount: max(2, sliceCount),
                            centerRadius: side * 0.30,
                            outerRadius: side * 0.44,
                            hubGap: side * 0.035
                        )
                        context.stroke(
                            Path(ellipseIn: CGRect(
                                x: centre.x - ring.outerRadius,
                                y: centre.y - ring.outerRadius,
                                width: ring.outerRadius * 2,
                                height: ring.outerRadius * 2
                            )),
                            with: .color(Palette.bone.opacity(0.16)),
                            lineWidth: 1
                        )
                        let bearing = ring.centerAngle(of: sliceIndex)
                        let pip = ring.point(radius: ring.outerRadius, angle: bearing)
                        context.fill(
                            Path(ellipseIn: CGRect(
                                x: centre.x + pip.x - 2.6,
                                y: centre.y + pip.y - 2.6,
                                width: 5.2,
                                height: 5.2
                            )),
                            with: .color(emphasised ? Palette.signal : Palette.bone.opacity(0.85))
                        )
                    }
                    .frame(width: side, height: side)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
            Text("\(slot)")
                .font(Palette.mono(isLit ? 8.5 : 12.5, isLit ? .semibold : .medium))
                .foregroundStyle(isLit
                    ? (emphasised ? Palette.bone : Palette.boneDim)
                    : Palette.boneFaint)
                .monospacedDigit()
        }
        .frame(width: 26, height: 26)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: emphasised)
        .help(helpText)
    }
}

// MARK: - Searching dial

/// The empty dial: its needle wanders, looking for something to point at.
///
/// Slow and slightly drunk, the way a real needle behaves when nothing is pulling on it.
struct SearchingDial: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MiniDial(filled: false, showsNeedle: false)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    let side = min(size.width, size.height)
                    let metrics = CompassMetrics(cardRadius: side * 0.36)
                    let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                    let wander = reduceMotion ? 0 : sin(time * 0.8) * 0.9 + sin(time * 2.1 + 1) * 0.22

                    var drawing = context
                    drawing.translateBy(x: centre.x, y: centre.y)
                    drawing.rotate(by: .radians(wander))
                    var needle = Path()
                    needle.move(to: CGPoint(x: 0, y: -metrics.cardRadius * 0.60))
                    needle.addLine(to: CGPoint(x: -side * 0.030, y: metrics.cardRadius * 0.42))
                    needle.addLine(to: CGPoint(x: side * 0.030, y: metrics.cardRadius * 0.42))
                    needle.closeSubpath()
                    drawing.fill(needle, with: .color(CompassTheme.vermilion.swiftUI().opacity(0.85)))

                    // The hub sits over the needle's pivot, as on the full dial.
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: centre.x - metrics.hubRadius,
                            y: centre.y - metrics.hubRadius,
                            width: metrics.hubRadius * 2,
                            height: metrics.hubRadius * 2
                        )),
                        with: .color(CompassTheme.brassDark.swiftUI())
                    )
                }
            }
        }
    }
}
