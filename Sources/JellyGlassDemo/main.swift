import AppKit
import JellyGlass

// JellyGlassDemo – drag any button.
//   default  "on top": the pressed button is lifted and drawn over its neighbour
//   K        switch to "merge": the pressed button melts into its neighbour instead
//   S        spring  (jelly / wobble / snappy)
//   A        stretch (standard / wide / heavy)
//   C        glass style (clear / regular)
//
// Launch flags (tests, screenshots, recording):
//   --showreel                     play a scripted sequence of drags
//   --pull TARGET DX DY            hold a pull; TARGET = attach|pill|mic|pin|search
//   --ready-file PATH [--ready-after SECONDS]   write the window number there when the scene is ready
//   --stage-file PATH              write the rectangle around all buttons (screen points, top-left origin) as "x y w h"
//   --merge   --look system   --style regular   --spring N   --stretch N   --dump (print the glass layer tree)

final class RootView: NSView {
    let backdrop = BackdropView()
    let stripes = StripesView()
    let bar = InputBar(frame: NSRect(x: 0, y: 0, width: 440, height: 240), lift: true)
    let header = HeaderBar(frame: NSRect(x: 0, y: 0, width: 300, height: 200), lift: true)
    let cursor = CursorOverlay(frame: .zero)

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(backdrop)
        addSubview(stripes)
        addSubview(header)
        addSubview(bar)
        addSubview(cursor)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        stripes.frame = bounds
        cursor.frame = bounds
        // Everything the demo shows sits in one compact cluster: the header pair above the input row, right-aligned.
        let barCenterY = bounds.height * 0.42
        bar.frame.origin = CGPoint(x: bounds.midX - bar.frame.width / 2, y: barCenterY - bar.frame.height / 2)
        header.frame.origin = CGPoint(x: bar.frame.minX + bar.frame.width - header.frame.width,
                                      y: barCenterY + 150 - header.frame.height / 2)
    }

    var allButtons: [JellyGlassButton] { bar.buttons + header.buttons }

    private func cycle<T: CaseIterable & Equatable>(_ value: T) -> T {
        let all = Array(T.allCases)
        return all[((all.firstIndex(of: value) ?? -1) + 1) % all.count]
    }

    override func keyDown(with event: NSEvent) {
        guard let first = allButtons.first else { return }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "k":
            let lift = !first.liftsOnPress
            allButtons.forEach { $0.liftsOnPress = lift }
            window?.title = lift ? "on top" : "merge"
        case "s":
            let next = cycle(first.spring)
            allButtons.forEach { $0.spring = next }
            window?.title = "spring: \(next.rawValue)"
        case "a":
            let next = cycle(first.stretch)
            allButtons.forEach { $0.stretch = next }
            window?.title = "stretch: \(next.rawValue)"
        case "c":
            let style: NSGlassEffectView.Style = first.glass.style == .regular ? .clear : .regular
            allButtons.forEach { $0.glass.style = style }
            window?.title = style == .clear ? "clear" : "regular"
        default:
            super.keyDown(with: event)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var root: RootView!
    var showreel: Showreel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        func value(_ flag: String, at offset: Int = 1) -> String? {
            guard let index = args.firstIndex(of: flag), index + offset < args.count else { return nil }
            return args[index + offset]
        }

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.title = "on top"
        root = RootView(frame: window.contentLayoutRect)
        window.contentView = root
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(root)
        NSApp.activate(ignoringOtherApps: true)

        let bar = root.bar, header = root.header
        if args.contains("--merge") { root.allButtons.forEach { $0.liftsOnPress = false } }
        if value("--look") == "system" { root.allButtons.forEach { $0.look = .system } }
        if value("--style") == "regular" { root.allButtons.forEach { $0.glass.style = .regular } }
        else if value("--look") == "system" { root.allButtons.forEach { $0.glass.style = .clear } }
        if let n = value("--spring").flatMap({ Int($0) }) {
            root.allButtons.forEach { $0.spring = JellyGlassButton.Spring.allCases[n % JellyGlassButton.Spring.allCases.count] }
        }
        if let n = value("--stretch").flatMap({ Int($0) }) {
            root.allButtons.forEach { $0.stretch = JellyGlassButton.Stretch.allCases[n % JellyGlassButton.Stretch.allCases.count] }
        }

        if let path = value("--stage-file"), let screen = window.screen {
            root.layoutSubtreeIfNeeded()
            var union = CGRect.null
            for button in root.allButtons { union = union.union(button.convert(button.bounds, to: nil)) }
            // room around the buttons for the cursor to wander; stay inside the window
            let area = union.insetBy(dx: -150, dy: -120).intersection(root.convert(root.bounds, to: nil))
            let stage = window.convertToScreen(area)
            let y = screen.frame.maxY - stage.maxY
            try? "\(Int(stage.minX)) \(Int(y)) \(Int(stage.width)) \(Int(stage.height))\n".write(toFile: path, atomically: true, encoding: .utf8)
        }

        if args.contains("--showreel") {
            root.layoutSubtreeIfNeeded()
            func center(_ b: JellyGlassButton) -> CGPoint {
                root.convert(CGPoint(x: b.bounds.midX, y: b.bounds.midY), from: b)
            }
            func v(_ x: CGFloat, _ y: CGFloat) -> CGVector { CGVector(dx: x, dy: y) }
            let takes: [Showreel.Take] = [
                // slow S-curve to the left over the pill, then a lazy drift back
                .init(button: bar.mic, waypoints: [v(-45, 10), v(-120, -14), v(-185, 20), v(-135, 48), v(-60, 24)], duration: 2.6, swing: 0.5),
                // a quick flick up and a loop in the air, wandering over the header
                .init(button: bar.mic, waypoints: [v(10, 60), v(70, 150), v(130, 110), v(60, 55), v(-45, 125), v(-20, 60)], duration: 2.3, swing: 0.8),
                // short horizontal sweep over the search pill, back and forth
                .init(button: header.pin, waypoints: [v(60, 6), v(140, -8), v(90, 14), v(165, 4), v(70, -6)], duration: 2.1, swing: 0.7),
                // diagonal figure-of-eight below the search pill
                .init(button: header.pill, waypoints: [v(-50, -35), v(-110, -95), v(-30, -140), v(55, -85), v(105, -30), v(30, 10)], duration: 2.7, swing: 0.6),
                // long sweep right, across the whole input row
                .init(button: bar.attach, waypoints: [v(80, -22), v(180, 28), v(280, -6), v(210, 70), v(110, 38), v(30, -10)], duration: 2.6, swing: 0.6),
                // big loop around the pill, fast then slow
                .init(button: bar.pill, waypoints: [v(-110, 46), v(-175, -12), v(-95, -70), v(55, -42), v(150, 24), v(90, 82), v(-20, 38)], duration: 3.0, swing: 0.85),
                // quick horizontal shake on the mic, the way you rattle a slider
                .init(button: bar.mic, waypoints: [v(-80, 0), v(55, 6), v(-120, -4), v(40, 8), v(-60, 0), v(10, 0)], duration: 1.6, swing: 0.4),
            ]
            let reel = Showreel(takes: takes, overlay: root.cursor,
                                startAt: CGPoint(x: root.bounds.midX - 40, y: center(bar.mic).y - 150), anchorOf: center)
            showreel = reel
            reel.start()
            if let path = value("--duration-file") {
                try? "\(reel.duration + 0.6)\n".write(toFile: path, atomically: true, encoding: .utf8)
            }
        }

        if let target = value("--pull") {
            let dx = CGFloat(Double(value("--pull", at: 2) ?? "0") ?? 0)
            let dy = CGFloat(Double(value("--pull", at: 3) ?? "0") ?? 0)
            let button: JellyGlassButton
            switch target {
            case "attach": button = bar.attach
            case "pill": button = bar.pill
            case "pin": button = header.pin
            case "search": button = header.pill
            default: button = bar.mic
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { button.pull(to: CGVector(dx: dx, dy: dy)) }
            if args.contains("--release") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { button.release() }
            }
        }

        if args.contains("--dump") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [self] in
                LayerDump.run(window: window)
                exit(0)
            }
        }

        if let readyFile = value("--ready-file") {
            let wait = value("--ready-after").flatMap { Double($0) } ?? 2.6
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [self] in
                try? "\(window.windowNumber)\n".write(toFile: readyFile, atomically: true, encoding: .utf8)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
