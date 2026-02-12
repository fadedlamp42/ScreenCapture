import Foundation
import Vision
import CoreGraphics

/// Actor responsible for performing OCR (Optical Character Recognition) operations.
/// Uses Vision framework's VNRecognizeTextRequest for text recognition.
actor OCRManager {
    // MARK: - Types

    /// Recognition level for OCR processing
    enum RecognitionLevel {
        case accurate
        case fast

        var visionLevel: VNRequestTextRecognitionLevel {
            switch self {
            case .accurate: return .accurate
            case .fast: return .fast
            }
        }
    }

    // MARK: - Properties

    /// Shared instance for app-wide OCR operations
    static let shared = OCRManager()

    /// Minimum confidence threshold for text recognition (0.0-1.0)
    private let minimumConfidence: Float = 0.1

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Recognizes text in given image using Vision framework.
    /// - Parameters:
    ///   - image: The CGImage to analyze
    ///   - languages: Array of language codes (e.g., ["en-US"]) in priority order
    ///   - level: Recognition level (accurate or fast)
    ///   - usesLanguageCorrection: Whether to apply language correction
    /// - Returns: Array of TextRegion with recognized text and positions
    /// - Throws: Vision errors or processing errors
    func recognizeText(
        from image: CGImage,
        languages: [String] = ["en-US"],
        level: RecognitionLevel = .accurate,
        usesLanguageCorrection: Bool = true
    ) async throws -> [TextRegion] {
        // Create text recognition request
        let request = VNRecognizeTextRequest()

        // Configure recognition level
        request.recognitionLevel = level.visionLevel

        // Configure language correction (improves accuracy, slows processing)
        request.usesLanguageCorrection = usesLanguageCorrection

        // Set recognition languages
        if !languages.isEmpty {
            request.recognitionLanguages = languages
        }

        // Perform recognition using async/await with continuation
        return try await withCheckedThrowingContinuation { continuation in
            // Create request handler
            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            // Perform request and handle results
            do {
                try handler.perform([request])

                // Get results
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                // Return empty if no observations
                if observations.isEmpty {
                    continuation.resume(returning: [])
                    return
                }

                // Convert observations to TextRegion objects
                let textRegions = observations.compactMap { observation -> TextRegion? in
                    guard let topCandidate = observation.topCandidates(1).first else { return nil }
                    guard topCandidate.confidence >= minimumConfidence else { return nil }

                    return TextRegion(
                        text: topCandidate.string,
                        boundingBox: observation.boundingBox,
                        confidence: topCandidate.confidence
                    )
                }

                continuation.resume(returning: textRegions)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Validates if a given language code is supported.
    /// - Parameter languageCode: Language code to validate (e.g., "en-US")
    /// - Returns: True if language is supported
    func isLanguageSupported(_ languageCode: String) -> Bool {
        let supported = Self.commonLanguages().map { $0.code }
        return supported.contains(languageCode)
    }

    /// Gets commonly supported languages for OCR.
    /// - Returns: Array of common language codes with display names
    static func commonLanguages() -> [(code: String, name: String)] {
        return [
            ("en-US", "English"),
            ("en-GB", "English (UK)"),
            ("es-ES", "Spanish"),
            ("fr-FR", "French"),
            ("de-DE", "German"),
            ("it-IT", "Italian"),
            ("pt-BR", "Portuguese"),
            ("tr-TR", "Turkish"),
            ("zh-Hans", "Chinese (Simplified)"),
            ("zh-Hant", "Chinese (Traditional)"),
            ("ja-JP", "Japanese"),
            ("ko-KR", "Korean"),
            ("ru-RU", "Russian"),
            ("ar-SA", "Arabic"),
            ("hi-IN", "Hindi")
        ]
    }
}
