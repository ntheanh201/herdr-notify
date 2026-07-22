import AppKit
import Foundation

// Renders an emoji into a macOS .iconset directory.
// usage: makeicon <emoji> <output-iconset-dir>

let emoji = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "🐑"
let outDir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "./AppIcon.iconset"

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// (pixel size, filename) — macOS wants both 1x and 2x for each logical size.
let variants: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

for (px, name) in variants {
    let size = NSSize(width: px, height: px)
    let image = NSImage(size: size)
    image.lockFocus()

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()

    // Inset slightly so the glyph doesn't touch the icon edges.
    let fontSize = CGFloat(px) * 0.82
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize)
    ]
    let str = NSAttributedString(string: emoji, attributes: attrs)
    let bounds = str.size()
    let origin = NSPoint(
        x: (CGFloat(px) - bounds.width) / 2,
        y: (CGFloat(px) - bounds.height) / 2
    )
    str.draw(at: origin)

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("failed to render \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

print("wrote \(variants.count) sizes to \(outDir)")
