import SwiftUI

extension View {
    @ViewBuilder
    func monitorpilotGlassCard(cornerRadius: CGFloat = 14) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func monitorpilotGlassControl(cornerRadius: CGFloat = 10) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

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
