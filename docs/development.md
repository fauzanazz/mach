# mach Development Guide

## Requirements

- macOS 13+
- Xcode Command Line Tools
- Swift 5.9+

Install toolchain if needed:

```bash
xcode-select --install
```

## Building

```bash
git clone https://github.com/fauzanazz/mach.git
cd mach
swift build
```

Build app bundle:

```bash
scripts/build-app.sh
```

Run:

```bash
open mach.app
```

## How It Works

1. `KeyboardEventMonitor` captures key down/up keycodes globally.
2. `SoundPackManager` loads pack metadata from `assets/manifest.json`.
3. `SoundEngine` resolves per-key buffers from config (or built-in default map).
4. On each key event, the engine routes to matching key sound (or random fallback).

### Core Source Files

| File | Purpose |
|------|---------|
| `Sources/mach/MachApp.swift` | App bootstrap + wiring |
| `Sources/mach/KeyboardEventMonitor.swift` | Global key capture |
| `Sources/mach/SoundEngine.swift` | Audio engine + key routing |
| `Sources/mach/SoundPackManager.swift` | Manifest/resource resolver |
| `Sources/mach/StatusBarController.swift` | Menu bar UI |
| `Sources/mach/SettingsStore.swift` | Persisted settings |

## Sound Pack Format

Packs are defined in `assets/manifest.json`.
Each pack can include one or more audio files and an optional config file.

### Manifest Fields

- `id` — pack identifier
- `label` — display name in UI
- `kind` — pack type metadata
- `audio` — audio file list
- `config` — optional config JSON path

### Config Mapping Keys

- `defines_down` (preferred) or `defines` for keydown
- `defines_up` for keyup

Mapping values support:

- sprite slice: `[startMs, durationMs]`
- sample filename string: `"key-01.wav"`

### Behavior Fallback Order

1. Config per-key map (if valid)
2. Built-in default map (for `packId == "default"`)
3. Random playback from available audio buffers

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/build-app.sh` | Build + bundle app |
| `scripts/release-preflight.sh` | Release checks (tools/plist/bundle/signing inputs) |
| `scripts/release-sign-notarize.sh` | Sign + notarize ZIP (+ optional DMG) |
| `scripts/generate-icon.sh` | Regenerate `Resources/mach.icns` |

## CI/CD

Workflows:

- `.github/workflows/ci.yml`
  - Build + preflight on push / PR
  - Uploads unsigned app artifact
- `.github/workflows/release.yml`
  - Signed + notarized release on `v*` tag or manual dispatch
  - Validates tag version vs `CFBundleShortVersionString`
- `.github/workflows/version-bump.yml`
  - Bumps `CFBundleShortVersionString` + `CFBundleVersion`
  - Supports PR flow (default) or direct push

## Signing Certificate (Developer ID Application)

1. Create CSR in **Keychain Access**
2. In Apple Developer portal, create **Developer ID Application** cert
3. Install downloaded `.cer`
4. Verify identity:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

5. Export cert + private key as `.p12`
6. Base64-encode for GitHub secret:

```bash
base64 -i /path/to/developer-id.p12 | tr -d '\n'
```

Use as `APPLE_SIGNING_CERT_BASE64`.
