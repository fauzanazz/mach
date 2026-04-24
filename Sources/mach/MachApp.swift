import AppKit
import Combine

private func log(_ message: String) {
    let msg = "\(Date()): [mach] \(message)\n"
    NSLog("[mach] %@", message)
    let logPath = NSHomeDirectory() + "/mach-debug.log"
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(msg.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: msg.data(using: .utf8))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let settings = SettingsStore()
    private let keyboardMonitor = KeyboardEventMonitor()
    private let soundEngine = SoundEngine()
    private let packManager = SoundPackManager()
    private var cancellables = Set<AnyCancellable>()
    private var onboardingController: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let assetsURL = findAssetsDirectory() {
            packManager.loadManifest(from: assetsURL)
            normalizeSelectedPackIfNeeded()
        }

        loadSelectedSoundPack()

        keyboardMonitor.onKeyDown = { [self] keyCode in
            self.soundEngine.playKeyDown(keyCode: keyCode)
        }
        keyboardMonitor.onKeyUp = { [self] keyCode in
            self.soundEngine.playKeyUp(keyCode: keyCode)
        }

        setupStatusBar()
        setupBindings()

        if !KeyboardEventMonitor.hasPermission() {
            showOnboarding()
        }
    }

    private func setupStatusBar() {
        statusBarController = StatusBarController(
            settings: settings,
            keyboardMonitor: keyboardMonitor,
            packManager: packManager
        )
        log("StatusBarController created")
    }

    private func setupBindings() {
        settings.$isEnabled
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    _ = self.keyboardMonitor.start()
                } else {
                    self.keyboardMonitor.stop()
                }
            }
            .store(in: &cancellables)

        settings.$volume
            .sink { [weak self] vol in
                self?.soundEngine.volume = Float(vol)
            }
            .store(in: &cancellables)

        settings.$selectedPack
            .dropFirst()
            .sink { [weak self] _ in
                self?.loadSelectedSoundPack()
            }
            .store(in: &cancellables)

        settings.$keyUpDebounceMs
            .sink { [weak self] ms in
                self?.keyboardMonitor.keyUpDebounceMs = ms
            }
            .store(in: &cancellables)
    }

    private func showOnboarding() {
        onboardingController = OnboardingWindowController()
        onboardingController?.onComplete = { [weak self] in
            self?.settings.hasCompletedOnboarding = true
            self?.onboardingController = nil
        }
        onboardingController?.show(settings: settings)
    }

    private func loadSelectedSoundPack() {
        guard let resources = packManager.resources(for: settings.selectedPack) else {
            print("[mach] No resources found for pack: \(settings.selectedPack)")
            return
        }

        do {
            try soundEngine.preloadPack(
                packId: settings.selectedPack,
                audioURLs: resources.audio,
                configURL: resources.config
            )
            print("[mach] Loaded pack: \(settings.selectedPack)")
        } catch {
            print("[mach] Failed to load pack: \(error)")
        }
    }

    private func normalizeSelectedPackIfNeeded() {
        if packManager.pack(for: settings.selectedPack) != nil {
            return
        }

        if let firstPack = packManager.packs.first {
            settings.selectedPack = firstPack.id
        }
    }

    private func findAssetsDirectory() -> URL? {
        let candidates: [URL] = [
            Bundle.main.resourceURL.map { $0.appendingPathComponent("assets") },
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("assets"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("assets")
        ].compactMap { $0 }

        return candidates.first { (try? $0.checkResourceIsReachable()) == true }
    }
}

@main
enum MachApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
