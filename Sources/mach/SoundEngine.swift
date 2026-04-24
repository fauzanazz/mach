import AVFoundation
import Foundation

private struct BuiltinSlice {
    let startMs: Double
    let durationMs: Double
}

private struct ResolvedPerKeyPack {
    let downBuffers: [Int: AVAudioPCMBuffer]
    let upBuffers: [Int: AVAudioPCMBuffer]
    let format: AVAudioFormat
}

private enum KeyPhase {
    case down
    case up
}

private func soundLog(_ message: String) {
    let msg = "\(Date()): [sound] \(message)\n"
    let logPath = NSHomeDirectory() + "/mach-debug.log"
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(msg.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: msg.data(using: .utf8))
    }
}

final class SoundEngine {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayerIndex = 0
    private var connectedFormat: AVAudioFormat?

    private var randomBuffers: [AVAudioPCMBuffer] = []
    private var perKeyDownBuffers: [Int: AVAudioPCMBuffer] = [:]
    private var perKeyUpBuffers: [Int: AVAudioPCMBuffer] = [:]
    private var perKeyMode = false

    var volume: Float = 0.75

    init() {
        soundLog("SoundEngine init")

        // Attach a small player pool up front; we connect once we know pack format.
        for _ in 0..<8 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            players.append(player)
        }

