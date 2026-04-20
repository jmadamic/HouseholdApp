# HouseholdApp

Household chore and shopping list app for any number of people, built with SwiftUI + Core Data + CloudKit.

## Build & Run

```bash
# Regenerate Xcode project (required after adding/removing Swift files)
xcodegen generate

# IMPORTANT: xcodegen overwrites entitlements to empty — restore after every generate
# Copy the entitlements from git: git checkout -- HouseholdApp/HouseholdApp.entitlements

# Build for simulator
xcodebuild -project HouseholdApp.xcodeproj -scheme HouseholdApp -sdk iphonesimulator -destination 'id=4236ECB3-DF1D-4F48-9A8B-EB1A5848D1FF' build

# Install and launch
xcrun simctl install 4236ECB3-DF1D-4F48-9A8B-EB1A5848D1FF <path-to-built-.app>
xcrun simctl launch 4236ECB3-DF1D-4F48-9A8B-EB1A5848D1FF com.householdapp.app
```

## Key Conventions

- **xcodegen**: `project.yml` is the source of truth. Never edit `HouseholdApp.xcodeproj` by hand.
- **Entitlements**: Must be restored after every `xcodegen generate` — it wipes CloudKit/iCloud keys.
- **Core Data codegen**: All entities use `codeGenerationType="class"` (Xcode auto-generates NSManagedObject subclasses). Do NOT set to "manual".
- **CloudKit compatibility**: All Core Data attributes must be `optional="YES"`. Store descriptions must NOT set `configuration: "Default"`.
- **@AppStorage for settings**: Member names, store lists, item type lists, and icon mappings are stored via `@AppStorage` in `AppSettings.swift`. Arrays and dictionaries are JSON-encoded as strings.
- **Multi-member support**: Household supports N members (not fixed to 2). Members stored as JSON array in `@AppStorage("memberNames")`. Assignment uses `MemberAssignment` struct: `-1` = Everyone, `0+` = member index. Old `AssignedTo` enum is removed.
- **Assignee order**: `allAssignments` returns `[.everyone, .member(0), .member(1), ...]` — Everyone is always first.
- **README**: Always update `README.md` when project structure or features change.
- **GitHub**: Push changes as PRs on feature branches (repo: jmadamic/HouseholdApp).

## Architecture

- **Persistence**: `NSPersistentCloudKitContainer` with private + shared stores for CloudKit Sharing (up to 100 participants)
- **4 Core Data entities**: Chore, Category, CompletionLog, ShoppingItem
- **Member assignment**: `MemberAssignment` struct wraps Int16. Core Data `assignedTo` field stores -1 (Everyone) or 0+ (member index). `completedByMembers` String stores comma-separated indices of who completed.
- **Edit pattern**: Categories, stores, and item types each have dedicated form views (CategoryFormView, StoreFormView, ItemTypeFormView) with name editing, icon picker, and delete at the bottom. Parent forms pass `onDelete` and `onSave` callbacks.
- **Icon options**: `CategoryFormView.iconOptions` is the shared static list of SF Symbols used across all icon pickers.
- **Data migration**: On first launch after multi-member update, `assignedTo=2` (old "Both") is migrated to `-1` (Everyone) via `migrateAssignedToBothToEveryone`.
