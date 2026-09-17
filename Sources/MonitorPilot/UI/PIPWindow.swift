import AppKit
import AVFoundation

@MainActor
final class PIPPanel: NSPanel {
    private let onFrameChange: (CGRect) -> Void

    init(contentSize: CGSize, aspect: CGSize, onFrameChange: @escaping (CGRect) -> Void) {
        self.onFrameChange = onFrameChange
        super.init(contentRect: CGRect(origin: .zero, size: contentSize),
                   styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        sharingType = ProcessInfo.processInfo.environment["MONITORPILOT_DEBUG"] != nil ? .readOnly : .none
        contentAspectRatio = NSSize(width: max(aspect.width, 1), height: max(aspect.height, 1))
        minSize = NSSize(width: 160, height: 90)
        isReleasedWhenClosed = false
        NotificationCenter.default.addObserver(
            self, selector: #selector(frameMoved), name: NSWindow.didMoveNotification, object: self)
        NotificationCenter.default.addObserver(
            self, selector: #selector(frameMoved), name: NSWindow.didEndLiveResizeNotification, object: self)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @objc private func frameMoved() { onFrameChange(frame) }

    func install(captureLayer: AVSampleBufferDisplayLayer) {
        let view = CaptureView(layer: captureLayer)
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true
        contentView = view
    }

    override func cancelOperation(_ sender: Any?) { close() }
}
