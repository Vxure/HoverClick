#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must be run on macOS. Current platform: $(uname -s)" >&2
  exit 2
fi

# Swift 6.4 / macOS 26 SDKs declare SwiftUI.State using the SwiftUIMacros
# plugin. The standalone Command Line Tools package may not include that
# host plugin even though its SDK exposes the macro declaration. If a full
# Xcode installation is available, prefer its complete toolchain.
MACOS_SWIFTUI_MACROS_RELATIVE_PATH="Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib"
ACTIVE_DEVELOPER_DIR="${DEVELOPER_DIR:-}"
if [[ -z "$ACTIVE_DEVELOPER_DIR" ]] && command -v xcode-select >/dev/null 2>&1; then
  ACTIVE_DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
fi

HAS_SWIFTUI_MACROS_PLUGIN=false
if [[ -n "$ACTIVE_DEVELOPER_DIR" && -f "$ACTIVE_DEVELOPER_DIR/$MACOS_SWIFTUI_MACROS_RELATIVE_PATH" ]]; then
  HAS_SWIFTUI_MACROS_PLUGIN=true
fi

# If Command Line Tools are selected but a full Xcode is installed in a
# conventional location, use that Xcode for this build only. DEVELOPER_DIR
# does not change the machine-wide xcode-select setting.
if [[ "$HAS_SWIFTUI_MACROS_PLUGIN" != true && -z "${DEVELOPER_DIR:-}" ]]; then
  shopt -s nullglob
  for xcode_app in /Applications/Xcode*.app "$HOME"/Applications/Xcode*.app; do
    candidate="$xcode_app/Contents/Developer"
    if [[ -f "$candidate/$MACOS_SWIFTUI_MACROS_RELATIVE_PATH" ]]; then
      export DEVELOPER_DIR="$candidate"
      ACTIVE_DEVELOPER_DIR="$candidate"
      HAS_SWIFTUI_MACROS_PLUGIN=true
      echo "Using full Xcode toolchain for this build: $DEVELOPER_DIR"
      break
    fi
  done
  shopt -u nullglob
fi

# Resolve Swift through xcrun so DEVELOPER_DIR selects the matching Xcode
# toolchain instead of accidentally invoking a different installation.
SWIFT_BIN=""
if command -v xcrun >/dev/null 2>&1; then
  SWIFT_BIN="$(xcrun --find swift 2>/dev/null || true)"
fi
if [[ -z "$SWIFT_BIN" ]]; then
  SWIFT_BIN="$(command -v swift || true)"
fi
if [[ -z "$SWIFT_BIN" || ! -x "$SWIFT_BIN" ]]; then
  echo "Swift is required. Install Xcode or the Xcode Command Line Tools first." >&2
  exit 2
fi

SWIFT_VERSION_OUTPUT="$("$SWIFT_BIN" --version 2>&1 || true)"
echo "$SWIFT_VERSION_OUTPUT"

# Check whether this toolchain exposes SwiftPM's backend selector. Prefer the
# default backend; only fall back to the deprecated native backend for the
# known SwiftPM 6.4 / CLT property-list initialization failure.
SWIFT_BUILD_HELP="$("$SWIFT_BIN" build --help 2>&1 || true)"
SUPPORTS_BUILD_SYSTEM=false
if grep -q -- '--build-system' <<<"$SWIFT_BUILD_HELP"; then
  SUPPORTS_BUILD_SYSTEM=true
fi

# Avoid an empty Bash array here. macOS ships Bash 3.2, where expanding an
# empty array under `set -u` can fail with "unbound variable" even when the
# array was declared. Track the selected backend with a scalar instead.
BUILD_SYSTEM_NATIVE=false
BUILD_LOG="$(mktemp -t hoverclick-build.XXXXXX)"
set +e
"$SWIFT_BIN" build --configuration release --product HoverClick 2>&1 | tee "$BUILD_LOG"
BUILD_STATUS=${PIPESTATUS[0]}
set -e

if [[ "$BUILD_STATUS" -ne 0 ]]; then
  if grep -Eq "SwiftUIMacros\.StateMacro|plugin for module 'SwiftUIMacros' not found" "$BUILD_LOG"; then
    cat >&2 <<'MESSAGE'

HoverClick could not compile because the active Swift toolchain is missing
SwiftUI's SwiftUIMacros compiler plugin. This commonly happens with Swift 6.4
when Command Line Tools are selected instead of a full Xcode installation.

Install/open Xcode, then either run this script with its developer directory:
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-macos-app.sh

or select Xcode as the active developer directory:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

If Xcode is installed under a different name or location, substitute its
actual Contents/Developer path. Check the selected path with:
  xcode-select -p

The later '_leftDraft', '_rightDraft', and immutable 'self' diagnostics are
cascading errors from the failed @State macro expansion, not separate fixes.
MESSAGE
    rm -f "$BUILD_LOG"
    exit "$BUILD_STATUS"
  fi

  if grep -q 'Unknown error parsing property list' "$BUILD_LOG" && [[ "$SUPPORTS_BUILD_SYSTEM" == true ]]; then
    echo "SwiftPM's default build backend failed during initialization; retrying with the legacy native backend."
    BUILD_SYSTEM_NATIVE=true
    if ! "$SWIFT_BIN" build --configuration release --product HoverClick --build-system native; then
      rm -f "$BUILD_LOG"
      exit 1
    fi
  else
    rm -f "$BUILD_LOG"
    exit "$BUILD_STATUS"
  fi
fi
rm -f "$BUILD_LOG"

# Ask SwiftPM for the active output directory rather than assuming the binary
# lives at .build/release (the layout differs between build backends/toolchains).
if [[ "$BUILD_SYSTEM_NATIVE" == true ]]; then
  BIN_DIR="$("$SWIFT_BIN" build --configuration release --show-bin-path --build-system native)"
else
  BIN_DIR="$("$SWIFT_BIN" build --configuration release --show-bin-path)"
fi
EXECUTABLE="$BIN_DIR/HoverClick"
if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Build completed, but the HoverClick executable was not found at: $EXECUTABLE" >&2
  echo "SwiftPM reported this binary directory: $BIN_DIR" >&2
  exit 1
fi

APP="$ROOT/build/HoverClick.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$EXECUTABLE" "$APP/Contents/MacOS/HoverClick"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>HoverClick</string>
    <key>CFBundleIdentifier</key>
    <string>com.openai.hoverclick</string>
    <key>CFBundleName</key>
    <string>HoverClick</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc signing is sufficient for a locally built personal utility.
# It is not Developer ID signing or notarization for public distribution.
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP"
fi

echo "Built: $APP"
echo "Launch with: open \"$APP\""
