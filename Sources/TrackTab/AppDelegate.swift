import AppKit
import ApplicationServices
import MultitouchBridge
import ServiceManagement
import TrackTabCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private let stream = TTMultitouchStream()
    private var enterTapDetector = GestureDetector(
        // Loosened the same way as the other tap gestures: a bit more
        // slack on timing/jitter, and don't cancel on a momentary
        // non-contact reading on the sampled touch. Movement tolerance
        // stays well under the swipe detector's minimum travel (0.08) so a
        // real tap here still can't also register as the close-window swipe.
        configuration: .init(
            fingerCount: 3,
            maxTapDuration: 0.55,
            movementTolerance: 0.05,
            requireContactWhileTracking: false
        )
    )
    private var threeFingerSwipeDetector = SwipeDetector(
        // overshootTolerance explicitly 0 (SwipeDetector's own default is
        // 1): this swipe shares its finger count with a real, distinct
        // 4-finger gesture (voice input), so it must not tolerate the
        // touch count reaching 4 the way an unshared finger count could.
        // Without this, a real 4-finger tap that drifts slightly while
        // held (natural over its ~0.5s duration) can pass through
        // touchCount 3 on lift-off and get misread as this swipe.
        // directionBias raised from the type's default (1.2, which accepts
        // up to ~40° off an axis) to 2.0 (~27°) so a clearly diagonal swipe
        // doesn't count as down/left. 3.0 (~18°) was tried and rejected too
        // many real, slightly imperfect swipes.
        configuration: .init(
            fingerCount: 3,
            directionBias: 2.0,
            overshootTolerance: 0,
            requireContactWhileTracking: false
        )
    )
    private var voiceInputDetector = GestureDetector(
        // Same loosening as the 3-finger tap: more slack on timing/jitter,
        // and don't cancel on a momentary non-contact reading. Overshoot
        // tolerance stays at 0 (the default) so a brief 5th-finger graze
        // still cancels this one instead of also arming the spotlight
        // gesture at the same time.
        configuration: .init(
            fingerCount: 4,
            maxTapDuration: 0.55,
            movementTolerance: 0.05,
            requireContactWhileTracking: false
        )
    )
    private var spotlightDetector = GestureDetector(
        // 5 is the hardware ceiling (fingerCount is capped at 5), so unlike
        // the 3/4-finger gestures there's no room above it to land on by
        // overshooting — all five fingers have to be read as touching in
        // the same frame, which happens less reliably than landing on a
        // lower count. Give it more slack on timing and jitter to compensate.
        configuration: .init(
            fingerCount: 5,
            maxTapDuration: 0.7,
            movementTolerance: 0.08,
            requireContactWhileTracking: false
        )
    )
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!
    private var enterItem: NSMenuItem!
    private var closeWindowItem: NSMenuItem!
    private var undoItem: NSMenuItem!
    private var redoItem: NSMenuItem!
    private var voiceInputItem: NSMenuItem!
    private var spotlightItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private var enabled = true
    private var enterEnabled = true
    private var closeWindowEnabled = true
    private var undoEnabled = true
    private var redoEnabled = true
    private var voiceInputEnabled = true
    private var spotlightEnabled = true
    private var lastActionAt = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        enterEnabled = defaults.object(forKey: "enterEnabled") as? Bool ?? true
        closeWindowEnabled = defaults.object(forKey: "closeWindowEnabled") as? Bool ?? true
        undoEnabled = defaults.object(forKey: "undoEnabled") as? Bool ?? true
        redoEnabled = defaults.object(forKey: "redoEnabled") as? Bool ?? true
        voiceInputEnabled = defaults.object(forKey: "voiceInputEnabled") as? Bool ?? true
        spotlightEnabled = defaults.object(forKey: "spotlightEnabled") as? Bool ?? true

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

        enterItem = NSMenuItem(
            title: "Three-finger tap: Enter",
            action: #selector(toggleEnterGesture),
            keyEquivalent: ""
        )
        enterItem.target = self
        menu.addItem(enterItem)

        closeWindowItem = NSMenuItem(
            title: "Three-finger swipe down: Close window (⌘W)",
            action: #selector(toggleCloseWindowGesture),
            keyEquivalent: ""
        )
        closeWindowItem.target = self
        menu.addItem(closeWindowItem)

        undoItem = NSMenuItem(
            title: "Three-finger swipe left: Undo (⌘Z)",
            action: #selector(toggleUndoGesture),
            keyEquivalent: ""
        )
        undoItem.target = self
        menu.addItem(undoItem)

        redoItem = NSMenuItem(
            title: "Three-finger swipe right: Redo (⇧⌘Z)",
            action: #selector(toggleRedoGesture),
            keyEquivalent: ""
        )
        redoItem.target = self
        menu.addItem(redoItem)

        voiceInputItem = NSMenuItem(
            title: "Four-finger tap: Voice input (Right Command)",
            action: #selector(toggleVoiceInputGesture),
            keyEquivalent: ""
        )
        voiceInputItem.target = self
        menu.addItem(voiceInputItem)

        spotlightItem = NSMenuItem(
            title: "Five-finger tap: ⌘ (Left) + Space",
            action: #selector(toggleSpotlightGesture),
            keyEquivalent: ""
        )
        spotlightItem.target = self
        menu.addItem(spotlightItem)

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

            let enterTapFired = self.enterTapDetector.ingest(
                touchCount: touchCount,
                firstTouchState: firstTouchState,
                x: x,
                y: y,
                timestamp: timestamp
            )
            let threeFingerSwipeDirection = self.threeFingerSwipeDetector.ingest(
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
            let spotlightFired = self.spotlightDetector.ingest(
                touchCount: touchCount,
                firstTouchState: firstTouchState,
                x: x,
                y: y,
                timestamp: timestamp
            )

            if enterTapFired {
                self.handleEnterTap()
            }
            switch threeFingerSwipeDirection {
            case .down:
                self.handleCloseWindowSwipe()
            case .left:
                self.handleUndoSwipe()
            case .right:
                self.handleRedoSwipe()
            default:
                break
            }
            if voiceInputFired {
                self.handleVoiceInputTap()
            }
            if spotlightFired {
                self.handleSpotlightTap()
            }
        }

        guard stream.start() else {
            showError(stream.lastErrorMessage ?? "Trackpad monitoring could not start.")
            return
        }
    }

    private func handleEnterTap() {
        guard enabled, enterEnabled else { return }
        guard Date().timeIntervalSince(lastActionAt) > 0.30 else { return }
        guard ensureAccessibility() else { return }

        sendReturn()
        lastActionAt = Date()
    }

    private func handleCloseWindowSwipe() {
        guard enabled, closeWindowEnabled else { return }
        guard Date().timeIntervalSince(lastActionAt) > 0.30 else { return }
        guard ensureAccessibility() else { return }

        sendCommandKey(13)
        lastActionAt = Date()
    }

    private func handleUndoSwipe() {
        guard enabled, undoEnabled else { return }
        guard Date().timeIntervalSince(lastActionAt) > 0.30 else { return }
        guard ensureAccessibility() else { return }

        sendCommandKey(6)
        lastActionAt = Date()
    }

    private func handleRedoSwipe() {
        guard enabled, redoEnabled else { return }
        guard Date().timeIntervalSince(lastActionAt) > 0.30 else { return }
        guard ensureAccessibility() else { return }

        sendCommandKey(6, extraFlags: .maskShift)
        lastActionAt = Date()
    }

    private func handleVoiceInputTap() {
        guard enabled, voiceInputEnabled else { return }
        guard Date().timeIntervalSince(lastActionAt) > 0.30 else { return }
        guard ensureAccessibility() else { return }

        sendRightCommandTap()
        lastActionAt = Date()
    }

    private func handleSpotlightTap() {
        guard enabled, spotlightEnabled else { return }
        guard Date().timeIntervalSince(lastActionAt) > 0.30 else { return }
        guard ensureAccessibility() else { return }

        sendLeftCommandSpace()
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

    private func sendReturn() {
        // Hardware key code 36 is the Return key on Apple keyboards.
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) else {
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func sendCommandKey(_ keyCode: CGKeyCode, extraFlags: CGEventFlags = []) {
        // Hardware key codes on Apple ANSI keyboards: 13 is W, 6 is Z.
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        let flags = CGEventFlags.maskCommand.union(extraFlags)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func sendRightCommandTap() {
        // Apple virtual key code 54 (0x36) is the right Command key.
        // Modifier keys are represented as flagsChanged events. The low-order
        // device bit 0x10 identifies the right-side Command key specifically.
        let rightCommandKey: CGKeyCode = 54
        let rightCommandDeviceMask = CGEventFlags(rawValue: 0x00000010)
        let rightCommandFlags = CGEventFlags(
            rawValue: CGEventFlags.maskCommand.rawValue | rightCommandDeviceMask.rawValue
        )
        let existingFlags = CGEventSource.flagsState(.hidSystemState)

        // Do not disturb a real Command key that the user is already holding.
        guard !existingFlags.contains(.maskCommand) else { return }

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
        down.flags = existingFlags.union(rightCommandFlags)
        up.type = .flagsChanged
        up.flags = existingFlags

        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.025)
        up.post(tap: .cghidEventTap)
    }

    private func sendLeftCommandSpace() {
        // Apple virtual key code 55 (0x37) is the left Command key, and 49
        // (0x31) is Space. The low-order device bit 0x08 identifies the
        // left-side Command key specifically, mirroring sendRightCommandTap.
        let leftCommandKey: CGKeyCode = 55
        let spaceKey: CGKeyCode = 49
        let leftCommandDeviceMask = CGEventFlags(rawValue: 0x00000008)
        let leftCommandFlags = CGEventFlags(
            rawValue: CGEventFlags.maskCommand.rawValue | leftCommandDeviceMask.rawValue
        )
        let existingFlags = CGEventSource.flagsState(.hidSystemState)

        // Do not disturb a real Command key that the user is already holding.
        guard !existingFlags.contains(.maskCommand) else { return }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let commandDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: leftCommandKey,
                keyDown: true
              ),
              let spaceDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: spaceKey,
                keyDown: true
              ),
              let spaceUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: spaceKey,
                keyDown: false
              ),
              let commandUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: leftCommandKey,
                keyDown: false
              ) else {
            return
        }

        commandDown.type = .flagsChanged
        commandDown.flags = existingFlags.union(leftCommandFlags)
        spaceDown.flags = leftCommandFlags
        spaceUp.flags = leftCommandFlags
        commandUp.type = .flagsChanged
        commandUp.flags = existingFlags

        commandDown.post(tap: .cghidEventTap)
        spaceDown.post(tap: .cghidEventTap)
        spaceUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)
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
        enterItem?.state = enterEnabled ? .on : .off
        closeWindowItem?.state = closeWindowEnabled ? .on : .off
        undoItem?.state = undoEnabled ? .on : .off
        redoItem?.state = redoEnabled ? .on : .off
        voiceInputItem?.state = voiceInputEnabled ? .on : .off
        spotlightItem?.state = spotlightEnabled ? .on : .off
        permissionItem?.title = AXIsProcessTrusted() ? "Accessibility: Granted" : "Accessibility: Required…"

        if #available(macOS 13.0, *) {
            launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        defaults.set(enabled, forKey: "enabled")
        enterTapDetector.reset()
        threeFingerSwipeDetector.reset()
        voiceInputDetector.reset()
        spotlightDetector.reset()
        refreshMenuState()
    }

    @objc private func toggleEnterGesture() {
        enterEnabled.toggle()
        defaults.set(enterEnabled, forKey: "enterEnabled")
        enterTapDetector.reset()
        refreshMenuState()
    }

    @objc private func toggleCloseWindowGesture() {
        closeWindowEnabled.toggle()
        defaults.set(closeWindowEnabled, forKey: "closeWindowEnabled")
        threeFingerSwipeDetector.reset()
        refreshMenuState()
    }

    @objc private func toggleUndoGesture() {
        undoEnabled.toggle()
        defaults.set(undoEnabled, forKey: "undoEnabled")
        refreshMenuState()
    }

    @objc private func toggleRedoGesture() {
        redoEnabled.toggle()
        defaults.set(redoEnabled, forKey: "redoEnabled")
        refreshMenuState()
    }

    @objc private func toggleVoiceInputGesture() {
        voiceInputEnabled.toggle()
        defaults.set(voiceInputEnabled, forKey: "voiceInputEnabled")
        voiceInputDetector.reset()
        refreshMenuState()
    }

    @objc private func toggleSpotlightGesture() {
        spotlightEnabled.toggle()
        defaults.set(spotlightEnabled, forKey: "spotlightEnabled")
        spotlightDetector.reset()
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
