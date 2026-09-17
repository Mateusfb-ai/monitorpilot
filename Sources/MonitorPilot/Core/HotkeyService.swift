import Foundation
import Carbon.HIToolbox
import AppKit

@MainActor
enum HotkeyService {
    struct Hotkey {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let action: () -> Void
    }

    private static var hotkeys: [UInt32: Hotkey] = [:]
    private static var refs: [EventHotKeyRef?] = []
    private static var handlerInstalled = false

    static func registerDefaults(step: Float = 0.0625) {
        register(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(optionKey | cmdKey)) {
            adjustBrightness(+step, target: .main)
        }
        register(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(optionKey | cmdKey)) {
            adjustBrightness(-step, target: .main)
        }
        register(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(optionKey | cmdKey)) {
            adjustBrightness(+step, target: .withMouse)
        }
        register(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(optionKey | cmdKey)) {
            adjustBrightness(-step, target: .withMouse)
        }
    }

    private enum Target { case main, withMouse }

    static var setBrightnessHook: ((CGDirectDisplayID, Float) -> Void)?

    private static func adjustBrightness(_ delta: Float, target: Target) {
        let display: DisplayInfo? = switch target {
        case .main:
            DisplayManager.onlineDisplays().first(where: \.isMain)
        case .withMouse:
            displayWithMouse()
        }
        guard let display else { return }
        let current = BrightnessService.brightness(display.id)
        let next = min(max(current + delta, 0), 1)
        if let hook = setBrightnessHook {
            hook(display.id, next)
        } else {
            BrightnessService.setBrightness(display.id, next)
        }
        OSD.show(icon: "sun.max.fill", value: next, title: display.name)
    }

    private static func displayWithMouse() -> DisplayInfo? {
        let mouse = NSEvent.mouseLocation
        let all = DisplayManager.onlineDisplays()
        for screen in NSScreen.screens where NSMouseInRect(mouse, screen.frame, false) {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            if let num = screen.deviceDescription[key] as? NSNumber,
               let match = all.first(where: { $0.id == num.uint32Value }) {
                return match
            }
        }
        return all.first(where: \.isMain)
    }

    static func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        let id = UInt32(hotkeys.count + 1)
        var hotKeyID = EventHotKeyID(signature: OSType(0x53504B44) , id: id)
        var ref: EventHotKeyRef?
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref) == noErr else {
            return
        }
        hotkeys[id] = Hotkey(id: id, keyCode: keyCode, modifiers: modifiers, action: action)
        refs.append(ref)
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            Task { @MainActor in
                HotkeyService.hotkeys[hotKeyID.id]?.action()
            }
            return noErr
        }, 1, &eventType, nil, nil)
        handlerInstalled = true
    }
}
