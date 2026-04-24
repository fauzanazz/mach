import Foundation

final class SettingsStore: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }

    @Published var volume: Double {
        didSet { UserDefaults.standard.set(volume, forKey: "volume") }
    }

    @Published var selectedPack: String {
        didSet { UserDefaults.standard.set(selectedPack, forKey: "selectedPack") }
    }

    @Published var keyUpDebounceMs: Double {
        didSet { UserDefaults.standard.set(keyUpDebounceMs, forKey: "keyUpDebounceMs") }
    }

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    init() {
        // Default to enabled with 75% volume on first launch
        self.isEnabled = UserDefaults.standard.object(forKey: "isEnabled") as? Bool ?? true
        self.volume = UserDefaults.standard.object(forKey: "volume") as? Double ?? 0.75
        self.selectedPack = UserDefaults.standard.string(forKey: "selectedPack") ?? "mx-speed-silver"
        self.keyUpDebounceMs = UserDefaults.standard.object(forKey: "keyUpDebounceMs") as? Double ?? 100
    }
}
