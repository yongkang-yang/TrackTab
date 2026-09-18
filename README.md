# TrackTab

A tiny macOS menu-bar utility that maps Magic Trackpad gestures to focused keyboard actions.

## Default behavior

| Gesture | Action |
|---|---|
| **Three-finger tap** | Sends **Return** |
| **Three-finger swipe down** | Sends **Command-W** (close window/tab), application-independent |
| **Three-finger swipe left** | Sends **Command-Z** (undo) |
| **Three-finger swipe right** | Sends **Shift-Command-Z** (redo) |
| **Four-finger tap** | Sends a synthetic **Right Command tap** anywhere, intended to trigger a voice-input tool bound to a single Right Command press |
| **Five-finger tap** | Sends **Left Command + Space** |

- The three-finger gestures need a few macOS trackpad settings changed first so the system doesn't also react to them. See [Required trackpad settings](#required-trackpad-settings)
- Each gesture can be enabled or disabled independently from the menu bar
- Rejects obvious swipes and long presses where they'd conflict with a tap gesture, and vice versa
- Optional **Launch at Login**
- No network access and no analytics

The intended voice-input workflow is:

1. Four-finger tap the trackpad.
2. Speak.
3. Use the normal click/tap that your voice-input tool already uses to finish input.

TrackTab only replaces the initial physical Right Command press; it does not take over the voice-input session itself.

### Why these particular gestures

Two-finger tap and two-finger double-tap were deliberately avoided: they're already claimed by macOS as, respectively, secondary click and (in apps like Safari) Smart Zoom, and TrackTab doesn't intercept or block the system's own handling of a gesture — it only listens and adds its own synthetic key press alongside. Overloading a single finger count with both a tap and a double-tap (e.g. "three-finger tap closes a tab, three-finger double-tap does something else") was tried and dropped for the same reason from the other direction: the two detectors share the same physical motion, so they ended up interfering with each other in practice. The three-finger swipe avoids all of this — it requires real, deliberate travel across the trackpad, which a tap never produces and a swipe always does, so the tap and swipe detectors on the same three fingers never fire off the same physical gesture.

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

## Required trackpad settings

TrackTab only listens to the trackpad; it never blocks macOS's own gesture handling. If a system gesture is bound to the same motion, both fire at once. For example, a three-finger swipe left would undo and also switch desktops. So you need to free up the three-finger gestures TrackTab uses in **System Settings → Trackpad**:

| TrackTab gesture | System setting to change | Change it to |
|---|---|---|
| Three-finger swipe left / right (undo / redo) | **More Gestures → Swipe between full-screen applications** | **Swipe left or right with four fingers**, or Off |
| Three-finger swipe left / right (undo / redo) | **More Gestures → Swipe between pages** | **Scroll left or right with two fingers**, or Off. Don't pick either option that includes three fingers |
| Three-finger swipe down (close window) | **More Gestures → App Exposé** | Off, or **Swipe down with four fingers** |
| Three-finger tap (Enter) | **Point & Click → Look up & data detectors** | Anything other than **Tap with three fingers** |

**Mission Control** (swipe up) can stay on three fingers, because TrackTab doesn't use a three-finger swipe up.

## How the modifier-key gestures are simulated

Right Command and Left Command are modifier keys, so TrackTab does not treat them like ordinary character keys. It emits `flagsChanged` events using Apple's virtual key codes (`54`/`0x36` for Right Command, `55`/`0x37` for Left Command) together with the device-specific flag bit for that side of the keyboard (`0x10` for right, `0x08` for left). Left Command + Space additionally sends a real Space key press while that flag is held, then releases both. Each press is followed by an explicit release shortly after so no modifier can remain logically stuck down, and TrackTab won't fire if it detects a real Command key already held (to avoid stomping on whatever the user is doing with it).

This is designed to resemble a physical key combination closely enough for tools that bind actions to it (e.g. a voice-input tool bound to a bare Right Command press). A third-party app can still choose to ignore synthetic events, so this behavior should be verified with the specific tool in use.

## Why a private framework?

macOS does not expose arbitrary raw multi-finger trackpad taps through a public API. TrackTab dynamically loads Apple's private `MultitouchSupport.framework` to obtain the finger count and first touch position. The app reads no text, browser data, or network traffic.

The private framework is intentionally loaded with `dlopen` instead of linked at build time. This keeps the dependency isolated, but Apple may still change or remove the API in a future macOS release.

## Safety against accidental triggers

Each tap gesture has its own `GestureDetector`, and the swipe gesture has its own `SwipeDetector` — both in `TrackTabCore`. A tap detector tracks an exact finger count, requires the touch to stay nearly stationary, and cancels if extra fingers land partway through (so a three-finger tap that grows a fourth finger doesn't fire the Enter action). A swipe detector requires the opposite: real travel across the trackpad, well past what a tap would ever produce, so a tap and a swipe sharing the same finger count can't both register from the same physical motion.

All gestures are application-independent — none of them check which app is frontmost before firing.

## Project layout

- `MultitouchBridge`: minimal Objective-C bridge to the private trackpad framework
- `TrackTabCore`: testable gesture state machines (`GestureDetector` for taps, `SwipeDetector` for directional swipes), plus `GesturePresets`, the exact detector settings the app ships with
- `TrackTab`: menu-bar UI, gesture routing, and keyboard-event synthesis
- `TrackTabCoreTests`: per-detector tests, plus `GesturePresetsTests`, which runs the shipped settings side by side on the same touch frames to check each gesture fires exactly its own action
