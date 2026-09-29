#!/bin/bash
# Installs or updates FanCurve: the daemon and its watchdog (LaunchDaemons), the menubar app in
# /Applications and its LaunchAgent for the user who runs sudo. Needs dist/ from a downloaded
# release or from ./scripts/build-app.sh (run that as your user, never as root):
#   ./scripts/build-app.sh && sudo ./scripts/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
M=$(sysctl -n hw.model); [ "$M" = MacBookPro16,1 ] || { echo "FanCurve supports only MacBookPro16,1 (this Mac: $M)"; exit 1; }
V=$(sw_vers -productVersion); [ "${V%%.*}" -ge 15 ] || { echo "FanCurve needs macOS 15 or later (this Mac: $V)"; exit 1; }

BIN=dist
APP=dist/FanCurve.app
for file in "$BIN/fancurved" "$BIN/fancurvectl" "$APP/Contents/MacOS/FanCurve"; do
  [ -x "$file" ] || { echo "missing $file - build first, as your user: ./scripts/build-app.sh"; exit 1; }
done
# A downloaded build carries the quarantine flag, which would keep the app from launching.
xattr -dr com.apple.quarantine dist packaging 2>/dev/null || true
# The menubar app belongs to the user who ran sudo.
USER_NAME=${SUDO_USER:-}
if [ -z "$USER_NAME" ] || [ "$USER_NAME" = root ]; then
  echo "run with sudo from your own account: the menubar app is installed for that user"
  exit 1
fi
USER_ID=$(id -u "$USER_NAME")
USER_HOME=$(dscl -plist . -read "/Users/$USER_NAME" NFSHomeDirectory 2>/dev/null \
  | plutil -extract 'dsAttrTypeStandard:NFSHomeDirectory.0' raw -o - - 2>/dev/null || true)
if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
  echo "cannot find the home folder of $USER_NAME"
  exit 1
fi
AGENT_DIR="$USER_HOME/Library/LaunchAgents"
AGENT="$AGENT_DIR/local.fancurve.app.plist"
HELPER_DIR=/Library/PrivilegedHelperTools/local.fancurve
LABELS=(local.fancurve.daemon local.fancurve.watchdog)
# Only FanCurve's own symlink and app are replaced.
if { [ -e /usr/local/bin/fancurvectl ] || [ -L /usr/local/bin/fancurvectl ]; } &&
   [ "$(readlink /usr/local/bin/fancurvectl)" != "$HELPER_DIR/fancurvectl" ]; then
  echo "/usr/local/bin/fancurvectl exists and is not FanCurve's symlink - move it away first"
  exit 1
fi
if [ -e /Applications/FanCurve.app ] &&
   [ "$(plutil -extract CFBundleIdentifier raw -o - /Applications/FanCurve.app/Contents/Info.plist 2>/dev/null)" != local.fancurve.app ]; then
  echo "/Applications/FanCurve.app exists and is not FanCurve's app - move it away first"
  exit 1
fi

# An update: the menubar app first, so it does not show the daemon's restart as a failure.
launchctl bootout "gui/$USER_ID/local.fancurve.app" 2>/dev/null || true
pkill -x FanCurve 2>/dev/null || true
# Then both jobs. The daemon hands the fans back to macOS on SIGTERM.
for label in "${LABELS[@]}"; do
  launchctl bootout "system/$label" 2>/dev/null || true
done
# The new daemon creates its own socket; removing the old file keeps the status check below from
# talking to a dead socket.
rm -f /var/run/fancurve.sock

# From here on the daemon and the watchdog are stopped (the daemon handed the fans back on SIGTERM).
# The trap itself stops both jobs first, so its message is true even if it fires after bootstrap.
trap 'for label in "${LABELS[@]}"; do launchctl bootout "system/$label" 2>/dev/null || true; done; echo "install stopped partway: the daemon and watchdog are stopped and the fans are under macOS control; fix the error above and run sudo ./scripts/install.sh again" >&2' ERR

# A root-owned path, so no ordinary process can swap the binary that launchd runs as root. The
# uninstaller goes along, so FanCurve can be removed without the download.
install -d -o root -g wheel -m 0755 "$HELPER_DIR"
install -o root -g wheel -m 0755 "$BIN/fancurved" "$HELPER_DIR/fancurved"
install -o root -g wheel -m 0755 "$BIN/fancurvectl" "$HELPER_DIR/fancurvectl"
install -o root -g wheel -m 0755 scripts/uninstall.sh "$HELPER_DIR/uninstall.sh"
mkdir -p /usr/local/bin
ln -sf "$HELPER_DIR/fancurvectl" /usr/local/bin/fancurvectl
# The menubar app, root-owned in /Applications.
rm -rf /Applications/FanCurve.app
cp -R "$APP" /Applications/FanCurve.app
# Belt and braces: whatever still carries the quarantine flag loses it before anything starts.
xattr -dr com.apple.quarantine "$HELPER_DIR" /Applications/FanCurve.app 2>/dev/null || true

for label in "${LABELS[@]}"; do
  install -o root -g wheel -m 0644 "packaging/$label.plist" "/Library/LaunchDaemons/$label.plist"
  launchctl bootstrap system "/Library/LaunchDaemons/$label.plist"
done

# The app's LaunchAgent, owned by the user (launchd refuses an agent plist that others can write).
# Without a desktop session (ssh) the app starts at the next login.
[ -d "$AGENT_DIR" ] || install -d -o "$USER_NAME" -g staff -m 0755 "$AGENT_DIR"
install -o "$USER_NAME" -g staff -m 0644 packaging/local.fancurve.app.plist "$AGENT"
if launchctl print "gui/$USER_ID" >/dev/null 2>&1; then
  launchctl bootstrap "gui/$USER_ID" "$AGENT" || echo "the menubar app could not start now; it starts at the next login"
else
  echo "no desktop session for $USER_NAME: the menubar app starts at the next login"
fi

for _ in $(seq 50); do
  if "$HELPER_DIR/fancurvectl" status >/dev/null 2>&1; then break; fi
  sleep 0.1
done
if ! "$HELPER_DIR/fancurvectl" status; then
  echo "the daemon did not answer; its log: log show --last 2m --predicate 'subsystem == \"local.fancurve\"'"
  exit 1
fi
echo "installed. Remove with: sudo $HELPER_DIR/uninstall.sh"
