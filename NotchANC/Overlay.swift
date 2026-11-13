// Menu-bar-height pill for AirPods Active Noise Cancellation, one per selected display.
// Layout (left to right):
//   [AirPods icon] [ ---- camera cutout ---- ] [ scrolling message ][waveform]

import Cocoa

let palette: [(name: String, color: NSColor)] = [
    ("Orange", .systemOrange),
    ("Green",  .systemGreen),
    ("Blue",   .systemBlue),
    ("Purple", .systemPurple),
    ("Pink",   .systemPink),
]

// Where the pill goes on one screen. macOS reports a notch and a Dynamic Island the same way:
// a top safe-area inset plus the unobscured areas left and right of the camera.
struct PillLayout: Equatable {
    let frame: NSRect       // window frame, screen coordinates
    let leftWing: CGFloat
    let middle: CGFloat     // the cutout's width, or the free space between the icons
    let hasCutout: Bool

    init(screen: NSRect, topInset: CGFloat, leftAux: NSRect, rightAux: NSRect, barHeight: CGFloat) {
        hasCutout = topInset > 0 && !leftAux.isEmpty && !rightAux.isEmpty
        let height = hasCutout ? topInset : barHeight
        let minX: CGFloat
        if hasCutout {
            // Widths, not midX: correct for any cutout size or position.
            leftWing = 52
            middle = screen.width - leftAux.width - rightAux.width
            minX = screen.minX + leftAux.width - leftWing
        } else {
            leftWing = 48
            middle = 290
            minX = screen.midX - middle / 2 - leftWing
        }
        let rightWing: CGFloat = hasCutout ? 168 : 48
        frame = NSRect(x: minX, y: screen.maxY - height, width: leftWing + middle + rightWing, height: height)
    }

    // ponytail: guesses by width since no API names the cutout; Island Macs ship narrower than every notch (~180pt+).
    var cutoutName: String? { hasCutout ? (middle < 150 ? "Dynamic Island" : "notch") : nil }
}

extension NSScreen {
    var pillLayout: PillLayout {
        PillLayout(screen: frame, topInset: safeAreaInsets.top,
                   leftAux: auxiliaryTopLeftArea ?? .zero, rightAux: auxiliaryTopRightArea ?? .zero,
                   barHeight: NSStatusBar.system.thickness)
    }

    // Stable across reboots and reconnects, unlike the display ID.
    var uuid: String {
        let id = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        guard let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "\(id)" }
        return CFUUIDCreateString(nil, u) as String
    }
}

final class NotchOverlay {
    private var windows: [NSWindow] = []
    private var visible = false
    var color: NSColor = .systemOrange
    var hiddenDisplays: Set<String> = []

    func setVisible(_ on: Bool) {
        visible = on
        on ? show(animated: true) : hide()
    }

    func refresh() { if visible { show(animated: false) } }

    private func hide() {
        let old = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            old.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { old.forEach { $0.orderOut(nil) } })
    }

    private func show(animated: Bool) {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.filter { !hiddenDisplays.contains($0.uuid) }.map(makeWindow)
        for w in windows {
            w.alphaValue = animated ? 0 : 1
            w.orderFrontRegardless()
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                windows.forEach { $0.animator().alphaValue = 1 }
            }
        }
    }

    private func makeWindow(on screen: NSScreen) -> NSWindow {
        let layout = screen.pillLayout
        let frame = layout.frame
        let height = frame.height
        let total = frame.width
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .statusBar
        // Without .fullScreenAuxiliary macOS keeps the window out of full-screen spaces. Only cutout
        // screens keep a black band beside the camera in full screen, so only they keep the pill.
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if layout.hasCutout { w.collectionBehavior.insert(.fullScreenAuxiliary) }

        // Black pill flush with the cutout, bottom corners rounded.
        let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
        root.wantsLayer = true
        let layer = root.layer!
        layer.backgroundColor = NSColor.black.cgColor
        layer.cornerRadius = 11
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.masksToBounds = true

        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let iconH: CGFloat = 18
        let iconY = (height - iconH) / 2

        // Left wing: AirPods icon.
        let pods = NSImageView(frame: NSRect(x: 16, y: iconY, width: 20, height: iconH))
        pods.image = NSImage(systemSymbolName: "airpodspro", accessibilityDescription: "AirPods")?
            .withSymbolConfiguration(cfg)
        pods.contentTintColor = color
        pods.imageScaling = .scaleProportionallyUpOrDown
        root.addSubview(pods)

        // Far right: animated waveform.
        let wave = NSImageView(frame: NSRect(x: total - 16 - 20, y: iconY, width: 20, height: iconH))
        wave.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Broadcasting")?
            .withSymbolConfiguration(cfg)
        wave.contentTintColor = color
        wave.imageScaling = .scaleProportionallyUpOrDown
        root.addSubview(wave)
        if !reduceMotion {
            wave.addSymbolEffect(.variableColor.iterative.reversing, options: .repeating)
        }

        // Marquee: right wing beside a cutout, the whole middle otherwise.
        let clipX = layout.hasCutout ? layout.leftWing + layout.middle + 10 : layout.leftWing
        let clip = NSView(frame: NSRect(x: clipX, y: 0, width: (total - 48) - clipX, height: height))
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        let fade = CAGradientLayer()
        fade.frame = clip.bounds
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, 0.12, 0.88, 1]
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        clip.layer?.mask = fade

        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let message = reduceMotion ? "ANC ON" : "NOISE CANCELLATION ON"
        let text = NSAttributedString(string: message, attributes: [
            .font: font, .foregroundColor: color, .kern: 0.8])
        let tw = ceil(text.size().width)
        let gap: CGFloat = 30
        let copies = reduceMotion ? 1 : Int(ceil(clip.bounds.width / (tw + gap))) + 1
        let strip = CALayer()
        strip.frame = CGRect(x: reduceMotion ? (clip.bounds.width - tw) / 2 : 0, y: 0,
                             width: (tw + gap) * CGFloat(copies), height: height)
        for i in 0..<copies {
            let t = CATextLayer()
            t.string = text
            t.contentsScale = screen.backingScaleFactor
            t.frame = CGRect(x: (tw + gap) * CGFloat(i), y: (height - 14) / 2,
                             width: tw + 2, height: 14)
            strip.addSublayer(t)
            if !reduceMotion {   // separator dot in the gap between repeats
                let d = CALayer()
                d.backgroundColor = color.cgColor
                d.cornerRadius = 2
                d.frame = CGRect(x: (tw + gap) * CGFloat(i) + tw + gap / 2 - 2,
                                 y: (height - 5) / 2, width: 4, height: 4)
                strip.addSublayer(d)
            }
        }
        clip.layer?.addSublayer(strip)
        if !reduceMotion {
            let scroll = CABasicAnimation(keyPath: "transform.translation.x")
            scroll.fromValue = 0
            scroll.toValue = -(tw + gap)
            scroll.duration = Double(tw + gap) / 32.0
            scroll.repeatCount = .infinity
            scroll.timingFunction = CAMediaTimingFunction(name: .linear)
            strip.add(scroll, forKey: "marquee")
        }
        root.addSubview(clip)

        w.contentView = root
        return w
    }
}
