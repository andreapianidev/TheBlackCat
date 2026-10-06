// Renders every posture of the rig side by side, to check the drawing without running the app.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let kinds = PoseKind.allCases
let cell = 220, cols = 4
let rows = (kinds.count + cols - 1) / cols
let ctx = CGContext(data: nil, width: cell * cols, height: cell * rows, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: cell * cols, height: cell * rows))
for (i, k) in kinds.enumerated() {
    let cx = CGFloat((i % cols) * cell + cell / 2), cy = CGFloat((rows - 1 - i / cols) * cell + 60)
    ctx.setFillColor(CGColor(red: 0.6, green: 0.62, blue: 0.66, alpha: 1))
    ctx.fill(CGRect(x: cx - 100, y: cy - 2, width: 200, height: 2))
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)
    ctx.scaleBy(x: 2.2, y: 2.2)
    let pose = CatPose.make(k)
    let style: TailStyle = [.sleep, .loaf, .sit].contains(k) ? .wrapped : (k == .dangle ? .hanging : (k == .hiss ? .angry : .relaxed))
    let tail = TailChain().settle(root: CatRig.tailRoot(pose), style: style, groundY: k == .dangle ? nil : 0)
    CatRig.draw(CatLook(pose: pose, tail: tail, tailPuff: style.puff, gaze: CGVector(dx: 0.4, dy: 0), glow: 0.5), in: ctx)
    ctx.restoreGState()
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
