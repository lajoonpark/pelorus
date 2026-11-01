import SwiftUI
import AppKit

// The manager window's design system: everything that makes a control feel like a brass part
// on a leather desk instead of a stock macOS widget. The tokens it draws on (colours, type) live
// in `Palette` and `CompassTheme`; this file is motion, light and the controls themselves.
//
// Mirrors preview/manager-preview.html, which is where the look was approved.

// MARK: - Motion

/// The springs the window moves with. One vocabulary, so a tab change, a toggle and a button
/// press feel like parts of the same machine.
enum Motion {
    /// Controls arriving at a new state: quick, a little overshoot.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.72)
    /// Big surfaces: tab plates, the composer, anything that travels.
    static let springSoft = Animation.spring(response: 0.55, dampingFraction: 0.80)
    /// Presses and hovers.
    static let snap = Animation.spring(response: 0.26, dampingFraction: 0.66)
}

private struct MotionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// `.animation(_:value:)` that stands down when Reduce Motion is on.
    func motion<Value: Equatable>(_ animation: Animation = Motion.spring, value: Value) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }

    /// A pointer-following highlight, clipped to `shape`. Reads as light moving over metal.
    func brassSheen<S: Shape>(in shape: S) -> some View {
        modifier(SheenModifier(shape: shape))
    }

    /// Rises a couple of points under the pointer.
    func liftOnHover(_ lift: CGFloat = 2) -> some View {
        modifier(LiftModifier(lift: lift))
    }
}

private struct SheenModifier<S: Shape>: ViewModifier {
    let shape: S
    @State private var point: CGPoint?

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    RadialGradient(
                        colors: [Color.white.opacity(0.32), Color.clear],
                        center: UnitPoint(
                            x: (point?.x ?? 0) / max(proxy.size.width, 1),
                            y: (point?.y ?? 0) / max(proxy.size.height, 1)
                        ),
                        startRadius: 0,
                        endRadius: 130
                    )
                    .blendMode(.softLight)
                    .opacity(point == nil ? 0 : 1)
                    .animation(.easeOut(duration: 0.22), value: point == nil)
                }
                .clipShape(shape)
                .allowsHitTesting(false)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): point = location
                case .ended: point = nil
                }
            }
    }
}

private struct LiftModifier: ViewModifier {
    let lift: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .offset(y: hovering ? -lift : 0)
            .onHover { hovering = $0 }
            .motion(Motion.spring, value: hovering)
    }
}

// MARK: - Brass

enum Brass {
    /// A polished plate, lit from above. Dark ink stays readable on every stop.
    static let plate = LinearGradient(
        colors: [
            CompassTheme.brassHi.swiftUI(),
            CompassTheme.brassLit.swiftUI(),
            Color(red: 0.62, green: 0.49, blue: 0.27),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// The bright upper edge every plate catches.
    static let edge = Color(red: 1.0, green: 0.96, blue: 0.84).opacity(0.55)
}

// MARK: - Pointer light

/// Where the cursor is inside the window, as 0…1 with y down.
///
/// Observed only by the views that use it (the leather, the 3D compass), so mouse movement
/// re-renders those and never the window around them. A local event monitor rather than
/// `onContinuousHover` because the light has to keep following the cursor underneath other
/// views, which SwiftUI hover would not deliver.
final class PointerTracker: ObservableObject {
    @Published private(set) var unit = CGPoint(x: 0.5, y: 0.3)
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard let bounds = event.window?.contentView?.bounds, bounds.width > 1, bounds.height > 1 else { return }
        let point = event.locationInWindow
        unit = CGPoint(
            x: min(max(point.x / bounds.width, 0), 1),
            y: min(max(1 - point.y / bounds.height, 0), 1)
        )
    }

    deinit { stop() }
}

/// The desk: warm leather, a pool of light under the cursor, a vignette, and fine grain.
struct LeatherBackground: View {
    @ObservedObject var tracker: PointerTracker

