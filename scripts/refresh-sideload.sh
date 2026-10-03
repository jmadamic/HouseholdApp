#!/bin/bash
# refresh-sideload.sh
# Rebuilds HouseholdApp and reinstalls it on all paired iPhones.
#
# Free-team provisioning profiles last 7 days. Rather than refreshing on
# fixed weekdays (which fails whenever the Mac is closed that whole day),
# launchd runs this every 30 minutes, every day, 7am-11pm, and the script
# refreshes a phone only once its last successful install is DUE_AFTER_SECS
# (3 days) old. A missed day is simply caught up the next time the Mac is
# awake and the phone is reachable; it takes 4+ days without a chance for
# the app to expire.
#
# State: <STAMP_DIR>/householdapp-refresh.<UDID>.stamp is touched on each
# successful install. When nothing is due the run exits after one log line,
# without touching provisioning profiles or the network.

set -e

PROJECT_DIR="/Users/jordanadamich/Coding/HouseholdApp"
SCHEME="HouseholdApp"
# Refresh a phone once its install is this old. 3 days leaves a 4-day
# buffer before the 7-day profile expires.
DUE_AFTER_SECS=$((3 * 24 * 3600))

# Stamps live alongside Xcode's data, not /tmp — macOS purges /tmp files
# after a few days, which silently erased the stamps this relies on.
STAMP_DIR="$HOME/Library/Application Support/HouseholdApp"
# Logs too: /tmp is purged, which erased the evidence of why runs were missed.
LOG_DIR="$HOME/Library/Logs/HouseholdApp"
mkdir -p "$LOG_DIR"
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

# ── Anything due? ─────────────────────────────────────────────────────────────
# Runs 33x a day, so bail out quietly when every phone is fresh.
stamp_age() {  # seconds since last successful install; huge if never
  local f="$STAMP_DIR/householdapp-refresh.$1.stamp"
  if [ -f "$f" ]; then echo $(( $(date +%s) - $(stat -f %m "$f") )); else echo 999999999; fi
}
DUE=()
for entry in "${DEVICES[@]}"; do
  IFS=":" read -r NAME ECID UDID <<< "$entry"
  AGE=$(stamp_age "$UDID")
  if [ "$AGE" -ge "$DUE_AFTER_SECS" ]; then
    DUE+=("$entry")
  fi
done
if [ "${#DUE[@]}" -eq 0 ]; then
  SUMMARY=""
  for entry in "${DEVICES[@]}"; do
    IFS=":" read -r NAME ECID UDID <<< "$entry"
    LEFT=$(( (DUE_AFTER_SECS - $(stamp_age "$UDID")) / 3600 ))
    SUMMARY+="$NAME due in ${LEFT}h; "
  done
  echo "[$(ts)] Nothing due — ${SUMMARY%; }"
  exit 0
fi

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

for entry in "${DUE[@]}"; do
  IFS=":" read -r NAME ECID UDID <<< "$entry"
  STAMP="$STAMP_DIR/householdapp-refresh.$UDID.stamp"

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
      build > "$LOG_DIR/build.log" 2>&1; then
    echo "[$(ts)] $NAME: BUILD FAILED — see "$LOG_DIR/build.log""
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
  if xcrun devicectl device install app --device "$UDID" "$APP_PATH" > "$LOG_DIR/install.log" 2>&1; then
    touch "$STAMP"
    echo "[$(ts)] $NAME: ✅ installed"
  else
    echo "[$(ts)] $NAME: install failed — see "$LOG_DIR/install.log""
    ANY_PENDING=1
  fi
done

if [ "$ANY_PENDING" -eq 1 ]; then
  echo "[$(ts)] Some devices pending — will retry next scheduled run"
  exit 1
fi

echo "[$(ts)] ✅ All devices refreshed"
