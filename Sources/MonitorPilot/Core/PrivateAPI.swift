import Foundation
import CoreGraphics

enum PrivateAPI {
    private static let handles: [UnsafeMutableRawPointer?] = [
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
        dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY),
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY),
    ]

    static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        _ = handles
        guard let sym = dlsym(dlopen(nil, RTLD_LAZY), name) ?? handles
            .compactMap({ $0 })
            .lazy
            .compactMap({ dlsym($0, name) })
            .first
        else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    typealias DSGetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias DSSetBrightness = @convention(c) (UInt32, Float) -> Int32
    typealias DSCanChange = @convention(c) (UInt32) -> Bool

    static let dsGetBrightness = symbol("DisplayServicesGetBrightness", as: DSGetBrightness.self)
    static let dsSetBrightness = symbol("DisplayServicesSetBrightness", as: DSSetBrightness.self)
    static let dsCanChangeBrightness = symbol("DisplayServicesCanChangeBrightness", as: DSCanChange.self)

    typealias DSAmbientEnabled = @convention(c) (UInt32, UnsafeMutablePointer<Bool>) -> Int32
    typealias DSAmbientSet = @convention(c) (UInt32, Bool) -> Int32
    typealias DSAmbientHas = @convention(c) (UInt32) -> Bool

    static let dsAmbientEnabled = symbol(
        "DisplayServicesAmbientLightCompensationEnabled", as: DSAmbientEnabled.self)
    static let dsSetAmbient = symbol(
        "DisplayServicesEnableAmbientLightCompensation", as: DSAmbientSet.self)
    static let dsHasAmbient = symbol(
        "DisplayServicesHasAmbientLightCompensation", as: DSAmbientHas.self)

    typealias IOAVCreateWithService = @convention(c) (CFAllocator?, UInt32) -> Unmanaged<CFTypeRef>?
    typealias IOAVI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32

    static let ioavCreateWithService = symbol("IOAVServiceCreateWithService", as: IOAVCreateWithService.self)
    static let ioavReadI2C = symbol("IOAVServiceReadI2C", as: IOAVI2C.self)
    static let ioavWriteI2C = symbol("IOAVServiceWriteI2C", as: IOAVI2C.self)

    typealias CGSMainConnection = @convention(c) () -> Int32
    typealias CGSConfigureDisplayEnabled = @convention(c) (CGDisplayConfigRef?, UInt32, Bool) -> CGError
    typealias SLSHDRSupported = @convention(c) (Int32, UInt32) -> Bool
    typealias SLSHDREnabled = @convention(c) (Int32, UInt32) -> Bool
    typealias SLSSetHDREnabled = @convention(c) (Int32, UInt32, Bool) -> Int32

    static let slsMainConnectionID = symbol("SLSMainConnectionID", as: CGSMainConnection.self)
    static let cgsConfigureDisplayEnabled = symbol("CGSConfigureDisplayEnabled", as: CGSConfigureDisplayEnabled.self)
    static let slsDisplaySupportsHDRMode = symbol("SLSDisplaySupportsHDRMode", as: SLSHDRSupported.self)
    static let slsDisplayIsHDRModeEnabled = symbol("SLSDisplayIsHDRModeEnabled", as: SLSHDREnabled.self)
    static let slsDisplaySetHDRModeEnabled = symbol("SLSDisplaySetHDRModeEnabled", as: SLSSetHDREnabled.self)
}
