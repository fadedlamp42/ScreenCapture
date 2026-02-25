import AppKit

/// A completely transparent, click-through window that draws a thin border
/// around the recording region. Cannot steal focus, cannot be clicked,
/// and is excluded from the SCStream capture so it doesn't appear in the video.
@MainActor
final class RecordingFrameWindow: NSPanel {
    // MARK: - Properties

    /// the CGWindowID used to exclude this window from SCStream capture
    var cgWindowID: CGWindowID {
        CGWindowID(windowNumber)
    }

    // MARK: - Initialization

    /// creates a frame window positioned over the given screen-coordinate rect.
    /// `screenRect` should be in Cocoa screen coordinates (origin bottom-left).
    init(screenRect: NSRect) {
        // inset the frame slightly so the border sits just outside the recording region
        let borderWidth: CGFloat = 1
        let frameRect = screenRect.insetBy(dx: -borderWidth - 1, dy: -borderWidth - 1)

        super.init(
            contentRect: frameRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configureWindow()
        setupBorderView(borderWidth: borderWidth)
    }

    // MARK: - Configuration

    private func configureWindow() {
        // fully transparent
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // always on top, but below the recording overlay controls
        level = .statusBar

        // complete click-through: all events pass to windows underneath
        ignoresMouseEvents = true

        // never steal focus
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false

        // visible on all spaces
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    private func setupBorderView(borderWidth: CGFloat) {
        let borderView = RecordingBorderView(borderWidth: borderWidth)
        borderView.frame = contentView?.bounds ?? .zero
        borderView.autoresizingMask = [.width, .height]
        contentView?.addSubview(borderView)
    }

    // MARK: - Prevent Activation

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Border View

/// draws a thin colored border and nothing else
private final class RecordingBorderView: NSView {
    private let borderWidth: CGFloat
    private let borderColor: NSColor = .systemRed.withAlphaComponent(0.7)

    init(borderWidth: CGFloat) {
        self.borderWidth = borderWidth
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        // the whole view is transparent except for the border stroke
        let strokeRect = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
        let path = NSBezierPath(rect: strokeRect)
        path.lineWidth = borderWidth
        borderColor.setStroke()
        path.stroke()
    }
}

// MARK: - Controller

/// manages the recording frame window lifecycle
@MainActor
final class RecordingFrameController {
    static let shared = RecordingFrameController()

    private var frameWindow: RecordingFrameWindow?

    private init() {}

    /// shows the frame around the given recording region.
    /// `region` is in display-local points, `display` identifies which screen.
    /// returns the CGWindowID so the caller can exclude it from SCStream.
    @discardableResult
    func show(region: CGRect, on display: DisplayInfo) -> CGWindowID {
        dismiss()

        // convert display-local region (quartz coords, Y=0 at top) to
        // Cocoa screen coordinates (Y=0 at bottom of primary screen)
        let screenRect = convertToCocoaScreenCoordinates(region: region, display: display)

        let window = RecordingFrameWindow(screenRect: screenRect)
        window.orderFrontRegardless()
        self.frameWindow = window

        return window.cgWindowID
    }

    /// shows a full-screen frame on the given display.
    /// returns the CGWindowID so the caller can exclude it from SCStream.
    @discardableResult
    func showFullScreen(on display: DisplayInfo) -> CGWindowID {
        dismiss()

        guard let screen = display.matchingScreen else {
            // fallback: use primary screen frame
            let fallbackRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
            let window = RecordingFrameWindow(screenRect: fallbackRect)
            window.orderFrontRegardless()
            self.frameWindow = window
            return window.cgWindowID
        }

        let window = RecordingFrameWindow(screenRect: screen.frame)
        window.orderFrontRegardless()
        self.frameWindow = window
        return window.cgWindowID
    }

    /// removes the frame
    func dismiss() {
        frameWindow?.close()
        frameWindow = nil
    }

    /// the CGWindowID of the current frame, if shown
    var currentWindowID: CGWindowID? {
        frameWindow?.cgWindowID
    }

    // MARK: - Coordinate Conversion

    /// converts a display-local rect in quartz coordinates to Cocoa screen coordinates.
    /// quartz: Y=0 at top of primary screen, display.frame.origin is in quartz coords.
    /// cocoa: Y=0 at bottom of primary screen.
    private func convertToCocoaScreenCoordinates(region: CGRect, display: DisplayInfo) -> NSRect {
        guard let primaryScreen = NSScreen.screens.first else {
            return NSRect(origin: .zero, size: region.size)
        }

        let primaryHeight = primaryScreen.frame.height

        // region is display-local in quartz coords.
        // display.frame.origin is also in quartz coords.
        let globalQuartzX = display.frame.origin.x + region.origin.x
        let globalQuartzY = display.frame.origin.y + region.origin.y

        // convert quartz Y (top=0) to cocoa Y (bottom=0)
        let cocoaY = primaryHeight - globalQuartzY - region.height

        return NSRect(
            x: globalQuartzX,
            y: cocoaY,
            width: region.width,
            height: region.height
        )
    }
}
