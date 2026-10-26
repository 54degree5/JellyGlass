import AppKit
import JellyGlass

/// A scripted sequence of drags, used to record the README animation: `JellyGlassDemo --showreel`.
final class Showreel {
    struct Gesture {
        let button: JellyGlassButton
        let vector: CGVector        // where the held cursor ends up, points from the press point (y up)
        let ramp: TimeInterval      // seconds to get there
        let hold: TimeInterval      // seconds held before letting go
    }

    private let gestures: [Gesture]
    private let settle: TimeInterval
    private var timer: Timer?

    init(gestures: [Gesture], settle: TimeInterval = 0.85) {
        self.gestures = gestures
        self.settle = settle
    }

    var duration: TimeInterval { gestures.reduce(0) { $0 + $1.ramp + $1.hold + settle } }

    func start(after delay: TimeInterval = 0.8) {
        var t = delay
        for gesture in gestures {
            let begin = t
            DispatchQueue.main.asyncAfter(deadline: .now() + begin) { self.drag(gesture) }
            t += gesture.ramp + gesture.hold + settle
        }
    }

    private func drag(_ g: Gesture) {
        g.button.press()
        let started = CACurrentMediaTime()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { timer in
            let progress = min((CACurrentMediaTime() - started) / g.ramp, 1)
            let eased = 1 - pow(1 - progress, 3)                       // ease-out
            g.button.pull(to: CGVector(dx: g.vector.dx * eased, dy: g.vector.dy * eased))
            if progress >= 1 {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + g.hold) { g.button.release() }
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
}
