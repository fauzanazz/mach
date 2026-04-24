# Milestone 4: Preferences Design

## Goals
1. Sound pack selector in menu
2. Launch at login toggle
3. Persist settings

## 1. Sound Pack Selector

### Model: SoundPackManager

```swift
struct SoundPack: Identifiable {
    let id: String
    let label: String
    let directory: URL
}

final class SoundPackManager {
    var availablePacks: [SoundPack] { get }
    func loadPacks(from assetsURL: URL)  // Reads manifest.json
}
```

### Menu Integration

- Submenu "Sound Pack" with radio items
- Check current selection
- On selection change: 
  1. Update SettingsStore.selectedPack
  2. Call soundEngine.preloadPack(directory:)

### SettingsStore Changes

```swift
@Published var selectedPack: String = "mx-speed-silver"
```

## 2. Launch at Login

### ServiceManagement Approach (macOS 13+)

```swift
import ServiceManagement

func setLaunchAtLogin(_ enabled: Bool) {
    do {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    } catch {
        print("[mach] Launch at login error: \(error)")
    }
}

func isLaunchAtLoginEnabled() -> Bool {
    SMAppService.mainApp.status == .enabled
}
```

### Menu Integration

- "Launch at Login" toggle item
- Check current state on menu open
- Toggle calls setLaunchAtLogin()

### SettingsStore Changes

```swift
@Published var launchAtLogin: Bool
// Note: This reflects SMAppService.mainApp.status, synced at menu display
```

## File Changes

- New: `Sources/mach/SoundPackManager.swift`
- Update: `SettingsStore.swift` - add selectedPack, launchAtLogin
- Update: `StatusBarController.swift` - add submenus
- Update: `MachApp.swift` - wire up pack changes
