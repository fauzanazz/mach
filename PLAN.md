# mach — macOS Mechanical Key Click App Plan

## Goal
Build a lightweight macOS menu bar app for Apple Silicon (M-series) that plays mechanical keyboard click sounds on key press.

## Product Scope (MVP)
- Menu bar app (no Dock icon)
- Global toggle: **Enable / Disable sounds**
- Play click sound on **key down**
- Volume control
- Basic sound pack selector
- Launch at login
- Local-only processing (no keystroke logging)

## Tech Stack
- **Swift + SwiftUI** (AppKit where needed for status bar)
- **CGEventTap** for global keyboard events
- **AVAudioEngine** for low-latency playback
- **UserDefaults / @AppStorage** for settings

## Architecture

### 1) App Layer
- `MenuBarApp` (entry point)
- `StatusBarController` (menu items + state bindings)

### 2) Input Layer
- `KeyboardEventMonitor`
  - Starts/stops `CGEventTap`
  - Emits `keyDown` events
  - Handles permission state and fallback messaging

### 3) Audio Layer
- `SoundEngine`
  - Preloads samples at startup
  - Keeps player-node pool for overlap during rapid typing
  - Exposes `playKeyDown()` with volume + selected pack

### 4) Settings Layer
- `SettingsStore`
  - `isEnabled`
  - `volume`
  - `selectedPack`
  - `launchAtLogin`

## Milestones

### Milestone 1 — Skeleton
- Create menu bar-only app (`LSUIElement = 1`)
- Add menu: toggle, volume, quit

### Milestone 2 — Global Key Capture
- Integrate `CGEventTap` for key down events
- Start/stop monitor with toggle
- Handle Input Monitoring permission UX

### Milestone 3 — Audio Playback
- Integrate `AVAudioEngine`
- Preload one sound pack
- Ensure low latency and overlap-safe playback

### Milestone 4 — Preferences
- Add sound pack selector
- Persist settings
- Add launch-at-login

### Milestone 5 — Polish & Release
- CPU/memory profiling under fast typing
- Error handling + user guidance
- Code signing and notarization

## Non-Goals (for MVP)
- Per-key unique sound mapping
- Advanced profiles/macros
- Cross-platform support
- Cloud sync

## Privacy
- No keystroke content is stored or transmitted.
- App only reacts to key events to trigger local audio playback.

## Risks / Notes
- macOS permissions can block event tap until granted.
- Some environments (secure input fields) may reduce event visibility.
- Keep audio path preloaded to avoid runtime lag.

## Next Step
Implement Milestone 1 and scaffold these files:
- `MenuBarApp.swift`
- `StatusBarController.swift`
- `KeyboardEventMonitor.swift`
- `SoundEngine.swift`
- `SettingsStore.swift`