        // Engine starts lazily once a pack is loaded and players are connected.
    }

    func preloadPack(packId: String, audioURLs: [URL], configURL: URL?) throws {
        soundLog(
            "preloadPack: packId=\(packId), audioCount=\(audioURLs.count), config=\(configURL?.lastPathComponent ?? "nil")"
        )

        perKeyMode = false
        perKeyDownBuffers = [:]
        perKeyUpBuffers = [:]
        randomBuffers = []

        if let configURL,
           let resolved = try resolvePerKeyPack(audioURLs: audioURLs, configURL: configURL) {
            reconnectPlayersIfNeeded(format: resolved.format)
            perKeyDownBuffers = resolved.downBuffers
            perKeyUpBuffers = resolved.upBuffers
            perKeyMode = true
            soundLog("Loaded config per-key map: down=\(perKeyDownBuffers.count), up=\(perKeyUpBuffers.count)")
            return
        }

        if packId == "default",
           let resolved = try resolveBuiltinDefaultPack(audioURLs: audioURLs) {
            reconnectPlayersIfNeeded(format: resolved.format)
            perKeyDownBuffers = resolved.downBuffers
            perKeyUpBuffers = resolved.upBuffers
            perKeyMode = true
            soundLog("Loaded built-in default map: down=\(perKeyDownBuffers.count), up=\(perKeyUpBuffers.count)")
            return
        }

        let fallback = try loadRandomBuffers(from: audioURLs)
        randomBuffers = fallback.buffers

        if let format = fallback.format {
            reconnectPlayersIfNeeded(format: format)
        }

        soundLog("Loaded fallback random buffers: \(randomBuffers.count)")
    }

    func playKeyDown(keyCode: UInt16) {
        if perKeyMode {
            _ = playPerKey(keyCode: keyCode, phase: .down)
            return
        }

        _ = playRandom(reason: "playKeyDown")
    }

    func playKeyUp(keyCode: UInt16) {
        if perKeyMode {
            if playPerKey(keyCode: keyCode, phase: .up) {
                return
            }

            // Fallback: if pack has no explicit key-up map (or key is missing),
            // reuse key-down mapping so release still produces a sound.
            _ = playPerKey(keyCode: keyCode, phase: .down)
            return
        }

        // Random-only packs should also emit release sounds.
        _ = playRandom(reason: "playKeyUp")
    }

    @discardableResult
    private func playPerKey(keyCode: UInt16, phase: KeyPhase) -> Bool {
        let bufferMap: [Int: AVAudioPCMBuffer] = phase == .down ? perKeyDownBuffers : perKeyUpBuffers
        guard !bufferMap.isEmpty else {
            return false
        }

        let scancodes = MAC_KEYCODE_TO_SCANCODES[keyCode] ?? []
        guard !scancodes.isEmpty else {
            return false
        }

        for scancode in scancodes {
            if let buffer = bufferMap[scancode] {
                play(buffer: buffer)
                return true
            }
        }

        return false
    }

    @discardableResult
    private func playRandom(reason: String) -> Bool {
        guard !randomBuffers.isEmpty else {
            soundLog("\(reason): NO BUFFERS")
            return false
        }

        let buffer = randomBuffers[Int.random(in: 0..<randomBuffers.count)]
        play(buffer: buffer)
        return true
    }

    private func play(buffer: AVAudioPCMBuffer) {
        guard engine.isRunning else {
            soundLog("play: engine not running")
            return
        }

        let player = players[nextPlayerIndex % players.count]
        nextPlayerIndex = (nextPlayerIndex + 1) % players.count

        if player.isPlaying { player.stop() }
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    private func resolvePerKeyPack(
        audioURLs: [URL],
        configURL: URL
    ) throws -> ResolvedPerKeyPack? {
        guard let rawConfig = loadRawConfig(from: configURL) else {
            return nil
        }

        let rawDownDefines = (rawConfig["defines_down"] as? [String: Any])
            ?? (rawConfig["defines"] as? [String: Any])
            ?? [:]
        let rawUpDefines = (rawConfig["defines_up"] as? [String: Any]) ?? [:]

        if rawDownDefines.isEmpty && rawUpDefines.isEmpty {
            soundLog("No usable defines in config: \(configURL.lastPathComponent)")
            return nil
        }

        let allRawValues = Array(rawDownDefines.values) + Array(rawUpDefines.values)
        let hasSliceDefines = allRawValues.contains(where: isSliceDefine)

        var targetFormat: AVAudioFormat?
        var spriteBuffer: AVAudioPCMBuffer?

        if hasSliceDefines {
            guard let spriteURL = audioURLs.first else {
                soundLog("Config has slice defines but no base audio file")
                return nil
            }

            let loadedSprite = try loadBuffer(url: spriteURL, expectedFormat: nil)
            guard let decodedSprite = loadedSprite.buffer else {
                soundLog("Failed to decode sprite audio: \(spriteURL.lastPathComponent)")
                return nil
            }

            spriteBuffer = decodedSprite
            targetFormat = loadedSprite.format
        }

        let configBaseDir = configURL.deletingLastPathComponent()
        let sampleNames: Set<String> = Set(allRawValues.compactMap { rawValue in
            guard let filename = rawValue as? String, !filename.isEmpty else { return nil }
            return filename
        })

        var sampleBuffers: [String: AVAudioPCMBuffer] = [:]
        for filename in sampleNames {
            let sampleURL = configBaseDir.appendingPathComponent(filename)
            let loaded = try loadBuffer(url: sampleURL, expectedFormat: targetFormat)
            if let sampleBuffer = loaded.buffer {
                if targetFormat == nil {
                    targetFormat = loaded.format
                }
                sampleBuffers[filename] = sampleBuffer
            } else {
                soundLog("Skipping \(filename): incompatible format")
            }
        }

        guard let resolvedFormat = targetFormat else {
            soundLog("No audio data could be resolved for config pack")
            return nil
        }

        let downBuffers = resolveKeyBuffers(
            rawDefines: rawDownDefines,
            spriteBuffer: spriteBuffer,
            sampleBuffers: sampleBuffers
        )
        let upBuffers = resolveKeyBuffers(
            rawDefines: rawUpDefines,
            spriteBuffer: spriteBuffer,
            sampleBuffers: sampleBuffers
        )

        if downBuffers.isEmpty && upBuffers.isEmpty {
            soundLog("Resolved config pack has 0 playable key mappings")
            return nil
        }

        return ResolvedPerKeyPack(
            downBuffers: downBuffers,
            upBuffers: upBuffers,
            format: resolvedFormat
        )
    }

    private func resolveBuiltinDefaultPack(audioURLs: [URL]) throws -> ResolvedPerKeyPack? {
        guard let spriteURL = audioURLs.first else {
            soundLog("Default pack has no audio file")
            return nil
        }

        let loadedSprite = try loadBuffer(url: spriteURL, expectedFormat: nil)
        guard let spriteBuffer = loadedSprite.buffer else {
            soundLog("Failed to decode default pack sprite")
            return nil
        }

        var downBuffers: [Int: AVAudioPCMBuffer] = [:]
        for (scancode, slice) in BUILTIN_DEFAULT_DOWN_BY_SCANCODE {
            if let buffer = makeSliceBuffer(
                from: spriteBuffer,
                startMs: slice.startMs,
                durationMs: slice.durationMs
            ) {
                downBuffers[scancode] = buffer
            }
        }

        var upBuffers: [Int: AVAudioPCMBuffer] = [:]
        for (scancode, slice) in BUILTIN_DEFAULT_UP_BY_SCANCODE {
            if let buffer = makeSliceBuffer(
                from: spriteBuffer,
                startMs: slice.startMs,
                durationMs: slice.durationMs
            ) {
                upBuffers[scancode] = buffer
            }
        }

        guard !downBuffers.isEmpty else {
            soundLog("Built-in default map resolved to 0 keydown buffers")
            return nil
        }

        return ResolvedPerKeyPack(
            downBuffers: downBuffers,
            upBuffers: upBuffers,
            format: loadedSprite.format
        )
    }

    private func resolveKeyBuffers(
        rawDefines: [String: Any],
        spriteBuffer: AVAudioPCMBuffer?,
        sampleBuffers: [String: AVAudioPCMBuffer]
    ) -> [Int: AVAudioPCMBuffer] {
        var keyBuffers: [Int: AVAudioPCMBuffer] = [:]

        for (scancodeString, rawValue) in rawDefines {
            guard let scancode = Int(scancodeString) else {
                continue
            }

            if let filename = rawValue as? String {
                if let sampleBuffer = sampleBuffers[filename] {
                    keyBuffers[scancode] = sampleBuffer
                }
                continue
            }

            guard
                let spriteBuffer,
                let (startMs, durationMs) = parseSlice(rawValue),
                let sliceBuffer = makeSliceBuffer(
                    from: spriteBuffer,
                    startMs: startMs,
                    durationMs: durationMs
                )
            else {
                continue
            }

            keyBuffers[scancode] = sliceBuffer
        }

        return keyBuffers
    }

    private func loadRandomBuffers(
        from audioURLs: [URL]
    ) throws -> (buffers: [AVAudioPCMBuffer], format: AVAudioFormat?) {
        guard let firstURL = audioURLs.first else {
            return ([], nil)
        }

        let firstLoaded = try loadBuffer(url: firstURL, expectedFormat: nil)
        guard let firstBuffer = firstLoaded.buffer else {
            return ([], nil)
        }

        let targetFormat = firstLoaded.format
        var loadedBuffers: [AVAudioPCMBuffer] = [firstBuffer]

        for url in audioURLs.dropFirst() {
            let loaded = try loadBuffer(url: url, expectedFormat: targetFormat)
            if let buffer = loaded.buffer {
                loadedBuffers.append(buffer)
            } else {
                soundLog("Skipping \(url.lastPathComponent): incompatible format")
            }
        }

        return (loadedBuffers, targetFormat)
    }

    private func loadBuffer(
        url: URL,
        expectedFormat: AVAudioFormat?
    ) throws -> (buffer: AVAudioPCMBuffer?, format: AVAudioFormat) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat

        if let expectedFormat, !formatsMatch(format, expectedFormat) {
            return (nil, format)
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        try file.read(into: buffer)
        return (buffer, format)
    }

    private func loadRawConfig(from configURL: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: configURL) else {
            soundLog("Failed to read config: \(configURL.path)")
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            soundLog("Failed to parse config JSON: \(configURL.lastPathComponent)")
            return nil
        }

        return json
    }

    private func isSliceDefine(_ rawValue: Any) -> Bool {
        guard let array = rawValue as? [Any], array.count >= 2 else {
            return false
        }

        return numberValue(from: array[0]) != nil && numberValue(from: array[1]) != nil
    }

    private func parseSlice(_ rawValue: Any) -> (Double, Double)? {
        guard
            let array = rawValue as? [Any],
            array.count >= 2,
            let startMs = numberValue(from: array[0]),
            let durationMs = numberValue(from: array[1]),
            durationMs > 0
        else {
            return nil
        }

        return (startMs, durationMs)
    }

    private func numberValue(from rawValue: Any) -> Double? {
        if let number = rawValue as? NSNumber {
            return number.doubleValue
        }
        if let text = rawValue as? String {
            return Double(text)
        }
        return nil
    }

    private func makeSliceBuffer(
        from source: AVAudioPCMBuffer,
        startMs: Double,
        durationMs: Double
    ) -> AVAudioPCMBuffer? {
        let sampleRate = source.format.sampleRate
        let startFrame = Int((startMs / 1000.0) * sampleRate)
        let requestedFrames = Int((durationMs / 1000.0) * sampleRate)
        return copyFrames(from: source, startFrame: startFrame, requestedFrames: requestedFrames)
    }

    private func copyFrames(
        from source: AVAudioPCMBuffer,
        startFrame: Int,
        requestedFrames: Int
    ) -> AVAudioPCMBuffer? {
        guard requestedFrames > 0 else {
            return nil
        }

        let totalFrames = Int(source.frameLength)
        guard startFrame >= 0, startFrame < totalFrames else {
            return nil
        }

        let frameCount = min(requestedFrames, totalFrames - startFrame)
        guard frameCount > 0 else {
            return nil
        }

        guard !source.format.isInterleaved else {
            soundLog("Interleaved audio format not supported for slicing")
            return nil
        }

        guard let destination = AVAudioPCMBuffer(
            pcmFormat: source.format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            return nil
        }

        destination.frameLength = AVAudioFrameCount(frameCount)
        let channels = Int(source.format.channelCount)

        switch source.format.commonFormat {
        case .pcmFormatFloat32:
            guard
                let sourceChannels = source.floatChannelData,
                let destinationChannels = destination.floatChannelData
            else {
                return nil
            }

            for channel in 0..<channels {
                let src = sourceChannels[channel]
                let dst = destinationChannels[channel]
                for frame in 0..<frameCount {
                    dst[frame] = src[startFrame + frame]
                }
            }

        case .pcmFormatInt16:
            guard
                let sourceChannels = source.int16ChannelData,
                let destinationChannels = destination.int16ChannelData
            else {
                return nil
            }

            for channel in 0..<channels {
                let src = sourceChannels[channel]
                let dst = destinationChannels[channel]
                for frame in 0..<frameCount {
                    dst[frame] = src[startFrame + frame]
                }
            }

        case .pcmFormatInt32:
            guard
                let sourceChannels = source.int32ChannelData,
                let destinationChannels = destination.int32ChannelData
            else {
                return nil
            }

            for channel in 0..<channels {
                let src = sourceChannels[channel]
                let dst = destinationChannels[channel]
                for frame in 0..<frameCount {
                    dst[frame] = src[startFrame + frame]
                }
            }

        default:
            soundLog("Unsupported audio format for slicing")
            return nil
        }

        return destination
    }

    private func reconnectPlayersIfNeeded(format: AVAudioFormat) {
        let needsReconnect = {
            guard let connectedFormat else { return true }
            return !formatsMatch(connectedFormat, format)
        }()

        if needsReconnect {
            if engine.isRunning {
                engine.stop()
            }

            let mixer = engine.mainMixerNode
            for player in players {
                player.stop()
                engine.disconnectNodeOutput(player)
                engine.connect(player, to: mixer, format: format)
            }

            connectedFormat = format
            soundLog(
                "Connected players format: sr=\(format.sampleRate), ch=\(format.channelCount), interleaved=\(format.isInterleaved)"
            )
        }

        if !engine.isRunning {
            do {
                try engine.start()
                soundLog("AVAudioEngine started")
            } catch {
                soundLog("AVAudioEngine failed: \(error)")
            }
        }
    }

    private func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }
}

