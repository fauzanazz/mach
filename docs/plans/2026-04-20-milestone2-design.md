# Milestone 2: Global Key Capture Design

## Goal
Capture global key down events using CGEventTap, integrated with enable toggle.

## Technical Approach

### New File: KeyboardEventMonitor.swift

```swift
final class KeyboardEventMonitor {
    var onKeyDown: (() -> Void)?
    
    func start() -> Bool   // Returns false if permission denied
    func stop()
    var isRunning: Bool { get }
}
```

### CGEventTap Setup

1. Create tap with `CGEvent.tapCreate`:
   - `tap`: `.cghidEventTap` (system-wide)
   - `place`: `.headInsertEventTap`
   - `options`: `.listenOnly` (passive, no modification)
   - `eventsOfInterest`: `1 << CGEventType.keyDown.rawValue`

2. Callback invokes `onKeyDown` closure

3. Add to `CFRunLoop.main` for event delivery

### Permission Handling

- `AXIsProcessTrusted()` checks current state
- If denied, `AXIsProcessTrustedWithOptions` can prompt user
- Show alert guiding user to System Preferences > Privacy > Input Monitoring

### Integration with SettingsStore

- When `isEnabled` changes:
  - true → call `start()`, handle permission failure
  - false → call `stop()`

### Menu Updates

- Show permission status in menu if denied
- "Request Permission..." menu item when needed
