#!/bin/bash
# refresh-sideload.sh
# Rebuilds HouseholdApp and reinstalls it on all paired iPhones.
# Runs via launchd every 10 min on Sundays 9am-9pm; retries devices that
# weren't unlocked/available on previous attempts.
#
# State tracking: stamps /tmp/householdapp-refresh.<UDID>.stamp on successful
# install. Skips any device already stamped within the past 6 days, so the
# weekly cycle re-installs but mid-week retries on a failed device don't
# unnecessarily reinstall on the working one.

set -e

PROJECT_DIR="/Users/jordanadamich/Coding/HouseholdApp"
SCHEME="HouseholdApp"
STAMP_TTL_SECS=$((6 * 24 * 3600))  # 6 days

# ── Devices ───────────────────────────────────────────────────────────────────
# Format: "<friendly name>:<ECID (for xcodebuild)>:<devicectl UDID>"
DEVICES=(
  "Jordan iPhone:00008101-000838881AE1001E:3A79D817-0BFF-5B15-AC01-2C48628788C4"
  "Wife iPhone:00008140-001A74A92678801C:8F9616CB-0E07-5556-B119-18859D9433F2"
)

DERIVED_DATA_APP="$HOME/Library/Developer/Xcode/DerivedData/HouseholdApp-btmbjbnnmvrsgodipeaswnzziody/Build/Products/Debug-iphoneos/HouseholdApp.app"

cd "$PROJECT_DIR"

ts() { date "+%Y-%m-%d %H:%M:%S"; }

# ── Force fresh provisioning profile ──────────────────────────────────────────
# Xcode caches mobileprovision files in ~/Library/Developer/Xcode/UserData/
# Provisioning Profiles/. If a stale (expired) one is there, xcodebuild will
# embed it in the .app and the install fails with "This provisioning profile
# has expired." Deleting them forces xcodebuild to fetch fresh ones.
PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
if [ -d "$PROFILE_DIR" ]; then
  echo "[$(ts)] Clearing cached provisioning profiles to force fresh fetch..."
  rm -f "$PROFILE_DIR"/*.mobileprovision
fi

# Cert expiry check — warn if cert expires within 14 days (the cert itself is
# annual, so this rarely fires, but when it does the user has to manually
# refresh via Xcode GUI since deleting the cert from CLI breaks Xcode's
# account state).
CERT_INFO=$(security find-certificate -c "Apple Development: jordan.adamich" -p 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
if [ -n "$CERT_INFO" ]; then
  CERT_EXPIRY_EPOCH=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$CERT_INFO" "+%s" 2>/dev/null)
  if [ -n "$CERT_EXPIRY_EPOCH" ]; then
    DAYS_LEFT=$(( (CERT_EXPIRY_EPOCH - $(date +%s)) / 86400 ))
    echo "[$(ts)] Signing cert: $DAYS_LEFT days until expiry"
    if [ "$DAYS_LEFT" -lt 14 ]; then
      echo "[$(ts)] ⚠️  CERT EXPIRES SOON — run Xcode GUI: Settings → Accounts → Manage Certificates → +"
    fi
  fi
fi

ANY_PENDING=0

for entry in "${DEVICES[@]}"; do
  IFS=":" read -r NAME ECID UDID <<< "$entry"
  STAMP="/tmp/householdapp-refresh.$UDID.stamp"

  # Skip if recently stamped successful
  if [ -f "$STAMP" ]; then
    AGE=$(($(date +%s) - $(stat -f %m "$STAMP")))
    if [ "$AGE" -lt "$STAMP_TTL_SECS" ]; then
      echo "[$(ts)] $NAME: already refreshed $((AGE/3600))h ago, skipping"
      continue
    fi
  fi

  echo ""
  echo "[$(ts)] ═══ $NAME (ECID=$ECID) ═══"

  STATUS=$(xcrun devicectl list devices 2>&1 | grep "$UDID" | grep -oE "available|unavailable|connected" | head -1)
  if [ "$STATUS" != "available" ] && [ "$STATUS" != "connected" ]; then
    echo "[$(ts)] $NAME is $STATUS — will retry next run"
    ANY_PENDING=1
    continue
  fi

  echo "[$(ts)] Building..."
  if ! xcodebuild \
      -project "HouseholdApp.xcodeproj" \
      -scheme "$SCHEME" \
      -destination "platform=iOS,id=$ECID" \
      -configuration Debug \
      -allowProvisioningUpdates \
      -allowProvisioningDeviceRegistration \
      build > /tmp/householdapp-build.log 2>&1; then
    echo "[$(ts)] $NAME: BUILD FAILED — see /tmp/householdapp-build.log"
    ANY_PENDING=1
    continue
  fi

  echo "[$(ts)] Installing..."
  if xcrun devicectl device install app --device "$UDID" "$DERIVED_DATA_APP" > /tmp/householdapp-install.log 2>&1; then
    touch "$STAMP"
    echo "[$(ts)] $NAME: ✅ installed"
  else
    echo "[$(ts)] $NAME: install failed — see /tmp/householdapp-install.log"
    ANY_PENDING=1
  fi
done

if [ "$ANY_PENDING" -eq 1 ]; then
  echo "[$(ts)] Some devices pending — will retry next scheduled run"
  exit 1
fi

echo "[$(ts)] ✅ All devices refreshed"
