import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct Palette {
    let body: NSColor
    let cutout: NSColor
    let backgroundTop: NSColor
    let backgroundBottom: NSColor
}

private let defaultPalette = Palette(
    body: NSColor(calibratedRed: 0.137, green: 0.165, blue: 0.196, alpha: 1.0),
    cutout: NSColor(calibratedRed: 0.933, green: 0.953, blue: 0.973, alpha: 1.0),
    backgroundTop: NSColor(calibratedRed: 0.965, green: 0.970, blue: 0.980, alpha: 1.0),
    backgroundBottom: NSColor(calibratedRed: 0.885, green: 0.895, blue: 0.910, alpha: 1.0)
)

private let darkPalette = Palette(
    body: NSColor(calibratedRed: 0.933, green: 0.953, blue: 0.973, alpha: 1.0),
    cutout: NSColor(calibratedRed: 0.137, green: 0.165, blue: 0.196, alpha: 1.0),
    backgroundTop: NSColor(calibratedRed: 0.185, green: 0.185, blue: 0.185, alpha: 1.0),
    backgroundBottom: NSColor(calibratedRed: 0.050, green: 0.054, blue: 0.060, alpha: 1.0)
)

private let monoPalette = Palette(
    body: NSColor(calibratedWhite: 0.96, alpha: 1.0),
    cutout: NSColor(calibratedWhite: 0.12, alpha: 1.0),
    backgroundTop: NSColor(calibratedWhite: 0.92, alpha: 1.0),
    backgroundBottom: NSColor(calibratedWhite: 0.72, alpha: 1.0)
)

private let size = 1024
private let bodyRect = CGRect(x: 218, y: 338, width: 588, height: 348)
private let keyCenters: [CGPoint] = [
    CGPoint(x: 356, y: 456),
    CGPoint(x: 434, y: 456),
    CGPoint(x: 512, y: 456),
    CGPoint(x: 590, y: 456),
    CGPoint(x: 668, y: 456),
    CGPoint(x: 356, y: 532),
    CGPoint(x: 434, y: 532),
    CGPoint(x: 512, y: 532),
    CGPoint(x: 590, y: 532),
    CGPoint(x: 668, y: 532),
]
private let spaceBarRect = CGRect(x: 362, y: 598, width: 300, height: 43)

private func context() -> CGContext {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        fatalError("Unable to create bitmap context.")
    }
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    return context
}

private func flip(_ context: CGContext) {
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: 1, y: -1)
}

private func fillRoundedRect(_ rect: CGRect, radius: CGFloat, color: NSColor, in context: CGContext) {
    context.setFillColor(color.cgColor)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}

private func drawSymbol(palette: Palette, in context: CGContext) {
    fillRoundedRect(bodyRect, radius: 82, color: palette.body, in: context)
    context.setFillColor(palette.cutout.cgColor)
    for center in keyCenters {
        context.fillEllipse(in: CGRect(x: center.x - 25, y: center.y - 25, width: 50, height: 50))
    }
    fillRoundedRect(spaceBarRect, radius: spaceBarRect.height / 2, color: palette.cutout, in: context)
}

private func drawLayer(palette: Palette, output: URL) throws {
    let context = context()
    flip(context)
    drawSymbol(palette: palette, in: context)
    try writePNG(context: context, output: output)
}

private func drawPreview(palette: Palette, output: URL) throws {
    let context = context()
    flip(context)

    let iconRect = CGRect(x: 0, y: 0, width: size, height: size)
    context.saveGState()
    context.addPath(CGPath(roundedRect: iconRect, cornerWidth: 220, cornerHeight: 220, transform: nil))
    context.clip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [palette.backgroundTop.cgColor, palette.backgroundBottom.cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 0, y: CGFloat(size)),
        options: []
    )

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: 18),
        blur: 24,
        color: NSColor(calibratedWhite: 0.0, alpha: 0.24).cgColor
    )
    fillRoundedRect(bodyRect, radius: 82, color: palette.body, in: context)
    context.restoreGState()

    drawSymbol(palette: palette, in: context)

    context.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.28).cgColor)
    context.setLineWidth(3)
    context.addPath(
        CGPath(
            roundedRect: iconRect.insetBy(dx: 6, dy: 6),
            cornerWidth: 214,
            cornerHeight: 214,
            transform: nil
        )
    )
    context.strokePath()
    context.restoreGState()

    try writePNG(context: context, output: output)
}

private func writePNG(context: CGContext, output: URL) throws {
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
              output as CFURL,
              UTType.png.identifier as CFString,
              1,
              nil
          )
    else {
        fatalError("Unable to create PNG destination.")
    }
    CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyPNGDictionary: [
            kCGImagePropertyPNGInterlaceType: 0,
        ],
    ] as CFDictionary)
    if !CGImageDestinationFinalize(destination) {
        fatalError("Unable to write \(output.path).")
    }
}

private func ensureDirectory(_ path: String) throws -> URL {
    let url = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let iconAssets = try ensureDirectory(root.appendingPathComponent("TypeSwitch/Resources/AppIcon.icon/Assets").path)
let previews = try ensureDirectory(root.appendingPathComponent("Design/AppIcon/Previews").path)

try drawLayer(palette: defaultPalette, output: iconAssets.appendingPathComponent("keyboard-layer.png"))
try drawLayer(palette: darkPalette, output: iconAssets.appendingPathComponent("keyboard-layer-dark.png"))
try drawLayer(palette: monoPalette, output: iconAssets.appendingPathComponent("keyboard-layer-mono.png"))

try drawPreview(palette: defaultPalette, output: previews.appendingPathComponent("typeswitch-icon-default.png"))
try drawPreview(palette: darkPalette, output: previews.appendingPathComponent("typeswitch-icon-dark.png"))
try drawPreview(palette: monoPalette, output: previews.appendingPathComponent("typeswitch-icon-mono.png"))
