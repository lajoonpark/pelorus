import Foundation
import QuartzCore

/// A critically damped spring, integrated per frame.
///
/// Springs (rather than eased curves) are what make the radial feel good: hover follows the
/// cursor with a little weight, and opening overshoots slightly before settling.
struct SpringValue {
    var target: Double
    private(set) var value: Double
    private var velocity: Double

    var stiffness: Double
    var damping: Double

    init(_ value: Double = 0, stiffness: Double = 360, damping: Double = 26) {
        self.target = value
        self.value = value
        self.velocity = 0
        self.stiffness = stiffness
        self.damping = damping
    }

    var isAnimating: Bool {
        abs(target - value) > 0.0005 || abs(velocity) > 0.0005
    }

    /// Advances by `dt` seconds and returns the new value.
    @discardableResult
    mutating func step(_ dt: Double) -> Double {
        // Sub-step so a hitchy frame cannot make the spring explode. The cap only exists to
        // bound the work per frame, so it has to sit far above any dt the driver can hand us:
        // capping at a nominal 1/30 was silently undoing `FrameDriver`'s real-time measurement
        // by compressing a 250ms stall into 33ms of motion. Every spring in this file is stable
        // at 0.25s with 240Hz sub-steps, which is the driver's own ceiling.
        let clamped = min(dt, FrameDriver.maximumStep)
        let steps = max(1, Int((clamped / (1.0 / 240.0)).rounded(.up)))
        let h = clamped / Double(steps)
        for _ in 0..<steps {
            let force = stiffness * (target - value) - damping * velocity
            velocity += force * h
            value += velocity * h
        }
        if !isAnimating {
            value = target
            velocity = 0
        }
        return value
    }

    /// Starts the spring already moving. Used where an object must be under way on the very
    /// first frame rather than easing away from rest, which reads as a stutter.
    mutating func kick(velocity newVelocity: Double) {
        velocity = newVelocity
    }

    /// Adds to the spring's speed without moving it, like a tap on something already at rest. The
    /// lid landing on its stop uses it to shake the case.
    mutating func impulse(_ deltaVelocity: Double) {
        velocity += deltaVelocity
    }

    mutating func snap(to newValue: Double) {
        value = newValue
        target = newValue
        velocity = 0
    }
}

enum Easing {
    /// Overshoots past 1 then settles — used for the menu's open pop.
    static func outBack(_ t: Double, overshoot: Double = 1.7) -> Double {
        let c = overshoot
        let p = t - 1
        return 1 + (c + 1) * p * p * p + c * p * p
    }

    static func outCubic(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    /// Decelerates hard at the end. Used for the bezel sweep, which should shoot off and settle.
    static func outQuint(_ t: Double) -> Double {
        1 - pow(1 - t, 5)
    }

    static func inCubic(_ t: Double) -> Double {
        t * t * t
    }

    static func inOutSine(_ t: Double) -> Double {
        -(cos(.pi * t) - 1) / 2
    }

    static func smoothstep(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }
}

/// Drives per-frame redraws while anything is moving. Deliberately idle when the menu is
/// closed so the app costs nothing in the background.
final class FrameDriver {
    /// Longest single step the springs are ever asked to take. Also the value `Timer` is
    /// clamped to, so the two cannot drift apart.
    static let maximumStep: Double = 0.25

    private var timer: Timer?
    private var tick: ((Double) -> Void)?
    /// When the previous tick ran. Held here rather than in the closure so the timer body never
    /// mutates a captured variable, which Swift 6 rejects as concurrent access.
    private var lastTick: Double = 0

    var isRunning: Bool { timer != nil }

    func start(_ onTick: @escaping (Double) -> Void) {
        tick = onTick
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            guard let self, let tick = self.tick else { return }
            // Real elapsed time, not the nominal interval. Summoning the menu activates the
            // app and orders the panel front, and the main run loop can be held off for a few
            // hundred milliseconds while that happens. Feeding the nominal 1/120 in afterwards
            // makes the springs re-live the stall frame by frame: the compass appears, the
            // motion stops, and only then does the lid swing. Measuring the clock instead lets
            // the animation resume exactly where wall-clock time says it should be.
            let now = CACurrentMediaTime()
            let dt = min(FrameDriver.maximumStep, max(0, now - self.lastTick))
            self.lastTick = now
            tick(dt)
        }
        // .common keeps animation alive while a menu or resize is tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tick = nil
    }
}
