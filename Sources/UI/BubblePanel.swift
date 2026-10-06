import AppKit
import SwiftUI

/// The cat's thought bubble, in Liquid Glass, floating above its head.
final class BubblePanel {
    private let panel = FloatingPanel(size: CGSize(width: 260, height: 80))
    private let host = NSHostingView(rootView: BubbleView(text: "", comic: false))
    private var hideWork: DispatchWorkItem?
    private(set) var visible = false

    init() {
        host.sizingOptions = []
        panel.contentView = host
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    }

    func show(_ text: String, above head: CGPoint, comic: Bool) {
        host.rootView = BubbleView(text: text, comic: comic)
        let size = host.fittingSize
        panel.setContentSize(size)
        place(above: head)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
        visible = true
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8 + Double(text.count) * 0.055, execute: work)
    }

    func hide() {
        guard visible else { return }
        visible = false
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }) { [weak self] in
            if self?.visible == false { self?.panel.orderOut(nil) }
        }
    }

    func place(above head: CGPoint) {
        let size = panel.frame.size
        var o = CGPoint(x: head.x - size.width / 2, y: head.y + 8)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(head) }) ?? NSScreen.main {
            let v = screen.visibleFrame
            o.x = min(max(o.x, v.minX + 4), v.maxX - size.width - 4)
            o.y = min(o.y, v.maxY - size.height - 2)
        }
        panel.setFrameOrigin(CGPoint(x: o.x.rounded(), y: o.y.rounded()))
    }
}

struct BubbleView: View {
    let text: String
    let comic: Bool

    var body: some View {
        if comic {
            // A comic balloon: white, inked border, hand lettering in capitals.
            Text(text.uppercased())
                .font(.custom("Chalkboard SE", size: 12).weight(.bold))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 220)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white).stroke(.black, lineWidth: 2.2))
                .padding(6)
        } else {
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 230)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .rect(cornerRadius: 15))
                .padding(6)
        }
    }
}

/// A bowl of kibble on the bottom of the screen.
final class BowlPanel {
    private let panel = FloatingPanel(size: CGSize(width: 64, height: 34))
    private let view = BowlView(frame: CGRect(x: 0, y: 0, width: 64, height: 34))
    let spot: CGPoint

    var fill: CGFloat {
        get { view.fill }
        set { view.fill = newValue; view.needsDisplay = true }
    }

    init(at spot: CGPoint, scale: CGFloat) {
        self.spot = spot
        let size = CGSize(width: 64 * scale, height: 34 * scale)
        view.frame = CGRect(origin: .zero, size: size)
        panel.contentView = view
        panel.setContentSize(size)
        panel.setFrameOrigin(CGPoint(x: spot.x - size.width / 2, y: spot.y - 2))
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.3; panel.animator().alphaValue = 1 }
    }

    func remove() {
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.6; panel.animator().alphaValue = 0 }) { [panel] in
            panel.orderOut(nil)
        }
    }
}

private final class BowlView: NSView {
    var fill: CGFloat = 1

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        let w = bounds.width, h = bounds.height
        let rim = CGRect(x: w * 0.06, y: h * 0.42, width: w * 0.88, height: h * 0.3)
        // Kibble heap.
        if fill > 0.02 {
            ctx.setFillColor(NSColor(calibratedRed: 0.62, green: 0.38, blue: 0.2, alpha: 1).cgColor)
            let n = Int(14 * fill)
            for i in 0..<n {
                let fx = CGFloat((i * 37) % 100) / 100, fy = CGFloat((i * 53) % 100) / 100
                let r = h * 0.09
                ctx.fillEllipse(in: CGRect(x: rim.minX + 6 + fx * (rim.width - 12) - r, y: rim.midY + fy * h * 0.18 * fill - r,
                                           width: 2 * r, height: 1.6 * r))
            }
        }
        // Bowl body.
        let body = CGMutablePath()
        body.move(to: CGPoint(x: rim.minX, y: rim.midY))
        body.addLine(to: CGPoint(x: w * 0.18, y: h * 0.06))
        body.addLine(to: CGPoint(x: w * 0.82, y: h * 0.06))
        body.addLine(to: CGPoint(x: rim.maxX, y: rim.midY))
        body.addArc(center: CGPoint(x: rim.midX, y: rim.midY), radius: rim.width / 2, startAngle: 0, endAngle: .pi, clockwise: true)
        ctx.addPath(body)
        ctx.setFillColor(NSColor(calibratedRed: 0.86, green: 0.24, blue: 0.27, alpha: 1).cgColor)
        ctx.fillPath()
        ctx.setFillColor(NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.85).cgColor)
        let label = NSAttributedString(string: "♥", attributes: [.font: NSFont.systemFont(ofSize: h * 0.26, weight: .bold),
                                                                 .foregroundColor: NSColor.white.withAlphaComponent(0.85)])
        let s = label.size()
        label.draw(at: CGPoint(x: w / 2 - s.width / 2, y: h * 0.12))
    }
}
