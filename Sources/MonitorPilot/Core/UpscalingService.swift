import Foundation
import AppKit
import Metal
import QuartzCore
import CoreGraphics

/// Upscaling de brilho XDR/HDR — método "color table" da análise do BetterDisplay:
/// com o pipeline EDR ativo, valores >1.0 na gamma table empurram o desktop SDR
/// pra faixa de luminância estendida (além de "100%" de brilho).
///
/// Pré-requisitos: Apple Silicon + display com headroom EDR (XDR interno, ou
/// HDR externo em modo HDR). O headroom cresce quando o brilho SDR está no teto.
@MainActor
final class UpscalingService: ObservableObject {
    static let shared = UpscalingService()

    @Published private(set) var edrPipelineActive = false
    private var activatorWindows: [NSWindow] = []

    // MARK: Headroom

    /// Headroom EDR potencial do display (1.0 = sem headroom; ex. XDR ≈ 2–8×).
    nonisolated static func potentialHeadroom(_ id: CGDirectDisplayID) -> Float {
        guard let screen = screen(for: id) else { return 1 }
        return Float(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
    }

    /// Headroom EDR utilizável AGORA (só sobe com o pipeline EDR ativo).
    nonisolated static func currentHeadroom(_ id: CGDirectDisplayID) -> Float {
        guard let screen = screen(for: id) else { return 1 }
        return Float(screen.maximumExtendedDynamicRangeColorComponentValue)
    }

    enum Mode {
        case edr       // headroom EDR real — brilho físico além de 100%, sem clipping
        case sdrBoost  // display sem EDR ativo — gamma >1 realça tons médios, brancos clipam
    }

    /// Todo display suporta ampliação; o MODO depende do headroom utilizável.
    nonisolated static func supportsUpscaling(_ id: CGDirectDisplayID) -> Bool { true }

    nonisolated static func mode(_ id: CGDirectDisplayID) -> Mode {
        currentHeadroom(id) > 1.01 ? .edr : .sdrBoost
    }

    nonisolated private static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }

    // MARK: Ativador EDR
    // O WindowServer só libera a faixa EDR quando "existe conteúdo HDR na tela".
    // Truque (usado por Lunar/Vivid): janela mínima com CAMetalLayer EDR
    // renderizando um pixel além de 1.0 — invisível, mas mantém o EDR aceso.

    func setEDRPipeline(active: Bool) {
        guard active != edrPipelineActive else { return }
        if active {
            for screen in NSScreen.screens
            where screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.01 {
                if let w = Self.makeActivatorWindow(on: screen) { activatorWindows.append(w) }
            }
            edrPipelineActive = !activatorWindows.isEmpty
        } else {
            activatorWindows.forEach { $0.orderOut(nil) }
            activatorWindows.removeAll()
            edrPipelineActive = false
        }
    }

    private static func makeActivatorWindow(on screen: NSScreen) -> NSWindow? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }

        let layer = CAMetalLayer()
        layer.device = device
        layer.wantsExtendedDynamicRangeContent = true
        layer.pixelFormat = .rgba16Float
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        layer.drawableSize = CGSize(width: 1, height: 1)
        layer.isOpaque = false

        let window = NSWindow(
            contentRect: NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 1, height: 1),
            styleMask: .borderless, backing: .buffered, defer: false, screen: screen
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.alphaValue = 0.01
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.addSublayer(layer)
        layer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)

        // Renderiza um único pixel EDR (valor 2.0) — suficiente pro WindowServer
        // classificar como conteúdo HDR presente.
        guard let drawable = layer.nextDrawable(),
              let queue = device.makeCommandQueue(),
              let cmd = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 2.0, green: 2.0, blue: 2.0, alpha: 1.0)
        cmd.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        cmd.present(drawable)
        cmd.commit()

        window.orderFrontRegardless()
        return window
    }
}