    var body: some View {
        GeometryReader { proxy in
            let longest = max(proxy.size.width, proxy.size.height)
            ZStack {
                Palette.void
                RadialGradient(
                    colors: [Palette.signal.opacity(0.13), Color.clear],
                    center: UnitPoint(x: tracker.unit.x, y: tracker.unit.y),
                    startRadius: 0,
                    endRadius: longest * 0.42
                )
                RadialGradient(
                    colors: [CompassTheme.brassLit.swiftUI(alpha: 0.07), Color.clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: longest * 0.8
                )
                RadialGradient(
                    colors: [Color.clear, Color.black.opacity(0.45)],
                    center: .center,
                    startRadius: min(proxy.size.width, proxy.size.height) * 0.45,
                    endRadius: longest * 0.75
                )
                GrainOverlay()
            }
            .animation(.easeOut(duration: 0.35), value: tracker.unit)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Leather grain. Seeded, so it never shimmers between redraws.
private struct GrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(seed >> 33) / 2_147_483_648.0
            }
            for _ in 0..<2600 {
                let x = next() * size.width
                let y = next() * size.height
                let light = next() > 0.5
                let alpha = 0.05 + next() * 0.05
                context.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color((light ? Color.white : Color.black).opacity(alpha))
                )
            }
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}

// MARK: - Controls

/// A square icon button that warms up under the pointer.
struct IconButton: View {
    let systemName: String
    let help: String
    var tint: Color = Palette.boneDim
    var hoverTint: Color = Palette.bone
    var size: CGFloat = 36
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(hovering ? hoverTint : tint)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.bone.opacity(hovering ? 0.10 : 0))
                )
                .scaleEffect(hovering ? 1.12 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Motion.snap, value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A keycap with real thickness: it sinks when `pressed`.
struct PhysicalKey: View {
    let text: String
    var pressed = false

    var body: some View {
        Text(text)
            .font(Palette.mono(15, .semibold))
            .foregroundStyle(pressed ? Palette.signal : Palette.bone)
            .frame(minWidth: 38, minHeight: 38)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Palette.hullLift, Palette.hull],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Palette.rim, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.65), radius: 0, x: 0, y: pressed ? 0 : 4)
            .offset(y: pressed ? 4 : 0)
            .motion(Motion.snap, value: pressed)
    }
}

/// A switch with a brass thumb. Replaces the system switch, which reads as a different product.
struct BrassToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 16) {
            configuration.label
            Spacer(minLength: 12)
            BrassSwitch(isOn: configuration.isOn) {
                configuration.isOn.toggle()
            }
        }
    }
}

private struct BrassSwitch: View {
    let isOn: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isOn ? Palette.signal.opacity(0.35) : Palette.void)
                    .overlay(
                        Capsule().strokeBorder(isOn ? Palette.signal.opacity(0.7) : Palette.rim, lineWidth: 1)
                    )
                    .shadow(color: Palette.signal.opacity(isOn ? 0.28 : 0), radius: 10)
                Circle()
                    .fill(RadialGradient(
                        colors: isOn
                            ? [Color(red: 0.95, green: 0.84, blue: 0.66), Palette.signal]
                            : [CompassTheme.brassHi.swiftUI(), CompassTheme.brassMid.swiftUI()],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 18
                    ))
                    .overlay(Circle().strokeBorder(Brass.edge.opacity(0.4), lineWidth: 0.5))
                    .shadow(color: Color.black.opacity(0.5), radius: 3, y: 2)
                    .frame(width: 24, height: 24)
                    .scaleEffect(hovering ? 1.08 : 1)
                    .padding(3)
                    .offset(x: isOn ? 22 : 0)
            }
            .frame(width: 52, height: 30)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Motion.spring, value: isOn)
        .motion(Motion.snap, value: hovering)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// A segmented control whose brass plate slides between choices.
struct BrassSegmented<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option
    @Namespace private var plate

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(Motion.springSoft) { selection = option }
                } label: {
                    Text(title(option))
                        .font(Palette.display(14.5, selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Palette.signalInk : Palette.boneDim)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Brass.plate)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Brass.edge, lineWidth: 0.5)
                                    )
                                    .shadow(color: Color.black.opacity(0.4), radius: 4, y: 2)
                                    .matchedGeometryEffect(id: "plate", in: plate)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.void))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.rim, lineWidth: 1))
    }
}

/// A slider with a brass thumb. The system slider cannot be reskinned on macOS.
struct BrassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    @State private var dragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
            let x = CGFloat(fraction) * max(width - 22, 1) + 11

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.void)
                    .frame(height: 6)
                    .overlay(Capsule().strokeBorder(Palette.rim, lineWidth: 1))
                Capsule()
                    .fill(Palette.signal)
                    .frame(width: x, height: 6)
                Circle()
                    .fill(RadialGradient(
                        colors: [CompassTheme.brassHi.swiftUI(), CompassTheme.brassLit.swiftUI(), CompassTheme.brassMid.swiftUI()],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 16
                    ))
                    .overlay(Circle().strokeBorder(Brass.edge.opacity(0.5), lineWidth: 0.5))
                    .shadow(color: Color.black.opacity(0.55), radius: 4, y: 3)
                    .frame(width: 22, height: 22)
                    .scaleEffect(dragging ? 0.92 : 1)
                    .position(x: x, y: proxy.size.height / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        dragging = true
                        let t = min(max((drag.location.x - 11) / max(width - 22, 1), 0), 1)
                        value = range.lowerBound + Double(t) * span
                    }
                    .onEnded { _ in dragging = false }
            )
            .motion(Motion.snap, value: dragging)
        }
        .frame(height: 24)
    }
}

