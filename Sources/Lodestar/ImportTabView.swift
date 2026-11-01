import SwiftUI
import AppKit
import RadialCore

/// Safari import, in one place, and honest about what it is about to do.
///
/// The explanation used to be spread across the header, the footer, Settings and onboarding.
/// The framing stays: Full Disk Access is optional, and the cost of skipping it is nothing but
/// this tab. Once access is there, the tab shows a dry run first (what is new, what is already on
/// the dial) so importing is a decision rather than a leap, then fills the slots on screen.
struct ImportTabView: View {
    @ObservedObject var model: BookmarkListModel
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase { case locked, ready, running, done }

    @State private var phase: Phase = .locked
    @State private var preview: BookmarkStore.MergePreview?
    @State private var previewError: String?
    /// How many slots the dial had before the import, so the ring knows where the new ones start.
    @State private var startCount = 0
    @State private var addedCount = 0
    @State private var progress = 0

    var body: some View {
        VStack(spacing: 22) {
            switch phase {
            case .locked: locked
            case .ready: ready
            case .running: running
            case .done: done
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
        .motion(Motion.springSoft, value: phase)
        .onAppear(perform: refresh)
        // Granting happens in System Settings; checking again when the user comes back is what
        // lets the lock open without a reload button.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if phase == .locked || phase == .ready { refresh() }
        }
    }

    // MARK: - Phases

    private var locked: some View {
        Group {
            LockBadge(open: false)
            heading("Bring your Safari\nbookmarks along")
            paragraph("Safari keeps them behind a macOS permission. It's optional: the dial, reordering and every setting work without it.")
            HStack(spacing: 12) {
                Button("Open Full Disk Access") { model.openFullDiskAccessSettings() }
                    .buttonStyle(SignalButtonStyle(size: 15))
                Button("Not now", action: onDone)
                    .buttonStyle(QuietButtonStyle(size: 15))
            }
            .padding(.top, 6)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var ready: some View {
        LockBadge(open: true)

        if let previewError {
            heading("Safari didn't answer")
            paragraph(previewError)
            Button("Try again", action: refresh)
                .buttonStyle(SignalButtonStyle(size: 15))
                .padding(.top, 6)
        } else if let preview {
            if preview.added.isEmpty {
                heading("You're all caught up")
                paragraph("Everything in Safari is already on your dial.")
                stats(preview)
                Button("See the dial", action: onDone)
                    .buttonStyle(SignalButtonStyle(size: 15))
                    .padding(.top, 6)
            } else {
                heading("Safari is connected")
                stats(preview)
                chips(preview.added)
                Button {
                    runImport()
                } label: {
                    Label(
                        "Import \(preview.added.count) bookmark\(preview.added.count == 1 ? "" : "s")",
                        systemImage: "arrow.down.to.line"
                    )
                }
                .buttonStyle(SignalButtonStyle(size: 15))
                Text("Slots you've arranged never move. New links are added after them.")
                    .font(Palette.display(14, .regular))
                    .foregroundStyle(Palette.boneFaint)
            }
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    private var running: some View {
        Group {
            ImportRing(startCount: startCount, progress: progress)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(progress)")
                    .font(Palette.mono(46, .semibold))
                    .foregroundStyle(Palette.bone)
                    .contentTransition(.numericText())
                Text("/ \(addedCount)")
                    .font(Palette.mono(22))
                    .foregroundStyle(Palette.boneFaint)
            }
            paragraph("Filling slots…")
        }
        .motion(Motion.spring, value: progress)
        .transition(.opacity)
    }

    private var done: some View {
        Group {
            LockBadge(open: true)
            heading(addedCount == 0 ? "Up to date" : "Added \(addedCount) bookmark\(addedCount == 1 ? "" : "s")")
            paragraph(addedCount == 0
                 ? "Everything in Safari is already on your dial."
                 : "They fill slots \(startCount + 1)–\(startCount + addedCount). Your existing slots never moved.")
            Button("See the dial", action: onDone)
                .buttonStyle(SignalButtonStyle(size: 15))
                .padding(.top, 6)
        }
        .transition(.opacity)
    }

    // MARK: - Pieces

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(Palette.display(40, .semibold))
            .tracking(-0.6)
            .foregroundStyle(Palette.bone)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(Palette.display(17, .regular))
            .lineSpacing(3)
            .foregroundStyle(Palette.boneDim)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func stats(_ preview: BookmarkStore.MergePreview) -> some View {
        HStack(spacing: 14) {
            ImportStat(value: preview.result.added, label: "New", tint: Palette.signal, delay: 0)
            ImportStat(value: preview.result.unchanged, label: "Already here", tint: Palette.bone, delay: 0.08)
            if preview.result.updated > 0 {
                ImportStat(value: preview.result.updated, label: "Renamed", tint: Palette.bone, delay: 0.16)
            }
        }
        .padding(.top, 4)
    }

    private func chips(_ added: [Bookmark]) -> some View {
        let shown = Array(added.prefix(8))
        let rest = added.count - shown.count
        return FlowLayout(spacing: 8) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, bookmark in
                chip(bookmark.displayTitle, delay: 0.25 + Double(index) * 0.05)
            }
            if rest > 0 {
                chip("+\(rest) more", delay: 0.25 + Double(shown.count) * 0.05)
            }
        }
        .frame(maxWidth: 520)
    }

    private func chip(_ text: String, delay: Double) -> some View {
        ImportChip(text: text, delay: delay)
    }

    // MARK: - Actions

    private func refresh() {
        let access = model.hasFullDiskAccess
        guard access else {
            phase = .locked
            preview = nil
            previewError = nil
            return
        }
        let result = model.previewSafariImport()
        preview = result.preview
        previewError = result.error
        phase = .ready
    }

    /// Does the real import up front, then plays it back one slot at a time. The data is final
    /// the moment the button is pressed, so leaving the tab mid-animation loses nothing.
    private func runImport() {
        let before = model.bookmarks.count
        model.syncFromSafari()
        let added = max(0, model.bookmarks.count - before)
        startCount = before
        addedCount = added
        progress = 0
        guard added > 0 else {
            phase = .done
            return
        }
        phase = .running
        let step = reduceMotion ? 0.02 : min(0.26, 2.4 / Double(added))
        Task { @MainActor in
            for slot in 1...added {
                try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
                progress = slot
            }
            try? await Task.sleep(nanoseconds: reduceMotion ? 50_000_000 : 450_000_000)
            phase = .done
        }
    }
}

// MARK: - Parts

private struct ImportStat: View {
    let value: Int
    let label: String
    let tint: Color
    let delay: Double
    @State private var shown = false

    var body: some View {
        VStack(spacing: 8) {
            Text("\(value)")
                .font(Palette.display(40, .semibold))
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(Palette.mono(11, .semibold))
                .tracking(1.4)
                .foregroundStyle(Palette.boneFaint)
        }
        .frame(width: 150)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.hull))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.rim, lineWidth: 1))
        .scaleEffect(shown ? 1 : 0.85)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(Motion.spring.delay(delay)) { shown = true }
        }
    }
}

