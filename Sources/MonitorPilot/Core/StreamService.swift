import Foundation
import AppKit
import CoreGraphics

/// Monitor de Transmissão: joga a captura ao vivo de uma tela dentro de OUTRA
/// tela, em janela sem bordas ocupando a tela inteira do destino.
///
///  • "Transmitir esta tela para uma tela virtual" — cria uma tela virtual do
///    tamanho exato da fonte e desenha a captura da fonte nela (é assim que o
///    BetterDisplay alimenta alvos Sidecar/AirPlay: quem espelha/estende a tela
///    virtual é o próprio macOS).
///  • "Transmitir <virtual> para esta tela" — o inverso: mostra o conteúdo de
///    uma tela virtual numa janela cheia do display físico.
///
/// Estado é de sessão (não persiste): `applicationWillTerminate` já destrói as
/// telas virtuais, e uma transmissão órfã no boot seria pior que reabrir na mão.
@MainActor
final class StreamService: ObservableObject {
    static let shared = StreamService()

    @MainActor
    final class Session: Identifiable {
        let id = UUID()
        let sourceDisplayID: CGDirectDisplayID
        let targetDisplayID: CGDirectDisplayID
        let label: String
        let window: NSWindow
        let capture: DisplayCaptureSession
        /// Tela virtual criada por esta transmissão (só no modo "para virtual").
        let ownedVirtual: VirtualScreen?

        init(sourceDisplayID: CGDirectDisplayID, targetDisplayID: CGDirectDisplayID,
             label: String, window: NSWindow, capture: DisplayCaptureSession,
             ownedVirtual: VirtualScreen?) {
            self.sourceDisplayID = sourceDisplayID
            self.targetDisplayID = targetDisplayID
            self.label = label
            self.window = window
            self.capture = capture
            self.ownedVirtual = ownedVirtual
        }
    }

    @Published private(set) var sessions: [Session] = []
    @Published var lastError: String?

    func isStreaming(source: CGDirectDisplayID) -> Bool {
        sessions.contains { $0.sourceDisplayID == source }
    }

    func session(source: CGDirectDisplayID) -> Session? {
        sessions.first { $0.sourceDisplayID == source }
    }

    /// (a) Transmite `source` para uma tela virtual recém-criada.
    func streamToVirtual(source: DisplayInfo, askPermission: Bool) async -> Bool {
        guard checkPermission(askPermission) else { return false }
        guard VirtualDisplayService.isAvailable else {
            lastError = "telas virtuais indisponíveis neste macOS"
            return false
        }
        let pixels = DisplayCaptureSession.pixelSize(source.id)
        let w = Int(pixels.width), h = Int(pixels.height)
        guard w > 0, h > 0 else { lastError = "tamanho da fonte desconhecido"; return false }

        // HiDPI segue a fonte: se o físico está em modo HiDPI, a virtual também.
        let hiDPI = pixels.width > CGFloat(CGDisplayPixelsWide(source.id)) + 1
        guard let virtual = VirtualDisplayService.shared.create(
            name: "Transmissão \(source.name)",
            pixelModes: [(w, h)], maxPixelsWide: w, maxPixelsHigh: h, hiDPI: hiDPI)
        else {
            lastError = "criação da tela virtual falhou"
            return false
        }
        guard let screen = await waitForScreen(of: virtual) else {
            VirtualDisplayService.shared.destroy(virtual)
            lastError = "a tela virtual não apareceu"
            return false
        }
        guard let targetID = displayID(of: screen) else {
            VirtualDisplayService.shared.destroy(virtual)
            lastError = "displayID da tela virtual desconhecido"
            return false
        }
        start(source: source.id, targetScreen: screen, targetDisplayID: targetID,
              label: "\(source.name) → Transmissão \(source.name)", ownedVirtual: virtual)
        return true
    }

    /// (b) Transmite a tela virtual `virtual` para o display físico `target`.
    func streamVirtual(_ virtual: VirtualScreen, to target: DisplayInfo,
                       askPermission: Bool) -> Bool {
        guard checkPermission(askPermission) else { return false }
        guard let sourceID = virtual.displayID else {
            lastError = "tela virtual sem displayID"
            return false
        }
        guard let screen = screen(for: target.id) else {
            lastError = "display de destino não encontrado"
            return false
        }
        start(source: sourceID, targetScreen: screen, targetDisplayID: target.id,
              label: "\(virtual.name) → \(target.name)", ownedVirtual: nil)
        return true
    }

    func stop(_ session: Session) {
        session.capture.stop()
        CaptureWindowRegistry.unregister(session.window)
        session.window.orderOut(nil)
        session.window.close()
        if let virtual = session.ownedVirtual {
            VirtualDisplayService.shared.destroy(virtual)
        }
        sessions.removeAll { $0.id == session.id }
    }

    func stopAll() { sessions.forEach(stop) }

    // MARK: interno

    private func checkPermission(_ ask: Bool) -> Bool {
        guard ScreenCapturePermission.granted else {
            if ask {
                ScreenCapturePermission.request()
                lastError = "Autorize a Gravação de Tela e tente de novo."
            }
            return false
        }
        return true
    }

    private func start(source: CGDirectDisplayID, targetScreen: NSScreen,
                       targetDisplayID: CGDirectDisplayID, label: String,
                       ownedVirtual: VirtualScreen?) {
        let capture = DisplayCaptureSession(sourceDisplayID: source)
        capture.showsCursor = true

        let window = NSWindow(contentRect: targetScreen.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false, screen: targetScreen)
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.sharingType = .none
        window.isReleasedWhenClosed = false
        window.contentView = CaptureView(layer: capture.layer)
        window.setFrame(targetScreen.frame, display: true)
        window.orderFront(nil)
        CaptureWindowRegistry.register(window)

        capture.excludedWindowIDs = CaptureWindowRegistry.all
        capture.scale = 1
        capture.start()

        sessions.append(Session(sourceDisplayID: source, targetDisplayID: targetDisplayID,
                                label: label, window: window, capture: capture,
                                ownedVirtual: ownedVirtual))
    }

    /// A tela virtual entra no sistema de forma assíncrona (~1–2s).
    private func waitForScreen(of virtual: VirtualScreen, timeout: Double = 4) async -> NSScreen? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let id = virtual.displayID, let screen = screen(for: id) { return screen }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    private func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id }
    }

    private func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
