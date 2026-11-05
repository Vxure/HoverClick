# HoverClick implementation audit

Date: 2026-11-05

## Existing features retained

- Carbon global hotkeys for left-click and right-click.
- The click coordinates are sampled at shortcut activation and used to post
  synthetic mouse-down/up events without moving the pointer.
- User-configurable shortcuts are saved in UserDefaults.
- The shortcut recorder uses AppKit event monitoring and suspends the app's own
  Carbon hotkeys while Settings is open.
- The build script includes workarounds discovered during native build attempts:
  SwiftUI macro toolchain detection, SwiftPM backend fallback, SwiftPM-reported
  executable output directory, and Bash 3.2-safe shell handling.

## New drawing gesture

- The feature is opt-in and persisted in UserDefaults.
- An active session-level CGEvent tap watches only right-button down, drag, and
  up events while the feature is enabled.
- Physical right-button events are held until release. Short presses are
  replayed as a standard right-click. A longer single stroke is compared to a
  normalized C template.
- A successful C recognition posts one tagged synthetic right-click at the
  stroke endpoint. Tagged events pass through the event tap to avoid recursion.
- Unrecognized longer drags are discarded rather than converted into clicks.
- The tap is detached when the feature is disabled and during manager teardown.

## Limits

- The first release recognizes only one C-shaped unistroke. It is not a full
  implementation of BetterTouchTool's custom drawing-template catalog,
  per-trigger scopes, or dedicated trackpad multi-finger drawing triggers.
- The right-click draw trigger is mouse-button based: hold the right mouse
  button while drawing. It has not yet been implemented as a three/four/five
  finger trackpad trace.
- As with any active global event filter, a native Mac test is required to
  confirm permission behavior and that all target apps respond normally.

## Validation performed

- Release `swift test`: 10 tests, 0 failures (Linux).
- `swift-format lint --strict`: passed.
- `swiftc -frontend -parse Sources/HoverClickApp/main.swift`: passed.
- `bash -n scripts/build-macos-app.sh`: passed.
- The C recognizer passes self-match, rotation/scale, circle-rejection, and
  insufficient-point tests.
- Native AppKit/SwiftUI/Carbon/Core Graphics compilation and live CGEvent tap
  behavior were not executable in this Linux environment.
