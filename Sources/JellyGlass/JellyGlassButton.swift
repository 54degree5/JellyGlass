import AppKit

/// A Liquid Glass control that stretches like jelly under the cursor (macOS 26+).
///
/// Press it and drag: the glass swells a little, lightens, follows the cursor and stretches along the axis of
/// the pull; let go and it wobbles back. Neighbouring buttons inside one `NSGlassEffectContainerView` still
/// share the container's glass group.
///
/// ## The model
/// Everything is a function of `d`, the cursor's distance (points) from where the button was pressed, measured
/// from a screen recording of a production app with per-frame cursor tracking (see `docs/MEASUREMENTS.md`):
///
///     translation of the body   t(d) = 6.5 · ln(1 + d / 28)
///     stretch                   e(d) = 0.105 · ln(1 + d / 50) · d² / (d² + 40²)
///
/// Both grow logarithmically, so there is no ceiling: the further you pull, the less each extra point adds.
/// The scaling is axis-aligned (the shape never rotates); pulled along an axis it stretches ×(1+e) along it and
/// ÷(1+e) across it (same area); pulled diagonally it does not elongate but grows uniformly.
///
/// ## How the glass is deformed
/// An `NSGlassEffectContainerView` renders all its glass children through one SDF canvas that is sized to the
/// undeformed buttons and reset on every layout, so transforming the SDF layers clips the blur. Instead the
/// `NSGlassEffectView` is made larger than the button by `margin` on all sides and its silhouette is set with
/// the private `_setPath:` – the resting capsule, scaled and shifted every frame. The container is told to
/// re-layout each frame so it re-reads the path. Icons live in the glass's content view, which gets its own,
/// bouncier spring.
///
/// - Important: uses private AppKit selectors (`_setPath:`, `_interactionState`). Fine for local tools and
///   experiments; not suitable for the App Store.
public final class JellyGlassButton: NSView {
    /// How the button settles. While held it follows the cursor with the `drag` springs, after release it
    /// uses the `release` springs.
    public enum Spring: String, CaseIterable {
        /// Quick to follow the cursor, slow to come back, swings past rest once or twice.
        case jelly
        /// Looser still.
        case wobble
        /// Back in ~60 ms with no overshoot; only the icon bounces. What the recording measured.
        case snappy

        fileprivate var set: SpringSet {
            switch self {
            case .jelly:  return SpringSet(dragGlass: (1500, 70), dragIcon: (1100, 50), releaseGlass: (420, 12), releaseIcon: (340, 9))
            case .wobble: return SpringSet(dragGlass: (1500, 70), dragIcon: (1100, 50), releaseGlass: (240, 6), releaseIcon: (200, 5))
            case .snappy: return SpringSet(dragGlass: (3600, 120), dragIcon: (2000, 45), releaseGlass: (3600, 120), releaseIcon: (2000, 45))
            }
        }
    }

    /// How far the button travels and how much it stretches for a given pull.
    public enum Stretch: String, CaseIterable {
        /// Matches the recording.
        case standard
        /// ×1.5.
        case wide
        /// ×2.
        case heavy

        fileprivate var response: Response {
            switch self {
            case .standard: return Response(travel: 6.5, travelScale: 28, stretch: 0.105, stretchScale: 50, softStart: 40)
            case .wide:     return Response(travel: 9.8, travelScale: 28, stretch: 0.16, stretchScale: 50, softStart: 40)
            case .heavy:    return Response(travel: 13, travelScale: 28, stretch: 0.21, stretchScale: 50, softStart: 40)
            }
        }
    }

    public var spring: Spring = .jelly
    public var stretch: Stretch = .standard

    /// `true` (default): the pressed button is lifted (private `_interactionState`) and drawn on top of its
    /// neighbours with a highlight; it does not merge with them while held.
    /// `false`: the pressed button stays in the container's glass group and melts into its neighbours.
    public var liftsOnPress = true

    /// How much the button swells while pressed. 1 disables it.
    public var pressGrowth: CGFloat = 1.07
    /// White tint at full press; the glass lightens instead of darkening. 0 disables it.
    public var pressTintAlpha: CGFloat = 0.16

    /// The underlying glass view, e.g. to change `style` or `tintColor`.
    public let glass = NSGlassEffectView()
    /// Size of the resting button.
    public let size: CGSize

    fileprivate struct SpringSet {
        let dragGlass: (k: CGFloat, c: CGFloat), dragIcon: (k: CGFloat, c: CGFloat)
        let releaseGlass: (k: CGFloat, c: CGFloat), releaseIcon: (k: CGFloat, c: CGFloat)
    }
    fileprivate struct Response {
        let travel: CGFloat, travelScale: CGFloat, stretch: CGFloat, stretchScale: CGFloat, softStart: CGFloat
    }