private let BUILTIN_DEFAULT_DOWN_BY_SCANCODE: [Int: BuiltinSlice] = [
    1: BuiltinSlice(startMs: 9069, durationMs: 115),
    2: BuiltinSlice(startMs: 2280, durationMs: 109),
    3: BuiltinSlice(startMs: 9444, durationMs: 102),
    4: BuiltinSlice(startMs: 9833, durationMs: 103),
    5: BuiltinSlice(startMs: 10185, durationMs: 107),
    6: BuiltinSlice(startMs: 10551, durationMs: 108),
    7: BuiltinSlice(startMs: 10899, durationMs: 107),
    8: BuiltinSlice(startMs: 11282, durationMs: 99),
    9: BuiltinSlice(startMs: 11623, durationMs: 103),
    10: BuiltinSlice(startMs: 11976, durationMs: 110),
    11: BuiltinSlice(startMs: 12337, durationMs: 108),
    12: BuiltinSlice(startMs: 12667, durationMs: 107),
    13: BuiltinSlice(startMs: 13058, durationMs: 105),
    14: BuiltinSlice(startMs: 13765, durationMs: 101),
    15: BuiltinSlice(startMs: 15916, durationMs: 97),
    16: BuiltinSlice(startMs: 16284, durationMs: 83),
    17: BuiltinSlice(startMs: 16637, durationMs: 97),
    18: BuiltinSlice(startMs: 16964, durationMs: 105),
    19: BuiltinSlice(startMs: 17275, durationMs: 102),
    20: BuiltinSlice(startMs: 17613, durationMs: 108),
    21: BuiltinSlice(startMs: 17957, durationMs: 95),
    22: BuiltinSlice(startMs: 18301, durationMs: 105),
    23: BuiltinSlice(startMs: 18643, durationMs: 110),
    24: BuiltinSlice(startMs: 18994, durationMs: 98),
    25: BuiltinSlice(startMs: 19331, durationMs: 108),
    26: BuiltinSlice(startMs: 19671, durationMs: 94),
    27: BuiltinSlice(startMs: 20020, durationMs: 96),
    28: BuiltinSlice(startMs: 26703, durationMs: 100),
    29: BuiltinSlice(startMs: 8036, durationMs: 92),
    30: BuiltinSlice(startMs: 22869, durationMs: 109),
    31: BuiltinSlice(startMs: 23237, durationMs: 98),
    32: BuiltinSlice(startMs: 23586, durationMs: 103),
    33: BuiltinSlice(startMs: 23898, durationMs: 98),
    34: BuiltinSlice(startMs: 24237, durationMs: 102),
    35: BuiltinSlice(startMs: 24550, durationMs: 106),
    36: BuiltinSlice(startMs: 24917, durationMs: 103),
    37: BuiltinSlice(startMs: 25274, durationMs: 102),
    38: BuiltinSlice(startMs: 25625, durationMs: 101),
    39: BuiltinSlice(startMs: 25989, durationMs: 100),
    40: BuiltinSlice(startMs: 26335, durationMs: 99),
    41: BuiltinSlice(startMs: 9069, durationMs: 115),
    42: BuiltinSlice(startMs: 28109, durationMs: 99),
    43: BuiltinSlice(startMs: 20387, durationMs: 97),
    44: BuiltinSlice(startMs: 28550, durationMs: 92),
    45: BuiltinSlice(startMs: 28855, durationMs: 101),
    46: BuiltinSlice(startMs: 29557, durationMs: 112),
    47: BuiltinSlice(startMs: 29557, durationMs: 112),
    48: BuiltinSlice(startMs: 29909, durationMs: 98),
    49: BuiltinSlice(startMs: 30252, durationMs: 112),
    50: BuiltinSlice(startMs: 30605, durationMs: 101),
    51: BuiltinSlice(startMs: 30965, durationMs: 117),
    52: BuiltinSlice(startMs: 31315, durationMs: 97),
    53: BuiltinSlice(startMs: 31659, durationMs: 96),
    54: BuiltinSlice(startMs: 28109, durationMs: 99),
    56: BuiltinSlice(startMs: 34551, durationMs: 96),
    57: BuiltinSlice(startMs: 33857, durationMs: 100),
    58: BuiltinSlice(startMs: 22560, durationMs: 100),
    59: BuiltinSlice(startMs: 2754, durationMs: 104),
    60: BuiltinSlice(startMs: 3155, durationMs: 99),
    61: BuiltinSlice(startMs: 3545, durationMs: 103),
    62: BuiltinSlice(startMs: 3913, durationMs: 100),
    63: BuiltinSlice(startMs: 4305, durationMs: 96),
    64: BuiltinSlice(startMs: 4666, durationMs: 103),
    65: BuiltinSlice(startMs: 5034, durationMs: 110),
    66: BuiltinSlice(startMs: 5433, durationMs: 103),
    67: BuiltinSlice(startMs: 7795, durationMs: 109),
    68: BuiltinSlice(startMs: 6146, durationMs: 105),
    87: BuiltinSlice(startMs: 7322, durationMs: 97),
    88: BuiltinSlice(startMs: 7699, durationMs: 98),
    100: BuiltinSlice(startMs: 2754, durationMs: 104),
    101: BuiltinSlice(startMs: 3155, durationMs: 99),
    3613: BuiltinSlice(startMs: 8036, durationMs: 92),
    3640: BuiltinSlice(startMs: 35878, durationMs: 90),
    3655: BuiltinSlice(startMs: 20766, durationMs: 102),
    3657: BuiltinSlice(startMs: 14522, durationMs: 108),
    3663: BuiltinSlice(startMs: 21409, durationMs: 83),
    3665: BuiltinSlice(startMs: 14852, durationMs: 93),
    3667: BuiltinSlice(startMs: 14199, durationMs: 100),
    3675: BuiltinSlice(startMs: 34551, durationMs: 96),
    3676: BuiltinSlice(startMs: 34181, durationMs: 97),
    57373: BuiltinSlice(startMs: 8036, durationMs: 92),
    57400: BuiltinSlice(startMs: 35878, durationMs: 90),
    57415: BuiltinSlice(startMs: 20766, durationMs: 102),
    57416: BuiltinSlice(startMs: 32429, durationMs: 96),
    57417: BuiltinSlice(startMs: 14522, durationMs: 108),
    57419: BuiltinSlice(startMs: 36907, durationMs: 90),
    57421: BuiltinSlice(startMs: 37586, durationMs: 88),
    57423: BuiltinSlice(startMs: 21409, durationMs: 83),
    57424: BuiltinSlice(startMs: 37267, durationMs: 94),
    57425: BuiltinSlice(startMs: 14852, durationMs: 93),
    57427: BuiltinSlice(startMs: 14199, durationMs: 100),
    57435: BuiltinSlice(startMs: 34551, durationMs: 96),
    57436: BuiltinSlice(startMs: 34181, durationMs: 97),
]

