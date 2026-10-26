import AppKit
import JellyGlass

/// A chat-style input row: attach circle, a pill with two icons, mic circle – all in one
/// NSGlassEffectContainerView, which is what lets neighbouring glass melt together in "merge" mode.
final class InputBar: NSGlassEffectContainerView {
    let holder = NSView()
    let attach = JellyGlassButton(size: CGSize(width: 42, height: 42), symbols: ["paperclip"])
    let pill = JellyGlassButton(size: CGSize(width: 104, height: 42), symbols: ["gift", "face.smiling"])
    let mic = JellyGlassButton(size: CGSize(width: 42, height: 42), symbols: ["mic"])

    var buttons: [JellyGlassButton] { [attach, pill, mic] }

    init(frame: NSRect, lift: Bool) {
        super.init(frame: frame)
        buttons.forEach { $0.liftsOnPress = lift }
        spacing = 14
        holder.frame = bounds
        holder.autoresizingMask = [.width, .height]
        contentView = holder
        buttons.forEach(holder.addSubview)
        let y = (bounds.height - 42) / 2
        attach.frame.origin = CGPoint(x: 40, y: y)
        pill.frame.origin = CGPoint(x: bounds.width - 40 - 42 - 14 - 104, y: y)
        mic.frame.origin = CGPoint(x: bounds.width - 40 - 42, y: y)
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// A header pair: a search pill with three dots, and a pin circle.
final class HeaderBar: NSGlassEffectContainerView {
    let holder = NSView()
    let pin = JellyGlassButton(size: CGSize(width: 42, height: 42), symbols: ["pin"])
    let pill = JellyGlassButton(size: CGSize(width: 96, height: 42), symbols: ["magnifyingglass", "ellipsis"])

    var buttons: [JellyGlassButton] { [pin, pill] }

    init(frame: NSRect, lift: Bool) {
        super.init(frame: frame)
        buttons.forEach { $0.liftsOnPress = lift }
        spacing = 14
        holder.frame = bounds
        holder.autoresizingMask = [.width, .height]
        contentView = holder
        buttons.forEach(holder.addSubview)
        let y = (bounds.height - 42) / 2
        pill.frame.origin = CGPoint(x: bounds.width - 40 - 96, y: y)
        pin.frame.origin = CGPoint(x: pill.frame.minX - 14 - 42, y: y)
    }

    required init?(coder: NSCoder) { fatalError() }
}
