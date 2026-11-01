import SwiftUI
import AppKit
import RadialCore

/// Home. The real compass on the right, and on the left whatever you are aiming at.
///
/// The compass is the overlay's own instrument (`LiveCompass`), so hovering a wedge swings its
/// needle, clicking a wedge opens the link, and the lid flips open every time you arrive. The
/// copy beside it follows the needle: aim at a slot and it becomes that bookmark's page.
struct DialTabView: View {
    @ObservedObject var model: BookmarkListModel
    @ObservedObject var settings: SettingsModel
    var onEdit: (Bookmark) -> Void
    var onAdd: () -> Void

    @State private var page = 0
    @State private var aimedID: UUID?
    @State private var handle = CompassHandle()

    var body: some View {
        HStack(spacing: 24) {
            copy
                .frame(maxWidth: .infinity, alignment: .leading)
            compassArea
                .frame(width: 520, height: 600)
        }
        .padding(.leading, 64)
        .padding(.trailing, 36)
        .background(DialKeys { handleKey($0) })
        .motion(Motion.springSoft, value: aimedID)
    }

    // MARK: - Data

    private var paging: RadialPaging { RadialPaging(total: model.bookmarks.count) }
    private var currentPage: Int { paging.clampedPage(page) }

    private var pageBookmarks: [Bookmark] {
        guard !model.bookmarks.isEmpty else { return [] }
        return Array(model.bookmarks[paging.indices(onPage: currentPage)])
    }

    /// The aimed bookmark, looked up fresh so an edit shows up immediately.
    private var aimed: Bookmark? {
        guard let aimedID else { return nil }
        return model.bookmarks.first { $0.id == aimedID }
    }

    // MARK: - Copy

