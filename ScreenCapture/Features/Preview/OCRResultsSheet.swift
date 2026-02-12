import SwiftUI
import AppKit

/// Sheet view for displaying OCR (text recognition) results.
/// Shows recognized text with options to copy and dismiss.
struct OCRResultsSheet: View {
    // MARK: - Properties

    /// The OCR result to display
    let ocrResult: OCRResult?

    /// Whether OCR is currently processing
    let isProcessing: Bool

    /// Callback when copy button is pressed
    let onCopy: () -> Void

    /// Callback when sheet should be dismissed
    let onClose: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            content

            Divider()

            // Footer
            footer
        }
        .frame(width: 600, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recognized Text")
                    .font(.headline)

                if let language = ocrResult?.language {
                    Text(verbatim: "• \(language)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isProcessing {
                ProgressView()
                    .controlSize(.small)
            } else if let result = ocrResult {
                Text(verbatim: "\(Int(result.processingTime * 1000))ms")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isProcessing {
                    loadingView
                } else if let result = ocrResult {
                    if result.fullText.isEmpty {
                        emptyView
                    } else {
                        textView(result: result)
                    }
                }
            }
            .padding(20)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            Text("Recognizing text...")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No text detected")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Try adjusting the image or selecting a different language in settings.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func textView(result: OCRResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Full text area
            Text(result.fullText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: CGFloat.infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)

            // Text regions count info
            if result.textRegions.count > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(verbatim: "\(result.textRegions.count) text regions detected")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()

            Button {
                onClose()
            } label: {
                Text("Close")
            }
            .keyboardShortcut(.escape, modifiers: [])
            .buttonStyle(.bordered)

            if let result = ocrResult, !result.fullText.isEmpty {
                Button {
                    onCopy()
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    OCRResultsSheet(
        ocrResult: OCRResult(
            fullText: "Sample text recognized from image",
            textRegions: [],
            processingTime: 0.5,
            language: "en-US"
        ),
        isProcessing: false,
        onCopy: {},
        onClose: {}
    )
}
#endif
