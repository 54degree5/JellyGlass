import AppKit
import JellyGlass

/// A drawn mouse cursor that sits above the whole scene, so a recording shows where the "user" presses.
/// It never receives events.
final class CursorOverlay: NSView {
    private let arrow = NSImageView()
    private let ripple = CAShapeLayer()
    private let image = NSCursor.arrow.image
    private let hotSpot = NSCursor.arrow.hotSpot
    private let scale: CGFloat = 1.45

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        arrow.image = image
        arrow.imageScaling = .scaleAxesIndependently
        arrow.wantsLayer = true
        arrow.layer?.shadowColor = NSColor.black.cgColor
        arrow.layer?.shadowOpacity = 0.45
        arrow.layer?.shadowRadius = 3
        arrow.layer?.shadowOffset = CGSize(width: 0, height: -1.5)
        ripple.path = CGPath(ellipseIn: CGRect(x: -20, y: -20, width: 40, height: 40), transform: nil)
        ripple.fillColor = NSColor(white: 1, alpha: 0.28).cgColor
        ripple.strokeColor = NSColor(white: 1, alpha: 0.85).cgColor
        ripple.lineWidth = 1.5
        ripple.opacity = 0
        layer?.addSublayer(ripple)
        addSubview(arrow)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `pressed` squeezes the arrow a little, the way a held click looks.
    func place(at point: CGPoint, pressed: Bool) {
        let s = scale * (pressed ? 0.86 : 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arrow.frame = CGRect(x: point.x - hotSpot.x * s, y: point.y - (image.size.height - hotSpot.y) * s,
                             width: image.size.width * s, height: image.size.height * s)
        CATransaction.commit()
    }

    /// An expanding ring at the click point.
    func click(at point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ripple.position = point
        CATransaction.commit()
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.35
        grow.toValue = 1.7
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.5
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ripple.add(group, forKey: "click")
    }
}

/// A scripted sequence for the README animation: a cursor travels to a button, presses it, wanders around with it
/// along smooth curves – back and forth, fast and slow, over its neighbours – lets go, and moves on.
final class Showreel {
    /// One press-drag-release. `waypoints` are offsets (points, y up) from the press point; the cursor follows a
    /// smooth spline through them. `swing` varies the speed along the way (0 = constant, 0.9 = surges and lulls).
    struct Take {
        let button: JellyGlassButton
        let waypoints: [CGVector]
        let duration: TimeInterval
        var swing: CGFloat = 0.5
    }

    private enum Phase {
        case travel(from: CGPoint, to: CGPoint, bend: CGFloat)
        case drag(Take, anchor: CGPoint)
        case idle
    }

    private struct Segment {
        let start: TimeInterval
        let end: TimeInterval
        let phase: Phase
    }

    private let overlay: CursorOverlay
    private var segments: [Segment] = []
    private var timer: Timer?
    private var begin = CACurrentMediaTime()
    private var pressed: JellyGlassButton?
    private(set) var duration: TimeInterval = 0

    /// - Parameter anchorOf: centre of a button in the overlay's coordinates.
    init(takes: [Take], overlay: CursorOverlay, startAt: CGPoint, anchorOf: (JellyGlassButton) -> CGPoint) {
        self.overlay = overlay

        var t: TimeInterval = 0.5
        var cursor = startAt
        segments.append(Segment(start: 0, end: t, phase: .idle))
        for (index, take) in takes.enumerated() {
            let anchor = anchorOf(take.button)
            let distance = hypot(anchor.x - cursor.x, anchor.y - cursor.y)
            let travel = min(max(0.34 + Double(distance) / 700, 0.4), 0.95)
            segments.append(Segment(start: t, end: t + travel,
                                    phase: .travel(from: cursor, to: anchor, bend: index % 2 == 0 ? 0.18 : -0.18)))
            t += travel
            segments.append(Segment(start: t, end: t + take.duration, phase: .drag(take, anchor: anchor)))
            t += take.duration
            let last = take.waypoints.last ?? .zero
            cursor = CGPoint(x: anchor.x + last.dx, y: anchor.y + last.dy)
        }
        segments.append(Segment(start: t, end: t + 1.1, phase: .idle))
        duration = t + 1.1
        overlay.place(at: startAt, pressed: false)
    }

    func start() {
        begin = CACurrentMediaTime()
        overlay.isHidden = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    // MARK: Playback

    private func tick() {
        let now = CACurrentMediaTime() - begin
        guard let segment = segments.last(where: { $0.start <= now }) ?? segments.first else { return }
        let local = min(max((now - segment.start) / (segment.end - segment.start), 0), 1)

        switch segment.phase {
        case .idle:
            releaseIfNeeded()
        case .travel(let from, let to, let bend):
            releaseIfNeeded()
            let u = CGFloat(smoothstep(local))
            let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            let dx = to.x - from.x, dy = to.y - from.y
            let control = CGPoint(x: mid.x - dy * bend, y: mid.y + dx * bend)        // an arc, never a straight line
            let a = (1 - u) * (1 - u), b = 2 * (1 - u) * u, c = u * u
            overlay.place(at: CGPoint(x: a * from.x + b * control.x + c * to.x,
                                      y: a * from.y + b * control.y + c * to.y), pressed: false)
        case .drag(let take, let anchor):
            if pressed !== take.button {
                pressed = take.button
                take.button.press()
                overlay.click(at: anchor)
            }
            let offset = spline([.zero] + take.waypoints, warp(local, swing: take.swing))
            overlay.place(at: CGPoint(x: anchor.x + offset.dx, y: anchor.y + offset.dy), pressed: true)
            take.button.pull(to: offset)
        }
    }

    private func releaseIfNeeded() {
        guard let button = pressed else { return }
        pressed = nil
        button.release()
    }

    // MARK: Curves

    private func smoothstep(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    /// Monotonic time warp: speeds up and slows down along the path instead of moving at a constant rate.
    private func warp(_ x: Double, swing: CGFloat) -> CGFloat {
        let k = 2.0                                                    // surges per take
        let a = Double(min(swing, 0.9))
        return CGFloat(x + a * sin(2 * .pi * k * x) / (2 * .pi * k))
    }

    /// Catmull-Rom spline through the points, u in 0...1.
    private func spline(_ p: [CGVector], _ u: CGFloat) -> CGVector {
        let n = p.count - 1
        guard n >= 1 else { return p.first ?? .zero }
        let f = min(max(u, 0), 1) * CGFloat(n)
        let i = min(Int(f), n - 1)
        let t = f - CGFloat(i)
        let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, n)]
        func axis(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
            0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t * t * t)
        }
        return CGVector(dx: axis(p0.dx, p1.dx, p2.dx, p3.dx), dy: axis(p0.dy, p1.dy, p2.dy, p3.dy))
    }
}
