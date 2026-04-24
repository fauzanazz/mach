# Milestone 3: Audio Playback Design

## Goal
Low-latency, overlap-safe audio playback on key press using AVAudioEngine.

## Sound Pack Types

1. **multi-sample**: Individual WAV files, randomly select one per key press
2. **sprite+config**: Single OGG with [start_ms, duration_ms] per key (defer to M4)

## MVP Scope
- Support multi-sample packs only (mx-speed-silver)
- Random sample selection per key press
- Volume control from SettingsStore

## Technical Approach

### SoundEngine.swift

```swift
final class SoundEngine {
    func preload(packId: String) throws
    func playKeyDown()  // Uses current volume from SettingsStore
    var volume: Float { get set }
}
```

### Implementation Details

1. **AVAudioEngine setup**:
   - `AVAudioEngine` as main engine
   - Pool of `AVAudioPlayerNode` (8-16) for overlapping sounds
   - Preload `AVAudioPCMBuffer` for each sample

2. **Playback strategy**:
   - Round-robin through player pool to ensure overlap works
   - Schedule buffer on next available player
   - Volume applied via player.volume

3. **Preloading**:
   - Read WAV files into `AVAudioPCMBuffer` at startup
   - Keep in memory for instant playback

4. **Random selection**:
   - Pick random sample from loaded buffers
   - Ensures natural sound variation

### Integration

- AppDelegate creates SoundEngine, passes to keyboardMonitor.onKeyDown
- Volume from SettingsStore observed and applied to engine

### File Changes
- New: `Sources/mach/SoundEngine.swift`
- Update: `MachApp.swift` - create engine, wire to onKeyDown
- Update: Package.swift - may need to bundle sound assets
