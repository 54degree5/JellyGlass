import AppKit

/// How the glass is rendered.
public enum GlassLook {
    /// AppKit's material as it ships: frosted, with a milky fill.
    case system
    /// Clear and refractive. The frosting and the milky fill are turned off and the lens at the edge is stronger, so
    /// whatever is behind the button stays sharp and visibly bends around its rim. Uses the private `glassBackground`
    /// backdrop filter; if it is missing the button falls back to `.system`.
    case transparent
}

/// Edits the inputs of the private `glassBackground` filter that AppKit puts on the glass backdrop layers.
/// Dumped on macOS 26: `inputBlurRadius`, `inputFaceOpacity`, `inputFaceColorMatrixFillColor`,
/// `inputRefractionOpacity`, `inputInnerRefractionAmount`, `inputInnerRefractionHeight`, …
enum GlassTuner {
    private static let backdropClass: AnyClass? = NSClassFromString("CABackdropLayer")
    private static let sdfLayerClass: AnyClass? = NSClassFromString("CASDFLayer")
    private static let gradientEffectClass: AnyClass? = NSClassFromString("CASDFGradientEffect")

    /// Input name (without the `input` prefix) and the value that gives the clear look.
    private static let clear: [(String, Double)] = [
        ("RefractionOpacity", 1),
        ("BlurRadius", 0),
        ("FaceOpacity", 0.15),
        ("InnerRefractionAmount", -70),
        ("InnerRefractionHeight", 20),
    ]

    /// Applies the clear look to every glass backdrop under `root`. Cheap when nothing changed. Returns whether it changed anything.
    @discardableResult
    static func applyClear(under root: CALayer) -> Bool {
        guard let backdropClass else { return false }
        var changed = false
        var stack = [root]
        while let layer = stack.popLast() {
            if layer.isKind(of: backdropClass), let filters = layer.filters, !filters.isEmpty {
                if retune(layer, filters) { changed = true }
            }
            // The lifted (pressed) glass adds a white gradient body on top; fade it so the glass stays clear.
            if let sdfLayerClass, let gradientEffectClass, layer.isKind(of: sdfLayerClass), layer.opacity > 0.25,
               let effect = layer.value(forKey: "effect") as? NSObject, effect.isKind(of: gradientEffectClass) {
                layer.opacity = 0.2
                changed = true
            }
            stack.append(contentsOf: layer.sublayers ?? [])
        }
        return changed
    }

    private static func retune(_ layer: CALayer, _ filters: [Any]) -> Bool {
        var changed = false
        var result: [Any] = []
        for item in filters {
            guard let filter = item as? NSObject, filter.value(forKey: "name") as? String == "glassBackground",
                  let keys = filter.value(forKey: "inputKeys") as? [String] else { result.append(item); continue }
            let known = Set(keys)
            let stale = clear.contains { name, value in
                known.contains("input" + name) && abs(((filter.value(forKey: "input" + name) as? NSNumber)?.doubleValue ?? value) - value) > 0.001
            }
            guard stale, let copy = filter.copy() as? NSObject else { result.append(item); continue }
            for (name, value) in clear where known.contains("input" + name) {
                copy.setValue(NSNumber(value: value), forKey: "input" + name)
            }
            if known.contains("inputFaceColorMatrixFillColor") {
                copy.setValue(CGColor(gray: 1, alpha: 0), forKey: "inputFaceColorMatrixFillColor")
            }
            result.append(copy)
            changed = true
        }
        // A new filter object, not an edited one: only then does the render server pick the change up.
        if changed { layer.filters = result }
        return changed
    }
}

/// AppKit rebuilds the glass layers whenever it likes (on press, on release, on layout), which puts the milky filter
/// back. This puts the clear one back at the end of every run-loop turn that did something, after AppKit is done and
/// before the thread sleeps, so an idle app costs nothing.
final class GlassLookKeeper {
    static let shared = GlassLookKeeper()
    private let buttons = NSHashTable<JellyGlassButton>.weakObjects()
    private var observer: CFRunLoopObserver?

    func add(_ button: JellyGlassButton) {
        buttons.add(button)
        guard observer == nil else { return }
        let created = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, true, Int.max) { [weak self] _, _ in
            self?.sweep()
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), created, .commonModes)
        observer = created
    }

    private func sweep() {
        var seen = Set<ObjectIdentifier>()
        var changed = false
        for button in buttons.allObjects where button.window != nil && button.look == .transparent {
            if button.applyLook(seen: &seen) { changed = true }
        }
        if changed { CATransaction.flush() }
    }
}
