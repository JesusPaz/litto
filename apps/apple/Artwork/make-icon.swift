// Litto icon in the AFK family: deep ink blue full-bleed, chunky ivory cards with a charcoal
// base, one warm orange accent. Opaque square; the system applies its own mask.
// Usage: swift Artwork/make-icon.swift Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    func rgb(_ hex: UInt32) -> CGColor {
        CGColor(red: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    ctx.setFillColor(rgb(0x0B2A8C))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

    func card(center: CGPoint, angle: CGFloat, face: CGColor, lines: Bool) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)
        let w = s * 0.46, h = s * 0.56, r = s * 0.05, depth = s * 0.035
        // charcoal base gives the chunky, tactile edge
        ctx.setFillColor(rgb(0x2B2D31))
        ctx.addPath(CGPath(roundedRect: CGRect(x: -w / 2, y: -h / 2 - depth, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(face)
        ctx.addPath(CGPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.fillPath()
        if lines {
            ctx.setFillColor(rgb(0x2B2D31))
            let lw = s * 0.03
            ctx.addPath(CGPath(roundedRect: CGRect(x: -w * 0.32, y: h * 0.08, width: w * 0.64, height: lw * 1.6), cornerWidth: lw * 0.8, cornerHeight: lw * 0.8, transform: nil))
            ctx.fillPath()
            ctx.setFillColor(rgb(0xB9B2A3))
            for (i, width) in [0.5, 0.36].enumerated() {
                ctx.addPath(CGPath(roundedRect: CGRect(x: -w * 0.32, y: -h * 0.1 - CGFloat(i) * lw * 2.2, width: w * width, height: lw), cornerWidth: lw / 2, cornerHeight: lw / 2, transform: nil))
                ctx.fillPath()
            }
            // orange tab: the one warm accent
            ctx.setFillColor(rgb(0xF26B1D))
            ctx.addPath(CGPath(roundedRect: CGRect(x: w * 0.12, y: -h / 2 - depth * 0.2, width: w * 0.26, height: h * 0.2), cornerWidth: s * 0.025, cornerHeight: s * 0.025, transform: nil))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }
    card(center: CGPoint(x: s * 0.57, y: s * 0.54), angle: -0.2, face: rgb(0xD9CFBC), lines: false)
    card(center: CGPoint(x: s * 0.46, y: s * 0.48), angle: 0.09, face: rgb(0xF4EDDD), lines: true)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: folder)
try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
var images = [#"{"filename":"ios-1024.png","idiom":"universal","platform":"ios","size":"1024x1024"}"#]
try! render(1024).write(to: folder.appendingPathComponent("ios-1024.png"))
for point in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "mac-\(point)@\(scale)x.png"
        try! render(point * scale).write(to: folder.appendingPathComponent(name))
        images.append(#"{"filename":"\#(name)","idiom":"mac","scale":"\#(scale)x","size":"\#(point)x\#(point)"}"#)
    }
}
try! #"{"images":[\#(images.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