    private var copy: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow)
                .font(Palette.mono(11, .semibold))
                .tracking(1.8)
                .foregroundStyle(Palette.boneFaint)

            Group {
                if let aimed {
                    aimedBlock(aimed)
                        .id(aimed.id)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 14)),
                            removal: .dissolve
                        ))
                } else {
                    introBlock
                        .transition(.opacity)
                }
            }
            // A fixed height, not a minimum: the intro (three headline lines, a sentence and two
            // buttons) is taller than the aimed block, and a minimum let it grow into the keys
            // below. Both blocks now sit in the same box, so nothing moves when you aim.
            .frame(height: 350, alignment: .topLeading)
            .padding(.top, 18)

            HStack(spacing: 14) {
                HotkeyKeycaps(displayName: settings.preferences.hotkey.displayName)
                Text("opens the dial, anywhere")
                    .font(Palette.display(15, .regular))
                    .foregroundStyle(Palette.boneFaint)
            }
            .padding(.top, 34)

            pager
                .padding(.top, 22)
        }
    }

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            headline
                .font(Palette.display(54, .semibold))
                .tracking(-1)
                .foregroundStyle(Palette.bone)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(Palette.display(17, .regular))
                .foregroundStyle(Palette.boneDim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            HStack(spacing: 10) {
                Button {
                    handle.replay()
                } label: {
                    Label("Flip it open", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(SignalButtonStyle(size: 15))
                .disabled(pageBookmarks.isEmpty)

                Button(action: onAdd) {
                    Label("Add a link", systemImage: "plus")
                }
                .buttonStyle(QuietButtonStyle(size: 15))
            }
            .padding(.top, 28)
        }
    }

    private func aimedBlock(_ bookmark: Bookmark) -> some View {
        let slot = (model.bookmarks.firstIndex { $0.id == bookmark.id } ?? 0) + 1
        return VStack(alignment: .leading, spacing: 0) {
            Text("SLOT \(slot)")
                .font(Palette.mono(12, .semibold))
                .tracking(1.8)
                .foregroundStyle(Palette.signal)

            Text(bookmark.displayTitle)
                .font(Palette.display(54, .semibold))
                .tracking(-1)
                .foregroundStyle(Palette.bone)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Text(bookmark.host.isEmpty ? bookmark.url : bookmark.host)
                .font(Palette.mono(15))
                .foregroundStyle(Palette.boneDim)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 14)

            openingLine(bookmark)
                .padding(.top, 10)

            HStack(spacing: 10) {
                Button {
                    open(bookmark)
                } label: {
                    Label("Open", systemImage: "arrow.up.right")
                }
                .buttonStyle(SignalButtonStyle(size: 15))

                Button {
                    onEdit(bookmark)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(QuietButtonStyle(size: 15))

                Button {
                    withAnimation(Motion.springSoft) {
                        aimedID = nil
                        model.remove(bookmark)
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(QuietButtonStyle(tint: Palette.alarm, size: 15))
                .help("Remove from the dial")
            }
            .padding(.top, 28)
        }
    }

    /// How this slot opens, and whether that is its own choice or the default's.
    private func openingLine(_ bookmark: Bookmark) -> some View {
        let behavior = bookmark.effectiveOpenBehavior(default: model.defaultOpenBehavior)
        let honoured = OpenPlan.honours(model.browser)
        return HStack(spacing: 7) {
            Image(systemName: behavior.symbol)
                .font(.system(size: 12, weight: .semibold))
            Text(honoured ? behavior.displayName : "Opened by \(model.browserName)")
            if honoured, bookmark.openBehavior == nil {
                Text("· default").foregroundStyle(Palette.boneFaint)
            }
        }
        .font(Palette.display(14, .regular))
        .foregroundStyle(bookmark.openBehavior == nil ? Palette.boneDim : Palette.signal)
    }

    private var eyebrow: String {
        let count = model.bookmarks.count
        guard count > 0 else { return "EMPTY DIAL" }
        let slots = "\(count) SLOT\(count == 1 ? "" : "S")"
        if paging.pageCount > 1 {
            return "PAGE \(currentPage + 1) OF \(paging.pageCount) · \(slots)"
        }
        return "\(slots) · 1 PAGE"
    }

    /// Three short lines read better in a narrow column than one that wraps:
    /// "Eight slots, / one turn / of the dial."
    private var headline: Text {
        let count = model.bookmarks.count
        guard count > 0 else {
            return Text("Nothing here\n") + Text("yet.").italic().foregroundColor(Palette.signal)
        }
        let noun = count == 1 ? "slot" : "slots"
        return Text("\(Self.words(count)) \(noun),\n")
            + Text("one turn").italic().foregroundColor(Palette.signal)
            + Text("\nof the dial.")
    }

    private var subtitle: String {
        model.bookmarks.isEmpty
            ? "Add your first link, or import your Safari bookmarks, and it appears here."
            : "Aim at a wedge to see it. Click one, or press its number, to open it."
    }

    private static func words(_ count: Int) -> String {
        let names = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
                     "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen"]
        return count < names.count ? names[count] : "\(count)"
    }

    // MARK: - Pager

    @ViewBuilder
    private var pager: some View {
        if paging.pageCount > 1 {
            HStack(spacing: 8) {
                IconButton(systemName: "chevron.left", help: "Previous page (←)", size: 30) { turn(-1) }
                HStack(spacing: 7) {
                    ForEach(0..<paging.pageCount, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Palette.signal : Palette.rimStrong)
                            .frame(width: 7, height: 7)
                            .scaleEffect(index == currentPage ? 1.35 : 1)
                            .shadow(color: Palette.signal.opacity(index == currentPage ? 0.7 : 0), radius: 5)
                    }
                }
                .motion(Motion.spring, value: currentPage)
                IconButton(systemName: "chevron.right", help: "Next page (→)", size: 30) { turn(1) }
            }
        }
    }

    // MARK: - Compass

    @ViewBuilder
    private var compassArea: some View {
        if pageBookmarks.isEmpty {
            VStack(spacing: 14) {
                SearchingDial()
                    .frame(width: 300, height: 300)
                    .shadow(color: Color.black.opacity(0.45), radius: 20, y: 14)
                Text("Nothing on the dial yet")
                    .font(Palette.display(20, .semibold))
                    .foregroundStyle(Palette.bone)
                Text("Press + to add your first link.")
                    .font(Palette.display(15, .regular))
                    .foregroundStyle(Palette.boneDim)
            }
        } else {
            LiveCompass(
                bookmarks: pageBookmarks,
                page: currentPage,
                paging: paging,
                showsNumbers: settings.preferences.showNumbers,
                radius: CGFloat(settings.preferences.menuRadius),
                handle: handle,
                onHover: { bookmark in
                    // Leaving the compass keeps the last slot on show: the buttons that act on it
                    // are off to the left, and the copy must not vanish on the way to them.
                    if let bookmark { aimedID = bookmark.id }
                },
                onActivate: { open($0) }
            )
        }
    }

    // MARK: - Actions

    private func open(_ bookmark: Bookmark) {
        model.openBookmark(bookmark)
        model.syncMessage = .success("Opening \(bookmark.host.isEmpty ? bookmark.displayTitle : bookmark.host)")
    }

    private func turn(_ delta: Int) {
        let count = paging.pageCount
        guard count > 1 else { return }
        withAnimation(Motion.springSoft) {
            page = (currentPage + delta + count) % count
            aimedID = nil
        }
    }

    /// Returns true when the key was the dial's.
    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123:
            turn(-1)
            return true
        case 124:
            turn(1)
            return true
        default:
            break
        }
        guard let character = event.charactersIgnoringModifiers?.first,
              let index = RadialLayout.sliceIndex(forKey: character),
              pageBookmarks.indices.contains(index)
        else { return false }
        let bookmark = pageBookmarks[index]
        handle.flash(index)
        aimedID = bookmark.id
        // The slice springs back before the page changes underneath it, as on the overlay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { open(bookmark) }
        return true
    }
}
