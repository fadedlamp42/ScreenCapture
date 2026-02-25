import AppKit
import AVKit
import SwiftUI

/// Preview window for a completed recording.
/// Provides video playback, trim controls, save, and copy to clipboard.
@MainActor
final class VideoPreviewWindow: NSPanel {
    // MARK: - Properties

    let viewModel: VideoPreviewViewModel
    private var hostingView: NSHostingView<VideoPreviewContentView>?

    // MARK: - Initialization

    init(recording: Recording) {
        self.viewModel = VideoPreviewViewModel(recording: recording)

        let windowSize = Self.calculateWindowSize(for: recording)

        super.init(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configureWindow()
        setupHostingView()
        center()
    }

    // MARK: - Configuration

    private func configureWindow() {
        title = "Recording Preview"
        level = .floating
        minSize = NSSize(width: 500, height: 380)
        maxSize = NSSize(width: 3000, height: 2000)
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces]
    }

    private func setupHostingView() {
        let content = VideoPreviewContentView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
        self.hostingView = hosting
    }

    private static func calculateWindowSize(for recording: Recording) -> NSSize {
        // try to fit the video at a reasonable size
        guard let screen = NSScreen.main else {
            return NSSize(width: 800, height: 550)
        }

        let maxWidth = screen.visibleFrame.width * 0.7
        let maxHeight = screen.visibleFrame.height * 0.7

        // get video dimensions from the asset
        let asset = AVURLAsset(url: recording.tempFileURL)
        let tracks = asset.tracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            return NSSize(width: 800, height: 550)
        }

        let naturalSize = videoTrack.naturalSize
        let aspectRatio = naturalSize.width / naturalSize.height

        // extra height for the trim UI and info bar
        let chromeHeight: CGFloat = 120

        var width = min(naturalSize.width, maxWidth)
        var height = width / aspectRatio + chromeHeight

        if height > maxHeight {
            height = maxHeight
            width = (height - chromeHeight) * aspectRatio
        }

        return NSSize(
            width: max(500, width),
            height: max(380, height)
        )
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            close()
        case 36: // Enter - save
            viewModel.saveRecording()
        default:
            // Cmd+S to save, Cmd+C to copy
            if event.modifierFlags.contains(.command) {
                if event.charactersIgnoringModifiers == "s" {
                    viewModel.saveRecording()
                    return
                }
                if event.charactersIgnoringModifiers == "c" {
                    viewModel.copyToClipboard()
                    return
                }
            }
            super.keyDown(with: event)
        }
    }

    override func close() {
        viewModel.cleanup()
        super.close()
    }
}

// MARK: - Window Controller

/// manages the video preview window lifecycle, parallel to PreviewWindowController
@MainActor
final class VideoPreviewWindowController {
    static let shared = VideoPreviewWindowController()

    private var previewWindow: VideoPreviewWindow?

    private init() {}

    /// shows a preview for the given recording
    func showPreview(
        for recording: Recording,
        onSave: ((URL) -> Void)? = nil
    ) {
        closePreview()

        let window = VideoPreviewWindow(recording: recording)
        window.viewModel.onSave = onSave
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.previewWindow = window
    }

    /// closes the current preview
    func closePreview() {
        previewWindow?.close()
        previewWindow = nil
    }
}

// MARK: - View Model

@MainActor
@Observable
final class VideoPreviewViewModel {
    // MARK: - State

    var recording: Recording
    var isSaving = false
    var isTrimming = false
    var statusMessage: String?

    /// trim range (0.0 to 1.0, normalized to duration)
    var trimStartNormalized: Double = 0.0
    var trimEndNormalized: Double = 1.0

    /// whether the trim range has been modified
    var hasTrimChanges: Bool {
        trimStartNormalized > 0.001 || trimEndNormalized < 0.999
    }

    @ObservationIgnored
    var onSave: ((URL) -> Void)?

    @ObservationIgnored
    private let exporter = VideoExporter.shared

    // MARK: - Computed

    var trimStartTime: TimeInterval {
        recording.duration * trimStartNormalized
    }

    var trimEndTime: TimeInterval {
        recording.duration * trimEndNormalized
    }

    var trimmedDuration: TimeInterval {
        trimEndTime - trimStartTime
    }

