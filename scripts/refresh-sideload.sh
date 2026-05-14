#!/bin/bash
# refresh-sideload.sh
# Rebuilds HouseholdApp and reinstalls it on all paired iPhones.
# Run weekly to keep the 7-day sideload certificate fresh.
#
# Prerequisites:
#   - Both phones unlocked and connected (USB or wireless via Xcode)
#   - Apple ID signed into Xcode (Settings → Accounts)
#   - Team selected in HouseholdApp target → Signing & Capabilities
#
# Building per-device with -allowProvisioningDeviceRegistration ensures both
# iPhones get added to the provisioning profile; a single generic/platform=iOS
# build doesn't always include both, leading to ApplicationVerificationFailed
# on install.

set -e

PROJECT_DIR="/Users/jordanadamich/Coding/HouseholdApp"
SCHEME="HouseholdApp"

# ── Device IDs ────────────────────────────────────────────────────────────────
# xcodebuild uses ECIDs; devicectl uses a different UDID. Both are listed here.
# Format: "<friendly name>:<ECID>:<devicectl UDID>"
DEVICES=(
  "Jordan iPhone:00008101-000838881AE1001E:3A79D817-0BFF-5B15-AC01-2C48628788C4"
  "Wife iPhone:00008140-001A74A92678801C:8F9616CB-0E07-5556-B119-18859D9433F2"
)

DERIVED_DATA_APP="$HOME/Library/Developer/Xcode/DerivedData/HouseholdApp-btmbjbnnmvrsgodipeaswnzziody/Build/Products/Debug-iphoneos/HouseholdApp.app"

cd "$PROJECT_DIR"

for entry in "${DEVICES[@]}"; do
  IFS=":" read -r NAME ECID UDID <<< "$entry"

  echo ""
  echo "═════════════════════════════════════════════════════════════════"
  echo "▶ $NAME (ECID=$ECID, UDID=$UDID)"
  echo "═════════════════════════════════════════════════════════════════"

  echo "  Checking device availability..."
  STATUS=$(xcrun devicectl list devices 2>&1 | grep "$UDID" | grep -oE "available|unavailable|connected" | head -1)
  if [ "$STATUS" != "available" ] && [ "$STATUS" != "connected" ]; then
    echo "  ⚠️  $NAME is $STATUS — skipping. Unlock the phone and re-run."
    continue
  fi

  echo "  Building (this also registers the device on the provisioning profile)..."
  xcodebuild \
    -project "HouseholdApp.xcodeproj" \
    -scheme "$SCHEME" \
    -destination "platform=iOS,id=$ECID" \
    -configuration Debug \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    build 2>&1 | tail -5 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

  echo "  Installing..."
  xcrun devicectl device install app --device "$UDID" "$DERIVED_DATA_APP" 2>&1 | tail -3
done

echo ""
echo "✅ Done"
