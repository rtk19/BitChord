import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let source = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let original = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("Cannot load upstream logo") }
// CoreGraphics supports RGBX drawing; a 24-bit NSGraphicsContext can be nil.
guard let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                              bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Cannot create icon canvas") }
context.setFillColor(CGColor(gray: 0.08, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.draw(original, in: CGRect(x: 80, y: 80, width: 864, height: 864))
guard let image = context.makeImage() else { fatalError("Cannot render app icon") }
let bitmap = NSBitmapImageRep(cgImage: image)
guard !bitmap.hasAlpha, let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("App icon must be opaque PNG") }
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
