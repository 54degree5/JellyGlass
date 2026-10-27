import AppKit
import ObjectiveC

/// How the glass is rendered.
public enum GlassLook {
    /// AppKit's material as it ships: frosted, with a milky fill.
    case system
    /// Clear and refractive. The frosting and the milky fill are turned off, so whatever is behind the button stays
    /// sharp and visibly bends around its rim. Uses the private `glassBackground` backdrop filter; if it is missing
    /// the button falls back to `.system`.
    case transparent
}

/// Edits the inputs of the private `glassBackground` filter that AppKit puts on the glass backdrop layers.
/// Dumped on macOS 26: `inputBlurRadius`, `inputFaceOpacity`, `inputFaceColorMatrixFillColor`,
/// `inputRefractionOpacity`, `inputInnerRefractionAmount`, …
enum GlassTuner {
    private static let backdropClass: AnyClass? = NSClassFromString("CABackdropLayer")
    private static let sdfLayerClass: AnyClass? = NSClassFromString("CASDFLayer")
    private static let gradientEffectClass: AnyClass? = NSClassFromString("CASDFGradientEffect")

    /// Input name (without the `input` prefix) and the value that gives the clear look. The strength of the rim lens
    /// is left at AppKit's value: stronger makes the edge sample black outside the backdrop and flicker.
    private static let clear: [(String, Double)] = [
        ("RefractionOpacity", 1),
        ("BlurRadius", 0),
        ("FaceOpacity", 0.15),
    ]

    /// Returns `filters` with every `glassBackground` replaced by a clear copy, and whether anything changed.
    static func tuned(_ filters: [Any]) -> (filters: [Any], changed: Bool) {
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
        return (result, changed)
    }

    /// A backdrop layer class whose `setFilters:` always clears the glass filter on the way in. AppKit rewrites the
    /// filter every frame while the glass moves, after any layout hook has run, so patching afterwards leaves frames
    /// in which the milky filter reaches the screen. Patching the setter leaves none.
    private static let clearBackdropClass: AnyClass? = {
        guard let base = backdropClass else { return nil }
        let name = "JellyGlassClearBackdropLayer"
        if let existing = NSClassFromString(name) { return existing }
        guard let sub = objc_allocateClassPair(base, name, 0) else { return nil }
        let selector = NSSelectorFromString("setFilters:")
        typealias Setter = @convention(c) (AnyObject, Selector, NSArray?) -> Void
        let original = unsafeBitCast(class_getMethodImplementation(base, selector), to: Setter.self)
        let patched: @convention(block) (AnyObject, NSArray?) -> Void = { layer, filters in
            if let filters = filters as? [Any] {
                original(layer, selector, tuned(filters).filters as NSArray)
            } else {
                original(layer, selector, filters)
            }
        }
        class_addMethod(sub, selector, imp_implementationWithBlock(patched), "v@:@")
        objc_registerClassPair(sub)
        return sub
    }()

    /// The same trick for the white gradient body that the lifted (pressed) glass adds on top: AppKit sets its opacity
    /// back to 1 every frame, so the opacity setter caps it.
    private static let fadedBodyClass: AnyClass? = {
        guard let base = sdfLayerClass else { return nil }
        let name = "JellyGlassFadedBodyLayer"
        if let existing = NSClassFromString(name) { return existing }
        guard let sub = objc_allocateClassPair(base, name, 0) else { return nil }
        let selector = NSSelectorFromString("setOpacity:")
        typealias Setter = @convention(c) (AnyObject, Selector, Float) -> Void
        let original = unsafeBitCast(class_getMethodImplementation(base, selector), to: Setter.self)
        let patched: @convention(block) (AnyObject, Float) -> Void = { layer, value in
            original(layer, selector, min(value, GlassTuner.bodyOpacity))
        }
        class_addMethod(sub, selector, imp_implementationWithBlock(patched), "v@:f")
        objc_registerClassPair(sub)
        return sub
    }()

    static let bodyOpacity: Float = 0.2

    /// Applies the clear look to every glass backdrop under `root`. Cheap when nothing changed. Returns whether it changed anything.
    @discardableResult
    static func applyClear(under root: CALayer) -> Bool {
        guard let backdropClass else { return false }
        var changed = false
        var stack = [root]
        while let layer = stack.popLast() {
            if layer.isKind(of: backdropClass), let filters = layer.filters, !filters.isEmpty {
                if let patchedClass = clearBackdropClass, object_getClass(layer) != patchedClass {
                    object_setClass(layer, patchedClass)        // from now on every new filter is cleared as it is set
                    changed = true
                }
                // The backdrop is captured at half resolution over a rectangle that follows the whole group, so when one
                // button moves, the sampling grid shifts and every glass in the group shimmers. Full resolution calms it.
                if let scale = layer.value(forKey: "scale") as? Double, scale < 0.99 {
                    layer.setValue(1.0, forKey: "scale")
                    changed = true
                }
                // The lens at the rim samples a little outside the backdrop's rectangle, which ends exactly at the group's
                // outer edges; give it room so it does not read black there.
                for (key, target) in [("bleedAmount", 40.0), ("marginWidth", 40.0)] {
                    if let current = layer.value(forKey: key) as? Double, current < target - 0.5 {
                        layer.setValue(target, forKey: key)
                        changed = true
                    }
                }
                let result = tuned(filters)
                if result.changed { layer.filters = result.filters; changed = true }
            }
            // The lifted (pressed) glass adds a white gradient body on top; fade it so the glass stays clear.
            if let sdfLayerClass, let gradientEffectClass, let fadedBodyClass, layer.isKind(of: sdfLayerClass),
               object_getClass(layer) != fadedBodyClass,
               let effect = layer.value(forKey: "effect") as? NSObject, effect.isKind(of: gradientEffectClass) {
                object_setClass(layer, fadedBodyClass)
                layer.opacity = bodyOpacity
                changed = true
            }
            stack.append(contentsOf: layer.sublayers ?? [])
        }
        return changed
    }
}

/// AppKit builds new glass layers whenever it likes (on press, on layout). This finds them at the end of every run-loop
/// turn that did something, after AppKit is done and before the thread sleeps, so an idle app costs nothing.
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
