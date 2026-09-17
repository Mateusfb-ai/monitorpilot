import Foundation
import ObjectiveC
import AppKit
import CoreGraphics

/// Telas virtuais via classes privadas CGVirtualDisplay* (receita BetterDummy),
/// acessadas por ObjC runtime (NSClassFromString + KVC + objc_msgSend) —
/// nada linkado, macOS sem as classes = feature indisponível, app segue vivo.
@MainActor
final class VirtualScreen: Identifiable {
    let id = UUID()
    let name: String
    let aspectWidth: Int
    let aspectHeight: Int
    private var display: NSObject?  // CGVirtualDisplay (retido = tela viva)

    var displayID: CGDirectDisplayID? {
        (display?.value(forKey: "displayID") as? NSNumber)?.uint32Value
    }

    convenience init?(name: String, aspectWidth: Int, aspectHeight: Int, hiDPI: Bool) {
        // Escada por múltiplos do aspect ratio (uso genérico "tela extra").
        let maxW = aspectWidth * (3840 / max(aspectWidth, 1))
        let maxH = aspectHeight * (3840 / max(aspectWidth, 1))
        var list: [(Int, Int)] = []
        var multiplier = 1
        while aspectWidth * multiplier <= maxW {
            let w = aspectWidth * multiplier, h = aspectHeight * multiplier
            if w >= 640 { list.append((w, h)) }
            multiplier += 1
        }
        self.init(name: name, aspectWidth: aspectWidth, aspectHeight: aspectHeight,
                  hiDPI: hiDPI, pixelModes: list, maxPixelsWide: maxW, maxPixelsHigh: maxH)
    }

    /// Init explícito em pixels — usado pelo HiDPI virtual, onde a tela precisa
    /// ter exatamente o tamanho de pixels do display físico (a escada por
    /// aspect ratio nunca acerta ultrawides tipo 3440×1440).
    init?(name: String, aspectWidth: Int, aspectHeight: Int, hiDPI: Bool,
          pixelModes: [(Int, Int)], maxPixelsWide: Int, maxPixelsHigh: Int) {
        self.name = name
        self.aspectWidth = aspectWidth
        self.aspectHeight = aspectHeight

        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let displayClass = NSClassFromString("CGVirtualDisplay") as? NSObject.Type,
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let modeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type
        else { return nil }

        let maxW = maxPixelsWide
        let maxH = maxPixelsHigh

        let descriptor = descriptorClass.init()
        descriptor.setValue(name, forKey: "name")
        descriptor.setValue(maxW, forKey: "maxPixelsWide")
        descriptor.setValue(maxH, forKey: "maxPixelsHigh")
        descriptor.setValue(NSValue(size: NSSize(width: 600, height: Double(600 * aspectHeight) / Double(aspectWidth))), forKey: "sizeInMillimeters")
        descriptor.setValue(0x5350, forKey: "vendorID")     // "SP"
        descriptor.setValue(0x594B, forKey: "productID")    // "YK"
        descriptor.setValue(UInt32.random(in: 1...0xFFFF), forKey: "serialNum")
        descriptor.setValue(DispatchQueue.main, forKey: "queue")

        typealias InitWithDescriptor = @convention(c) (NSObject, Selector, NSObject) -> NSObject?
        let initSel = NSSelectorFromString("initWithDescriptor:")
        guard displayClass.instancesRespond(to: initSel) else { return nil }
        let alloc = class_createInstance(displayClass, 0) as! NSObject
        let initFn = unsafeBitCast(alloc.method(for: initSel), to: InitWithDescriptor.self)
        guard let vDisplay = initFn(alloc, initSel, descriptor) else { return nil }

        // Gera modos: múltiplos do aspect ratio, HiDPI opcional
        typealias InitMode = @convention(c) (NSObject, Selector, UInt, UInt, Double) -> NSObject?
        let modeSel = NSSelectorFromString("initWithWidth:height:refreshRate:")
        var modes: [NSObject] = []
        for (w, h) in pixelModes where w >= 640 {
            let mAlloc = class_createInstance(modeClass, 0) as! NSObject
            let mInit = unsafeBitCast(mAlloc.method(for: modeSel), to: InitMode.self)
            if let mode = mInit(mAlloc, modeSel, UInt(w), UInt(h), 60) { modes.append(mode) }
        }
        guard !modes.isEmpty else { return nil }

        let settings = settingsClass.init()
        settings.setValue(hiDPI ? 1 : 0, forKey: "hiDPI")   // 1 = liga (semântica documentada em BetterDummy); sonda 12/set: 1 e 2 expõem HiDPI
        settings.setValue(modes, forKey: "modes")

        typealias ApplySettings = @convention(c) (NSObject, Selector, NSObject) -> Bool
        let applySel = NSSelectorFromString("applySettings:")
        guard vDisplay.responds(to: applySel) else { return nil }
        let applyFn = unsafeBitCast(vDisplay.method(for: applySel), to: ApplySettings.self)
        guard applyFn(vDisplay, applySel, settings) else { return nil }

        self.display = vDisplay
    }

    func destroy() { display = nil }  // soltar a referência desconecta a tela
}

@MainActor
final class VirtualDisplayService: ObservableObject {
    static let shared = VirtualDisplayService()
    @Published private(set) var screens: [VirtualScreen] = []

    /// É uma tela virtual nossa? (vendor "SP" = 0x5350, gravado no descriptor)
    /// — cobre as do PIP/stream e as do HiDPI virtual, mesmo as que já
    /// saíram de `screens` (o WindowServer ainda pode listá-las por um instante).
    func isVirtual(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayVendorNumber(id) == 0x5350 || screens.contains { $0.displayID == id }
    }

    static var isAvailable: Bool { NSClassFromString("CGVirtualDisplay") != nil }

    /// Tela virtual com tamanho de pixels explícito (base do HiDPI virtual).
    @discardableResult
    func create(name: String, pixelModes: [(Int, Int)], maxPixelsWide: Int, maxPixelsHigh: Int,
                hiDPI: Bool = true) -> VirtualScreen? {
        guard let screen = VirtualScreen(
            name: name, aspectWidth: maxPixelsWide, aspectHeight: maxPixelsHigh, hiDPI: hiDPI,
            pixelModes: pixelModes, maxPixelsWide: maxPixelsWide, maxPixelsHigh: maxPixelsHigh)
        else { return nil }
        screens.append(screen)
        return screen
    }

    @discardableResult
    func create(name: String, aspectWidth: Int = 16, aspectHeight: Int = 9, hiDPI: Bool = true) -> VirtualScreen? {
        guard let screen = VirtualScreen(name: name, aspectWidth: aspectWidth, aspectHeight: aspectHeight, hiDPI: hiDPI) else {
            return nil
        }
        screens.append(screen)
        return screen
    }

    func destroy(_ screen: VirtualScreen) {
        screen.destroy()
        screens.removeAll { $0.id == screen.id }
    }

    func destroyAll() {
        screens.forEach { $0.destroy() }
        screens.removeAll()
    }
}
