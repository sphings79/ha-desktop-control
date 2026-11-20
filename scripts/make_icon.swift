// Generates Resources/AppIcon.icns: `swift scripts/make_icon.swift`
import AppKit

let px = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("no context") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

let canvas = NSRect(x: 0, y: 0, width: px, height: px)
let body = canvas.insetBy(dx: 100, dy: 100)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 190, yRadius: 190)

// Shadow + gradient body
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.shadowBlurRadius = 28
shadow.set()
NSColor.black.setFill()
bodyPath.fill()
NSGraphicsContext.restoreGraphicsState()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.86, alpha: 1),
    NSColor(calibratedRed: 0.12, green: 0.62, blue: 0.86, alpha: 1)
])!
gradient.draw(in: bodyPath, angle: -50)

// Soft highlight on the upper half
NSGraphicsContext.saveGraphicsState()
bodyPath.addClip()
let highlight = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
highlight.draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
NSGraphicsContext.restoreGraphicsState()

// White window glyph
let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .regular)
if let symbol = NSImage(systemSymbolName: "window.vertical.open", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceIn)
        return true
    }
    let target = NSRect(
        x: body.midX - tinted.size.width / 2 - 28,
        y: body.midY - tinted.size.height / 2 + 24,
        width: tinted.size.width, height: tinted.size.height)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    glow.shadowOffset = NSSize(width: 0, height: -8)
    glow.shadowBlurRadius = 16
    glow.set()
    tinted.draw(in: target)
    NSGraphicsContext.restoreGraphicsState()
}

// Orange pause badge
let badgeCenter = NSPoint(x: body.maxX - 150, y: body.minY + 150)
let radius: CGFloat = 138
let badge = NSBezierPath(ovalIn: NSRect(
    x: badgeCenter.x - radius, y: badgeCenter.y - radius, width: radius * 2, height: radius * 2))
NSGraphicsContext.saveGraphicsState()
let badgeShadow = NSShadow()
badgeShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
badgeShadow.shadowOffset = NSSize(width: 0, height: -8)
badgeShadow.shadowBlurRadius = 18
badgeShadow.set()
NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.12, alpha: 1).setFill()
badge.fill()
NSGraphicsContext.restoreGraphicsState()
NSColor.white.withAlphaComponent(0.9).setStroke()
badge.lineWidth = 12
badge.stroke()

NSColor.white.setFill()
for dx in [-34.0, 34.0] {
    NSBezierPath(roundedRect: NSRect(x: badgeCenter.x + dx - 20, y: badgeCenter.y - 56, width: 40, height: 112),
                 xRadius: 12, yRadius: 12).fill()
}

NSGraphicsContext.restoreGraphicsState()
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png")
try rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
