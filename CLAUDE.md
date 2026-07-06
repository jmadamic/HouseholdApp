# HouseholdApp

Household chore, shopping, and meal-planning app for any number of people, built with **SwiftUI + Firebase** (Cloud Firestore + Firebase Auth, project ID `jordan-code`). Jordan and his wife use it daily — **never make changes that could wipe or orphan household data.**

## Build & Run

```bash
# Regenerate Xcode project (required after adding/removing Swift files)
xcodegen generate

# IMPORTANT: xcodegen overwrites the entitlements file — restore after every generate
git checkout -- HouseholdApp/HouseholdApp.entitlements

# Build for simulator
xcodebuild -project HouseholdApp.xcodeproj -scheme HouseholdApp -sdk iphonesimulator -destination 'id=4236ECB3-DF1D-4F48-9A8B-EB1A5848D1FF' build

# Install and launch
xcrun simctl install 4236ECB3-DF1D-4F48-9A8B-EB1A5848D1FF <path-to-built-.app>
xcrun simctl launch 4236ECB3-DF1D-4F48-9A8B-EB1A5848D1FF com.householdapp.app

# Build for real devices (free personal team JBZQM9YC55 — per-device destination
# with device registration; generic/platform=iOS may miss devices on the profile)
xcodebuild -project HouseholdApp.xcodeproj -scheme HouseholdApp \
  -destination 'platform=iOS,id=<ECID>' -configuration Debug \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

# Install on a device (must be unlocked)
xcrun devicectl device install app --device <UDID> <path-to-built-.app>

# Deploy Firestore security rules (firestore.rules is the source of truth)
firebase deploy --only firestore:rules
```

`scripts/refresh-sideload.sh` runs the device rebuild/reinstall weekly via launchd (free-team apps expire every 7 days). Device IDs live in that script.

## Key Conventions

- **xcodegen**: `project.yml` is the source of truth. Never edit `HouseholdApp.xcodeproj` by hand. Restore the entitlements file after every generate.
- **Firestore-first**: All shared data is Codable `*Doc` structs + `*Store` observable classes in `HouseholdApp/Firebase/`. Each store opens a snapshot listener in `HouseholdAppApp.startStores` and exposes `save`/`delete` (guard against empty `householdId`).
- **New subcollections need rules**: add a member-only `match` block in `firestore.rules` AND deploy it (`firebase deploy --only firestore:rules`) — a listener that starts before rules allow it fails with "Missing or insufficient permissions" and does not retry until app restart.
- **Backward-compatible model changes only**: new fields on `*Doc` structs must be optional with a default value so existing Firestore documents still decode and old app builds keep working. No migrations.
- **@AppStorage for device-local settings**: store lists, item-type lists, icon mappings, and notification prefs live in `AppSettings.swift` (JSON-encoded strings). Member names are the exception — they sync via `memberNames` on the household doc.
- **Multi-member support**: household supports N members. Assignment is `assignedToMembers: [Int]` (member indices); empty = Everyone.
- **Filter bars**: "All" + one tab per member. Filtering shows items with empty `assignedToMembers` OR containing the selected index.
- **Row conventions**: 44 pt check-button tap targets, haptic on toggle, VoiceOver summary via `.accessibilityLabel`, `.caption2` (never fixed point sizes).
- **Auto-cleanup**: completed chores / purchased items / past meals older than 1 month are deleted once per session on first snapshot (`hasCleanedUp` flag in each store).
- **Cross-tab links**: `TabRouter` (in `RootView.swift`) owns tab selection; `router.openMeal(id)` jumps to the Meals tab and opens a meal.
- **README**: Always update `README.md` when project structure or features change.
- **GitHub**: Push changes as PRs on feature branches (repo: jmadamic/HouseholdApp), merge after verifying in the simulator.

## Architecture

- **Auth** (`AuthController`): anonymous Firebase sign-in on first launch; optional Google Sign-In upgrade links the account and keeps the same UID.
- **Household** (`HouseholdController` + `HouseholdDoc`): all data lives under `/households/{id}` with subcollections `chores`, `categories`, `completions`, `shoppingItems`, `meals`. Access = `request.auth.uid ∈ memberIds`, enforced by `firestore.rules`. Join via 6-char invite codes at `/invites/{code}`. A permission error or UID missing from `memberIds` triggers stale-household recovery (clear cached ID, auto-create).
- **Meal ↔ grocery link**: grocery items created from a meal's missing ingredients carry `mealId`/`mealName`; the shopping row shows a badge that routes back to the meal.
- **Notifications** (`NotificationManager`): local-only due-date reminders (9 am day-of / day-before), rescheduled on every chore snapshot and settings change. No APNs entitlement — free personal teams can't provision it.
- **Repeat logic**: completing a repeating chore advances its due date (rolling model) and writes a `CompletionLogDoc`; non-repeating chores archive in place.
- **Edit pattern**: categories, stores, and item types have dedicated form views (`CategoryFormView`, `StoreFormView`, `ItemTypeFormView`) with name, icon picker, and delete; parents pass `onDelete`/`onSave` callbacks. `CategoryFormView.iconOptions` is the shared SF Symbol list.
