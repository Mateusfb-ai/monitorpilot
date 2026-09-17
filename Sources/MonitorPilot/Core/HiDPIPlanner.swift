import Foundation

enum HiDPIPlanner {
    static let baseCap = 6144
    static let proCap = 7680

    static var machineCap: Int {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        let brand = String(cString: buf)
        let pro = ["Pro", "Max", "Ultra"].contains { brand.contains($0) }
        return pro ? proCap : baseCap
    }

    static func plan(nativeW: Int, nativeH: Int, cap: Int = baseCap, supersample: Bool = false)
        -> (virtualW: Int, virtualH: Int, logicalW: Int, logicalH: Int)
    {
        guard nativeW > 0, nativeH > 0 else { return (0, 0, 0, 0) }
        let f = supersample ? 2.0 : 1.0
        var w = Double(nativeW) * f
        var h = Double(nativeH) * f
        let capD = Double(cap)
        if w > capD {
            h *= capD / w
            w = capD
        }
        if h > capD {
            w *= capD / h
            h = capD
        }
        let vw = max(2, Int(w.rounded(.down)) & ~1)
        let vh = max(2, Int(h.rounded(.down)) & ~1)
        return (vw, vh, vw / 2, vh / 2)
    }
}
