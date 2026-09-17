/// Decide se o HDR salvo precisa ser reaplicado — puro, sem tocar em display real.
enum HDRPolicy {
    /// `saved` = valor gerenciado em config (nil = não gerenciado, não mexe).
    /// `current` = estado real lido do display.
    /// Devolve o valor a aplicar, ou nil quando não há o que fazer
    /// (não gerenciado, ou já bate com o estado atual).
    static func shouldApply(saved: Bool?, current: Bool) -> Bool? {
        guard let saved else { return nil }
        return saved == current ? nil : saved
    }
}
