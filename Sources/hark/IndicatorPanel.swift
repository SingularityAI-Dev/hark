import AppKit
import SwiftUI

final class IndicatorModel: ObservableObject {
    enum Phase: Equatable {
        case listening, locked, processing
        case message(String)
    }

    @Published var phase: Phase = .listening
    @Published var level: Float = 0
    @Published var polish = false
}

/// A small floating pill near the bottom of the screen. It never takes focus, so the app
/// being dictated into keeps the cursor.
@MainActor
final class IndicatorPanel {
    let model = IndicatorModel()
    private let panel: NSPanel
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: IndicatorView(model: model))
    }

    func show(_ phase: IndicatorModel.Phase) {
        hideWork?.cancel()
        model.phase = phase
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 60))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
        model.level = 0
    }

    /// Shows a short message, then hides.
    func flash(_ message: String, seconds: TimeInterval = 2.5) {
        show(.message(message))
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

private struct IndicatorView: View {
    @ObservedObject var model: IndicatorModel

    var body: some View {
        HStack(spacing: 8) {
            switch model.phase {
            case .listening, .locked:
                Image(systemName: model.phase == .locked ? "lock.fill" : "mic.fill")
                    .foregroundStyle(.red)
                LevelBars(level: model.level)
                Text(model.phase == .locked ? "Hands-free" : "Listening")
                if model.polish { Image(systemName: "sparkles") }
            case .processing:
                ProgressView().controlSize(.small)
                Text(model.polish ? "Polishing" : "Cleaning up")
            case .message(let text):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(text).lineLimit(1)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(.black.opacity(0.82)))
    }
}

private struct LevelBars: View {
    let level: Float
    private static let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.8, 0.5]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.weights.indices, id: \.self) { index in
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: 4 + 14 * CGFloat(level) * Self.weights[index])
            }
        }
        .frame(height: 18)
        .animation(.linear(duration: 0.08), value: level)
    }
}
