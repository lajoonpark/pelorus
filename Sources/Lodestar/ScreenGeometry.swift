import AppKit
import RadialCore

/// Coordinate conversion helpers shared by the panel and the view.
enum ScreenGeometry {
    /// Screen containing the mouse pointer, falling back to the main screen.
    static func activeScreen() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// The pointer position expressed in the screen's own coordinate space, y down,
    /// which is what the flipped menu view expects.
    static func pointerInView(_ screen: NSScreen) -> CGPoint {
        let point = NSEvent.mouseLocation
        return CGPoint(x: point.x - screen.frame.minX, y: screen.frame.maxY - point.y)
    }
}