/// A status message that rises from the bottom edge and leaves on its own.
struct ToastView: View {
    let message: BookmarkListModel.SyncMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: message.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(message.isError ? Palette.alarm : Palette.mint)
            Text(message.text)
                .font(Palette.display(15, .medium))
                .foregroundStyle(Palette.bone)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.voidRaised))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.rimStrong, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.5), radius: 24, y: 12)
    }
}

/// How tabs arrive and leave: a short slide with a slight tilt in depth, as if the page were
/// swung onto the desk. `amount` runs -1…1; 0 is at rest.
struct DepthTransition: ViewModifier {
    let amount: Double

    func body(content: Content) -> some View {
        content
            .opacity(1 - abs(amount))
            .rotation3DEffect(.degrees(amount * 7), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .offset(y: CGFloat(amount) * 26)
            .scaleEffect(1 - abs(amount) * 0.015)
    }
}

extension AnyTransition {
    static var depth: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: DepthTransition(amount: 1), identity: DepthTransition(amount: 0)),
            removal: .modifier(active: DepthTransition(amount: -1), identity: DepthTransition(amount: 0))
        )
    }
}

/// A pop-up menu drawn in brass. The system menu cannot be restyled on macOS, so this is a
/// field that opens a list of its own.
///
/// The host must raise whatever contains it (`.zIndex`), or later siblings paint over the list.
struct BrassDropdown<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option
    @State private var open = false

    var body: some View {
        Button {
            withAnimation(Motion.spring) { open.toggle() }
        } label: {
            HStack(spacing: 10) {
                Text(title(selection))
                    .font(Palette.display(15, .medium))
                    .foregroundStyle(Palette.bone)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(open ? Palette.signal : Palette.boneDim)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.void))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(open ? Palette.signal : Palette.rim, lineWidth: open ? 1.5 : 1)
            )
            .shadow(color: Palette.signal.opacity(open ? 0.2 : 0), radius: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .liftOnHover(1.5)
        .overlay(alignment: .topTrailing) {
            if open {
                ZStack(alignment: .topTrailing) {
                    // Clicking anywhere else closes the list.
                    Color.clear
                        .frame(width: 3000, height: 3000)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(Motion.spring) { open = false } }
                    list
                        .offset(y: 46)
                }
                .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(options, id: \.self) { option in
                DropdownRow(title: title(option), selected: option == selection) {
                    withAnimation(Motion.spring) {
                        selection = option
                        open = false
                    }
                }
            }
        }
        .padding(6)
        .frame(minWidth: 190)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.voidRaised))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.rimStrong, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.6), radius: 26, y: 14)
    }
}

private struct DropdownRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.signal)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 14)
                Text(title)
                    .font(Palette.display(15, selected ? .semibold : .regular))
                    .foregroundStyle(Palette.bone)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? Palette.signal.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Motion.snap, value: hovering)
    }
}

// MARK: - Fields and badges

extension View {
    /// The text-field surface: a dark well that glows orange when focused, red when it has a problem.
    func brassField(focused: Bool, error: Bool = false, height: CGFloat = 46) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let accent = error ? Palette.alarm : Palette.signal
        let active = focused || error
        return self
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(shape.fill(Palette.void))
            .overlay(shape.strokeBorder(active ? accent : Palette.rim, lineWidth: active ? 1.5 : 1))
            .shadow(color: accent.opacity(active ? 0.22 : 0), radius: 12)
            .motion(Motion.spring, value: focused)
            .motion(Motion.spring, value: error)
    }
}

/// Splits a shortcut's display name into one keycap per key: modifiers each get their own, and
/// whatever follows is the last ("⌃⌘E" becomes ⌃, ⌘, E).
enum KeyParts {
    static func split(_ name: String) -> [String] {
        let modifiers: Set<Character> = ["⌘", "⌃", "⌥", "⇧"]
        var parts: [String] = []
        var rest = ""
        for character in name {
            if modifiers.contains(character) && rest.isEmpty {
                parts.append(String(character))
            } else {
                rest.append(character)
            }
        }
        if !rest.isEmpty { parts.append(rest) }
        return parts
    }
}

/// A brass plate with a symbol on it: the same object the Import tab's padlock is.
struct BrassBadge: View {
    let symbol: String
    var size: CGFloat = 112

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(Palette.signalInk)
            .frame(width: size, height: size)
            .background(shape.fill(Brass.plate))
            .overlay(shape.strokeBorder(Brass.edge, lineWidth: 0.5))
            .brassSheen(in: shape)
            .shadow(color: Color.black.opacity(0.55), radius: 22, y: 14)
    }
}

