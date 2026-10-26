import AppKit

// Private NSGlassEffectView selectors, resolved through the Objective-C runtime on macOS 26.
// The names and type encodings come from class_copyMethodList on a live system:
//   _setPath:           v24@0:8r^{CGPath=}16
//   set_interactionState: v24@0:8q16
// If a selector is missing (older or future AppKit) the call is skipped and the button degrades gracefully:
// no deformed silhouette / no "lift" – the icons still animate.

private func resolve<F>(_ object: NSObject, _ name: String, as type: F.Type) -> (F, Selector)? {
    let selector = NSSelectorFromString(name)
    guard object.responds(to: selector) else { return nil }
    return (unsafeBitCast(object.method(for: selector), to: F.self), selector)
}

extension NSGlassEffectView {
    /// Replaces the rounded-rect silhouette with an arbitrary path in the view's own coordinates.
    func setPrivatePath(_ path: CGPath?) {
        typealias Setter = @convention(c) (AnyObject, Selector, CGPath?) -> Void
        guard let (call, selector) = resolve(self, "_setPath:", as: Setter.self) else { return }
        call(self, selector, path)
    }

    /// 1 puts the glass in the "interacting" state: it is lifted out of its container group, drawn on top of
    /// its neighbours with a highlight, and does not melt into them until it is reset to 0.
    var privateInteractionState: Int {
        get {
            typealias Getter = @convention(c) (AnyObject, Selector) -> Int
            guard let (call, selector) = resolve(self, "_interactionState", as: Getter.self) else { return 0 }
            return call(self, selector)
        }
        set {
            typealias Setter = @convention(c) (AnyObject, Selector, Int) -> Void
            guard let (call, selector) = resolve(self, "set_interactionState:", as: Setter.self) else { return }
            call(self, selector, newValue)
        }
    }
}
