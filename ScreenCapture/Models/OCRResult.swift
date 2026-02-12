import Foundation
import CoreGraphics

/// Represents a single region of recognized text with its location and confidence.
struct TextRegion: Identifiable, Sendable {
    /// Unique identifier
    let id: UUID

    /// Recognized text content
    let text: String

    /// Bounding box in image coordinates (normalized 0-1)
    let boundingBox: CGRect

    /// Confidence score (0.0-1.0)
    let confidence: Float

    init(id: UUID = UUID(), text: String, boundingBox: CGRect, confidence: Float) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

/// Complete OCR result with all recognized text and metadata.
struct OCRResult: Sendable {
    /// Concatenated text from all regions
    let fullText: String

    /// Individual text regions with their positions
    let textRegions: [TextRegion]

    /// Time taken to process in seconds
    let processingTime: TimeInterval

    /// Detected or specified language (e.g., "en-US")
    let language: String?

    init(fullText: String, textRegions: [TextRegion], processingTime: TimeInterval, language: String? = nil) {
        self.fullText = fullText
        self.textRegions = textRegions
        self.processingTime = processingTime
        self.language = language
    }
}
