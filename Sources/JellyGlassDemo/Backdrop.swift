import AppKit

/// `--still-backdrop` freezes the moving colour blobs (smaller GIFs when recording).
let backdropAnimates = !CommandLine.arguments.contains("--still-backdrop")

/// Colourful moving scene behind the glass so refraction, rim and blur are visible.
final class BackdropView: NSView {
    private let gradient = CAGradientLayer()
    private var blobs: [CAGradientLayer] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = true

        gradient.colors = [
            NSColor(srgbRed: 0.05, green: 0.06, blue: 0.20, alpha: 1).cgColor,
            NSColor(srgbRed: 0.28, green: 0.08, blue: 0.38, alpha: 1).cgColor,
            NSColor(srgbRed: 0.04, green: 0.22, blue: 0.34, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradient)

        let palette: [NSColor] = [
            NSColor(srgbRed: 1.00, green: 0.35, blue: 0.45, alpha: 1),
            NSColor(srgbRed: 0.20, green: 0.80, blue: 1.00, alpha: 1),
            NSColor(srgbRed: 1.00, green: 0.80, blue: 0.20, alpha: 1),
            NSColor(srgbRed: 0.55, green: 0.40, blue: 1.00, alpha: 1),
            NSColor(srgbRed: 0.20, green: 1.00, blue: 0.60, alpha: 1),
        ]
        for (index, color) in palette.enumerated() {
            let blob = CAGradientLayer()
            blob.type = .radial
            blob.colors = [color.withAlphaComponent(0.95).cgColor, color.withAlphaComponent(0).cgColor]
            blob.startPoint = CGPoint(x: 0.5, y: 0.5)
            blob.endPoint = CGPoint(x: 1, y: 1)
            blob.bounds = CGRect(x: 0, y: 0, width: 360, height: 360)
            blob.name = "blob\(index)"
            layer?.addSublayer(blob)
            blobs.append(blob)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        for (index, blob) in blobs.enumerated() {
            let t = CGFloat(index) / CGFloat(max(blobs.count - 1, 1))
            let from = CGPoint(x: bounds.width * (0.1 + 0.8 * t), y: bounds.height * (0.25 + 0.5 * sin(t * 5)))
            let to = CGPoint(x: bounds.width * (0.9 - 0.8 * t), y: bounds.height * (0.75 - 0.5 * cos(t * 4)))
            blob.position = from
            blob.removeAllAnimations()
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = from
            move.toValue = to
            move.duration = 9 + Double(index) * 2.3
            move.autoreverses = true
            move.repeatCount = .infinity
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if backdropAnimates { blob.add(move, forKey: "move") }
        }
        CATransaction.commit()
    }

    override func draw(_ dirtyRect: NSRect) {}
}

/// Thin stripes: straight lines make glass refraction obvious at the edges.
final class StripesView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.10).setFill()
        var y: CGFloat = 0
        while y < bounds.height {
            NSRect(x: 0, y: y, width: bounds.width, height: 2).fill()
            y += 22
        }
        var x: CGFloat = 0
        while x < bounds.width {
            NSRect(x: x, y: 0, width: 2, height: bounds.height).fill()
            x += 44
        }
    }
}