    /// One animated pose: body translation and axis scale, with velocities.
    private struct Motion {
        var offset = CGVector.zero, offsetVelocity = CGVector.zero
        var scale = CGVector(dx: 1, dy: 1), scaleVelocity = CGVector.zero

        mutating func step(to target: Pose, k: CGFloat, c: CGFloat, dt: CGFloat) {
            offsetVelocity.dx += (k * (target.offset.dx - offset.dx) - c * offsetVelocity.dx) * dt
            offsetVelocity.dy += (k * (target.offset.dy - offset.dy) - c * offsetVelocity.dy) * dt
            scaleVelocity.dx += (k * (target.scale.dx - scale.dx) - c * scaleVelocity.dx) * dt
            scaleVelocity.dy += (k * (target.scale.dy - scale.dy) - c * scaleVelocity.dy) * dt
            offset.dx += offsetVelocity.dx * dt
            offset.dy += offsetVelocity.dy * dt
            scale.dx += scaleVelocity.dx * dt
            scale.dy += scaleVelocity.dy * dt
        }

        var isAtRest: Bool {
            hypot(offset.dx, offset.dy) < 0.02 && hypot(offsetVelocity.dx, offsetVelocity.dy) < 0.05
                && abs(scale.dx - 1) < 0.0005 && abs(scale.dy - 1) < 0.0005
                && hypot(scaleVelocity.dx, scaleVelocity.dy) < 0.005
        }
    }

    private struct Pose {
        var offset = CGVector.zero
        var scale = CGVector(dx: 1, dy: 1)
    }

    private let margin: CGFloat = 90          // room for the deformed silhouette around the resting button
    private let content = NSView()

    private var shape = Motion()              // silhouette
    private var icon = Motion()               // content
    private var target = Pose()
    private var dragStart = CGPoint.zero
    private var dragging = false
    private var pressLevel: CGFloat = 0       // 0 = resting colour, 1 = fully pressed
    private var link: CADisplayLink?

    /// - Parameters:
    ///   - size: size of the resting button; it is drawn as a capsule.
    ///   - contentView: anything to show on the glass, laid out in a `size`-sized frame. It deforms together
    ///     with the glass.
    public init(size: CGSize, contentView: NSView) {
        self.size = size
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        clipsToBounds = false

        glass.frame = bounds.insetBy(dx: -margin, dy: -margin)
        glass.cornerRadius = size.height / 2
        content.frame = NSRect(origin: .zero, size: glass.frame.size)
        content.wantsLayer = true
        contentView.frame = NSRect(x: margin, y: margin, width: size.width, height: size.height)
        content.addSubview(contentView)
        glass.contentView = content
        addSubview(glass)
        render()
    }

