import AppKit
import ObjectiveC

/// Debug aid (`--dump`): prints the layer tree under the window's frame view with the private properties of the
/// glass layers, to find what makes system glass blurry or milky.
enum LayerDump {
    static func properties(of cls: AnyClass) -> [String] {
        var names: [String] = []
        var current: AnyClass? = cls
        while let c = current, c != NSObject.self, c != CALayer.self {
            var count: UInt32 = 0
            if let list = class_copyPropertyList(c, &count) {
                for i in 0..<Int(count) { names.append(String(cString: property_getName(list[i]))) }
                free(list)
            }
            current = class_getSuperclass(c)
        }
        return names
    }

    static func describe(_ value: Any?) -> String {
        guard let value else { return "nil" }
        if let array = value as? [Any] { return "[" + array.map { describe($0) }.joined(separator: ", ") + "]" }
        if let filter = value as? NSObject, filter.responds(to: NSSelectorFromString("inputKeys")),
           let keys = filter.value(forKey: "inputKeys") as? [String] {
            let pairs = keys.map { "\($0)=\(String(describing: filter.value(forKey: $0) ?? "nil"))" }
            return "\(filter.value(forKey: "name") ?? "?"){\(pairs.joined(separator: " "))}"
        }
        return String(describing: value).replacingOccurrences(of: "\n", with: " ").prefix(160).description
    }

    static func dump(_ layer: CALayer, depth: Int = 0, into out: inout [String], seen: inout Set<String>) {
        let pad = String(repeating: "  ", count: depth)
        let name = String(describing: type(of: layer))
        var line = "\(pad)\(name) frame=\(layer.frame) opacity=\(layer.opacity)"
        if let f = layer.filters, !f.isEmpty { line += " filters=\(describe(f))" }
        if let f = layer.backgroundFilters, !f.isEmpty { line += " bgFilters=\(describe(f))" }
        if let f = layer.compositingFilter { line += " comp=\(describe(f))" }
        out.append(line)
        if name.hasPrefix("CASDF") || name.contains("Backdrop") || name.contains("Portal") {
            let props = properties(of: type(of: layer))
            var shown: [String] = []
            for p in props where layer.responds(to: Selector(p)) {
                shown.append("\(p)=\(describe(layer.value(forKey: p)))")
            }
            if !shown.isEmpty { out.append("\(pad)  · " + shown.joined(separator: "  ")) }
            if let effect = layer.value(forKey: "effect") as? NSObject, name.hasPrefix("CASDF") {
                let en = String(describing: type(of: effect))
                var eshown: [String] = []
                for p in properties(of: type(of: effect)) where effect.responds(to: Selector(p)) {
                    eshown.append("\(p)=\(describe(effect.value(forKey: p)))")
                }
                out.append("\(pad)  · effect \(en): " + eshown.joined(separator: "  "))
                seen.insert(en)
            }
        }
        for sub in layer.sublayers ?? [] { dump(sub, depth: depth + 1, into: &out, seen: &seen) }
    }

    static func run(window: NSWindow) {
        var out: [String] = [], seen = Set<String>()
        if let root = window.contentView?.superview?.layer { dump(root, into: &out, seen: &seen) }
        print(out.joined(separator: "\n"))
    }
}
