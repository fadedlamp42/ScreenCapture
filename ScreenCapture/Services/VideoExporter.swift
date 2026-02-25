import Foundation
import AVFoundation
import AppKit

/// Handles saving recordings to disk, copying to clipboard, and trimming.
/// Uses AVAssetExportSession for trim operations (fast copy, no re-encode).
struct VideoExporter: Sendable {
    static let shared = VideoExporter()

    // MARK: - Save

    /// saves a recording to the user's configured save location
    func save(_ recording: Recording, muteAudio: Bool = false) async throws -> URL {
        let settings = await MainActor.run { AppSettings.shared }
        let saveLocation = await MainActor.run { settings.saveLocation }
        let destinationURL = generateFileURL(in: saveLocation)

        // verify the directory is writable
        let directory = destinationURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            throw ScreenCaptureError.invalidSaveLocation(directory)
        }

        if muteAudio && recording.hasAudio {
            // re-export with audio stripped
            try await exportStrippingAudio(from: recording.tempFileURL, to: destinationURL)
        } else {
            // straight copy — preserves audio as-is
            try FileManager.default.copyItem(at: recording.tempFileURL, to: destinationURL)
        }

        #if DEBUG
        print("recording saved: \(destinationURL.lastPathComponent)")
        #endif

        return destinationURL
    }

    /// saves a recording to a specific URL
    func save(_ recording: Recording, to url: URL, muteAudio: Bool = false) async throws -> URL {
        if muteAudio && recording.hasAudio {
            try await exportStrippingAudio(from: recording.tempFileURL, to: url)
        } else {
            try FileManager.default.copyItem(at: recording.tempFileURL, to: url)
        }
        return url
    }

    // MARK: - Clipboard

    /// saves the recording to the output directory then copies its URL to the clipboard.
    /// receiving apps (slack, discord, etc.) read the file as a video attachment.
    /// we save first because:
    ///   - temp files get cleaned up when the preview closes
    ///   - pasting an empty/deleted file results in 0B uploads
    ///   - the saved file gets a nice "Recording YYYY-MM-DD at HH.mm.ss.mp4" name
    func copyToClipboard(_ recording: Recording, muteAudio: Bool = false) async throws -> URL {
        // save to the output directory so the file persists after preview closes
        let savedURL = try await save(recording, muteAudio: muteAudio)

        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([savedURL as NSURL])
        }

        return savedURL
    }

    // MARK: - Trim

    /// trims a recording to the given time range.
    /// uses AVAssetExportSession with passthrough (no re-encode) for speed.
    func trim(
        _ recording: Recording,
        from startTime: TimeInterval,
        to endTime: TimeInterval
    ) async throws -> Recording {
        let asset = AVURLAsset(url: recording.tempFileURL)

        let trimmedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenCapture-trimmed-\(UUID().uuidString).mp4")

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw ScreenCaptureError.recordingError(message: "failed to create export session")
        }

        let startCMTime = CMTime(seconds: startTime, preferredTimescale: 600)
        let endCMTime = CMTime(seconds: endTime, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startCMTime, end: endCMTime)

        exportSession.outputURL = trimmedURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = timeRange

        await exportSession.export()

        guard exportSession.status == .completed else {
            let errorMessage = exportSession.error?.localizedDescription ?? "unknown trim error"
            throw ScreenCaptureError.recordingError(message: "trim failed: \(errorMessage)")
        }

        let trimmedDuration = endTime - startTime

        // clean up the original temp file
        recording.cleanupTempFile()

        let trimmedRecording = Recording(
            tempFileURL: trimmedURL,
            captureDate: recording.captureDate,
            sourceDisplay: recording.sourceDisplay,
            sourceRegion: recording.sourceRegion,
            duration: trimmedDuration
        )

        #if DEBUG
        print("recording trimmed: \(String(format: "%.1f", recording.duration))s -> \(String(format: "%.1f", trimmedDuration))s")
        #endif

        return trimmedRecording
    }

    // MARK: - Audio Stripping

    /// re-exports a video file with only the video track, dropping all audio.
    /// uses AVMutableComposition for a fast passthrough re-mux (no re-encode).
    private func exportStrippingAudio(from sourceURL: URL, to destinationURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()

        // load video tracks from the source asset
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw ScreenCaptureError.recordingError(message: "no video track found in recording")
        }

        // add only the video track to the composition — audio is intentionally omitted
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ScreenCaptureError.recordingError(message: "failed to create composition track")
        }

        let duration = try await asset.load(.duration)
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try compositionVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)

        // export with passthrough (no re-encode)
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw ScreenCaptureError.recordingError(message: "failed to create export session for muting")
        }

        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .mp4

        await exportSession.export()

        guard exportSession.status == .completed else {
            let errorMessage = exportSession.error?.localizedDescription ?? "unknown mute export error"
            throw ScreenCaptureError.recordingError(message: "mute export failed: \(errorMessage)")
        }
    }

    // MARK: - Filename Generation

    /// generates a unique filename in the "Recording YYYY-MM-DD at HH.mm.ss.mp4" format
    func generateFileURL(in directory: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let datePart = formatter.string(from: Date())

        formatter.dateFormat = "HH.mm.ss"
        let timePart = formatter.string(from: Date())

        let baseName = "Recording \(datePart) at \(timePart)"
        var url = directory.appendingPathComponent("\(baseName).mp4")

        // collision avoidance
        var counter = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(baseName) (\(counter)).mp4")
            counter += 1
        }

        return url
    }
}
