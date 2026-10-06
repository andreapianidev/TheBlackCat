import AVFoundation
import Vision

/// The webcam, read a few times a second with Vision: is someone there, are they waving.
/// Frames are analysed and dropped on the spot, nothing is stored.
final class SightSense: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onPresence: ((Bool) -> Void)?
    var onAway: ((Bool) -> Void)?
    var onWave: (() -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.andreapiani.theblackcat.sight")
    private var configured = false
    private var lastRun: CFTimeInterval = 0
    private var lastFace: CFTimeInterval = 0
    private var present = false
    private var away = false
    private var palm: [(CFTimeInterval, CGFloat)] = []
    private var lastWave: CFTimeInterval = 0

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
            guard ok, let self else { return }
            self.queue.async {
                if !self.configured { self.configure() }
                self.lastFace = CACurrentMediaTime()
                if !self.session.isRunning { self.session.startRunning() }
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
        if present { present = false; DispatchQueue.main.async { self.onPresence?(false) } }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        // Five frames a second are plenty: less work for the camera and for Vision.
        if (try? device.lockForConfiguration()) != nil {
            if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 5 }) {
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 5)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 5)
            }
            device.unlockForConfiguration()
        }
        session.beginConfiguration()
        session.sessionPreset = .low
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        configured = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastRun > 0.5, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastRun = now

        let faces = VNDetectFaceRectanglesRequest()
        let hands = VNDetectHumanHandPoseRequest()
        hands.maximumHandCount = 1
        // Hands are the expensive request: only look for them when someone is there.
        let lookForHands = now - lastFace < 3
        try? VNImageRequestHandler(cvPixelBuffer: buffer, options: [:]).perform(lookForHands ? [faces, hands] : [faces])

        if !(faces.results ?? []).isEmpty { lastFace = now }
        let isPresent = now - lastFace < 3
        if isPresent != present {
            present = isPresent
            DispatchQueue.main.async { self.onPresence?(isPresent) }
        }
        if !away && now - lastFace > 25 {
            away = true
            DispatchQueue.main.async { self.onAway?(true) }
        } else if away && isPresent {
            away = false
            DispatchQueue.main.async { self.onAway?(false) }
        }

        if let hand = hands.results?.first, let x = openPalmX(hand) {
            palm.append((now, x))
        }
        palm.removeAll { now - $0.0 > 1.6 }
        if palm.count >= 4, now - lastWave > 4 {
            let xs = palm.map(\.1)
            if (xs.max() ?? 0) - (xs.min() ?? 0) > 0.06 {
                lastWave = now
                palm.removeAll()
                DispatchQueue.main.async { self.onWave?() }
            }
        }
    }

    /// The wrist x of a raised open hand, or nil.
    private func openPalmX(_ hand: VNHumanHandPoseObservation) -> CGFloat? {
        guard let pts = try? hand.recognizedPoints(.all), let wrist = pts[.wrist], wrist.confidence > 0.3 else { return nil }
        let pairs: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] =
            [(.indexTip, .indexMCP), (.middleTip, .middleMCP), (.ringTip, .ringMCP), (.littleTip, .littleMCP)]
        for (tipName, mcpName) in pairs {
            guard let tip = pts[tipName], let mcp = pts[mcpName], tip.confidence > 0.3, mcp.confidence > 0.3 else { return nil }
            let dTip = hypot(tip.location.x - wrist.location.x, tip.location.y - wrist.location.y)
            let dMcp = hypot(mcp.location.x - wrist.location.x, mcp.location.y - wrist.location.y)
            if dTip < dMcp * 1.5 || tip.location.y < wrist.location.y { return nil }
        }
        return wrist.location.x
    }
}
