#!/bin/bash
# Builds everything in release into dist/: the daemon, fancurvectl and the menubar app wrapped into
# FanCurve.app, ad-hoc signed. Run as your user, never as root (a root build leaves root-owned
# files in .build):
#   ./scripts/build-app.sh && sudo ./scripts/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(id -u)" -ne 0 ] || { echo "build as your user, not with sudo"; exit 1; }

swift build -c release
rm -rf dist
APP=dist/FanCurve.app
mkdir -p "$APP/Contents/MacOS"
cp .build/release/fancurved .build/release/fancurvectl dist/
cp .build/release/FanCurveApp "$APP/Contents/MacOS/FanCurve"
cp packaging/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The x86_64 linker leaves the tools unsigned; sign everything ad hoc, the app last.
codesign --force --sign - dist/fancurved dist/fancurvectl "$APP"
codesign --verify --strict dist/fancurved dist/fancurvectl "$APP"
echo "built dist/: fancurved, fancurvectl, FanCurve.app"
