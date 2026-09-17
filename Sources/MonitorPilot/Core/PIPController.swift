import Foundation
import AppKit
import CoreGraphics

/// Registro das nossas janelas de captura — elas são excluídas de toda captura
/// (junto com `sharingType = .none`) pra um PIP da própria tela não se filmar.
@MainActor
enum CaptureWindowRegistry {
    private(set) static var ids: Set<CGWindowID> = []
    static func register(_ window: NSWindow) {
        guard window.windowNumber > 0 else { return }
        ids.insert(CGWindowID(window.windowNumber))
    }
    static func unregister(_ window: NSWindow) {
        guard window.windowNumber > 0 else { return }
        ids.remove(CGWindowID(window.windowNumber))
    }
    static var all: [CGWindowID] { Array(ids) }
}

/// Um PIP vivo: painel + sessão de captura.
@MainActor
final class PIPSession {
    let anchorKey: String                 // display "dono" da linha no popover
    let sourceDisplayID: CGDirectDisplayID
    let panel: PIPPanel
    let capture: DisplayCaptureSession
    var config: PIPConfig

    init(anchorKey: String, sourceDisplayID: CGDirectDisplayID,
         panel: PIPPanel, capture: DisplayCaptureSession, config: PIPConfig) {
        self.anchorKey = anchorKey
        self.sourceDisplayID = sourceDisplayID
        self.panel = panel
        self.capture = capture
        self.config = config
    }
}

/// Controla os PIPs (um por display "dono"). Estado persistido em ConfigStore
/// pelo callback `onConfigChange` (o DisplayStore é quem escreve o arquivo).
@MainActor
final class PIPController: ObservableObject {
    static let shared = PIPController()

    @Published private(set) var sessions: [String: PIPSession] = [:]
    @Published var lastError: String?

    /// (anchorKey, config ou nil pra apagar) — ligado pelo DisplayStore.
    var onConfigChange: ((String, PIPConfig?) -> Void)?

    func session(for anchorKey: String) -> PIPSession? { sessions[anchorKey] }
    func isActive(_ anchorKey: String) -> Bool { sessions[anchorKey] != nil }

    /// Abre (ou reabre) o PIP do display `anchor` mostrando a tela `source`.
    /// `askPermission` só é true quando veio de clique do dono.
    @discardableResult
    func open(anchorKey: String, source: CGDirectDisplayID, config: PIPConfig,
              askPermission: Bool) -> Bool {
        guard ScreenCapturePermission.granted else {
            if askPermission {
                ScreenCapturePermission.request()
                lastError = "Autorize a Gravação de Tela e tente de novo."
            }
            return false
        }
        close(anchorKey: anchorKey, forget: false)

        let config = config
        let pointSize = DisplayCaptureSession.pointSize(source)
        let aspect = croppedAspect(pointSize: pointSize, crop: config.crop)

        let capture = DisplayCaptureSession(sourceDisplayID: source)
        capture.showsCursor = config.showCursor
        capture.crop = config.crop

        let panel = PIPPanel(contentSize: config.frame.size, aspect: aspect) { [weak self] frame in
            self?.frameChanged(anchorKey: anchorKey, frame: frame)
        }
        panel.install(captureLayer: capture.layer)
        panel.setFrame(placedFrame(config.frame, aspect: aspect), display: true)
        panel.alphaValue = min(max(config.alpha, 0.2), 1)
        panel.ignoresMouseEvents = config.clickThrough
        panel.level = config.alwaysOnTop ? .floating : .normal
        panel.orderFront(nil)
        CaptureWindowRegistry.register(panel)

        capture.excludedWindowIDs = CaptureWindowRegistry.all
        capture.scale = captureScale(for: config.frame.size, source: source, on: panel.screen)
        capture.start()

        let session = PIPSession(anchorKey: anchorKey, sourceDisplayID: source,
                                 panel: panel, capture: capture, config: config)
        sessions[anchorKey] = session
        onConfigChange?(anchorKey, config)
        return true
    }

