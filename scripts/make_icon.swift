// Generates Assets/AppIcon.iconset, which build.sh turns into Assets/AppIcon.icns
// when the icns is missing. Run from the repository root.
//
// Artwork: the clock's defining trait is a see-through face you can read content
// through, so the icon shows exactly that -- lines of text on a graphite tile,
// running on underneath a translucent face. Hands, ticks and the red-dot centre
// cap are drawn the way the app draws them.
//
// The grid is the classic macOS one (1024 canvas, 824 squircle with 100 margins).
// macOS 26 accepts that shape without putting it in a grey backdrop, and on 14
// and 15 it sits at the same size as every other icon. Detail drops out as the
// icon shrinks: at 16px the text lines go and the hands move to 3:00, because
// 10:09 reads as a tick mark at that size.
import AppKit
import SwiftUI

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
func c(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: rgb, components: [CGFloat(r)/255, CGFloat(g)/255, CGFloat(b)/255, a])!
}
let tileTop = c(70, 75, 84), tileBottom = c(36, 39, 45)
let textLine = c(236, 232, 224, 0.55)
let faceFill = c(214, 214, 216, 0.60)     // translucent, like the real face
let faceRim = c(245, 245, 247, 0.85)
let ink = c(24, 24, 26), tick = c(40, 40, 44)
let red = c(222, 48, 44)

func render(_ px: Int) -> CGImage {
    let S = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)   // top-left origin

    let inset = S * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: S - 2*inset, height: S - 2*inset)
    let B = body.width
    let squircle = RoundedRectangle(cornerRadius: B * 0.2237, style: .continuous).path(in: body).cgPath

    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let g = CGGradient(colorsSpace: rgb, colors: [tileTop, tileBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])

    // Text lines, drawn first so they run on underneath the face. Irregular
    // lengths so they read as prose rather than stripes, and one stops short
    // under the glass: a line ending you can see through the face is what
    // makes it read as see-through.
    if px >= 32 {
        let lines: [(CGFloat, CGFloat, CGFloat)] = px >= 64
            ? [(0.19, 0.12, 0.64), (0.35, 0.12, 0.77), (0.51, 0.12, 0.33),
               (0.67, 0.12, 0.72), (0.83, 0.12, 0.46)]
            : [(0.30, 0.10, 0.80), (0.70, 0.10, 0.62)]
        let h = max(1, B * (px >= 64 ? 0.036 : 0.06))
        ctx.setFillColor(textLine)
        for (y, x, w) in lines {
            let r = CGRect(x: body.minX + B * x, y: body.minY + B * y - h / 2, width: B * w, height: h)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
            ctx.fillPath()
        }
    }
    ctx.restoreGState()

    // The face: translucent, so the lines stay legible through it.
    let centre = CGPoint(x: body.midX, y: body.midY)
    let faceR = B * (px <= 16 ? 0.43 : 0.38)
    let faceRect = CGRect(x: centre.x - faceR, y: centre.y - faceR, width: 2*faceR, height: 2*faceR)
    ctx.setFillColor(px <= 16 ? c(214, 214, 216, 0.78) : faceFill)
    ctx.fillEllipse(in: faceRect)
    if px >= 32 {
        ctx.setStrokeColor(faceRim); ctx.setLineWidth(max(1, B * 0.010))
        let rr = faceR - B * 0.005
        ctx.strokeEllipse(in: CGRect(x: centre.x - rr, y: centre.y - rr, width: 2*rr, height: 2*rr))
    }

    func point(_ angleFromTop: CGFloat, _ r: CGFloat) -> CGPoint {
        let a = angleFromTop - .pi / 2
        return CGPoint(x: centre.x + cos(a) * r, y: centre.y + sin(a) * r)
    }

    // Ticks: sixty with bold hours where there is room (as the app draws them),
    // twelve at 64, the four quarters at 32, none at 16.
    let count = px >= 128 ? 60 : (px >= 64 ? 12 : (px >= 32 ? 4 : 0))
    ctx.setLineCap(.butt)
    for i in 0..<count {
        let step = count == 60 ? i : i * (60 / count)
        let hour = step % 5 == 0
        let outer = faceR * 0.93
        let len = faceR * (hour ? 0.13 : 0.05)
        ctx.setStrokeColor(tick)
        ctx.setLineWidth(max(1, B * (hour ? 0.016 : 0.005)))
        let ang = CGFloat(step) / 60 * 2 * .pi
        ctx.move(to: point(ang, outer)); ctx.addLine(to: point(ang, outer - len)); ctx.strokePath()
    }

    func hand(_ ang: CGFloat, length: CGFloat, width: CGFloat, color: CGColor, tail: CGFloat = 0) {
        // Round caps merge two hands into one wedge at 16px; square them off there.
        ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.setLineCap(px <= 16 ? .butt : .round)
        ctx.move(to: point(ang + .pi, tail)); ctx.addLine(to: point(ang, length)); ctx.strokePath()
    }
    if px <= 16 {
        // At 16px 10:09 reads as a tick mark. 3:00 is the universal small clock
        // glyph, and its axis-aligned 2px hands land on whole pixels.
        hand(.pi / 2, length: faceR * 0.62, width: 2, color: ink)
        hand(0, length: faceR * 0.80, width: 2, color: ink)
        return ctx.makeImage()!
    }
    // 10:09, the watch-photograph pose, so the hands never overlap.
    let heavy: CGFloat = px == 32 ? 1.25 : 1.0
    hand((10.0 + 9.0 / 60) / 12 * 2 * .pi, length: faceR * 0.52, width: max(1.5, B * 0.046 * heavy), color: ink)
    hand(9.0 / 60 * 2 * .pi, length: faceR * 0.80, width: max(1.2, B * 0.030 * heavy), color: ink)
    hand(36.0 / 60 * 2 * .pi, length: faceR * 0.84, width: max(1, B * 0.010), color: red, tail: faceR * 0.20)

    // Centre cap: black ring with a red dot, as in the app.
    let cap = max(1.5, B * 0.034)
    ctx.setFillColor(ink)
    ctx.fillEllipse(in: CGRect(x: centre.x - cap, y: centre.y - cap, width: 2*cap, height: 2*cap))
    if px >= 64 {
        let dot = cap * 0.5
        ctx.setFillColor(red)
        ctx.fillEllipse(in: CGRect(x: centre.x - dot, y: centre.y - dot, width: 2*dot, height: 2*dot))
    }
    return ctx.makeImage()!
}

func write(_ img: CGImage, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
for (base, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    write(render(base * scale), scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png")
}
print("wrote iconset to \(outDir)")
