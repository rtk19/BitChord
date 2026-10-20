import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let source = NSImage(contentsOfFile: CommandLine.arguments[1]) else { exit(1) }
let size = NSSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                                   bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
source.draw(in: NSRect(x: 80, y: 80, width: 864, height: 864))
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