/// A tick that draws itself.
struct DrawnCheck: View {
    var tint: Color = Palette.mint
    var lineWidth: CGFloat = 3.5
    @State private var drawn = false

    var body: some View {
        CheckShape()
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .onAppear {
                withAnimation(.easeOut(duration: 0.38).delay(0.12)) { drawn = true }
            }
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.54))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.74))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.80, y: rect.minY + rect.height * 0.28))
        return path
    }
}

// MARK: - Hotkey keycaps

extension Notification.Name {
    /// Posted by the app whenever the global shortcut fires, so on-screen keycaps can press too.
    static let dialHotkeyPressed = Notification.Name("Lodestar.dialHotkeyPressed")
}

/// The shortcut drawn as physical keys, which sink when you press the real thing.
struct HotkeyKeycaps: View {
    let displayName: String
    @State private var pressed = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(KeyParts.split(displayName).enumerated()), id: \.offset) { _, part in
                PhysicalKey(text: part, pressed: pressed)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dialHotkeyPressed)) { _ in
            pressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { pressed = false }
        }
    }
}

// MARK: - Action menu

struct BrassMenuItem: Identifiable {
    let id = UUID()
    let title: String
    var systemImage: String?
    var destructive = false
    /// Draws a hairline above this item.
    var separatorBefore = false
    let action: () -> Void
}

/// A "more" button that opens a brass list of actions: the system menu cannot be restyled.
///
/// The host raises its own row while `isOpen` is true (`.zIndex`), or later siblings paint over
/// the list. The list opens downward, or upward when the click was low in the window, so it is
/// never cut off by the edge of a scroll view.
struct BrassActionMenu: View {
    let items: [BrassMenuItem]
    var help = "More"
    @Binding var isOpen: Bool
    @State private var opensUpward = false
    @State private var hovering = false

    var body: some View {
        Button {
            if !isOpen, let event = NSApp.currentEvent {
                // Window coordinates run up from the bottom edge: a click in the lowest part of
                // the window leaves no room below for the list.
                opensUpward = event.locationInWindow.y < 260
            }
            withAnimation(Motion.spring) { isOpen.toggle() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOpen ? Palette.signal : (hovering ? Palette.bone : Palette.boneDim))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.bone.opacity(hovering || isOpen ? 0.10 : 0))
                )
                .scaleEffect(hovering ? 1.12 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Motion.snap, value: hovering)
        .help(help)
        .accessibilityLabel(help)
        .overlay(alignment: opensUpward ? .bottomTrailing : .topTrailing) {
            if isOpen {
                ZStack(alignment: opensUpward ? .bottomTrailing : .topTrailing) {
                    Color.clear
                        .frame(width: 3000, height: 3000)
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                    list
                        .offset(y: opensUpward ? -42 : 42)
                }
                .transition(.scale(scale: 0.92, anchor: opensUpward ? .bottomTrailing : .topTrailing)
                    .combined(with: .opacity))
            }
        }
    }

    private func close() {
        withAnimation(Motion.spring) { isOpen = false }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items) { item in
                if item.separatorBefore {
                    Rectangle()
                        .fill(Palette.rim)
                        .frame(height: 1)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                }
                MenuRow(item: item) {
                    close()
                    item.action()
                }
            }
        }
        .padding(6)
        .frame(minWidth: 200)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.voidRaised))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.rimStrong, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.6), radius: 26, y: 14)
    }
}

private struct MenuRow: View {
    let item: BrassMenuItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let tint = item.destructive ? Palette.alarm : Palette.bone
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage ?? "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.destructive ? Palette.alarm : Palette.boneDim)
                    .frame(width: 16)
                    .opacity(item.systemImage == nil ? 0 : 1)
                Text(item.title)
                    .font(Palette.display(15, .regular))
                    .foregroundStyle(tint)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill((item.destructive ? Palette.alarm : Palette.signal).opacity(hovering ? 0.16 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Motion.snap, value: hovering)
    }
}

// MARK: - Dissolve

/// A removed thing goes soft and slides off, instead of simply vanishing.
struct DissolveModifier: ViewModifier {
    /// 0 at rest, 1 when gone.
    let amount: Double

    func body(content: Content) -> some View {
        content
            .opacity(1 - amount)
            .blur(radius: amount * 10)
            .scaleEffect(1 - amount * 0.05)
            .offset(x: CGFloat(amount) * 36)
    }
}

extension AnyTransition {
    static var dissolve: AnyTransition {
        .modifier(active: DissolveModifier(amount: 1), identity: DissolveModifier(amount: 0))
    }
}
