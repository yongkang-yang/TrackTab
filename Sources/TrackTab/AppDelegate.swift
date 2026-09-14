import AppKit
import ApplicationServices
import MultitouchBridge
import ServiceManagement
import TrackTabCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private let stream = TTMultitouchStream()
    private var closeTabDetector = GestureDetector(
        configuration: .init(fingerCount: 3)
    )
    private var voiceInputDetector = GestureDetector(
        configuration: .init(fingerCount: 4)
    )
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!
    private var closeTabItem: NSMenuItem!
    private var voiceInputItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private var enabled = true
    private var closeTabEnabled = true
    private var voiceInputEnabled = true
    private var lastActionAt = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        closeTabEnabled = defaults.object(forKey: "closeTabEnabled") as? Bool ?? true
        voiceInputEnabled = defaults.object(forKey: "voiceInputEnabled") as? Bool ?? true

        setUpMenuBar()
        requestAccessibilityIfNeeded()
        startMultitouch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stream.stop()
    }

    private func setUpMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: "TrackTab")
            button.toolTip = "TrackTab"
        }

        let menu = NSMenu()

        enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)

        menu.addItem(.separator())

        closeTabItem = NSMenuItem(
            title: "Three-finger tap: Close Chrome tab",
            action: #selector(toggleCloseTabGesture),
            keyEquivalent: ""
        )
        closeTabItem.target = self
        menu.addItem(closeTabItem)

        voiceInputItem = NSMenuItem(
            title: "Four-finger tap: Voice input (Right Command)",
            action: #selector(toggleVoiceInputGesture),
            keyEquivalent: ""
        )
        voiceInputItem.target = self
        menu.addItem(voiceInputItem)

        menu.addItem(.separator())

        permissionItem = NSMenuItem(title: "Accessibility", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit TrackTab", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshMenuState()
    }

    private func startMultitouch() {
        stream.frameHandler = { [weak self] touchCount, firstTouchState, x, y, timestamp in
            guard let self else { return }

            let closeTabFired = self.closeTabDetector.ingest(
                touchCount: touchCount,
                firstTouchState: firstTouchState,
                x: x,
                y: y,
                timestamp: timestamp
            )
            let voiceInputFired = self.voiceInputDetector.ingest(
                touchCount: touchCount,
                firstTouchState: firstTouchState,
                x: x,
                y: y,
                timestamp: timestamp
            )

            if closeTabFired {
                self.handleCloseTabTap()
            }
            if voiceInputFired {
                self.handleVoiceInputTap()
            }
        }

        guard stream.start() else {
            showError(stream.lastErrorMessage ?? "Trackpad monitoring could not start.")
            return
        }
    }

    private func handleCloseTabTap() {
        guard enabled, closeTabEnabled else { return }
        guard Date().timeIntervalSince(lastActionAt) > 0.30 else { return }
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmost.bundleIdentifier,
              bundleID.hasPrefix("com.google.Chrome") else {
            return
        }
        guard ensureAccessibility() else { return }

        sendCommandW()
        lastActionAt = Date()
    }

    private func handleVoiceInputTap() {
        guard enabled, voiceInputEnabled else { return }
        guard Date().timeIntervalSince(lastActionAt) > 0.30 else { return }
        guard ensureAccessibility() else { return }

        sendRightCommandTap()
        lastActionAt = Date()
    }

    private func ensureAccessibility() -> Bool {
        guard AXIsProcessTrusted() else {
            requestAccessibilityIfNeeded()
            refreshMenuState()
            return false
        }
        return true
    }

    private func sendCommandW() {
        // Hardware key code 13 is the W key on Apple ANSI keyboards.
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 13, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 13, keyDown: false) else {
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func sendRightCommandTap() {
        // Apple virtual key code 54 (0x36) is the right Command key.
        // Modifier keys are represented as flagsChanged events. The low-order
        // device bit 0x10 identifies the right-side Command key specifically.
        let rightCommandKey: CGKeyCode = 54
        let rightCommandDeviceMask = CGEventFlags(rawValue: 0x00000010)
        let pressedFlags = CGEventFlags(
            rawValue: CGEventFlags.maskCommand.rawValue | rightCommandDeviceMask.rawValue
        )

        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(
                keyboardEventSource: source,
                virtualKey: rightCommandKey,
                keyDown: true
              ),
              let up = CGEvent(
                keyboardEventSource: source,
                virtualKey: rightCommandKey,
                keyDown: false
              ) else {
            return
        }

        down.type = .flagsChanged
        down.flags = pressedFlags
        up.type = .flagsChanged
        up.flags = []

        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.025)
        up.post(tap: .cghidEventTap)
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else {
            refreshMenuState()
            return
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshMenuState()
    }

    private func refreshMenuState() {
        enabledItem?.state = enabled ? .on : .off
        closeTabItem?.state = closeTabEnabled ? .on : .off
        voiceInputItem?.state = voiceInputEnabled ? .on : .off
        permissionItem?.title = AXIsProcessTrusted() ? "Accessibility: Granted" : "Accessibility: Required…"

        if #available(macOS 13.0, *) {
            launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        defaults.set(enabled, forKey: "enabled")
        closeTabDetector.reset()
        voiceInputDetector.reset()
        refreshMenuState()
    }

    @objc private func toggleCloseTabGesture() {
        closeTabEnabled.toggle()
        defaults.set(closeTabEnabled, forKey: "closeTabEnabled")
        closeTabDetector.reset()
        refreshMenuState()
    }

    @objc private func toggleVoiceInputGesture() {
        voiceInputEnabled.toggle()
        defaults.set(voiceInputEnabled, forKey: "voiceInputEnabled")
        voiceInputDetector.reset()
        refreshMenuState()
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showError("Could not change Launch at Login: \(error.localizedDescription)")
        }
        refreshMenuState()
    }

    @objc private func openAccessibilitySettings() {
        requestAccessibilityIfNeeded()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "TrackTab"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
