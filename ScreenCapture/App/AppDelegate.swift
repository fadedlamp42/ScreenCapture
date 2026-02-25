import AppKit

/// Application delegate responsible for menu bar setup, hotkey registration, and app lifecycle.
/// Runs on the main actor to ensure thread-safe UI operations.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties

    /// Menu bar controller for status item management
    private var menuBarController: MenuBarController?

    /// Store for recent captures
    private var recentCapturesStore: RecentCapturesStore?

    /// Registered hotkey for full screen capture
    private var fullScreenHotkeyRegistration: HotkeyManager.Registration?

    /// Registered hotkey for selection capture
    private var selectionHotkeyRegistration: HotkeyManager.Registration?

    /// Registered hotkey for video recording
    private var recordingHotkeyRegistration: HotkeyManager.Registration?

    /// Shared app settings
    private let settings = AppSettings.shared

    /// Display selector for multi-monitor support
    private let displaySelector = DisplaySelector()

    /// Whether a capture is currently in progress (prevents overlapping captures)
    private var isCaptureInProgress = false

    /// Whether a recording is currently in progress
    private var isRecordingInProgress = false

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure we're a menu bar only app (no dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Initialize recent captures store
        recentCapturesStore = RecentCapturesStore(settings: settings)

        // Set up menu bar
        menuBarController = MenuBarController(
            appDelegate: self,
            recentCapturesStore: recentCapturesStore!
        )
        menuBarController?.setup()

        // Register global hotkeys
        Task {
            await registerHotkeys()
        }

        // Check for screen recording permission on first launch,
        // then pre-warm the display cache so the first capture is snappy
        Task {
            await checkAndRequestScreenRecordingPermission()
            _ = try? await ScreenDetector.shared.availableDisplays()
        }

        #if DEBUG
        print("ScreenCapture launched - settings loaded from: \(settings.saveLocation.path)")
        #endif
    }

    /// Checks for screen recording permission and shows an explanatory prompt if needed.
    private func checkAndRequestScreenRecordingPermission() async {
        // Check if we already have permission
        let hasPermission = await CaptureManager.shared.hasPermission

        if !hasPermission {
            // Show an explanatory alert before triggering the system prompt
            await MainActor.run {
                showPermissionExplanationAlert()
            }
        }
    }

    /// Shows an alert explaining why screen recording permission is needed.
    private func showPermissionExplanationAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("permission.prompt.title", comment: "Screen Recording Permission Required")
        alert.informativeText = NSLocalizedString("permission.prompt.message", comment: "")
        alert.addButton(withTitle: NSLocalizedString("permission.prompt.continue", comment: "Continue"))
        alert.addButton(withTitle: NSLocalizedString("permission.prompt.later", comment: "Later"))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Trigger the system permission prompt by attempting a capture
            Task {
                _ = await CaptureManager.shared.requestPermission()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Unregister hotkeys
        Task {
            await unregisterHotkeys()
        }

        // Remove menu bar item
        menuBarController?.teardown()

        #if DEBUG
        print("ScreenCapture terminating")
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // For menu bar apps, we don't need to do anything special on reopen
        // The menu bar icon is always visible
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        // Enable secure state restoration
        return true
    }

    // MARK: - Hotkey Management

    /// Registers global hotkeys for capture actions
    private func registerHotkeys() async {
        let hotkeyManager = HotkeyManager.shared

        // Register full screen capture hotkey (if bound)
        if let shortcut = settings.fullScreenShortcut {
            do {
                fullScreenHotkeyRegistration = try await hotkeyManager.register(
                    shortcut: shortcut
                ) { [weak self] in
                    Task { @MainActor in
                        self?.captureFullScreen()
                    }
                }
                #if DEBUG
                print("Registered full screen hotkey: \(shortcut.displayString)")
                #endif
            } catch {
                #if DEBUG
                print("Failed to register full screen hotkey: \(error)")
                #endif
            }
        }

        // Register selection capture hotkey (if bound)
        if let shortcut = settings.selectionShortcut {
            do {
                selectionHotkeyRegistration = try await hotkeyManager.register(
                    shortcut: shortcut
                ) { [weak self] in
                    Task { @MainActor in
                        self?.captureSelection()
                    }
                }
                #if DEBUG
                print("Registered selection hotkey: \(shortcut.displayString)")
                #endif
            } catch {
                #if DEBUG
                print("Failed to register selection hotkey: \(error)")
                #endif
            }
        }

        // Register recording hotkey (if bound)
        if let shortcut = settings.recordingShortcut {
            do {
                recordingHotkeyRegistration = try await hotkeyManager.register(
                    shortcut: shortcut
                ) { [weak self] in
                    Task { @MainActor in
                        self?.toggleRecording()
                    }
                }
                #if DEBUG
                print("Registered recording hotkey: \(shortcut.displayString)")
                #endif
            } catch {
                #if DEBUG
                print("Failed to register recording hotkey: \(error)")
                #endif
            }
        }
    }

    /// Unregisters all global hotkeys
    private func unregisterHotkeys() async {
        let hotkeyManager = HotkeyManager.shared

        if let registration = fullScreenHotkeyRegistration {
            await hotkeyManager.unregister(registration)
            fullScreenHotkeyRegistration = nil
        }

        if let registration = selectionHotkeyRegistration {
            await hotkeyManager.unregister(registration)
            selectionHotkeyRegistration = nil
        }

        if let registration = recordingHotkeyRegistration {
            await hotkeyManager.unregister(registration)
            recordingHotkeyRegistration = nil
        }
    }

    /// Re-registers hotkeys after settings change
    func updateHotkeys() {
        Task {
            await unregisterHotkeys()
            await registerHotkeys()
        }
    }

    // MARK: - Capture Actions

    /// Triggers a full screen capture
    @objc func captureFullScreen() {
        // Prevent overlapping captures
        guard !isCaptureInProgress else {
            #if DEBUG
            print("Capture already in progress, ignoring request")
            #endif
            return
        }

        #if DEBUG
        print("Full screen capture triggered via hotkey or menu")
        #endif

        isCaptureInProgress = true

        Task {
            defer { isCaptureInProgress = false }

            do {
                // Get available displays
                let displays = try await CaptureManager.shared.availableDisplays()

                // Select display (shows menu if multiple)
                guard let selectedDisplay = await displaySelector.selectDisplay(from: displays) else {
                    #if DEBUG
                    print("Display selection cancelled")
                    #endif
                    return
                }

                #if DEBUG
                print("Capturing display: \(selectedDisplay.name)")
                #endif

                // Perform capture
                let screenshot = try await CaptureManager.shared.captureFullScreen(display: selectedDisplay)

                #if DEBUG
                print("Capture successful: \(screenshot.formattedDimensions)")
                #endif

                // Show preview window
                PreviewWindowController.shared.showPreview(for: screenshot) { [weak self] savedURL in
                    // Add to recent captures when saved
                    self?.addRecentCapture(filePath: savedURL, image: screenshot.image)
                }

            } catch let error as ScreenCaptureError {
                showCaptureError(error)
            } catch {
                showCaptureError(.captureFailure(underlying: error))
            }
        }
    }

    /// Triggers a selection capture
    @objc func captureSelection() {
        // Prevent overlapping captures
        guard !isCaptureInProgress else {
            #if DEBUG
            print("Capture already in progress, ignoring request")
            #endif
            return
        }

        NSLog("[capture] selection hotkey triggered")

        isCaptureInProgress = true

        Task {
            do {
                // Present the selection overlay on all displays
                let overlayController = SelectionOverlayController.shared

                // Set up callbacks before presenting
                overlayController.onSelectionComplete = { [weak self] rect, display in
                    Task { @MainActor in
                        await self?.handleSelectionComplete(rect: rect, display: display)
                    }
                }

                overlayController.onSelectionCancel = { [weak self] in
                    Task { @MainActor in
                        self?.handleSelectionCancel()
                    }
                }

                try await overlayController.presentOverlay()

            } catch {
                isCaptureInProgress = false
                #if DEBUG
                print("Failed to present selection overlay: \(error)")
                #endif
                showCaptureError(.captureFailure(underlying: error))
            }
        }
    }

    /// Handles successful selection completion
    private func handleSelectionComplete(rect: CGRect, display: DisplayInfo) async {
        defer { isCaptureInProgress = false }

        do {
            #if DEBUG
            print("Selection complete: \(Int(rect.width))×\(Int(rect.height)) on \(display.name)")
            #endif

            // Capture the selected region
            let screenshot = try await CaptureManager.shared.captureRegion(rect, from: display)

            #if DEBUG
            print("Region capture successful: \(screenshot.formattedDimensions)")
            #endif

            // Show preview window
            PreviewWindowController.shared.showPreview(for: screenshot) { [weak self] savedURL in
                // Add to recent captures when saved
                self?.addRecentCapture(filePath: savedURL, image: screenshot.image)
            }

        } catch let error as ScreenCaptureError {
            showCaptureError(error)
        } catch {
            showCaptureError(.captureFailure(underlying: error))
        }
    }

    /// Handles selection cancellation
    private func handleSelectionCancel() {
        isCaptureInProgress = false
        #if DEBUG
        print("Selection cancelled by user")
        #endif
    }

    // MARK: - Recording Actions

    /// Toggles recording on/off. If recording, stops it. If not, starts selection flow.
    @objc func toggleRecording() {
        if isRecordingInProgress {
            stopRecording()
        } else {
            startRecordingSelection()
        }
    }

    /// Triggers the selection overlay for choosing a recording region
    @objc func startRecordingSelection() {
        guard !isRecordingInProgress, !isCaptureInProgress else {
            #if DEBUG
            print("Capture or recording already in progress, ignoring")
            #endif
            return
        }

        #if DEBUG
        print("Recording selection triggered")
        #endif

        isCaptureInProgress = true

        Task {
            do {
                let overlayController = SelectionOverlayController.shared

                overlayController.onSelectionComplete = { [weak self] rect, display in
                    Task { @MainActor in
                        await self?.handleRecordingSelectionComplete(rect: rect, display: display)
                    }
                }

                overlayController.onSelectionCancel = { [weak self] in
                    Task { @MainActor in
                        self?.isCaptureInProgress = false
                        #if DEBUG
                        print("Recording selection cancelled")
                        #endif
                    }
                }

                try await overlayController.presentOverlay()

            } catch {
                isCaptureInProgress = false
                showCaptureError(.captureFailure(underlying: error))
            }
        }
    }

    /// Starts recording the selected region
    private func handleRecordingSelectionComplete(rect: CGRect, display: DisplayInfo) async {
        isCaptureInProgress = false

        do {
            isRecordingInProgress = true

            #if DEBUG
            print("Starting recording: \(Int(rect.width))x\(Int(rect.height)) on \(display.name)")
            #endif

            // show the recording frame border around the selected region.
            // must be shown before starting the stream so SCShareableContent
            // can find the window to exclude it from capture.
            let frameWindowID = RecordingFrameController.shared.show(region: rect, on: display)

            // show the recording overlay with stop button + timer
            RecordingOverlayController.shared.show(on: display) { [weak self] in
                self?.stopRecording()
            }

            // update the menu bar to show recording state
            menuBarController?.setRecordingState(true)

            // get the overlay window ID too so both UI windows are excluded
            var excludedIDs: [CGWindowID] = [frameWindowID]
            if let overlayID = RecordingOverlayController.shared.currentWindowID {
                excludedIDs.append(overlayID)
            }

            // start recording, excluding our overlay windows from the capture
            try await VideoRecorder.shared.startRegionRecording(
                region: rect,
                display: display,
                excludedWindowIDs: excludedIDs,
                recordAudio: settings.recordAudio
            ) { [weak self] elapsed in
                // update the overlay timer on every tick
                self?.handleRecordingElapsedTime(elapsed)
            }

        } catch {
            isRecordingInProgress = false
            RecordingFrameController.shared.dismiss()
            RecordingOverlayController.shared.dismiss()
            menuBarController?.setRecordingState(false)
            showCaptureError(.recordingFailure(underlying: error))
        }
    }

    /// Starts a full screen recording
    @objc func startFullScreenRecording() {
        guard !isRecordingInProgress, !isCaptureInProgress else { return }

        isRecordingInProgress = true

        Task {
            do {
                let displays = try await CaptureManager.shared.availableDisplays()
                guard let selectedDisplay = await displaySelector.selectDisplay(from: displays) else {
                    isRecordingInProgress = false
                    return
                }

                // show the frame border around the full screen
                let frameWindowID = RecordingFrameController.shared.showFullScreen(on: selectedDisplay)

                RecordingOverlayController.shared.show(on: selectedDisplay) { [weak self] in
                    self?.stopRecording()
                }

                menuBarController?.setRecordingState(true)

                var excludedIDs: [CGWindowID] = [frameWindowID]
                if let overlayID = RecordingOverlayController.shared.currentWindowID {
                    excludedIDs.append(overlayID)
                }

                try await VideoRecorder.shared.startFullScreenRecording(
                    display: selectedDisplay,
                    excludedWindowIDs: excludedIDs,
                    recordAudio: settings.recordAudio
                ) { [weak self] elapsed in
                    self?.handleRecordingElapsedTime(elapsed)
                }

            } catch {
                isRecordingInProgress = false
                RecordingFrameController.shared.dismiss()
                RecordingOverlayController.shared.dismiss()
                menuBarController?.setRecordingState(false)
                showCaptureError(.recordingFailure(underlying: error))
            }
        }
    }

    /// Stops the current recording and shows the preview
    @objc func stopRecording() {
        guard isRecordingInProgress else { return }

        #if DEBUG
        print("Stopping recording...")
        #endif

        Task {
            do {
                let recording = try await VideoRecorder.shared.stopRecording()

                RecordingFrameController.shared.dismiss()
                RecordingOverlayController.shared.dismiss()
                menuBarController?.setRecordingState(false)
                isRecordingInProgress = false

                // show the video preview window
                VideoPreviewWindowController.shared.showPreview(for: recording) { [weak self] savedURL in
                    self?.addRecentCapture(filePath: savedURL, recording: recording)
                }

            } catch {
                RecordingFrameController.shared.dismiss()
                RecordingOverlayController.shared.dismiss()
                menuBarController?.setRecordingState(false)
                isRecordingInProgress = false
                showCaptureError(.recordingFailure(underlying: error))
            }
        }
    }

    /// Updates the recording overlay with elapsed time
    private func handleRecordingElapsedTime(_ elapsed: TimeInterval) {
        RecordingOverlayController.shared.updateElapsedTime(elapsed)
    }

    /// Opens the settings window
    @objc func openSettings() {
        #if DEBUG
        print("Opening settings window")
        #endif

        SettingsWindowController.shared.showSettings(appDelegate: self)
    }

    // MARK: - Error Handling

    /// Shows an error alert for capture failures
    private func showCaptureError(_ error: ScreenCaptureError) {
        #if DEBUG
        print("Capture error: \(error)")
        #endif

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = error.errorDescription ?? NSLocalizedString("error.capture.failed", comment: "")
        alert.informativeText = error.recoverySuggestion ?? ""

        switch error {
        case .permissionDenied:
            alert.addButton(withTitle: NSLocalizedString("error.permission.open.settings", comment: "Open System Settings"))
            alert.addButton(withTitle: NSLocalizedString("error.dismiss", comment: "Dismiss"))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open System Settings > Privacy > Screen Recording
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }

        case .displayDisconnected:
            // Offer to retry capture on a different display
            alert.addButton(withTitle: NSLocalizedString("error.retry.capture", comment: "Retry"))
            alert.addButton(withTitle: NSLocalizedString("error.dismiss", comment: "Dismiss"))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Retry the capture on the remaining displays
                captureFullScreen()
            }

        case .diskFull, .invalidSaveLocation:
            // Offer to open settings to change save location
            alert.addButton(withTitle: NSLocalizedString("menu.settings", comment: "Settings..."))
            alert.addButton(withTitle: NSLocalizedString("error.dismiss", comment: "Dismiss"))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                openSettings()
            }

        case .recordingFailure:
            alert.addButton(withTitle: NSLocalizedString("error.retry.capture", comment: "Retry"))
            alert.addButton(withTitle: NSLocalizedString("error.dismiss", comment: "Dismiss"))
            alert.runModal()

        default:
            alert.addButton(withTitle: NSLocalizedString("error.ok", comment: "OK"))
            alert.runModal()
        }
    }

    // MARK: - Recent Captures

    /// Adds a capture to recent captures store
    func addRecentCapture(filePath: URL, image: CGImage) {
        recentCapturesStore?.add(filePath: filePath, image: image)
        menuBarController?.updateRecentCapturesMenu()
    }

    /// Adds a recording to recent captures store (uses a generic video thumbnail)
    func addRecentCapture(filePath: URL, recording: Recording) {
        // generate a thumbnail from the first frame of the video
        let capture = RecentCapture(
            filePath: filePath,
            captureDate: recording.captureDate,
            thumbnailData: nil
        )
        recentCapturesStore?.addCapture(capture)
        menuBarController?.updateRecentCapturesMenu()
    }
}
