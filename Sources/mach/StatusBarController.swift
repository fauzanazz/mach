import AppKit
import ServiceManagement

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

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let settings: SettingsStore
    private let keyboardMonitor: KeyboardEventMonitor
    private let packManager: SoundPackManager

    init(settings: SettingsStore, keyboardMonitor: KeyboardEventMonitor, packManager: SoundPackManager) {
        self.settings = settings
        self.keyboardMonitor = keyboardMonitor
        self.packManager = packManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        log("StatusBarController init, statusItem created")

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "mach")
            log("StatusBar button configured with keyboard icon")
        } else {
            log("WARNING: statusItem.button is nil")
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        if !KeyboardEventMonitor.hasPermission() {
            let permissionItem = NSMenuItem(
                title: "Permission Required",
                action: #selector(requestPermission),
                keyEquivalent: ""
            )
            permissionItem.target = self
            menu.addItem(permissionItem)
            menu.addItem(.separator())
        }

        let toggleItem = NSMenuItem(
            title: "Enable",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = settings.isEnabled ? .on : .off
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let volumeLabel = NSMenuItem(title: volumeTitle, action: nil, keyEquivalent: "")
        volumeLabel.isEnabled = false
        menu.addItem(volumeLabel)

        let sliderItem = NSMenuItem()
        sliderItem.view = makeVolumeSliderView(labelItem: volumeLabel)
        menu.addItem(sliderItem)

        menu.addItem(.separator())

        let debounceLabel = NSMenuItem(title: debounceTitle, action: nil, keyEquivalent: "")
        debounceLabel.isEnabled = false
        menu.addItem(debounceLabel)

        let debounceSliderItem = NSMenuItem()
        debounceSliderItem.view = makeDebounceSliderView(labelItem: debounceLabel)
        menu.addItem(debounceSliderItem)

        // Sound Pack submenu
        if !packManager.packs.isEmpty {
            menu.addItem(.separator())

            let submenu = NSMenu(title: "Sound Pack")
            for pack in packManager.packs {
                let packItem = NSMenuItem(title: pack.label, action: #selector(selectPack(_:)), keyEquivalent: "")
                packItem.target = self
                packItem.representedObject = pack.id
                packItem.state = pack.id == settings.selectedPack ? .on : .off
                submenu.addItem(packItem)
            }

            let submenuItem = NSMenuItem(title: "Sound Pack", action: nil, keyEquivalent: "")
            submenuItem.submenu = submenu
            menu.addItem(submenuItem)
        }

        menu.addItem(.separator())

        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit mach",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    private func makeVolumeSliderView(labelItem: NSMenuItem) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))

        let slider = NSSlider(
            value: settings.volume,
            minValue: 0.0,
            maxValue: 1.0,
            target: self,
            action: #selector(volumeChanged(_:))
        )
        slider.frame = NSRect(x: 12, y: 4, width: 176, height: 22)
        slider.isContinuous = true

        objc_setAssociatedObject(slider, &AssociatedKeys.labelItem, labelItem, .OBJC_ASSOCIATION_RETAIN)

        container.addSubview(slider)
        return container
    }

    private func makeDebounceSliderView(labelItem: NSMenuItem) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))

        let slider = NSSlider(
            value: settings.keyUpDebounceMs,
            minValue: 0.0,
            maxValue: 300.0,
            target: self,
            action: #selector(debounceChanged(_:))
        )
        slider.frame = NSRect(x: 12, y: 4, width: 176, height: 22)
        slider.isContinuous = true

        objc_setAssociatedObject(slider, &AssociatedKeys.labelItem, labelItem, .OBJC_ASSOCIATION_RETAIN)

        container.addSubview(slider)
        return container
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        settings.isEnabled.toggle()
        sender.state = settings.isEnabled ? .on : .off
    }

    @objc private func requestPermission() {
        KeyboardEventMonitor.requestPermission()
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        settings.volume = sender.doubleValue

        if let labelItem = objc_getAssociatedObject(sender, &AssociatedKeys.labelItem) as? NSMenuItem {
            labelItem.title = volumeTitle
        }
    }

    @objc private func debounceChanged(_ sender: NSSlider) {
        settings.keyUpDebounceMs = sender.doubleValue

        if let labelItem = objc_getAssociatedObject(sender, &AssociatedKeys.labelItem) as? NSMenuItem {
            labelItem.title = debounceTitle
        }
    }

    @objc private func selectPack(_ sender: NSMenuItem) {
        guard let packId = sender.representedObject as? String else { return }
        settings.selectedPack = packId
        buildMenu()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("[mach] Launch at login error: \(error)")
        }
        buildMenu()
    }

    private var volumeTitle: String {
        "Volume: \(Int(settings.volume * 100))%"
    }

    private var debounceTitle: String {
        "Key Up Delay: \(Int(settings.keyUpDebounceMs))ms"
    }
}

private enum AssociatedKeys {
    static var labelItem: UInt8 = 0
}
