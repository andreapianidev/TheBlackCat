// Draws the app icon with the same rig the app uses, so the icon is the cat.
// Build and run through tools/render-icon.sh.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func renderIcon(size: Int) -> CGImage? {
    let s = CGFloat(size)
    let k = s / 1024
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.scaleBy(x: k, y: k)

    // Night sky, full bleed: macOS draws the rounded mask itself.
    let sky = CGGradient(colorsSpace: nil, colors: [
        CGColor(red: 0.16, green: 0.09, blue: 0.29, alpha: 1),
        CGColor(red: 0.06, green: 0.08, blue: 0.2, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 1024), options: [])

    // Moon with a soft halo.
    let moon = CGPoint(x: 730, y: 760)
    let halo = CGGradient(colorsSpace: nil, colors: [
        CGColor(red: 1, green: 0.95, blue: 0.75, alpha: 0.45),
        CGColor(red: 1, green: 0.95, blue: 0.75, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(halo, startCenter: moon, startRadius: 120, endCenter: moon, endRadius: 330, options: [])
    ctx.setFillColor(CGColor(red: 1, green: 0.96, blue: 0.82, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: moon.x - 150, y: moon.y - 150, width: 300, height: 300))
    ctx.setFillColor(CGColor(red: 0.93, green: 0.88, blue: 0.72, alpha: 1))
    for (x, y, r) in [(680.0, 800.0, 30.0), (790, 700, 22), (760, 820, 14)] as [(CGFloat, CGFloat, CGFloat)] {
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    // Stars.
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
    for (x, y, r) in [(150.0, 880.0, 6.0), (300, 950, 4), (420, 830, 5), (110, 700, 4), (900, 930, 5),
                      (950, 560, 4), (250, 760, 3), (540, 960, 3)] as [(CGFloat, CGFloat, CGFloat)] {
        ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    // A window, the cat's favourite perch.
    let win = CGRect(x: 150, y: -120, width: 724, height: 470)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 40, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
    ctx.setFillColor(CGColor(red: 0.93, green: 0.94, blue: 0.97, alpha: 1))
    ctx.addPath(CGPath(roundedRect: win, cornerWidth: 46, cornerHeight: 46, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.setFillColor(CGColor(red: 0.84, green: 0.86, blue: 0.9, alpha: 1))
    ctx.fill(CGRect(x: win.minX, y: win.maxY - 70, width: win.width, height: 2))
    for (i, c) in [CGColor(red: 1, green: 0.37, blue: 0.34, alpha: 1),
                   CGColor(red: 1, green: 0.74, blue: 0.18, alpha: 1),
                   CGColor(red: 0.16, green: 0.79, blue: 0.25, alpha: 1)].enumerated() {
        ctx.setFillColor(c)
        ctx.fillEllipse(in: CGRect(x: win.minX + 44 + CGFloat(i) * 48, y: win.maxY - 50, width: 28, height: 28))
    }

    // The cat, sitting on the window, tail hanging over the edge, looking at you.
    ctx.saveGState()
    ctx.translateBy(x: 575, y: win.maxY)
    ctx.scaleBy(x: 9.2, y: 9.2)
    var pose = CatPose.make(.sit)
    pose.pupil = 0.55
    pose.headTilt = 0.08
    let tail = TailChain().settle(root: CatRig.tailRoot(pose),
                                  style: TailStyle(angle: 4.3, curl: 1.5, waveAmp: 0, waveFreq: 0, stiffness: 30, puff: 1),
                                  groundY: nil)
    CatRig.draw(CatLook(pose: pose, tail: tail, gaze: CGVector(dx: -0.35, dy: -0.1), glow: 1,
                        groundShadow: 0, halo: 0.0), in: ctx)
    ctx.restoreGState()

    return ctx.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
var entries: [String] = []
for base in [16, 32, 128, 256, 512] {
    for mult in [1, 2] {
        let px = base * mult
        let name = "icon_\(base)x\(base)\(mult == 2 ? "@2x" : "").png"
        if let img = renderIcon(size: px) { write(img, to: out.appendingPathComponent(name)) }
        entries.append("""
            { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(mult)x", "size" : "\(base)x\(base)" }
        """)
    }
}
let json = "{\n  \"images\" : [\n" + entries.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try? json.write(to: out.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("icon written to \(out.path)")
