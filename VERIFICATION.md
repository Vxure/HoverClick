# HoverClick drawing-gesture build — verification report

Date: 2026-11-05

## Checks run in this environment

| Check | Result |
|---|---|
| `swift test` on Linux | PASS — 10 tests, 0 failures |
| C template self-recognition | PASS |
| Rotation/scale normalization | PASS |
| Noisy, unevenly sampled C recognition | PASS |
| Circle rejection against C template | PASS |
| Too-short stroke rejection | PASS |
| Existing keyboard shortcut tests | PASS — 5 tests |
| Swift parser check for app source | PASS |
| Bash build-script syntax (`bash -n`) | PASS |
| `.gitignore` and Git workflow review | PASS |
| ZIP archive integrity | PASS |

## What is not verified here

This environment is Linux, so it cannot compile/link AppKit, SwiftUI, Carbon,
Core Graphics, or run the macOS event tap. In particular, the drawing gesture's
right-button event suppression/replay and Accessibility permission behavior
must be tested on the user's Mac. The app has not been represented as
macOS-runtime-verified.

## Native macOS test checklist

1. Build and launch the app on macOS using the included script.
2. Leave drawing mode off: confirm physical right-click behavior is unchanged.
3. Enable drawing mode in Settings.
4. Confirm a short right-click still opens exactly one context menu.
5. Hold the right mouse button, draw a C, and release; confirm one context menu
   appears at the stroke endpoint.
6. Draw an unrelated long stroke; confirm it does not produce a context click.
7. Use the keyboard right-click shortcut while drawing mode is enabled; confirm
   it still produces exactly one context click and does not recurse through the
   event tap.
8. Disable drawing mode and confirm normal right-click behavior is restored.
9. Quit/relaunch and confirm the drawing preference persists.

If creating the event tap fails, the regular keyboard shortcuts should continue
to work; use the app's status message to inspect the permission failure.
