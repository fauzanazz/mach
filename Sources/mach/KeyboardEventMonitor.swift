import AppKit
import CoreGraphics

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

final class KeyboardEventMonitor {
    var onKeyDown: ((UInt16) -> Void)?
    var onKeyUp: ((UInt16) -> Void)?
    var keyUpDebounceMs: Double = 100

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retainedSelfPointer: UnsafeMutableRawPointer?
    private var pressedKeys = Set<UInt16>()
    private var keyDownStartedAt: [UInt16: CFAbsoluteTime] = [:]

    private(set) var isRunning = false

    // MARK: - Public API

    func start() -> Bool {
        log("KeyboardEventMonitor.start() called")
        guard !isRunning else {
            log("Already running")
            return true
        }
        log("Attempting to create tap...")
        pressedKeys.removeAll()
        keyDownStartedAt.removeAll()

        let eventMask =
            CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)

        let selfPointer = Unmanaged.passRetained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: selfPointer
        ) else {
            log("CGEvent.tapCreate FAILED")
            Unmanaged<KeyboardEventMonitor>.fromOpaque(selfPointer).release()
            return false
        }
        log("Tap created successfully")

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        self.retainedSelfPointer = selfPointer
        self.isRunning = true
        return true
    }

    func stop() {
        guard isRunning else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        pressedKeys.removeAll()
        keyDownStartedAt.removeAll()
        releaseRetainedSelfIfNeeded()
        isRunning = false
    }

    fileprivate func handleKeyDown(keyCode: UInt16, isAutoRepeat: Bool) {
        guard !isAutoRepeat else {
            return
        }

        guard !pressedKeys.contains(keyCode) else {
            return
        }

        pressedKeys.insert(keyCode)
        keyDownStartedAt[keyCode] = CFAbsoluteTimeGetCurrent()
        onKeyDown?(keyCode)
    }

    fileprivate func handleKeyUp(keyCode: UInt16) {
        pressedKeys.remove(keyCode)

        guard let downAt = keyDownStartedAt.removeValue(forKey: keyCode) else {
            return
        }

        let heldDurationMs = (CFAbsoluteTimeGetCurrent() - downAt) * 1000
        guard heldDurationMs >= keyUpDebounceMs else {
            return
        }

        onKeyUp?(keyCode)
    }

    // MARK: - Permission

    static func hasPermission() -> Bool {
        // Try creating a tap to check if Input Monitoring is granted
        // AXIsProcessTrusted only checks Accessibility, not Input Monitoring
        let testMask =
            CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        if let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: testMask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) {
            CFMachPortInvalidate(tap)
            return true
        }
        return false
    }

    static func requestPermission() {
        // Attempt to create a tap to trigger macOS to add app to Input Monitoring list
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        _ = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )

        // Open Input Monitoring preferences
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private func releaseRetainedSelfIfNeeded() {
        guard let retainedSelfPointer else { return }
        Unmanaged<KeyboardEventMonitor>.fromOpaque(retainedSelfPointer).release()
        self.retainedSelfPointer = nil
    }

    deinit {
        releaseRetainedSelfIfNeeded()
    }
}

// C-compatible callback — self is recovered from userInfo via Unmanaged.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let pointer = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown || type == .keyUp else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<KeyboardEventMonitor>.fromOpaque(pointer).takeUnretainedValue()
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

    if type == .keyDown {
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        monitor.handleKeyDown(keyCode: keyCode, isAutoRepeat: isAutoRepeat)
    } else {
        monitor.handleKeyUp(keyCode: keyCode)
    }

    return Unmanaged.passUnretained(event)
}
