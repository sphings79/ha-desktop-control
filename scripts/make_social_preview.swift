// Generates docs/social-preview.png (1280x640, GitHub social preview size):
// `swift scripts/make_social_preview.swift docs/social-preview.png docs/app-icon.png`
import AppKit

let width = 1280, height = 640
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("no context") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

let canvas = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.27, alpha: 1),
    NSColor(calibratedRed: 0.09, green: 0.36, blue: 0.55, alpha: 1)
])!.draw(in: canvas, angle: -25)

// Soft glow behind the icon
NSGradient(colors: [NSColor(calibratedRed: 0.35, green: 0.6, blue: 1, alpha: 0.35), .clear])!
    .draw(fromCenter: NSPoint(x: 330, y: 320), radius: 0, toCenter: NSPoint(x: 330, y: 320), radius: 330, options: [])

let args = CommandLine.arguments
if args.count > 2, let icon = NSImage(contentsOfFile: args[2]) {
    icon.draw(in: NSRect(x: 130, y: 130, width: 400, height: 400))
}

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, in rect: NSRect) {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 4
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        .paragraphStyle: style
    ]).draw(in: rect)
}

draw("HA Desktop\nControl", size: 88, weight: .bold, alpha: 1, in: NSRect(x: 590, y: 330, width: 640, height: 200))
draw("Pause video and minimize windows on your Mac when any Home Assistant sensor triggers.",
     size: 33, weight: .regular, alpha: 0.88, in: NSRect(x: 592, y: 160, width: 620, height: 130))
draw("macOS  ·  MQTT  ·  Home Assistant", size: 28, weight: .semibold, alpha: 0.7,
     in: NSRect(x: 592, y: 100, width: 640, height: 50))

NSGraphicsContext.restoreGraphicsState()
let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "social-preview.png")
try rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
