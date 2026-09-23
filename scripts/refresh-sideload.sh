#!/bin/bash
# refresh-sideload.sh
# Rebuilds HouseholdApp and reinstalls it on all paired iPhones.
#
# Free-team provisioning profiles last 7 days, so this runs TWICE a week
# (Sundays and Wednesdays, every 30 min 8am-10pm) rather than weekly. The
# longest gap between runs is 4 days, so it now takes two consecutive
# missed days — not one — for the app to expire on a phone.
#
# State tracking: stamps <STAMP_DIR>/householdapp-refresh.<UDID>.stamp on a
# successful install, and skips devices stamped within STAMP_TTL_SECS so the
# many retry fires in a day are no-ops. That TTL MUST stay below the
# Sunday->Wednesday gap (3 days) or the Wednesday run would always skip.

set -e

PROJECT_DIR="/Users/jordanadamich/Coding/HouseholdApp"
SCHEME="HouseholdApp"
# Must be < 3 days (the Sun->Wed gap) so both scheduled days actually run,
# and > 1 day so same-day retries skip a device that already succeeded.
STAMP_TTL_SECS=$((2 * 24 * 3600))  # 2 days

# Stamps live alongside Xcode's data, not /tmp — macOS purges /tmp files
# after a few days, which silently erased the stamps this relies on.
STAMP_DIR="$HOME/Library/Application Support/HouseholdApp"
mkdir -p "$STAMP_DIR"

# ── Devices ───────────────────────────────────────────────────────────────────
# Format: "<friendly name>:<ECID (for xcodebuild)>:<devicectl UDID>"
DEVICES=(
  "Jordan iPhone:00008101-000838881AE1001E:3A79D817-0BFF-5B15-AC01-2C48628788C4"
  "Wife iPhone:00008140-001A74A92678801C:8F9616CB-0E07-5556-B119-18859D9433F2"
)

# Located by glob: the DerivedData hash changes if the project is moved or
# DerivedData is cleared, and a hardcoded path would silently install nothing.
find_built_app() {
  find "$HOME/Library/Developer/Xcode/DerivedData" \
       -maxdepth 5 -name "HouseholdApp.app" -path "*Debug-iphoneos*" 2>/dev/null | head -1
}

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
  STAMP="$STAMP_DIR/householdapp-refresh.$UDID.stamp"

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

  # Match on EITHER identifier. `devicectl list devices` prints the ECID in
  # its Identifier column on current macOS, but printed the CoreDevice UDID
  # on older versions — matching only one silently reported every device as
  # unreachable and made every scheduled run a no-op.
  DEVICE_LINE=$(xcrun devicectl list devices 2>&1 | grep -E "$UDID|$ECID" | head -1)
  if [ -z "$DEVICE_LINE" ]; then
    echo "[$(ts)] $NAME: not listed by devicectl (phone off, asleep, or off the network) — will retry next run"
    ANY_PENDING=1
    continue
  fi
  STATUS=$(echo "$DEVICE_LINE" | grep -oE "available|unavailable|connected" | head -1)
  if [ "$STATUS" != "available" ] && [ "$STATUS" != "connected" ]; then
    echo "[$(ts)] $NAME: ${STATUS:-unknown state} — will retry next run"
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

  APP_PATH=$(find_built_app)
  if [ -z "$APP_PATH" ]; then
    echo "[$(ts)] $NAME: no built .app found in DerivedData — will retry next run"
    ANY_PENDING=1
    continue
  fi

  # A build can succeed without recompiling and still re-sign, so check the
  # profile actually embedded in what we are about to install rather than
  # trusting the build result.
  PROFILE_END=$(security cms -D -i "$APP_PATH/embedded.mobileprovision" 2>/dev/null \
                | plutil -extract ExpirationDate raw -o - - 2>/dev/null)
  if [ -n "$PROFILE_END" ]; then
    PROFILE_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$PROFILE_END" "+%s" 2>/dev/null)
    NOW_EPOCH=$(date +%s)
    if [ -n "$PROFILE_EPOCH" ]; then
      PROFILE_DAYS=$(( (PROFILE_EPOCH - NOW_EPOCH) / 86400 ))
      echo "[$(ts)] Embedded profile valid for $PROFILE_DAYS more day(s) (until $PROFILE_END)"
      if [ "$PROFILE_EPOCH" -le "$NOW_EPOCH" ]; then
        echo "[$(ts)] $NAME: built app carries an EXPIRED profile — refusing to install; will retry next run"
        ANY_PENDING=1
        continue
      fi
    fi
  fi

  echo "[$(ts)] Installing..."
  if xcrun devicectl device install app --device "$UDID" "$APP_PATH" > /tmp/householdapp-install.log 2>&1; then
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
