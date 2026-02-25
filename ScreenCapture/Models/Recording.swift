import Foundation
import CoreGraphics

/// Represents a completed screen recording with metadata.
/// Parallel to Screenshot - same idea, different media type.
struct Recording: Identifiable, Sendable {
    /// unique identifier for this recording
    let id: UUID

    /// path to the temp MP4 file (before user saves)
    let tempFileURL: URL

    /// when the recording started
    let captureDate: Date

    /// display from which this was recorded
    let sourceDisplay: DisplayInfo

    /// region that was recorded (nil = full screen)
    let sourceRegion: CGRect?

    /// total duration in seconds
    let duration: TimeInterval

    /// saved file location (nil until user saves)
    var filePath: URL?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        tempFileURL: URL,
        captureDate: Date = Date(),
        sourceDisplay: DisplayInfo,
        sourceRegion: CGRect? = nil,
        duration: TimeInterval,
        filePath: URL? = nil
    ) {
        self.id = id
        self.tempFileURL = tempFileURL
        self.captureDate = captureDate
        self.sourceDisplay = sourceDisplay
        self.sourceRegion = sourceRegion
        self.duration = duration
        self.filePath = filePath
    }

    // MARK: - Computed Properties

    /// formatted duration string (e.g., "0:05", "1:23")
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    /// whether the temp file still exists
    var tempFileExists: Bool {
        FileManager.default.fileExists(atPath: tempFileURL.path)
    }

    /// whether this recording has been saved to a permanent location
    var isSaved: Bool {
        filePath != nil
    }

    /// file size of the temp file in bytes
    var fileSize: Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: tempFileURL.path)
        return (attributes?[.size] as? Int) ?? 0
    }

    /// formatted file size (e.g., "1.2 MB")
    var formattedFileSize: String {
        let bytes = fileSize
        if bytes < 1024 {
            return "\(bytes) B"
        }
        if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        }
        return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
    }

    // MARK: - State Transitions

    /// creates a copy with the saved file path set
    func saved(to url: URL) -> Recording {
        var copy = self
        copy.filePath = url
        return copy
    }

    /// cleans up the temp file. call when recording is discarded without saving.
    func cleanupTempFile() {
        try? FileManager.default.removeItem(at: tempFileURL)
    }
}
