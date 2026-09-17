import Foundation

/// Cálculo puro do par (tela virtual, resolução lógica) usado pra dar HiDPI a
/// um display que não tem modo HiDPI nativo: cria-se uma tela virtual do
/// tamanho de pixels nativo e espelha-se o físico nela, rodando em 2×.
/// Limite horizontal do framebuffer (análise §5): 6144 px em Apple Silicon
/// base, 7680 px em Pro/Max/Ultra.
enum HiDPIPlanner {
    static let baseCap = 6144
    static let proCap = 7680

    /// Teto desta máquina, lido do modelo de CPU (`hw.model` / brand string).
    static var machineCap: Int {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        let brand = String(cString: buf)
        let pro = ["Pro", "Max", "Ultra"].contains { brand.contains($0) }
        return pro ? proCap : baseCap
    }

    /// Tamanho da tela virtual (pixels) e a resolução lógica 2× resultante.
    /// Mantém o aspect ratio; nunca ultrapassa o teto horizontal nem o
    /// equivalente vertical; largura/altura sempre pares (2× exato).
    /// `supersample`: a virtual nasce com o DOBRO dos pixels do painel e o
    /// físico espelha em downscale — a resolução lógica fica IGUAL à nativa,
    /// só que renderizada em 2× (Dell 1080×1920 → lógico 1080×1920 nítido,
    /// virtual 2160×3840). É o "Alta Resolução" do BetterDisplay pra painéis
    /// 1080p. Sem supersample, a virtual tem o tamanho nativo e a lógica é a metade.
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
