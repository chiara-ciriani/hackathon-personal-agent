#!/bin/bash
# Generate the Xcode project and open it. Run from the unzipped ios folder: ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode is not the active developer directory. Install Xcode 26, then run:"
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi
xcodebuild -version | head -1

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing XcodeGen with Homebrew..."
    brew install xcodegen
  else
    echo "XcodeGen is missing and Homebrew is not installed. Install XcodeGen (https://github.com/yonaskolb/XcodeGen) and rerun."
    exit 1
  fi
fi

xcodegen generate --quiet
echo "Opening QuietCompassWalk.xcodeproj. In Xcode: pick your Team under Signing & Capabilities, choose the iPhone as the run target, press Run."
open QuietCompassWalk.xcodeproj
