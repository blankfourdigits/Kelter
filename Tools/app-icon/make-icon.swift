// Draws Kelter's app icon: a minimal wine press ("Kelter") on a deep
// wine-red tile. Writes Resources/AppIcon.icns (bundled by make-app.sh) and
// Tools/app-icon/AppIcon-preview.png.
//
// Usage: swift Tools/app-icon/make-icon.swift [output directory]
// Needs only macOS (AppKit, sips, iconutil).
import AppKit

let size: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func draw(in context: CGContext) {
    // macOS icon grid: 824 x 824 tile in a 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = roundedRect(tile, 185)

    // Shadow under the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    context.addPath(tilePath)
    context.setFillColor(color(0x3A0D27))
    context.fillPath()
    context.restoreGState()

    // Wine-red gradient.
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0x7A1E3C), color(0x4A1036), color(0x2A0A26)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Soft light from the top.
    let glow = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 900), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 900), endRadius: 620, options: [])
    context.restoreGState()

    let cream = color(0xF4E7D1)
    let gap = color(0x4A1036)

    // A minimal wine press: frame, screw with handle, basket, base.
    // Base, wider than the frame.
    context.setFillColor(cream)
    context.addPath(roundedRect(CGRect(x: 222, y: 250, width: 580, height: 50), 25))
    context.fillPath()

    // Basket: one block with four vertical gaps (the staves).
    let basket = CGRect(x: 360, y: 300, width: 304, height: 220)
    context.addPath(roundedRect(basket, 16))
    context.fillPath()
    context.setFillColor(gap)
    for index in 1...4 {
        let x = basket.minX + basket.width * CGFloat(index) / 5 - 6
        context.fill(CGRect(x: x, y: basket.minY + 22, width: 12, height: basket.height - 44))
    }

    // Press plate.
    context.setFillColor(cream)
    context.addPath(roundedRect(CGRect(x: 346, y: 540, width: 332, height: 34), 17))
    context.fillPath()

    // Frame: two posts on the base and an overhanging beam.
    for x: CGFloat in [282, 694] {
        context.addPath(roundedRect(CGRect(x: x, y: 290, width: 48, height: 450), 0))
        context.fillPath()
    }
    context.addPath(roundedRect(CGRect(x: 242, y: 712, width: 540, height: 58), 29))
    context.fillPath()

    // Screw between plate and beam, and its handle above the beam.
    context.fill(CGRect(x: 490, y: 574, width: 44, height: 140))
    context.fill(CGRect(x: 490, y: 768, width: 44, height: 40))
    context.addPath(roundedRect(CGRect(x: 412, y: 800, width: 200, height: 34), 17))
    context.fillPath()
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/Resources")

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
draw(in: NSGraphicsContext.current!.cgContext)
NSGraphicsContext.restoreGraphicsState()

let work = FileManager.default.temporaryDirectory.appendingPathComponent("kelter-icon-\(UUID().uuidString)")
let iconset = work.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = work.appendingPathComponent("icon_1024.png")
try bitmap.representation(using: .png, properties: [:])!.write(to: master)

func run(_ tool: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "make-icon", code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "\(tool) failed"])
    }
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try run("/usr/bin/sips", ["-z", "\(pixels)", "\(pixels)", master.path,
                                  "--out", iconset.appendingPathComponent(name).path])
    }
}
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
try run("/usr/bin/iconutil", ["-c", "icns", iconset.path,
                              "-o", outputDirectory.appendingPathComponent("AppIcon.icns").path])
let preview = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("AppIcon-preview.png")
try? FileManager.default.removeItem(at: preview)
try FileManager.default.copyItem(at: master, to: preview)
try? FileManager.default.removeItem(at: work)
print("Fertig: \(outputDirectory.appendingPathComponent("AppIcon.icns").path)")
