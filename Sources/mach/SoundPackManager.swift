import Foundation

struct SoundPack: Identifiable {
    let id: String
    let label: String
    let kind: String
    let audioFiles: [String]
    let configFile: String?
}

final class SoundPackManager {
    private(set) var packs: [SoundPack] = []
    private var assetsURL: URL?

    func loadManifest(from assetsURL: URL) {
        self.assetsURL = assetsURL
        let manifestURL = assetsURL.appendingPathComponent("manifest.json")

        guard
            let data = try? Data(contentsOf: manifestURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawPacks = json["packs"] as? [[String: Any]]
        else {
            print("[mach] Failed to parse manifest at \(manifestURL.path)")
            return
        }

        packs = rawPacks.compactMap { entry in
            guard
                let id = entry["id"] as? String,
                let label = entry["label"] as? String,
                let kind = entry["kind"] as? String,
                let audio = entry["audio"] as? [String]
            else { return nil }

            let config = entry["config"] as? String
            return SoundPack(id: id, label: label, kind: kind, audioFiles: audio, configFile: config)
        }
    }

    func pack(for packId: String) -> SoundPack? {
        packs.first(where: { $0.id == packId })
    }

    func resources(for packId: String) -> (audio: [URL], config: URL?)? {
        guard let assetsURL, let pack = pack(for: packId) else { return nil }

        let audioURLs = pack.audioFiles.map { assetsURL.appendingPathComponent($0) }
        let configURL = pack.configFile.map { assetsURL.appendingPathComponent($0) }
        return (audio: audioURLs, config: configURL)
    }

    func directory(for packId: String) -> URL? {
        guard let resources = resources(for: packId),
              let firstAudio = resources.audio.first
        else {
            return nil
        }
        return firstAudio.deletingLastPathComponent()
    }
}
