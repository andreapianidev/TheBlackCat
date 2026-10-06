// Renders postures and coats side by side, to check the drawing without running the app.
// Usage: pose-sheet out.png [coats]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let coatsMode = CommandLine.arguments.count > 2
let cell = 200, cols = coatsMode ? CatCoat.all.count : 6
let items: [(PoseKind, CatCoat, Bool)] = coatsMode
    ? CatCoat.all.map { (.sit, $0, false) } + CatCoat.all.map { (.stand, $0, false) }
      + CatCoat.all.map { (.sit, $0, true) } + CatCoat.all.map { (.stand, $0, true) }
    : PoseKind.allCases.map { ($0, .black, false) } + PoseKind.allCases.map { ($0, .black, true) }
let rows = (items.count + cols - 1) / cols
let ctx = CGContext(data: nil, width: cell * cols, height: cell * rows, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(red: 0.62, green: 0.68, blue: 0.76, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: cell * cols, height: cell * rows))
for (i, (k, coat, comic)) in items.enumerated() {
    let cx = CGFloat((i % cols) * cell + cell / 2), cy = CGFloat((rows - 1 - i / cols) * cell + (k == .hang ? 150 : 50))
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)
    ctx.scaleBy(x: 2.0, y: 2.0)
    let pose = CatPose.make(k)
    let style: TailStyle = [.sleep, .loaf, .sit].contains(k) ? .wrapped : ([.dangle, .hang].contains(k) ? .hanging : (k == .hiss ? .angry : .happy))
    let tail = TailChain().settle(root: CatRig.tailRoot(pose), style: style, groundY: [.dangle, .hang].contains(k) ? nil : 0)
    CatRig.draw(CatLook(pose: pose, tail: tail, tailPuff: style.puff, gaze: CGVector(dx: 0.4, dy: 0), glow: 0.5,
                        coat: coat, comic: comic, boil: 0.5), in: ctx)
    ctx.restoreGState()
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
