# Milestone 1: Menu Bar Skeleton Design

## Goal
Create a menu bar-only macOS app with basic controls (toggle, volume, quit).

## Technical Approach

### Project Structure
```
mach/
├── Package.swift
├── Sources/
│   └── mach/
│       ├── MachApp.swift          # @main entry point
│       ├── StatusBarController.swift # NSStatusItem management
│       └── SettingsStore.swift    # @AppStorage-based state
└── Resources/
    └── Info.plist                 # LSUIElement = 1
```

### Key Implementation Details

1. **No Dock Icon**: Set `LSUIElement = 1` in Info.plist
2. **Menu Bar Icon**: Use SF Symbol `keyboard` or custom icon
3. **Menu Structure**:
   - Toggle: "Enable Sounds" with checkmark
   - Volume: Slider (0-100%)
   - Separator
   - Quit

4. **State Management**: `SettingsStore` with `@AppStorage` for:
   - `isEnabled: Bool`
   - `volume: Double`

### Build System
Using Swift Package Manager with executable target. Build with:
```bash
swift build -c release
```

## Files to Create
1. `Package.swift` - SPM manifest
2. `Sources/mach/MachApp.swift` - App entry
3. `Sources/mach/StatusBarController.swift` - Menu bar logic
4. `Sources/mach/SettingsStore.swift` - Settings persistence
5. `Resources/Info.plist` - App configuration
