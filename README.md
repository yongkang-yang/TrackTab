# TrackTab

A tiny macOS menu-bar utility for closing the current Google Chrome tab with a trackpad tap.

## Default behavior

- Three-finger tap → sends **Command-W**
- Only fires when **Google Chrome** is the frontmost app
- Switch between **three-finger** and **four-finger** tap from the menu bar
- Rejects obvious swipes and long presses
- Optional **Launch at Login**
- No network access and no analytics

## Requirements

- macOS 13 or later
- Apple trackpad / Magic Trackpad
- Xcode Command Line Tools (`xcode-select --install` if needed)
- Accessibility permission, because TrackTab posts a synthetic Command-W keystroke

## Build

```bash
./build_app.sh
```

This runs the gesture-detector tests, makes a release build, packages `TrackTab.app`, and ad-hoc signs it.

Then:

```bash
mv TrackTab.app /Applications/
open /Applications/TrackTab.app
```

On first launch, grant **System Settings → Privacy & Security → Accessibility → TrackTab**.

> Because the app is ad-hoc signed, rebuilding it can cause macOS to forget its Accessibility grant. If that happens, remove TrackTab from the Accessibility list and add it again.

## Why a private framework?

macOS does not expose arbitrary raw multi-finger trackpad taps through a public API. TrackTab dynamically loads Apple's private `MultitouchSupport.framework` to obtain the finger count and first touch position. The app reads no text, browser data, or network traffic.

The private framework is intentionally loaded with `dlopen` instead of linked at build time. This keeps the dependency isolated, but Apple may still change or remove the API in a future macOS release.

## Safety against accidental closes

A tap must:

1. Reach exactly the selected number of fingers.
2. Finish within 0.45 seconds.
3. Keep the first touch within a small movement threshold.
4. Return below the selected finger count before firing.
5. Occur while Chrome is frontmost.

If three-finger gestures conflict with your macOS settings, choose **Four-finger tap** from the TrackTab menu.

## Project layout

- `MultitouchBridge`: minimal Objective-C bridge to the private trackpad framework
- `TrackTabCore`: testable gesture state machine
- `TrackTab`: menu-bar UI + Chrome check + Command-W event
- `TrackTabCoreTests`: tap/swipe/long-press tests
