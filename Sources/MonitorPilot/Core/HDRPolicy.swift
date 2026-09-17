enum HDRPolicy {
    static func shouldApply(saved: Bool?, current: Bool) -> Bool? {
        guard let saved else { return nil }
        return saved == current ? nil : saved
    }
}