    var formattedTrimmedDuration: String {
        let totalSeconds = Int(trimmedDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    // MARK: - Initialization

    init(recording: Recording) {
        self.recording = recording
    }

    // MARK: - Actions

    func saveRecording() {
        guard !isSaving else { return }
        isSaving = true
        statusMessage = nil

        Task {
            do {
                // trim first if needed
                var recordingToSave = recording
                if hasTrimChanges {
                    statusMessage = "trimming..."
                    recordingToSave = try await exporter.trim(
                        recording,
                        from: trimStartTime,
                        to: trimEndTime
                    )
                    self.recording = recordingToSave
                }

                statusMessage = "saving..."
                let savedURL = try await exporter.save(recordingToSave)
                self.recording = recordingToSave.saved(to: savedURL)

                statusMessage = "saved"
                onSave?(savedURL)

                // dismiss after a brief pause
                try? await Task.sleep(for: .milliseconds(500))
                VideoPreviewWindowController.shared.closePreview()

            } catch {
                statusMessage = "save failed: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }

    func copyToClipboard() {
        Task {
            do {
                // trim first if needed
                var recordingToCopy = recording
                if hasTrimChanges {
                    statusMessage = "trimming..."
                    recordingToCopy = try await exporter.trim(
                        recording,
                        from: trimStartTime,
                        to: trimEndTime
                    )
                    self.recording = recordingToCopy
                }

                // saves to output directory first, then puts that URL on clipboard
                statusMessage = "saving & copying..."
                let savedURL = try await exporter.copyToClipboard(recordingToCopy)
                self.recording = recordingToCopy.saved(to: savedURL)
                onSave?(savedURL)

                statusMessage = "copied to clipboard"

                try? await Task.sleep(for: .milliseconds(800))
                VideoPreviewWindowController.shared.closePreview()

            } catch {
                statusMessage = "copy failed: \(error.localizedDescription)"
            }
        }
    }

    func resetTrim() {
        trimStartNormalized = 0.0
        trimEndNormalized = 1.0
    }

    func cleanup() {
        // don't delete the temp file if it was saved - the saved copy is separate
        if !recording.isSaved {
            recording.cleanupTempFile()
        }
    }
}

// MARK: - SwiftUI Content

struct VideoPreviewContentView: View {
    @Bindable var viewModel: VideoPreviewViewModel

    var body: some View {
        VStack(spacing: 0) {
            // video player
            VideoPlayerView(url: viewModel.recording.tempFileURL)
                .frame(minHeight: 200)

            Divider()

            // trim controls
            trimBar

            Divider()

            // info + action bar
            infoBar
        }
    }

    // MARK: - Trim Bar

    private var trimBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Trim")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                if viewModel.hasTrimChanges {
                    Button("Reset") {
                        viewModel.resetTrim()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }

            // trim range slider
            TrimRangeSlider(
                startValue: $viewModel.trimStartNormalized,
                endValue: $viewModel.trimEndNormalized,
                duration: viewModel.recording.duration
            )

            HStack {
                Text(formatTime(viewModel.trimStartTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Text(viewModel.formattedTrimmedDuration)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))

                Spacer()

                Text(formatTime(viewModel.trimEndTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Info Bar

    private var infoBar: some View {
        HStack {
            // left: recording info
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.recording.formattedDuration) - \(viewModel.recording.formattedFileSize)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // right: action buttons
            HStack(spacing: 8) {
                Button(action: { viewModel.copyToClipboard() }) {
                    Label("Copy", systemImage: "doc.on.clipboard")
                }
                .help("Copy to Clipboard (Cmd+C)")

                Button(action: { viewModel.saveRecording() }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .help("Save Recording (Cmd+S)")
                .disabled(viewModel.isSaving)

                Button(action: {
                    VideoPreviewWindowController.shared.closePreview()
                }) {
                    Label("Dismiss", systemImage: "xmark")
                }
                .help("Dismiss (Esc)")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        let tenths = Int((seconds - Double(totalSeconds)) * 10)
        return String(format: "%d:%02d.%d", minutes, secs, tenths)
    }
}

// MARK: - Video Player (AVPlayerView wrapper)

/// wraps AVPlayerView in an NSViewRepresentable for SwiftUI
struct VideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        let player = AVPlayer(url: url)
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = false
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

// MARK: - Trim Range Slider

/// dual-handle slider for selecting a trim range
struct TrimRangeSlider: View {
    @Binding var startValue: Double
    @Binding var endValue: Double
    let duration: TimeInterval

    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false

    private let handleWidth: CGFloat = 12
    private let trackHeight: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let startX = startValue * totalWidth
            let endX = endValue * totalWidth

            ZStack(alignment: .leading) {
                // track background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: trackHeight)

                // selected range highlight
                Rectangle()
                    .fill(Color.accentColor.opacity(0.25))
                    .frame(
                        width: max(0, endX - startX),
                        height: trackHeight
                    )
                    .offset(x: startX)

                // start handle
                trimHandle(at: startX, isDragging: isDraggingStart)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingStart = true
                                let newValue = max(0, min(value.location.x / totalWidth, endValue - 0.01))
                                startValue = newValue
                            }
                            .onEnded { _ in isDraggingStart = false }
                    )

                // end handle
                trimHandle(at: endX - handleWidth, isDragging: isDraggingEnd)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingEnd = true
                                let newValue = min(1.0, max(value.location.x / totalWidth, startValue + 0.01))
                                endValue = newValue
                            }
                            .onEnded { _ in isDraggingEnd = false }
                    )
            }
        }
        .frame(height: trackHeight)
    }

    private func trimHandle(at xOffset: CGFloat, isDragging: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(isDragging ? Color.accentColor : Color.white)
            .frame(width: handleWidth, height: trackHeight)
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
            )
            .offset(x: xOffset)
    }
}
