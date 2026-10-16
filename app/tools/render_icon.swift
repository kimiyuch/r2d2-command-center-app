// Renders the app icon (robot on a rounded tile) from the SVG: swift tools/render_icon.swift <svg> <out.png> <size>
// Source artwork: DreameMac/Assets.xcassets/Robot.imageset/robot.svg
import AppKit

let args = CommandLine.arguments
let svgURL = URL(filePath: args[1]), outURL = URL(filePath: args[2])
let size = CGFloat(Double(args[3])!)
guard let robot = NSImage(contentsOf: svgURL) else { fatalError("cannot load svg") }

let scale = size / 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.scaleBy(x: scale, y: scale)

// macOS icon grid: 824×824 tile centered in a 1024 canvas, ~185 corner radius, soft drop shadow.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
NSColor.white.setFill()
path.fill()
ctx.restoreGState()

ctx.saveGState()
path.addClip()
NSGradient(colors: [NSColor(srgbRed: 0.93, green: 0.97, blue: 0.96, alpha: 1),
                    NSColor(srgbRed: 0.56, green: 0.80, blue: 0.82, alpha: 1)])!.draw(in: tile, angle: -90)
// Robot, aspect-fit with some breathing room, slightly lowered so the floor shadow sits near the bottom.
let height: CGFloat = 700, width = height * robot.size.width / robot.size.height
robot.draw(in: NSRect(x: 512 - width / 2, y: 140, width: width, height: height))
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: outURL)
