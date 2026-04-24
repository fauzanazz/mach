import AppKit

final class OnboardingWindowController: NSObject {
    private var window: NSWindow?
    private var permissionCheckTimer: Timer?
    private var statusLabel: NSTextField?
    private var instructionLabel: NSTextField?
    private var primaryButton: NSButton?
    private var secondaryButton: NSButton?
    private weak var settings: SettingsStore?
    private var isCompleting = false
    var onComplete: (() -> Void)?

    func show(settings: SettingsStore) {
        self.settings = settings

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "mach"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        let contentView = NSView(frame: window.contentView!.bounds)

        let iconSize: CGFloat = 48
        if let iconURL = Bundle.main.url(forResource: "mach", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            let iconView = NSImageView(frame: NSRect(x: 20, y: 152, width: iconSize, height: iconSize))
            iconView.image = icon
            contentView.addSubview(iconView)
        }

        let titleLabel = NSTextField(labelWithString: "mach")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.frame = NSRect(x: 76, y: 172, width: 220, height: 24)
        contentView.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "Mechanical keyboard sounds")
        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 76, y: 154, width: 220, height: 16)
        contentView.addSubview(subtitleLabel)

        let separator = NSBox(frame: NSRect(x: 20, y: 140, width: 280, height: 1))
        separator.boxType = .separator
        contentView.addSubview(separator)

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.frame = NSRect(x: 20, y: 110, width: 280, height: 20)
        contentView.addSubview(statusLabel)
        self.statusLabel = statusLabel

        let instructionLabel = NSTextField(wrappingLabelWithString: "")
        instructionLabel.font = NSFont.systemFont(ofSize: 11)
        instructionLabel.textColor = .secondaryLabelColor
        instructionLabel.frame = NSRect(x: 20, y: 70, width: 280, height: 32)
        contentView.addSubview(instructionLabel)
        self.instructionLabel = instructionLabel

        let secondaryButton = NSButton(frame: NSRect(x: 20, y: 20, width: 135, height: 32))
        secondaryButton.bezelStyle = .rounded
        secondaryButton.target = self
        secondaryButton.action = #selector(secondaryTapped)
        contentView.addSubview(secondaryButton)
        self.secondaryButton = secondaryButton

        let primaryButton = NSButton(frame: NSRect(x: 165, y: 20, width: 135, height: 32))
        primaryButton.bezelStyle = .rounded
        primaryButton.target = self
        primaryButton.action = #selector(primaryTapped)
        contentView.addSubview(primaryButton)
        self.primaryButton = primaryButton

        window.contentView = contentView
        self.window = window

        updateUI()

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        startPermissionCheck()
    }

    private func updateUI() {
        let hasPermission = KeyboardEventMonitor.hasPermission()

        if hasPermission {
            let enabled = settings?.isEnabled ?? false
            statusLabel?.stringValue = enabled ? "✓ Sounds enabled" : "Sounds disabled"
            statusLabel?.textColor = enabled ? .systemGreen : .secondaryLabelColor
            instructionLabel?.stringValue = ""
            secondaryButton?.title = "Quit"
            primaryButton?.title = enabled ? "Disable" : "Enable"
            primaryButton?.keyEquivalent = "\r"
        } else {
            statusLabel?.stringValue = "⚠ Input Monitoring required"
            statusLabel?.textColor = .systemOrange
            instructionLabel?.stringValue = "Click + in System Settings, then add mach.app"
            secondaryButton?.title = "Show in Finder"
            primaryButton?.title = "Open Settings"
            primaryButton?.keyEquivalent = "\r"
        }
    }

    @objc private func primaryTapped() {
        if KeyboardEventMonitor.hasPermission() {
            settings?.isEnabled = true
            complete()
        } else {
            KeyboardEventMonitor.requestPermission()
        }
    }

    @objc private func secondaryTapped() {
        if KeyboardEventMonitor.hasPermission() {
            settings?.isEnabled = false
            complete()
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        }
    }

    private func startPermissionCheck() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateUI()
        }
    }

    private func complete() {
        guard !isCompleting else { return }
        isCompleting = true
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
        window?.close()
        NSApp.setActivationPolicy(.accessory)
        onComplete?()
    }
}

extension OnboardingWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        complete()
    }
}
