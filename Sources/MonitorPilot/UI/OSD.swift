import SwiftUI
import AppKit

/// OSD estilo Apple: painel flutuante com material, ícone SF Symbol e barra de nível.
@MainActor
enum OSD {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(icon: String, value: Float, title: String) {
        let content = OSDView(icon: icon, value: value, title: title)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 200)

        let panel = self.panel ?? {
            let p = NSPanel(
                contentRect: hosting.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            p.level = .screenSaver
            p.isOpaque = false
            p.backgroundColor = .clear
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = p
            return p
        }()

        panel.contentView = hosting
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 100, y: f.minY + f.height * 0.12))
        }
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }
}

private struct OSDView: View {
    let icon: String
    let value: Float
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.primary.opacity(0.85))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(.primary.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
                }
            }
            .frame(width: 120, height: 7)
        }
        .padding(24)
        .frame(width: 200, height: 200)
        .modifier(OSDBackground())
    }
}

private struct OSDBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}
