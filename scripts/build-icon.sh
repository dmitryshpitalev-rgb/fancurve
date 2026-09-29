#!/bin/bash
# Renders packaging/AppIcon.icns from docs/icon/app-icon.svg — and from app-icon-small.svg for the
# 16 and 32 px sizes, where the 48 fins and the thin scale would blur into a smudge. Needs librsvg
# (brew install librsvg); the .icns is committed, so build-app.sh does not.
#   ./scripts/build-icon.sh
set -euo pipefail
cd "$(dirname "$0")/.."
command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found: brew install librsvg"; exit 1; }
SET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$SET"
render() { rsvg-convert -w "$2" -h "$2" -o "$SET/$3" "docs/icon/$1"; }
render app-icon-small.svg 16 icon_16x16.png
render app-icon-small.svg 32 icon_16x16@2x.png
render app-icon-small.svg 32 icon_32x32.png
render app-icon.svg 64 icon_32x32@2x.png
render app-icon.svg 128 icon_128x128.png
render app-icon.svg 256 icon_128x128@2x.png
render app-icon.svg 256 icon_256x256.png
render app-icon.svg 512 icon_256x256@2x.png
render app-icon.svg 512 icon_512x512.png
render app-icon.svg 1024 icon_512x512@2x.png
iconutil -c icns "$SET" -o packaging/AppIcon.icns
rm -rf "$(dirname "$SET")"
echo "wrote packaging/AppIcon.icns"
