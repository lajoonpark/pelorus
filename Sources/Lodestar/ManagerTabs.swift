import SwiftUI

/// The manager window's sections. One job each: the window used to do all of them at once.
enum ManagerTab: String, CaseIterable, Identifiable {
    case dial
    case library
    case importer
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dial: return "Dial"
        case .library: return "Library"
        case .importer: return "Import"
        case .settings: return "Settings"
        }
    }

    /// ⌘1…⌘4.
    var shortcut: KeyEquivalent {
        switch self {
        case .dial: return "1"
        case .library: return "2"
        case .importer: return "3"
        case .settings: return "4"
        }
    }
}

/// Lets the app delegate steer the window ("Settings…" opens the Settings tab) without owning
/// any of its view state.
final class ManagerRouter: ObservableObject {
    @Published var tab: ManagerTab = .dial
}

/// A brass pill with a lit plate that slides between sections.
struct BrassTabBar: View {
    @Binding var selection: ManagerTab
    @Namespace private var plate
    @State private var hovered: ManagerTab?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ManagerTab.allCases) { tab in
                let selected = tab == selection
                Button {
                    withAnimation(Motion.springSoft) { selection = tab }
                } label: {
                    Text(tab.title)
                        .font(Palette.display(15, .semibold))
                        .foregroundStyle(
                            selected ? Palette.signalInk : (hovered == tab ? Palette.bone : Palette.boneDim)
                        )
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Brass.plate)
                                    .overlay(Capsule().strokeBorder(Brass.edge, lineWidth: 0.5))
                                    .shadow(color: Color.black.opacity(0.45), radius: 6, y: 2)
                                    .brassSheen(in: Capsule())
                                    .matchedGeometryEffect(id: "plate", in: plate)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(TabPressStyle())
                .keyboardShortcut(tab.shortcut, modifiers: .command)
                .onHover { inside in
                    hovered = inside ? tab : (hovered == tab ? nil : hovered)
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(5)
        .background(
            Capsule().fill(LinearGradient(
                colors: [Color(red: 0.184, green: 0.145, blue: 0.114), Color(red: 0.133, green: 0.102, blue: 0.082)],
                startPoint: .top,
                endPoint: .bottom
            ))
        )
        .overlay(Capsule().strokeBorder(Palette.rim, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.45), radius: 16, y: 8)
        .motion(Motion.snap, value: hovered)
    }
}

private struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .motion(Motion.snap, value: configuration.isPressed)
    }
}
