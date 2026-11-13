// Renders the app icon into NotchANC/Assets.xcassets/AppIcon.appiconset.
// Orange squircle, a black notch hanging from the top edge, white sound bars below it.
// Drawn from paths only: SF Symbols may not be used in app icons.
// Usage: swift tools/icon.swift
import AppKit

let set = "NotchANC/Assets.xcassets/AppIcon.appiconset"

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let k = CGFloat(px) / 1024
    let t = NSAffineTransform()
    t.scale(by: k)
    t.concat()

    // macOS icon grid: 824pt tile centred in 1024 with room for the drop shadow.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)
    NSGraphicsContext.saveGraphicsState()
    let drop = NSShadow()
    drop.shadowColor = NSColor.black.withAlphaComponent(0.3)
    drop.shadowOffset = NSSize(width: 0, height: -12)
    drop.shadowBlurRadius = 24
    drop.set()
    NSColor.black.setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 1.00, green: 0.42, blue: 0.00, alpha: 1),
               ending:   NSColor(calibratedRed: 1.00, green: 0.70, blue: 0.24, alpha: 1))!.draw(in: squircle, angle: 90)

    // The notch: flat top flush with the tile, rounded bottom corners, clipped to the squircle.
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    let notch = NSBezierPath(roundedRect: NSRect(x: 292, y: 744, width: 440, height: 260), xRadius: 64, yRadius: 64)
    NSColor.black.setFill()
    notch.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Sound bars, tallest in the middle.
    let heights: [CGFloat] = [150, 270, 380, 270, 150]
    let barW: CGFloat = 64, gap: CGFloat = 40
    let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
    let midY: CGFloat = 430
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor(calibratedRed: 0.55, green: 0.2, blue: 0, alpha: 0.35)
    glow.shadowOffset = NSSize(width: 0, height: -10)
    glow.shadowBlurRadius = 18
    glow.set()
    NSColor.white.setFill()
    for (i, h) in heights.enumerated() {
        let x = 512 - totalW / 2 + CGFloat(i) * (barW + gap)
        NSBezierPath(roundedRect: NSRect(x: x, y: midY - h / 2, width: barW, height: h),
                     xRadius: barW / 2, yRadius: barW / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [String] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try! render(pt * scale).write(to: URL(fileURLWithPath: "\(set)/\(name)"))
        images.append(#"{ "filename" : "\#(name)", "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(pt)x\#(pt)" }"#)
    }
}
let json = "{\n  \"images\" : [\n    \(images.joined(separator: ",\n    "))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try! json.write(toFile: "\(set)/Contents.json", atomically: true, encoding: .utf8)
