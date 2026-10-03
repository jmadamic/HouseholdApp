#!/bin/bash
# install-refresh-agent.sh
# Installs (or reinstalls) the launchd agent that runs refresh-sideload.sh,
# then verifies launchd will actually fire it.
#
# ALWAYS use this instead of `launchctl load` / `unload`. On current macOS a
# job registered with the legacy `load` can sit in a "needs LWCR update"
# state: its calendar triggers are listed but never spawn it (runs = 0).
# That silently skipped every scheduled refresh from Sep 23 to Oct 2, 2026.
# `bootout` + `bootstrap` registers it correctly.

set -euo pipefail

LABEL="com.householdapp.refresh-sideload"
SRC="$(cd "$(dirname "$0")" && pwd)/$LABEL.plist"
DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

mkdir -p "$HOME/Library/Logs/HouseholdApp"
plutil -lint "$SRC" >/dev/null
cp "$SRC" "$DEST"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
# bootout is asynchronous; bootstrap fails with "Input/output error" until
# the old registration is fully gone, so retry briefly.
for attempt in 1 2 3 4 5; do
  if launchctl bootstrap "$DOMAIN" "$DEST" 2>/dev/null; then break; fi
  [ "$attempt" -eq 5 ] && { echo "❌ launchctl bootstrap failed"; exit 1; }
  sleep 1
done
launchctl enable "$DOMAIN/$LABEL"

INFO=$(launchctl print "$DOMAIN/$LABEL")
TRIGGERS=$(echo "$INFO" | grep -c "com.apple.launchd.calendarinterval" || true)
echo "Installed $LABEL — $TRIGGERS calendar triggers armed"

if echo "$INFO" | grep -q "needs LWCR update"; then
  echo "⚠️  launchd reports 'needs LWCR update' — scheduled runs will NOT fire."
  echo "    Fix: launchctl kickstart $DOMAIN/$LABEL   then re-run this script."
  exit 1
fi
echo "✅ Registration healthy (no pending LWCR update)"
