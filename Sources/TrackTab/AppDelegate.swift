import AppKit
import ApplicationServices
import MultitouchBridge
import ServiceManagement
import TrackTabCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private let stream = TTMultitouchStream()
    private var detector = GestureDetector()
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!
    private var threeFingerItem: NSMenuItem!
    private var fourFingerItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private var enabled = true
    private var lastActionAt = Date.distantPast

    private var fingerCount: Int {
        let saved = defaults.integer(forKey: "fingerCount")
        return saved == 4 ? 4 : 3
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        detector.configuration.fingerCount = fingerCount

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

        let fingerMenuItem = NSMenuItem(title: "Tap gesture", action: nil, keyEquivalent: "")
        let fingerMenu = NSMenu()
        threeFingerItem = NSMenuItem(title: "Three-finger tap", action: #selector(useThreeFingers), keyEquivalent: "")
        fourFingerItem = NSMenuItem(title: "Four-finger tap", action: #selector(useFourFingers), keyEquivalent: "")
        threeFingerItem.target = self
        fourFingerItem.target = self
        fingerMenu.addItem(threeFingerItem)
        fingerMenu.addItem(fourFingerItem)
        fingerMenuItem.submenu = fingerMenu
        menu.addItem(fingerMenuItem)

        menu.addItem(.separator())

        let scopeItem = NSMenuItem(title: "Chrome only · action: ⌘W", action: nil, keyEquivalent: "")
        scopeItem.isEnabled = false
        menu.addItem(scopeItem)

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
            let fired = self.detector.ingest(
                touchCount: touchCount,
                firstTouchState: firstTouchState,
                x: x,
                y: y,
                timestamp: timestamp
            )
            if fired {
                self.handleTap()
            }
        }

        guard stream.start() else {
            showError(stream.lastErrorMessage ?? "Trackpad monitoring could not start.")
            return
        }
    }

    private func handleTap() {
        guard enabled else { return }
        guard Date().timeIntervalSince(lastActionAt) > 0.30 else { return }
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmost.bundleIdentifier,
              bundleID.hasPrefix("com.google.Chrome") else {
            return
        }

        guard AXIsProcessTrusted() else {
            requestAccessibilityIfNeeded()
            refreshMenuState()
            return
        }

        sendCommandW()
        lastActionAt = Date()
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
        threeFingerItem?.state = fingerCount == 3 ? .on : .off
        fourFingerItem?.state = fingerCount == 4 ? .on : .off
        permissionItem?.title = AXIsProcessTrusted() ? "Accessibility: Granted" : "Accessibility: Required…"

        if #available(macOS 13.0, *) {
            launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    private func setFingerCount(_ count: Int) {
        defaults.set(count, forKey: "fingerCount")
        detector.configuration.fingerCount = count
        detector.reset()
        refreshMenuState()
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        defaults.set(enabled, forKey: "enabled")
        detector.reset()
        refreshMenuState()
    }

    @objc private func useThreeFingers() {
        setFingerCount(3)
    }

    @objc private func useFourFingers() {
        setFingerCount(4)
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
