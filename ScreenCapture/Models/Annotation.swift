import Foundation
import CoreGraphics

/// A drawing element placed on a screenshot.
/// Supports rectangle, freehand, arrow, and text annotation types.
enum Annotation: Identifiable, Equatable, Sendable {
    case rectangle(RectangleAnnotation)
    case freehand(FreehandAnnotation)
    case arrow(ArrowAnnotation)
    case text(TextAnnotation)

    /// Unique identifier for this annotation
    var id: UUID {
        switch self {
        case .rectangle(let annotation):
            return annotation.id
        case .freehand(let annotation):
            return annotation.id
        case .arrow(let annotation):
            return annotation.id
        case .text(let annotation):
            return annotation.id
        }
    }

    /// The bounding rect of this annotation
    var bounds: CGRect {
        switch self {
        case .rectangle(let annotation):
            return annotation.rect
        case .freehand(let annotation):
            return annotation.bounds
        case .arrow(let annotation):
            return annotation.bounds
        case .text(let annotation):
            return annotation.bounds
        }
    }
}

// MARK: - Rectangle Annotation

/// A rectangle annotation with position, size, and stroke style.
struct RectangleAnnotation: Identifiable, Equatable, Sendable {
    /// Unique identifier
    let id: UUID

    /// Position and size in image coordinates
    var rect: CGRect

    /// Stroke color and line width
    var style: StrokeStyle

    /// Whether the rectangle is filled (solid) or hollow (outline only)
    /// When filled, the rectangle uses the stroke color as fill to hide underlying content
    var isFilled: Bool

    init(id: UUID = UUID(), rect: CGRect, style: StrokeStyle = .default, isFilled: Bool = false) {
        self.id = id
        self.rect = rect
        self.style = style
        self.isFilled = isFilled
    }
}

// MARK: - Freehand Annotation

/// A freehand path annotation with points and stroke style.
struct FreehandAnnotation: Identifiable, Equatable, Sendable {
    /// Unique identifier
    let id: UUID

    /// Path vertices in image coordinates (minimum 2 points)
    var points: [CGPoint]

    /// Stroke color and line width
    var style: StrokeStyle

    init(id: UUID = UUID(), points: [CGPoint], style: StrokeStyle = .default) {
        self.id = id
        self.points = points
        self.style = style
    }

    /// Whether this annotation has enough points to be valid
    var isValid: Bool {
        points.count >= 2
    }

    /// The bounding rectangle of all points
    var bounds: CGRect {
        guard !points.isEmpty else { return .zero }

        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity

        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Arrow Annotation

/// An arrow annotation with start point, end point (arrowhead), and stroke style.
struct ArrowAnnotation: Identifiable, Equatable, Sendable {
    /// Unique identifier
    let id: UUID

    /// Start point of the arrow (tail) in image coordinates
    var startPoint: CGPoint

    /// End point of the arrow (head) in image coordinates
    var endPoint: CGPoint

    /// Stroke color and line width
    var style: StrokeStyle

    init(id: UUID = UUID(), startPoint: CGPoint, endPoint: CGPoint, style: StrokeStyle = .default) {
        self.id = id
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.style = style
    }

    /// Whether this annotation has meaningful length
    var isValid: Bool {
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let length = sqrt(dx * dx + dy * dy)
        return length >= 5
    }

    /// The bounding rectangle of the arrow
    var bounds: CGRect {
        let minX = min(startPoint.x, endPoint.x)
        let minY = min(startPoint.y, endPoint.y)
        let maxX = max(startPoint.x, endPoint.x)
        let maxY = max(startPoint.y, endPoint.y)

        // Add padding for the arrowhead
        let padding: CGFloat = style.lineWidth * 3
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: maxX - minX + padding * 2,
            height: maxY - minY + padding * 2
        )
    }
}

// MARK: - Text Annotation

/// A text annotation with position, content, and text style.
struct TextAnnotation: Identifiable, Equatable, Sendable {
    /// Unique identifier
    let id: UUID

    /// Anchor point in image coordinates
    var position: CGPoint

    /// User-entered text content
    var content: String

    /// Font, size, and color
    var style: TextStyle

    /// Text container width in image coordinates (nil = dynamic/auto-size, non-nil = fixed wrap width)
    var containerWidth: CGFloat?

    init(id: UUID = UUID(), position: CGPoint, content: String, style: TextStyle = .default, containerWidth: CGFloat? = nil) {
        self.id = id
        self.position = position
        self.content = content
        self.style = style
        self.containerWidth = containerWidth
    }

    /// Whether this annotation has non-empty content
    var isValid: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Estimated bounds of the text annotation based on font size, content, and container width
    var bounds: CGRect {
        let lineHeight = style.fontSize * 1.3
        let charWidth = style.fontSize * 0.6
        let lines = content.components(separatedBy: "\n")

        if let containerWidth = containerWidth {
            // fixed width: estimate wrapped line count
            let charsPerLine = max(1, Int(containerWidth / charWidth))
            let wrappedLineCount = lines.reduce(0) { total, line in
                total + max(1, Int(ceil(Double(max(1, line.count)) / Double(charsPerLine))))
            }
            return CGRect(
                origin: position,
                size: CGSize(width: containerWidth, height: CGFloat(wrappedLineCount) * lineHeight)
            )
        }

        // dynamic: estimate from content
        let maxLineWidth = lines.map { CGFloat(max(1, $0.count)) * charWidth }.max() ?? charWidth
        let estimatedWidth = max(maxLineWidth, style.fontSize * 2)
        let estimatedHeight = max(CGFloat(lines.count) * lineHeight, lineHeight)

        return CGRect(
            origin: position,
            size: CGSize(width: estimatedWidth, height: estimatedHeight)
        )
    }
}

// MARK: - CGPoint Sendable Conformance

extension CGPoint: @retroactive @unchecked Sendable {}

// MARK: - Annotation Type

extension Annotation {
    /// The type of this annotation for display purposes
    var typeName: String {
        switch self {
        case .rectangle:
            return NSLocalizedString("tool.rectangle", comment: "")
        case .freehand:
            return NSLocalizedString("tool.freehand", comment: "")
        case .arrow:
            return NSLocalizedString("tool.arrow", comment: "")
        case .text:
            return NSLocalizedString("tool.text", comment: "")
        }
    }
}
