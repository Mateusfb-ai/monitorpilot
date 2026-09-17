import Foundation
import AppKit
import CoreGraphics
import CoreMedia
import AVFoundation
import ScreenCaptureKit

enum CaptureConfigPlanner {
    static let maxDimension = 4096

    static func size(forPixels pixels: CGSize, scale: Double,
                     maxDim: Int = maxDimension) -> (width: Int, height: Int) {
        let w = max(pixels.width, 1), h = max(pixels.height, 1)
        let s = max(scale, 0.01)
        var outW = w * s, outH = h * s
        let cap = Double(maxDim)
        if outW > cap || outH > cap {
            let k = min(cap / outW, cap / outH)
            outW *= k; outH *= k
        }
        func even(_ v: Double) -> Int { max(2, Int(v.rounded()) / 2 * 2) }
        return (even(outW), even(outH))
    }

    static func cropRect(normalized: CGRect, inPixels pixels: CGSize) -> CGRect {
        let w = max(pixels.width, 1), h = max(pixels.height, 1)
        let x = min(max(normalized.origin.x, 0), 0.99)
        let y = min(max(normalized.origin.y, 0), 0.99)
        let cw = min(max(normalized.width, 0.01), 1 - x)
        let ch = min(max(normalized.height, 0.01), 1 - y)
        return CGRect(x: (x * w).rounded(), y: (y * h).rounded(),
                      width: max((cw * w).rounded(), 2), height: max((ch * h).rounded(), 2))
    }
}

enum ScreenCapturePermission {
    static var granted: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    static func openPrivacySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

final class CaptureSink: NSObject, SCStreamOutput, SCStreamDelegate {
    let layer: AVSampleBufferDisplayLayer
    private let onStop: @Sendable (Error) -> Void

    init(layer: AVSampleBufferDisplayLayer, onStop: @escaping @Sendable (Error) -> Void) {
        self.layer = layer
        self.onStop = onStop
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              CMSampleBufferGetImageBuffer(sampleBuffer) != nil,
              Self.isComplete(sampleBuffer) else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true)
            as? [CFMutableDictionary], let first = attachments.first {
            CFDictionarySetValue(first,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sampleBuffer)
        frameCount += 1
        if Self.debug, frameCount % 60 == 1 {
            FileHandle.standardError.write("[pip] frames=\(frameCount) status=\(renderer.status.rawValue) \(CVPixelBufferGetWidth(CMSampleBufferGetImageBuffer(sampleBuffer)!))x\(CVPixelBufferGetHeight(CMSampleBufferGetImageBuffer(sampleBuffer)!))\n".data(using: .utf8)!)
        }
    }
    private var frameCount = 0
    static let debug = ProcessInfo.processInfo.environment["MONITORPILOT_DEBUG"] != nil

    func stream(_ stream: SCStream, didStopWithError error: Error) { onStop(error) }

    private static func isComplete(_ buffer: CMSampleBuffer) -> Bool {
        guard let array = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = array.first?[.status] as? Int else { return true }
        return SCFrameStatus(rawValue: raw) == .complete
    }
}

@MainActor
final class DisplayCaptureSession: ObservableObject {
    let sourceDisplayID: CGDirectDisplayID
    let layer = AVSampleBufferDisplayLayer()
    @Published private(set) var error: String?
    @Published private(set) var running = false

    private var stream: SCStream?
    private var sink: CaptureSink?
    private var scDisplay: SCDisplay?
    private var startTask: Task<Void, Never>?
    private let queue = DispatchQueue(label: "app.monitorpilot.capture", qos: .userInteractive)

    var excludedWindowIDs: [CGWindowID] = []
    var scale: Double = 1
    var showsCursor = false
    var crop: CGRect?

    init(sourceDisplayID: CGDirectDisplayID) {
        self.sourceDisplayID = sourceDisplayID
        layer.videoGravity = .resizeAspect
    }

    static func pixelSize(_ id: CGDirectDisplayID) -> CGSize {
        guard let mode = CGDisplayCopyDisplayMode(id) else {
            return CGSize(width: CGDisplayPixelsWide(id), height: CGDisplayPixelsHigh(id))
        }
        return CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
    }

    static func pointSize(_ id: CGDirectDisplayID) -> CGSize {
        CGSize(width: CGDisplayPixelsWide(id), height: CGDisplayPixelsHigh(id))
    }

    func start() {
        guard startTask == nil, !running else { return }
        guard ScreenCapturePermission.granted else {
            error = "sem permissão de Gravação de Tela"
            return
        }
        let id = sourceDisplayID
        let excluded = excludedWindowIDs
        startTask = Task { @MainActor in
            defer { startTask = nil }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true)
                guard !Task.isCancelled else { return }
                guard let display = content.displays.first(where: { $0.displayID == id }) else {
                    error = "display não está disponível para captura"
                    return
                }
                scDisplay = display
                let windows = content.windows.filter { excluded.contains($0.windowID) }
                let filter = SCContentFilter(display: display, excludingWindows: windows)
                let config = makeConfiguration(display: display)

                let sink = CaptureSink(layer: layer) { err in
                    Task { @MainActor [weak self] in
                        self?.running = false
                        self?.error = err.localizedDescription
                    }
                }
                let stream = SCStream(filter: filter, configuration: config, delegate: sink)
                try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: queue)
                try await stream.startCapture()
                guard !Task.isCancelled else {
                    try? await stream.stopCapture()
                    return
                }
                self.sink = sink
                self.stream = stream
                self.running = true
                self.error = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                self.running = false
            }
        }
    }

    func applySettings() {
        guard let stream, let display = scDisplay else { return }
        let config = makeConfiguration(display: display)
        Task { try? await stream.updateConfiguration(config) }
    }

    private func makeConfiguration(display: SCDisplay) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let pixels = Self.pixelSize(sourceDisplayID)
        let backing = max(Double(pixels.width) / Double(max(display.width, 1)), 1)
        var effective = pixels
        if let crop {
            let rectPoints = CaptureConfigPlanner.cropRect(
                normalized: crop,
                inPixels: CGSize(width: display.width, height: display.height))
            config.sourceRect = rectPoints
            effective = CGSize(width: rectPoints.width * backing,
                               height: rectPoints.height * backing)
        }
        let size = CaptureConfigPlanner.size(forPixels: effective, scale: scale)
        config.width = size.width
        config.height = size.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = showsCursor
        config.queueDepth = 5
        config.scalesToFit = true
        return config
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        guard let stream else { running = false; return }
        self.stream = nil
        self.sink = nil
        self.scDisplay = nil
        running = false
        Task { try? await stream.stopCapture() }
    }

    deinit { }
}

final class CaptureView: NSView {
    private let displayLayer: AVSampleBufferDisplayLayer

    init(layer: AVSampleBufferDisplayLayer) {
        self.displayLayer = layer
        super.init(frame: .zero)
        self.layer = layer
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        layer.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não usado") }

    override func layout() {
        super.layout()
        displayLayer.frame = bounds
    }
}