    func close(anchorKey: String, forget: Bool = true) {
        guard let session = sessions.removeValue(forKey: anchorKey) else {
            if forget { onConfigChange?(anchorKey, nil) }
            return
        }
        session.capture.stop()
        CaptureWindowRegistry.unregister(session.panel)
        session.panel.orderOut(nil)
        session.panel.close()
        if forget { onConfigChange?(anchorKey, nil) }
    }

    func closeAll() {
        for key in sessions.keys { close(anchorKey: key, forget: false) }
    }

    // MARK: ajustes ao vivo

    func update(anchorKey: String, _ mutate: (inout PIPConfig) -> Void) {
        guard let session = sessions[anchorKey] else { return }
        var config = session.config
        let before = config
        mutate(&config)
        session.config = config

        session.panel.alphaValue = min(max(config.alpha, 0.2), 1)
        session.panel.ignoresMouseEvents = config.clickThrough
        session.panel.level = config.alwaysOnTop ? .floating : .normal

        // Cursor e recorte mudam a config da stream — sem derrubar a captura.
        if before.showCursor != config.showCursor || before.crop != config.crop {
            let aspect = croppedAspect(
                pointSize: DisplayCaptureSession.pointSize(session.sourceDisplayID),
                crop: config.crop)
            session.panel.contentAspectRatio = NSSize(width: aspect.width, height: aspect.height)
            session.capture.showsCursor = config.showCursor
            session.capture.crop = config.crop
            session.capture.applySettings()
        }
        onConfigChange?(anchorKey, config)
    }

    /// Ampliação: fator sobre o tamanho atual da janela (mantém o aspecto).
    func setMagnification(anchorKey: String, factor: Double) {
        guard let session = sessions[anchorKey] else { return }
        let aspect = session.panel.contentAspectRatio
        let width = max(160, min(3000, session.panel.frame.width * factor))
        let height = width * aspect.height / max(aspect.width, 1)
        var frame = session.panel.frame
        frame.size = NSSize(width: width, height: height)
        session.panel.setFrame(frame, display: true, animate: false)
        frameChanged(anchorKey: anchorKey, frame: frame)
    }

    private func frameChanged(anchorKey: String, frame: CGRect) {
        guard let session = sessions[anchorKey] else { return }
        session.config.frame = frame
        let scale = captureScale(for: frame.size, source: session.sourceDisplayID,
                                 on: session.panel.screen)
        if abs(scale - session.capture.scale) > 0.02 {
            session.capture.scale = scale
            session.capture.applySettings()   // redimensionar sobe/desce a resolução capturada
        }
        onConfigChange?(anchorKey, session.config)
    }

    // MARK: helpers

    /// Só restaura o frame salvo se ele ainda cai em alguma tela.
    private func placedFrame(_ frame: CGRect, aspect: CGSize) -> CGRect {
        var frame = frame
        let wanted = aspect.height / max(aspect.width, 1)
        if frame.width < 160 || frame.height < 90 {
            frame.size = NSSize(width: 480, height: 480 * wanted)
        } else if abs(frame.height / frame.width - wanted) > 0.01 {
            // Aspecto mudou (ex.: recorte novo) — a altura segue o novo aspecto.
            frame.size = NSSize(width: frame.width, height: frame.width * wanted)
        }
        if NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) { return frame }
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGRect(x: visible.minX + 40, y: visible.maxY - frame.height - 40,
                      width: frame.width, height: frame.height)
    }

    private func croppedAspect(pointSize: CGSize, crop: CGRect?) -> CGSize {
        guard let crop else { return pointSize }
        let rect = CaptureConfigPlanner.cropRect(normalized: crop, inPixels: pointSize)
        return rect.size
    }

    /// Captura só o que a janela mostra (× backing da tela ONDE a janela está)
    /// — economiza GPU sem borrar.
    private func captureScale(for windowSize: CGSize, source: CGDirectDisplayID,
                              on screen: NSScreen?) -> Double {
        let pixels = DisplayCaptureSession.pixelSize(source)
        guard pixels.width > 0 else { return 1 }
        let backing = (screen ?? NSScreen.main)?.backingScaleFactor ?? 2
        let wanted = windowSize.width * backing
        return min(max(wanted / pixels.width, 0.1), 1)
    }
}
