import SwiftUI

// Liquid Glass (macOS 26 Tahoe) com fallback de material pra macOS 14-15.
// Regra da skill: glass em CONTROLES e superfícies de navegação, nunca em conteúdo.

extension View {
    /// Card de controle com Liquid Glass (fallback: material).
    @ViewBuilder
    func monitorpilotGlassCard(cornerRadius: CGFloat = 14) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Glass interativo pra controles clicáveis (fallback: material + hover nada).
    @ViewBuilder
    func monitorpilotGlassControl(cornerRadius: CGFloat = 10) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

/// Botão de ícone com Liquid Glass (footer do popover).
struct GlassIconButton: View {
    let systemImage: String
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                Button(action: action) {
                    Image(systemName: systemImage).frame(width: 24, height: 24)
                }
                .buttonStyle(.glass)
            } else {
                Button(action: action) {
                    Image(systemName: systemImage).frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
            }
        }
        .help(help)
    }
}