    /// Convenience: SF Symbol names laid out side by side.
    public convenience init(size: CGSize, symbols: [String]) {
        let row = NSView(frame: NSRect(origin: .zero, size: size))
        let slot = size.width / CGFloat(max(symbols.count, 1))
        for (index, name) in symbols.enumerated() {
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size.height * 0.40, weight: .regular))
            let view = NSImageView(image: image ?? NSImage())
            view.contentTintColor = NSColor(white: 0.92, alpha: 1)
            view.frame = NSRect(x: CGFloat(index) * slot, y: 0, width: slot, height: size.height)
            row.addSubview(view)
        }
        self.init(size: size, contentView: row)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Cursor -> target pose

    /// Pull = cursor minus press point, in this view's coordinates (y up), in points.
    private func setPull(_ pull: CGVector) {
        let d = hypot(pull.dx, pull.dy)
        let press: CGFloat = dragging ? pressGrowth : 1
        guard d > 0.001 else { target = Pose(offset: .zero, scale: CGVector(dx: press, dy: press)); return }
        let r = stretch.response

        let travel = r.travel * log(1 + d / r.travelScale)
        let soft = d * d / (d * d + r.softStart * r.softStart)        // no stretch right at the press point
        let e = r.stretch * log(1 + d / r.stretchScale) * soft

        // How axis-aligned the pull is: 1 along an axis, 0 on the 45° diagonal.
        let phi = atan2(abs(pull.dy), abs(pull.dx))
        let alignment = abs(cos(2 * phi))
        let grow = 1 + 0.6 * e * (1 - alignment)          // diagonal pull: uniform growth
        let stretchFactor = 1 + e * alignment             // axial pull: stretch / squash

        var scale = CGVector(dx: grow / stretchFactor, dy: grow * stretchFactor)
        if abs(pull.dx) >= abs(pull.dy) { scale = CGVector(dx: grow * stretchFactor, dy: grow / stretchFactor) }
        scale = CGVector(dx: scale.dx * press, dy: scale.dy * press)
        target = Pose(offset: CGVector(dx: pull.dx / d * travel, dy: pull.dy / d * travel), scale: scale)
    }

    // MARK: Rendering

    private func render() {
        guard let layer = content.layer else { return }
        let c = CGPoint(x: glass.bounds.midX, y: glass.bounds.midY)

        // Silhouette: the resting capsule scaled about its centre and shifted, in the glass view's coordinates.
        let rest = CGRect(x: margin, y: margin, width: size.width, height: size.height)
        var map = CGAffineTransform(a: shape.scale.dx, b: 0, c: 0, d: shape.scale.dy,
                                    tx: c.x + shape.offset.dx - shape.scale.dx * c.x,
                                    ty: c.y + shape.offset.dy - shape.scale.dy * c.y)
        let capsule = CGPath(roundedRect: rest, cornerWidth: size.height / 2, cornerHeight: size.height / 2, transform: nil)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glass.setPrivatePath(capsule.copy(using: &map))
        glass.tintColor = pressLevel > 0.002 ? NSColor(white: 1, alpha: pressTintAlpha * pressLevel) : nil
        // the container only re-reads silhouettes during its layout pass
        glass.needsLayout = true
        var ancestor: NSView? = superview
        while let view = ancestor {
            view.needsLayout = true
            if view is NSGlassEffectContainerView { break }
            ancestor = view.superview
        }

        // Icons: same map with the icon motion; the content layer's anchor is its origin.
        let about = CGAffineTransform(a: icon.scale.dx, b: 0, c: 0, d: icon.scale.dy,
                                      tx: c.x + icon.offset.dx - icon.scale.dx * c.x,
                                      ty: c.y + icon.offset.dy - icon.scale.dy * c.y)
        let anchor = CGPoint(x: content.frame.minX + layer.anchorPoint.x * content.frame.width,
                             y: content.frame.minY + layer.anchorPoint.y * content.frame.height)
        let relative = CGAffineTransform(translationX: anchor.x, y: anchor.y)
            .concatenating(about)
            .concatenating(CGAffineTransform(translationX: -anchor.x, y: -anchor.y))
        layer.transform = CATransform3DMakeAffineTransform(relative)
        CATransaction.commit()
    }

    // MARK: Spring

    private func startSpring() {
        if link == nil {
            let created = displayLink(target: self, selector: #selector(tick(_:)))
            created.add(to: .main, forMode: .common)
            link = created
        }
        link?.isPaused = false
    }

    @objc private func tick(_ sender: CADisplayLink) {
        let frame = min(max(sender.targetTimestamp - sender.timestamp, 1.0 / 240), 1.0 / 30)
        let steps = 8                                      // stiff springs need small steps
        let dt = CGFloat(frame) / CGFloat(steps)
        let set = spring.set
        let glassSpring = dragging ? set.dragGlass : set.releaseGlass
        let iconSpring = dragging ? set.dragIcon : set.releaseIcon
        for _ in 0..<steps {
            shape.step(to: target, k: glassSpring.k, c: glassSpring.c, dt: dt)
            icon.step(to: target, k: iconSpring.k, c: iconSpring.c, dt: dt)
        }
        // colour follows the press smoothly: quick to lighten, a bit slower to fade back
        let tau: CGFloat = dragging ? 0.07 : 0.18
        pressLevel += ((dragging ? 1 : 0) - pressLevel) * (1 - exp(-CGFloat(frame) / tau))
        render()

        if !dragging && shape.isAtRest && icon.isAtRest && pressLevel < 0.002 {
            pressLevel = 0
            shape = Motion(); icon = Motion()
            render()
            link?.isPaused = true
        }
    }

    // MARK: Input

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        press()
    }

    public override func mouseDragged(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        pull(to: CGVector(dx: current.x - dragStart.x, dy: current.y - dragStart.y))
    }

    public override func mouseUp(with event: NSEvent) { release() }

    // MARK: Programmatic control (tests, screenshots, showreels)

    /// Same as pressing the button.
    public func press() {
        dragging = true
        setPull(.zero)                                   // swell right away, smoothly via the spring
        if liftsOnPress { glass.privateInteractionState = 1 }
        startSpring()
    }

    /// Same as moving the held cursor to `(dx, dy)` points from the press point (y up).
    public func pull(to vector: CGVector) {
        if !dragging { press() }
        setPull(vector)
        startSpring()
    }

    /// Same as letting go.
    public func release() {
        dragging = false
        if liftsOnPress { glass.privateInteractionState = 0 }
        target = Pose()
        startSpring()
    }
}