private let BUILTIN_DEFAULT_UP_BY_SCANCODE: [Int: BuiltinSlice] = [
    1: BuiltinSlice(startMs: 9184, durationMs: 94),
    2: BuiltinSlice(startMs: 2389, durationMs: 90),
    3: BuiltinSlice(startMs: 9546, durationMs: 83),
    4: BuiltinSlice(startMs: 9936, durationMs: 84),
    5: BuiltinSlice(startMs: 10292, durationMs: 87),
    6: BuiltinSlice(startMs: 10659, durationMs: 88),
    7: BuiltinSlice(startMs: 11006, durationMs: 87),
    8: BuiltinSlice(startMs: 11381, durationMs: 81),
    9: BuiltinSlice(startMs: 11726, durationMs: 85),
    10: BuiltinSlice(startMs: 12086, durationMs: 90),
    11: BuiltinSlice(startMs: 12445, durationMs: 89),
    12: BuiltinSlice(startMs: 12774, durationMs: 87),
    13: BuiltinSlice(startMs: 13163, durationMs: 86),
    14: BuiltinSlice(startMs: 13866, durationMs: 83),
    15: BuiltinSlice(startMs: 16013, durationMs: 79),
    16: BuiltinSlice(startMs: 16367, durationMs: 67),
    17: BuiltinSlice(startMs: 16734, durationMs: 79),
    18: BuiltinSlice(startMs: 17069, durationMs: 85),
    19: BuiltinSlice(startMs: 17377, durationMs: 83),
    20: BuiltinSlice(startMs: 17721, durationMs: 88),
    21: BuiltinSlice(startMs: 18052, durationMs: 78),
    22: BuiltinSlice(startMs: 18406, durationMs: 85),
    23: BuiltinSlice(startMs: 18753, durationMs: 90),
    24: BuiltinSlice(startMs: 19092, durationMs: 80),
    25: BuiltinSlice(startMs: 19439, durationMs: 89),
    26: BuiltinSlice(startMs: 19765, durationMs: 77),
    27: BuiltinSlice(startMs: 20116, durationMs: 79),
    28: BuiltinSlice(startMs: 26803, durationMs: 81),
    29: BuiltinSlice(startMs: 8128, durationMs: 76),
    30: BuiltinSlice(startMs: 22978, durationMs: 89),
    31: BuiltinSlice(startMs: 23335, durationMs: 80),
    32: BuiltinSlice(startMs: 23689, durationMs: 84),
    33: BuiltinSlice(startMs: 23996, durationMs: 81),
    34: BuiltinSlice(startMs: 24339, durationMs: 83),
    35: BuiltinSlice(startMs: 24656, durationMs: 86),
    36: BuiltinSlice(startMs: 25020, durationMs: 85),
    37: BuiltinSlice(startMs: 25376, durationMs: 83),
    38: BuiltinSlice(startMs: 25726, durationMs: 82),
    39: BuiltinSlice(startMs: 26089, durationMs: 82),
    40: BuiltinSlice(startMs: 26434, durationMs: 81),
    41: BuiltinSlice(startMs: 9184, durationMs: 94),
    42: BuiltinSlice(startMs: 28208, durationMs: 81),
    43: BuiltinSlice(startMs: 20484, durationMs: 79),
    44: BuiltinSlice(startMs: 28642, durationMs: 75),
    45: BuiltinSlice(startMs: 28956, durationMs: 83),
    46: BuiltinSlice(startMs: 29669, durationMs: 92),
    47: BuiltinSlice(startMs: 29669, durationMs: 92),
    48: BuiltinSlice(startMs: 30007, durationMs: 81),
    49: BuiltinSlice(startMs: 30364, durationMs: 91),
    50: BuiltinSlice(startMs: 30706, durationMs: 83),
    51: BuiltinSlice(startMs: 31082, durationMs: 95),
    52: BuiltinSlice(startMs: 31412, durationMs: 79),
    53: BuiltinSlice(startMs: 31755, durationMs: 79),
    54: BuiltinSlice(startMs: 28208, durationMs: 81),
    56: BuiltinSlice(startMs: 34647, durationMs: 79),
    57: BuiltinSlice(startMs: 33957, durationMs: 82),
    58: BuiltinSlice(startMs: 22660, durationMs: 81),
    59: BuiltinSlice(startMs: 2858, durationMs: 85),
    60: BuiltinSlice(startMs: 3254, durationMs: 81),
    61: BuiltinSlice(startMs: 3648, durationMs: 84),
    62: BuiltinSlice(startMs: 4013, durationMs: 83),
    63: BuiltinSlice(startMs: 4401, durationMs: 78),
    64: BuiltinSlice(startMs: 4769, durationMs: 84),
    65: BuiltinSlice(startMs: 5144, durationMs: 90),
    66: BuiltinSlice(startMs: 5536, durationMs: 84),
    67: BuiltinSlice(startMs: 7904, durationMs: 89),
    68: BuiltinSlice(startMs: 6251, durationMs: 86),
    87: BuiltinSlice(startMs: 7419, durationMs: 80),
    88: BuiltinSlice(startMs: 7797, durationMs: 80),
    100: BuiltinSlice(startMs: 2858, durationMs: 85),
    101: BuiltinSlice(startMs: 3254, durationMs: 81),
    3613: BuiltinSlice(startMs: 8128, durationMs: 76),
    3640: BuiltinSlice(startMs: 35968, durationMs: 74),
    3655: BuiltinSlice(startMs: 20868, durationMs: 83),
    3657: BuiltinSlice(startMs: 14630, durationMs: 88),
    3663: BuiltinSlice(startMs: 21492, durationMs: 68),
    3665: BuiltinSlice(startMs: 14945, durationMs: 76),
    3667: BuiltinSlice(startMs: 14299, durationMs: 81),
    3675: BuiltinSlice(startMs: 34647, durationMs: 79),
    3676: BuiltinSlice(startMs: 34278, durationMs: 80),
    57373: BuiltinSlice(startMs: 8128, durationMs: 76),
    57400: BuiltinSlice(startMs: 35968, durationMs: 74),
    57415: BuiltinSlice(startMs: 20868, durationMs: 83),
    57416: BuiltinSlice(startMs: 32525, durationMs: 78),
    57417: BuiltinSlice(startMs: 14630, durationMs: 88),
    57419: BuiltinSlice(startMs: 36997, durationMs: 73),
    57421: BuiltinSlice(startMs: 37674, durationMs: 72),
    57423: BuiltinSlice(startMs: 21492, durationMs: 68),
    57424: BuiltinSlice(startMs: 37361, durationMs: 76),
    57425: BuiltinSlice(startMs: 14945, durationMs: 76),
    57427: BuiltinSlice(startMs: 14299, durationMs: 81),
    57435: BuiltinSlice(startMs: 34647, durationMs: 79),
    57436: BuiltinSlice(startMs: 34278, durationMs: 80),
]

