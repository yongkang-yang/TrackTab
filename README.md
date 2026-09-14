# TrackTab

A tiny macOS menu-bar utility that maps Magic Trackpad taps to focused keyboard actions.

## Default behavior

- **Three-finger tap** → sends **Command-W** when Google Chrome is frontmost, closing the current tab
- **Four-finger tap** → sends a synthetic **Right Command tap** anywhere, intended to trigger a voice-input tool bound to a single Right Command press
- The two gestures can be enabled or disabled independently from the menu bar
- Rejects obvious swipes and long presses
- Optional **Launch at Login**
- No network access and no analytics

The intended voice-input workflow is:

1. Four-finger tap the trackpad.
2. Speak.
3. Use the normal click/tap that your voice-input tool already uses to finish input.

TrackTab only replaces the initial physical Right Command press; it does not take over the voice-input session itself.

## Requirements

- macOS 13 or later
- Apple trackpad / Magic Trackpad
- Xcode Command Line Tools (`xcode-select --install` if needed)
- Accessibility permission, because TrackTab posts synthetic keyboard events

## Build

```bash
./build_app.sh
```

This makes a release build, packages `TrackTab.app`, and ad-hoc signs it.

Then:

```bash
mv TrackTab.app /Applications/
open /Applications/TrackTab.app
```

On first launch, grant **System Settings → Privacy & Security → Accessibility → TrackTab**.

> Because the app is ad-hoc signed, rebuilding it can cause macOS to forget its Accessibility grant. If that happens, remove TrackTab from the Accessibility list and add it again.

## How Right Command is simulated

Right Command is a modifier key, so TrackTab does not treat it like an ordinary character key. It emits `flagsChanged` events using Apple virtual key code `54` (`0x36`) together with the device-specific right-Command flag. The press is followed by an explicit release after a short interval so the Command modifier cannot remain logically held down.

This is designed to resemble a physical Right Command tap closely enough for tools that bind voice input to that key. A third-party app can still choose to ignore synthetic events, so this behavior should be verified with the specific voice-input tool in use.

## Why a private framework?

macOS does not expose arbitrary raw multi-finger trackpad taps through a public API. TrackTab dynamically loads Apple's private `MultitouchSupport.framework` to obtain the finger count and first touch position. The app reads no text, browser data, or network traffic.

The private framework is intentionally loaded with `dlopen` instead of linked at build time. This keeps the dependency isolated, but Apple may still change or remove the API in a future macOS release.

## Safety against accidental triggers

Each action has its own gesture detector:

- the Chrome action tracks exactly **three fingers**
- the voice-input action tracks exactly **four fingers**

A tap must finish within 0.45 seconds and keep the first touch within a small movement threshold. If a three-finger gesture grows to four fingers, the three-finger detector cancels that candidate rather than firing a close-tab action.

The Chrome action also checks that Chrome is the frontmost application before sending Command-W. The four-finger Right Command action is intentionally application-independent.

## Project layout

- `MultitouchBridge`: minimal Objective-C bridge to the private trackpad framework
- `TrackTabCore`: testable gesture state machine
- `TrackTab`: menu-bar UI, gesture routing, Chrome check, Command-W, and Right Command event synthesis
- `TrackTabCoreTests`: tap/swipe/long-press tests
