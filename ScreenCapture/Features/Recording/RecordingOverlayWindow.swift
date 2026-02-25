import AppKit
import SwiftUI

/// Floating panel that shows a stop button and elapsed timer during recording.
/// Sits in the top-right corner of the recording display, always on top.
@MainActor
final class RecordingOverlayWindow: NSPanel {
    // MARK: - Properties

    private var elapsedTime: TimeInterval = 0
    private var hostingView: NSHostingView<RecordingOverlayContent>?
    private let onStop: () -> Void

    // MARK: - Initialization

    init(display: DisplayInfo, onStop: @escaping () -> Void) {
        self.onStop = onStop

        // small floating panel
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configureWindow()
        positionOnDisplay(display)
        setupContent()
    }

    // MARK: - Configuration

    private func configureWindow() {
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true

        // don't steal focus from the app being recorded
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
    }

    private func positionOnDisplay(_ display: DisplayInfo) {
        guard let screen = display.matchingScreen else {
            // fallback: position on main screen
            if let mainScreen = NSScreen.main {
                let screenFrame = mainScreen.visibleFrame
                let windowFrame = frame
                let originX = screenFrame.maxX - windowFrame.width - 16
                let originY = screenFrame.maxY - windowFrame.height - 16
                setFrameOrigin(NSPoint(x: originX, y: originY))
            }
            return
        }

        let screenFrame = screen.visibleFrame
        let windowFrame = frame
        let originX = screenFrame.maxX - windowFrame.width - 16
        let originY = screenFrame.maxY - windowFrame.height - 16
        setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func setupContent() {
        let content = RecordingOverlayContent(
            elapsedTime: elapsedTime,
            onStop: onStop
        )
        let hosting = NSHostingView(rootView: content)
        hosting.frame = contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        contentView?.addSubview(hosting)
        self.hostingView = hosting
    }

    // MARK: - Public API

    /// updates the displayed elapsed time
    func updateElapsedTime(_ time: TimeInterval) {
        elapsedTime = time
        let content = RecordingOverlayContent(
            elapsedTime: time,
            onStop: onStop
        )
        hostingView?.rootView = content
    }
}

// MARK: - Recording Overlay Controller

/// manages the recording overlay window lifecycle
@MainActor
final class RecordingOverlayController {
    static let shared = RecordingOverlayController()

    private var overlayWindow: RecordingOverlayWindow?

    private init() {}

    /// shows the recording overlay on the given display
    func show(on display: DisplayInfo, onStop: @escaping () -> Void) {
        dismiss()

        let window = RecordingOverlayWindow(display: display, onStop: onStop)
        window.orderFrontRegardless()
        self.overlayWindow = window
    }

    /// updates the elapsed time display
    func updateElapsedTime(_ time: TimeInterval) {
        overlayWindow?.updateElapsedTime(time)
    }

    /// dismisses the recording overlay
    func dismiss() {
        overlayWindow?.close()
        overlayWindow = nil
    }

    /// the CGWindowID of the overlay window, for excluding from SCStream
    var currentWindowID: CGWindowID? {
        guard let window = overlayWindow else { return nil }
        return CGWindowID(window.windowNumber)
    }
}

// MARK: - SwiftUI Content

/// the actual content of the recording overlay: a red dot, timer, and stop button
private struct RecordingOverlayContent: View {
    let elapsedTime: TimeInterval
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // pulsing red recording indicator
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .shadow(color: .red.opacity(0.6), radius: 4)

            // elapsed time
            Text(formattedTime)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white)

            Divider()
                .frame(height: 20)

            // stop button
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .help("Stop Recording")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var formattedTime: String {
        let totalSeconds = Int(elapsedTime)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let tenths = Int((elapsedTime - Double(totalSeconds)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}
