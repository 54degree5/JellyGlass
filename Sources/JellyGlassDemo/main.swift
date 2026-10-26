import AppKit
import JellyGlass

// JellyGlassDemo – drag any button.
//   default  "on top": the pressed button is lifted and drawn over its neighbour
//   K        switch to "merge": the pressed button melts into its neighbour instead
//   S        spring  (jelly / wobble / snappy)
//   A        stretch (standard / wide / heavy)
//   C        glass style (regular / clear)
//
// Launch flags (tests, screenshots, recording):
//   --showreel                     play a scripted sequence of drags
//   --pull TARGET DX DY            hold a pull; TARGET = attach|pill|mic|pin|search
//   --ready-file PATH [--ready-after SECONDS]   write the window number there when the scene is ready
//   --stage-file PATH              write the rectangle around all buttons (screen points, top-left origin) as "x y w h"
//   --merge   --style clear   --spring N   --stretch N

final class RootView: NSView {
    let backdrop = BackdropView()
    let stripes = StripesView()
    let bar = InputBar(frame: NSRect(x: 0, y: 0, width: 440, height: 240), lift: true)
    let header = HeaderBar(frame: NSRect(x: 0, y: 0, width: 300, height: 200), lift: true)

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(backdrop)
        addSubview(stripes)
        addSubview(header)
        addSubview(bar)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        stripes.frame = bounds
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
        if value("--style") == "clear" { root.allButtons.forEach { $0.glass.style = .clear } }
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
            let stage = window.convertToScreen(union.insetBy(dx: -70, dy: -60))
            let y = screen.frame.maxY - stage.maxY
            try? "\(Int(stage.minX)) \(Int(y)) \(Int(stage.width)) \(Int(stage.height))\n".write(toFile: path, atomically: true, encoding: .utf8)
        }

        if args.contains("--showreel") {
            let reel = Showreel(gestures: [
                .init(button: bar.mic, vector: CGVector(dx: -150, dy: 0), ramp: 0.45, hold: 0.9),
                .init(button: bar.mic, vector: CGVector(dx: 0, dy: 170), ramp: 0.45, hold: 0.7),
                .init(button: header.pin, vector: CGVector(dx: 130, dy: 0), ramp: 0.45, hold: 0.8),
                .init(button: header.pill, vector: CGVector(dx: -120, dy: -80), ramp: 0.5, hold: 0.8),
                .init(button: bar.attach, vector: CGVector(dx: 90, dy: 100), ramp: 0.5, hold: 0.8),
                .init(button: bar.mic, vector: CGVector(dx: -320, dy: 40), ramp: 0.6, hold: 0.9),
            ])
            showreel = reel
            reel.start()
            if let path = value("--duration-file") {
                try? "\(reel.duration + 0.8)\n".write(toFile: path, atomically: true, encoding: .utf8)
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
