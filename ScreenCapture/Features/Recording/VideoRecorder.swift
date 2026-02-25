import Foundation
import AVFoundation
@preconcurrency import ScreenCaptureKit
import CoreMedia
import os.signpost

/// Records screen content to an MP4 file using SCStream and AVAssetWriter.
/// Streams frames directly to a temp file at 60fps - no frames held in memory.
actor VideoRecorder {
    // MARK: - Types

    /// Current state of the recorder
    enum State: Sendable {
        case idle
        case preparing
        case recording
        case stopping
    }

    // MARK: - Properties

    static let shared = VideoRecorder()

    private static let performanceLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "ScreenCapture",
        category: .pointsOfInterest
    )

    /// current recorder state
    private(set) var state: State = .idle

    /// the active SCStream delivering frames
    private var stream: SCStream?

    /// writes encoded video to disk
    private var assetWriter: AVAssetWriter?

    /// video input feeding sample buffers to the writer
    private var videoInput: AVAssetWriterInput?

    /// audio input feeding sample buffers to the writer (nil when audio disabled)
    private var audioInput: AVAssetWriterInput?

    /// whether the current recording has audio
    private var recordingHasAudio = false

    /// when recording started (for elapsed time)
    private var recordingStartTime: Date?

    /// path to the temp file being written
    private var tempFileURL: URL?

    /// display info for the current recording
    private var sourceDisplay: DisplayInfo?

    /// region being recorded (nil = full screen)
    private var sourceRegion: CGRect?

    /// output delegate that writes frames directly to the asset writer
    private var outputDelegate: StreamOutputDelegate?

    /// callback for elapsed time updates (called on main actor)
    private var onElapsedTimeUpdate: (@MainActor @Sendable (TimeInterval) -> Void)?

    /// timer for elapsed time callbacks
    private var elapsedTimeTimer: Timer?

    // MARK: - Initialization

    private init() {}

    // MARK: - Recording Lifecycle

    /// begins recording the full screen of a display
    func startFullScreenRecording(
        display: DisplayInfo,
        excludedWindowIDs: [CGWindowID] = [],
        recordAudio: Bool = true,
        onElapsedTime: @escaping @MainActor @Sendable (TimeInterval) -> Void
    ) async throws {
        try await startRecording(
            display: display,
            region: nil,
            excludedWindowIDs: excludedWindowIDs,
            recordAudio: recordAudio,
            onElapsedTime: onElapsedTime
        )
    }

    /// begins recording a region of a display
    func startRegionRecording(
        region: CGRect,
        display: DisplayInfo,
        excludedWindowIDs: [CGWindowID] = [],
        recordAudio: Bool = true,
        onElapsedTime: @escaping @MainActor @Sendable (TimeInterval) -> Void
    ) async throws {
        try await startRecording(
            display: display,
            region: region,
            excludedWindowIDs: excludedWindowIDs,
            recordAudio: recordAudio,
            onElapsedTime: onElapsedTime
        )
    }

    /// stops recording and returns the completed Recording
    func stopRecording() async throws -> Recording {
        guard state == .recording else {
            throw ScreenCaptureError.recordingError(message: "not currently recording")
        }

        state = .stopping

        // stop the stream first so no more frames arrive
        if let stream = stream {
            try? await stream.stopCapture()
        }
        stream = nil
        outputDelegate = nil

        // stop the elapsed time timer
        await stopElapsedTimeTimer()

        // finalize the asset writer
        guard let assetWriter = assetWriter,
              let videoInput = videoInput else {
            throw ScreenCaptureError.recordingError(message: "asset writer not available")
        }

        videoInput.markAsFinished()
        audioInput?.markAsFinished()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            assetWriter.finishWriting {
                continuation.resume()
            }
        }

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let hasAudio = recordingHasAudio

        guard let tempURL = tempFileURL,
              let display = sourceDisplay else {
            throw ScreenCaptureError.recordingError(message: "recording metadata lost")
        }

        let recording = Recording(
            tempFileURL: tempURL,
            captureDate: recordingStartTime ?? Date(),
            sourceDisplay: display,
            sourceRegion: sourceRegion,
            duration: duration,
            hasAudio: hasAudio
        )

        // clean up state
        self.assetWriter = nil
        self.videoInput = nil
        self.audioInput = nil
        self.recordingHasAudio = false
        self.tempFileURL = nil
        self.sourceDisplay = nil
        self.sourceRegion = nil
        self.recordingStartTime = nil
        self.onElapsedTimeUpdate = nil
        self.state = .idle

        #if DEBUG
        print("recording complete: \(String(format: "%.1f", duration))s -> \(tempURL.lastPathComponent)")
        #endif

        return recording
    }

    /// how long the current recording has been going
    var elapsedTime: TimeInterval {
        guard let startTime = recordingStartTime, state == .recording else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    /// whether a recording is in progress
    var isRecording: Bool {
        state == .recording
    }

    // MARK: - Private Implementation

    private func startRecording(
        display: DisplayInfo,
        region: CGRect?,
        excludedWindowIDs: [CGWindowID] = [],
        recordAudio: Bool = true,
        onElapsedTime: @escaping @MainActor @Sendable (TimeInterval) -> Void
    ) async throws {
        guard state == .idle else {
            throw ScreenCaptureError.recordingError(message: "recording already in progress")
        }

        state = .preparing
        self.onElapsedTimeUpdate = onElapsedTime

        do {
            // resolve the SCDisplay from the display info
            let scContent = try await SCShareableContent.current
            guard let scDisplay = scContent.displays.first(where: { $0.displayID == display.id }) else {
                throw ScreenCaptureError.displayDisconnected(displayName: display.name)
            }

            // find SCWindow objects matching the excluded window IDs
            // (e.g. the recording frame border window)
            let excludedWindows = scContent.windows.filter { scWindow in
                excludedWindowIDs.contains(scWindow.windowID)
            }

            // configure the stream
            let filter = SCContentFilter(display: scDisplay, excludingWindows: excludedWindows)
            let config = createStreamConfiguration(for: display, region: region, recordAudio: recordAudio)

            // set up the temp file and asset writer
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ScreenCapture-\(UUID().uuidString).mp4")
            let writer = try AVAssetWriter(url: tempURL, fileType: .mp4)

            let outputWidth = region != nil
                ? Int(round(region!.width * display.scaleFactor))
                : Int(display.frame.width * display.scaleFactor)
            let outputHeight = region != nil
                ? Int(round(region!.height * display.scaleFactor))
                : Int(display.frame.height * display.scaleFactor)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: outputWidth,
                AVVideoHeightKey: outputHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: outputWidth * outputHeight * 10,
                    AVVideoExpectedSourceFrameRateKey: 60,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoMaxKeyFrameIntervalKey: 60,
                ]
            ]

            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: videoSettings
            )
            input.expectsMediaDataInRealTime = true
            writer.add(input)

            // set up audio input when audio capture is enabled
            var audioWriterInput: AVAssetWriterInput?
            if recordAudio {
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128_000,
                ]
                let aInput = AVAssetWriterInput(
                    mediaType: .audio,
                    outputSettings: audioSettings
                )
                aInput.expectsMediaDataInRealTime = true
                writer.add(aInput)
                audioWriterInput = aInput
            }

            // store everything
            self.assetWriter = writer
            self.videoInput = input
            self.audioInput = audioWriterInput
            self.recordingHasAudio = recordAudio
            self.tempFileURL = tempURL
            self.sourceDisplay = display
            self.sourceRegion = region

            // create the output delegate that writes frames directly to the
            // AVAssetWriterInput on the handler queue - no actor hop needed,
            // which avoids CMSampleBuffer sendability issues and reduces latency.
            let delegate = StreamOutputDelegate(
                assetWriter: writer,
                videoInput: input,
                audioInput: audioWriterInput
            )
            self.outputDelegate = delegate

            // create and start the stream
            let scStream = SCStream(filter: filter, configuration: config, delegate: nil)
            try scStream.addStreamOutput(delegate, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))

            // register audio output when enabled
            if recordAudio {
                try scStream.addStreamOutput(delegate, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
            }

            self.stream = scStream

            // start the writer - it waits for the first sample buffer
            guard writer.startWriting() else {
                throw ScreenCaptureError.recordingError(
                    message: "asset writer failed to start: \(writer.error?.localizedDescription ?? "unknown")"
                )
            }

            // start capture
            try await scStream.startCapture()

            self.recordingStartTime = Date()
            self.state = .recording

            // start elapsed time updates
            await startElapsedTimeTimer()

            #if DEBUG
            print("recording started: \(outputWidth)x\(outputHeight) @ 60fps -> \(tempURL.lastPathComponent)")
            #endif

        } catch {
            // clean up on failure
            self.assetWriter = nil
            self.videoInput = nil
            self.audioInput = nil
            self.recordingHasAudio = false
            self.tempFileURL = nil
            self.sourceDisplay = nil
            self.sourceRegion = nil
            self.outputDelegate = nil
            self.stream = nil
            self.state = .idle
            throw error
        }
    }

    /// creates an SCStreamConfiguration for 60fps video capture
    private func createStreamConfiguration(
        for display: DisplayInfo,
        region: CGRect?,
        recordAudio: Bool = true
    ) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()

        if let region = region {
            // region recording
            config.sourceRect = CGRect(
                x: round(region.origin.x),
                y: round(region.origin.y),
                width: round(region.width),
                height: round(region.height)
            )
            config.width = Int(round(region.width * display.scaleFactor))
            config.height = Int(round(region.height * display.scaleFactor))
        } else {
            // full screen recording
            config.width = Int(display.frame.width * display.scaleFactor)
            config.height = Int(display.frame.height * display.scaleFactor)
        }

        // 60fps video capture
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.colorSpaceName = CGColorSpace.sRGB

        // audio capture via ScreenCaptureKit's built-in system audio support
        if recordAudio {
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
        }

        return config
    }

    // MARK: - Elapsed Time Timer

    private func startElapsedTimeTimer() async {
        let callback = self.onElapsedTimeUpdate
        await MainActor.run {
            let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task {
                    let elapsed = await self.elapsedTime
                    await callback?(elapsed)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            Task { await self.storeTimer(timer) }
        }
    }

    private func storeTimer(_ timer: Timer) {
        self.elapsedTimeTimer = timer
    }

    private func stopElapsedTimeTimer() async {
        let timer = self.elapsedTimeTimer
        self.elapsedTimeTimer = nil
        // Timer is not Sendable but we're just invalidating it on the main thread
        // where it was originally created - safe to transfer.
        nonisolated(unsafe) let timerToInvalidate = timer
        await MainActor.run {
            timerToInvalidate?.invalidate()
        }
    }
}

// MARK: - Stream Output Delegate

/// Handles SCStream frame delivery and writes directly to AVAssetWriterInput.
/// Owns the writer session start and frame append to avoid crossing actor boundaries
/// with non-Sendable CMSampleBuffer objects.
private final class StreamOutputDelegate: NSObject, SCStreamOutput, @unchecked Sendable {
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private var hasStartedSession = false

    init(
        assetWriter: AVAssetWriter,
        videoInput: AVAssetWriterInput,
        audioInput: AVAssetWriterInput? = nil
    ) {
        self.assetWriter = assetWriter
        self.videoInput = videoInput
        self.audioInput = audioInput
        super.init()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid else { return }

        // start the asset writer session on the first video frame's timestamp
        if !hasStartedSession, type == .screen {
            guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter.startSession(atSourceTime: timestamp)
            hasStartedSession = true
        }

        guard hasStartedSession else { return }

        if type == .screen {
            guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil,
                  videoInput.isReadyForMoreMediaData else { return }
            videoInput.append(sampleBuffer)
        }

        if type == .audio {
            guard let audioInput = audioInput,
                  audioInput.isReadyForMoreMediaData else { return }
            audioInput.append(sampleBuffer)
        }
    }
}
