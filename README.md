See `ses_3740246dfffenkdilGlPRD72mi` for stash

# ScreenCapture

A fast, lightweight macOS menu bar app for capturing screenshots with OCR text recognition.

## Features

- **Instant Capture** - Full screen or selection region with custom hotkeys
- **OCR Text Recognition** - Extract text from screenshots (Press 'O' key)
- **Annotation Tools** - Rectangles, arrows, freehand drawing, text
- **Multi-Display Support** - Works seamlessly across all connected displays
- **Flexible Export** - Save as PNG, JPEG, or HEIC with quality control
- **Crop & Edit** - Crop screenshots with pixel-perfect precision
- **Clipboard Integration** - One-click copy to clipboard

## Requirements

- macOS 13.0 (Ventura) or later
- Screen Recording permission (System Settings → Privacy & Security)

## Installation

Download the latest release and drag to Applications folder.

## Usage

### Global Hotkeys

| Action | Shortcut |
|--------|----------|
| Full Screen Capture | Custom (default: ⌘⇧⌘X) |
| Selection Capture | Custom (default: ⌘⇧⌘A) |
| OCR Text | O |

### Preview Window

| Action | Shortcut |
|--------|----------|
| Save | ⌘S or Enter |
| Copy to Clipboard | ⌘C |
| Rectangle Tool | R |
| Freehand/Drawing Tool | D |
| Arrow Tool | A |
| Text Tool | T |
| Crop Mode | C |
| Undo | ⌘Z |
| Redo | ⌘⇧⌘Z |
| Dismiss | Escape |

## Tech Stack

- **Swift 6.2** with strict concurrency
- **SwiftUI + AppKit** for native macOS UI
- **ScreenCaptureKit** for system-level capture
- **Vision Framework** for OCR text recognition
- **CoreGraphics** for image processing

## License

MIT License

# tasks

## my opencode sessions

`ses_376a9853bffeRs3RGWRCCQuDTK` - initial version fix, plans for next features
`ses_36d47b340ffeJopAkly82xurve` - audio capture, section muting, export pipeline

## todo

## ongoing

### active

- [ ] add audio to screen recordings — branch `feat/audio-section-muting`, session `ses_36d47b340ffeJopAkly82xurve`
  - [x] milestone 1+2: audio capture + mute on export (committed to main)
  - [x] milestone 3: section muting (committed to branch, untested)
    - [ ] test: record with system audio playing, verify playback has sound
    - [ ] test: add a mute region via "+", drag red handles, save, verify silence in that section
    - [ ] test: full mute toggle (speaker icon), save, verify completely silent
  - [ ] milestone 4: voiceover recording + mixing
  - [ ] milestone 5: timestamped text annotations burned into video

### passive

### waiting

## done

## cancelled
