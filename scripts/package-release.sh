#!/bin/bash
# Packs a downloadable build: the binaries from build-app.sh, the launchd plists, the install and
# uninstall scripts, README and LICENSE - the layout install.sh expects, under one folder.
#   ./scripts/build-app.sh && ./scripts/package-release.sh
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/.*static let string = "\(.*\)".*/\1/p' Sources/FanCurveCore/Version.swift)
[ -n "$VERSION" ] || { echo "cannot read the version from Sources/FanCurveCore/Version.swift"; exit 1; }
for file in dist/fancurved dist/fancurvectl dist/FanCurve.app/Contents/MacOS/FanCurve; do
  [ -x "$file" ] || { echo "missing $file - run ./scripts/build-app.sh first"; exit 1; }
done
NAME="FanCurve-$VERSION"
STAGE=$(mktemp -d)/"$NAME"
# Only what install.sh reads: never the previous zip, a .DS_Store or the app's own plist and icon.
mkdir -p "$STAGE/dist" "$STAGE/packaging" "$STAGE/scripts"
cp -R dist/fancurved dist/fancurvectl dist/FanCurve.app "$STAGE/dist/"
cp packaging/local.fancurve.*.plist "$STAGE/packaging/"
cp scripts/install.sh scripts/uninstall.sh "$STAGE/scripts/"
cp README.md LICENSE "$STAGE/"
rm -f "dist/$NAME.zip"
# ditto keeps the app bundle's structure; --norsrc leaves out the AppleDouble ._ files.
ditto -c -k --norsrc --keepParent "$STAGE" "dist/$NAME.zip"
rm -rf "$(dirname "$STAGE")"
echo "wrote dist/$NAME.zip"
