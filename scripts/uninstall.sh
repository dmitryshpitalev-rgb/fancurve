#!/bin/bash
# Removes FanCurve: the menubar app and its LaunchAgent go, the fans go back to macOS, gpuswitch
# back to the values from before auto-graphics, every installed file is deleted. Needs nothing but
# itself, so the copy install.sh leaves next to the daemon works as well as the one in the download:
#   sudo /Library/PrivilegedHelperTools/local.fancurve/uninstall.sh
#   sudo ./scripts/uninstall.sh
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
HELPER_DIR=/Library/PrivilegedHelperTools/local.fancurve

# The menubar app first, so it does not show the daemon's shutdown as a failure.
USER_NAME=${SUDO_USER:-}
if [ -n "$USER_NAME" ] && [ "$USER_NAME" != root ]; then
  USER_ID=$(id -u "$USER_NAME")
  USER_HOME=$(dscl -plist . -read "/Users/$USER_NAME" NFSHomeDirectory 2>/dev/null \
    | plutil -extract 'dsAttrTypeStandard:NFSHomeDirectory.0' raw -o - - 2>/dev/null)
  launchctl bootout "gui/$USER_ID/local.fancurve.app" 2>/dev/null || true
  if [ -n "$USER_HOME" ] && [ -d "$USER_HOME" ]; then
    rm -f "$USER_HOME/Library/LaunchAgents/local.fancurve.app.plist"
  fi
fi
pkill -x FanCurve 2>/dev/null || true
if [ "$(plutil -extract CFBundleIdentifier raw -o - /Applications/FanCurve.app/Contents/Info.plist 2>/dev/null)" = local.fancurve.app ]; then
  rm -rf /Applications/FanCurve.app
elif [ -e /Applications/FanCurve.app ]; then
  echo "/Applications/FanCurve.app is not FanCurve's app: left in place"
fi

# The daemon hands the fans back on SIGTERM; --restore does it once more and restores gpuswitch,
# and works even if the daemon is already dead.
for label in local.fancurve.daemon local.fancurve.watchdog; do
  launchctl bootout "system/$label" 2>/dev/null || true
done
restored=0
if [ -x "$HELPER_DIR/fancurved" ]; then
  "$HELPER_DIR/fancurved" --restore && restored=1
else
  echo "$HELPER_DIR/fancurved is missing, so --restore could not run"
fi

rm -f /Library/LaunchDaemons/local.fancurve.daemon.plist /Library/LaunchDaemons/local.fancurve.watchdog.plist
rm -rf "$HELPER_DIR" "/Library/Application Support/FanCurve" /var/run/fancurve
rm -f /var/run/fancurve.sock /var/log/fancurve.log /var/log/fancurve-watchdog.log
# Only FanCurve's own symlink.
if [ "$(readlink /usr/local/bin/fancurvectl)" = "$HELPER_DIR/fancurvectl" ]; then rm -f /usr/local/bin/fancurvectl; fi
if [ "$restored" -eq 1 ]; then
  echo "uninstalled: the fans are under macOS control"
else
  echo "uninstalled, but --restore reported a problem (see above)"
fi