// KeyZen-style scancode candidates mapped from macOS virtual key codes (CGKeyCode).
private let MAC_KEYCODE_TO_SCANCODES: [UInt16: [Int]] = [
    // Escape / digits / symbols
    53: [1],
    18: [2], 19: [3], 20: [4], 21: [5], 23: [6],
    22: [7], 26: [8], 28: [9], 25: [10], 29: [11],
    27: [12], 24: [13], 51: [14],

    // Tab + alpha rows
    48: [15],
    12: [16], 13: [17], 14: [18], 15: [19], 17: [20],
    16: [21], 32: [22], 34: [23], 31: [24], 35: [25],
    33: [26], 30: [27], 36: [28],

    // Modifiers + middle rows
    59: [29],
    0: [30], 1: [31], 2: [32], 3: [33], 5: [34],
    4: [35], 38: [36], 40: [37], 37: [38], 41: [39],
    39: [40], 50: [41], 56: [42], 42: [43], 6: [44],
    7: [45], 8: [46], 9: [47], 11: [48], 45: [49],
    46: [50], 43: [51], 47: [52], 44: [53], 60: [54],

    // Bottom-row modifiers
    58: [56],
    49: [57],
    57: [58],

    // Function keys
    122: [59], 120: [60], 99: [61], 118: [62],
    96: [63], 97: [64], 98: [65], 100: [66],
    101: [67], 109: [68], 103: [87], 111: [88],
    105: [100, 88], 107: [101, 88],

    // Right-side/extended keys
    63: [29], // Fn
    62: [57373, 3613], // ControlRight
    61: [57400, 3640], // AltRight
    55: [57435, 3675], // MetaLeft
    54: [57436, 3676], // MetaRight
    115: [57415, 3655], // Home
    119: [57423, 3663], // End
    116: [57417, 3657], // PageUp
    121: [57425, 3665], // PageDown
    117: [57427, 3667], // Delete (Forward Delete)
    126: [57416], // ArrowUp
    123: [57419], // ArrowLeft
    124: [57421], // ArrowRight
    125: [57424], // ArrowDown
]