private struct ImportChip: View {
    let text: String
    let delay: Double
    @State private var shown = false

    var body: some View {
        Text(text)
            .font(Palette.display(14, .regular))
            .foregroundStyle(Palette.bone)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Palette.signal.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Palette.signal.opacity(0.35), lineWidth: 1))
            .scaleEffect(shown ? 1 : 0.8)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(Motion.spring.delay(delay)) { shown = true }
            }
    }
}

/// A page of the dial as nine pips on a ring: the ones that were already there sit dim, and each
/// new slot lights in orange as it is filled, the newest pip swelling.
private struct ImportRing: View {
    let startCount: Int
    let progress: Int

    var body: some View {
        let slots = RadialLayout.maxSlicesPerPage
        let newest = startCount + max(progress, 1) - 1
        let page = newest / slots
        let newestPosition = newest % slots
        // Positions before this were on the dial already, when this page is the one that was
        // already partly filled.
        let existingBelow = page == startCount / slots ? startCount % slots : 0

        return ZStack {
            Circle()
                .strokeBorder(Palette.rim, lineWidth: 1)
                .frame(width: 124, height: 124)
            ForEach(0..<slots, id: \.self) { position in
                let angle = Double(position) / Double(slots) * 2 * Double.pi
                let lit = progress > 0 && position <= newestPosition
                let isNew = position >= existingBelow
                let isNewest = progress > 0 && position == newestPosition
                Circle()
                    .fill(lit ? (isNew ? Palette.signal : Palette.bone.opacity(0.55)) : Palette.rimStrong)
                    .frame(width: 10, height: 10)
                    .scaleEffect(isNewest ? 1.6 : 1)
                    .shadow(color: Palette.signal.opacity(isNewest ? 0.9 : 0), radius: 8)
                    .offset(x: CGFloat(sin(angle)) * 62, y: CGFloat(-cos(angle)) * 62)
            }
            Text("PAGE \(page + 1)")
                .font(Palette.mono(11, .semibold))
                .tracking(1.4)
                .foregroundStyle(Palette.boneFaint)
        }
        .frame(width: 150, height: 150)
        .motion(Motion.spring, value: progress)
    }
}

/// Chips that wrap onto as many centred rows as they need.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    private func rows(in width: CGFloat, subviews: Subviews) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var x: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(index)
            x += size.width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var widest: CGFloat = 0
        for row in rows(in: width, subviews: subviews) {
            let sizes = row.map { subviews[$0].sizeThatFits(.unspecified) }
            let rowWidth = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, sizes.count - 1))
            widest = max(widest, rowWidth)
            height += (sizes.map(\.height).max() ?? 0) + spacing
        }
        return CGSize(width: widest, height: max(0, height - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews: subviews) {
            let sizes = row.map { subviews[$0].sizeThatFits(.unspecified) }
            let rowWidth = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, sizes.count - 1))
            var x = bounds.minX + (bounds.width - rowWidth) / 2
            for (offset, index) in row.enumerated() {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += sizes[offset].width + spacing
            }
            y += (sizes.map(\.height).max() ?? 0) + spacing
        }
    }
}

/// A brass padlock that opens when access is granted.
private struct LockBadge: View {
    let open: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        Image(systemName: open ? "lock.open.fill" : "lock.fill")
            .font(.system(size: 50, weight: .semibold))
            .foregroundStyle(Palette.signalInk)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 112, height: 112)
            .background(shape.fill(Brass.plate))
            .overlay(shape.strokeBorder(Brass.edge, lineWidth: 0.5))
            .brassSheen(in: shape)
            .shadow(color: Color.black.opacity(0.55), radius: 22, y: 14)
            .scaleEffect(open ? 1.04 : 1)
            .motion(Motion.spring, value: open)
    }
}
