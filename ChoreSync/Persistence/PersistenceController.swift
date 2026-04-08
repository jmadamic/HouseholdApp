// PersistenceController.swift
// ChoreSync
//
// Sets up NSPersistentCloudKitContainer with TWO persistent stores:
//
//   1. Private store  — syncs to the user's private CloudKit database.
//      Used for personal settings and as the initial data store before sharing.
//
//   2. Shared store   — syncs to CloudKit's shared database.
//      When Person A shares the household with Person B, all chores and
//      categories live here. Both people read/write to it using their
//      own separate Apple IDs.
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  How sharing works:                                                │
// │  1. Person A taps "Invite Partner" in Settings                    │
// │  2. A CKShare is created for the private zone's data              │
// │  3. Person B receives an invite (iMessage, email, link)           │
// │  4. Person B accepts → data appears in their shared store         │
// │  5. Both people can now add/edit/complete chores                  │
// └─────────────────────────────────────────────────────────────────────┘
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  CloudKit setup checklist (do once after cloning):                 │
// │  1. Set your bundle ID in project.yml                             │
// │  2. Xcode: Signing & Capabilities → iCloud → check CloudKit      │
// │  3. Replace the container ID constant below with yours            │
// │  4. Run once with initializeCloudKitSchema uncommented            │
// └─────────────────────────────────────────────────────────────────────┘

import CoreData
import CloudKit
import SwiftUI

// ── CloudKit container identifier ──────────────────────────────────────────────
// Replace this with your own iCloud container ID from the Apple Developer portal.
let cloudKitContainerID = "iCloud.com.choresync.app"

struct PersistenceController {

    // ── Singleton ──────────────────────────────────────────────────────────────
    static let shared = PersistenceController()

    // ── In-memory instance for SwiftUI Previews ────────────────────────────────
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let ctx = controller.container.viewContext
        let _ = PersistenceController.seedPreviewData(in: ctx)
        return controller
    }()

    // ── Container ──────────────────────────────────────────────────────────────
    let container: NSPersistentCloudKitContainer

    // ── Store URLs ─────────────────────────────────────────────────────────────
    // We need two separate SQLite files — one for private data, one for shared.
    private static let privateStoreURL: URL = {
        let dir = NSPersistentContainer.defaultDirectoryURL()
        return dir.appendingPathComponent("ChoreSync-Private.sqlite")
    }()

    private static let sharedStoreURL: URL = {
        let dir = NSPersistentContainer.defaultDirectoryURL()
        return dir.appendingPathComponent("ChoreSync-Shared.sqlite")
    }()

    // ── Init ───────────────────────────────────────────────────────────────────
    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "ChoreSync")

        if inMemory {
            // Preview / test — single in-memory store, no CloudKit.
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
            container.persistentStoreDescriptions.first!.cloudKitContainerOptions = nil
        } else {
            // ── Two-store configuration for sharing ───────────────────────────

            // 1) Private store — syncs to the user's private CloudKit database.
            let privateDesc = NSPersistentStoreDescription(url: Self.privateStoreURL)
            let privateOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: cloudKitContainerID
            )
            privateOptions.databaseScope = .private
            privateDesc.cloudKitContainerOptions = privateOptions
            Self.configureStoreDescription(privateDesc)

            // 2) Shared store — syncs to CloudKit's shared database.
            //    Data that Person A shares with Person B appears here on
            //    Person B's device automatically.
            let sharedDesc = NSPersistentStoreDescription(url: Self.sharedStoreURL)
            let sharedOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: cloudKitContainerID
            )
            sharedOptions.databaseScope = .shared
            sharedDesc.cloudKitContainerOptions = sharedOptions
            Self.configureStoreDescription(sharedDesc)

            container.persistentStoreDescriptions = [privateDesc, sharedDesc]
        }

        // Load both stores.
        container.loadPersistentStores { description, error in
            if let error {
                fatalError("Core Data store failed to load (\(description.url?.lastPathComponent ?? "?")): \(error.localizedDescription)")
            }
        }

        // ── View context configuration ─────────────────────────────────────────
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Required so @FetchRequest sees objects from BOTH stores (private + shared).
        container.viewContext.transactionAuthor = "app"

        // ── One-time CloudKit schema initialisation ────────────────────────────
        // Uncomment the FIRST time you run after adding/changing entities,
        // then comment it back out.
        //
        // #if DEBUG
        // do {
        //     try container.initializeCloudKitSchema(options: [])
        //     print("CloudKit schema initialised successfully.")
        // } catch {
        //     print("CloudKit schema init failed: \(error)")
        // }
        // #endif

        // ── Seed default categories on first launch ────────────────────────────
        if !inMemory {
            let ctx = container.viewContext
            let fetchRequest: NSFetchRequest<Category> = Category.fetchRequest()
            let count = (try? ctx.count(for: fetchRequest)) ?? 0
            if count == 0 {
                PersistenceController.seedDefaultCategories(in: ctx)
                try? ctx.save()
            }
        }
    }

    // ── Store description setup ────────────────────────────────────────────────
    /// Applies the common options required for CloudKit sync to a store description.
    private static func configureStoreDescription(_ desc: NSPersistentStoreDescription) {
        // Required: persistent history tracking for CloudKit sync.
        desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        // Required: notification when remote changes arrive.
        desc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    }

    // ── Sharing helpers ────────────────────────────────────────────────────────

    /// Returns the persistent store (private or shared) that owns the given managed object.
    /// Used by ShareController to determine which store a record lives in.
    func store(for object: NSManagedObject) -> NSPersistentStore? {
        let objectID = object.objectID
        if let url = objectID.persistentStore?.url {
            return container.persistentStoreCoordinator.persistentStore(for: url)
        }
        return nil
    }

    /// Returns true if the given object lives in the shared store (i.e. it was
    /// shared by someone else and we are a participant).
    func isShared(_ object: NSManagedObject) -> Bool {
        guard let store = store(for: object) else { return false }
        return store.url == Self.sharedStoreURL
    }

    /// Fetches the CKShare associated with the given managed object, if any.
    /// Returns nil if the object hasn't been shared yet.
    func existingShare(for object: NSManagedObject) -> CKShare? {
        guard store(for: object) != nil else { return nil }
        do {
            let shares = try container.fetchShares(matching: [object.objectID])
            return shares[object.objectID]
        } catch {
            print("Failed to fetch share: \(error)")
            return nil
        }
    }

    /// Returns all CKShares across both stores.
    func allShares() throws -> [CKShare] {
        let stores = container.persistentStoreCoordinator.persistentStores
        var allShares = [CKShare]()
        for store in stores {
            let shares = try container.fetchShares(in: store)
            allShares.append(contentsOf: shares)
        }
        return allShares
    }

    /// Returns the private persistent store.
    var privateStore: NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first {
            $0.url == Self.privateStoreURL
        }
    }

    /// Returns the shared persistent store.
    var sharedStore: NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first {
            $0.url == Self.sharedStoreURL
        }
    }

    /// Creates a new CKShare for a root managed object and persists it.
    /// Used when Person A taps "Invite Partner" — creates the share so
    /// a UICloudSharingController can present the invitation UI.
    func shareCategoryGroup() async throws -> CKShare {
        // Share a root Category object. CloudKit zone sharing means ALL
        // objects in the same zone (all chores and categories) are shared.
        // We pick any category as the "root" — the share covers the whole zone.
        let ctx = container.viewContext
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.fetchLimit = 1
        let categories = try ctx.fetch(request)

        guard let rootObject = categories.first else {
            // No categories yet — create one as the share root.
            let cat = Category(context: ctx)
            cat.id = UUID()
            cat.name = "General"
            cat.iconName = "house.fill"
            cat.colorHex = "#DDA0DD"
            cat.sortOrder = 0
            try ctx.save()
            return try await createShare(for: cat)
        }

        return try await createShare(for: rootObject)
    }

    /// Creates a CKShare for the given managed object.
    private func createShare(for object: NSManagedObject) async throws -> CKShare {
        let (_, share, _) = try await container.share(
            [object],
            to: nil // nil = create a new share
        )
        // Set share metadata so the invitation looks nice.
        share[CKShare.SystemFieldKey.title] = "ChoreSync Household" as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = "com.choresync.household" as CKRecordValue
        // Allow the partner to read AND write.
        share.publicPermission = .none // Only invited participants, not public.
        return share
    }

    // ── Convenience save ───────────────────────────────────────────────────────

    /// Saves the view context if it has unsaved changes.
    func save() {
        let ctx = container.viewContext
        guard ctx.hasChanges else { return }
        do {
            try ctx.save()
        } catch {
            print("Core Data save error: \(error.localizedDescription)")
        }
    }

    // ── Default category seeding ───────────────────────────────────────────────

    @discardableResult
    static func seedDefaultCategories(in context: NSManagedObjectContext) -> [Category] {
        let defaults: [(name: String, icon: String, hex: String)] = [
            ("Kitchen",   "fork.knife",     "#FF6B6B"),
            ("Bathroom",  "shower",          "#4ECDC4"),
            ("Outdoor",   "leaf.fill",       "#45B7D1"),
            ("Laundry",   "washer.fill",     "#96CEB4"),
            ("Groceries", "cart.fill",       "#FFEAA7"),
            ("General",   "house.fill",      "#DDA0DD"),
        ]
        return defaults.enumerated().map { index, item in
            let category = Category(context: context)
            category.id        = UUID()
            category.name      = item.name
            category.iconName  = item.icon
            category.colorHex  = item.hex
            category.sortOrder = Int32(index)
            return category
        }
    }

    @discardableResult
    static func seedPreviewData(in context: NSManagedObjectContext) -> [Category] {
        let categories = seedDefaultCategories(in: context)

        let sampleChores: [(title: String, catIndex: Int, assignedTo: AssignedTo, dueDateType: DueDateType)] = [
            ("Wash the dishes",    0, .me,      .specificDate),
            ("Vacuum living room", 5, .partner, .week),
            ("Take out trash",     5, .both,    .specificDate),
            ("Buy groceries",      4, .partner, .month),
            ("Clean bathroom",     1, .me,      .week),
        ]

        for (index, sample) in sampleChores.enumerated() {
            let chore = Chore(context: context)
            chore.id             = UUID()
            chore.title          = sample.title
            chore.assignedTo     = Int16(sample.assignedTo.rawValue)
            chore.dueDateType    = Int16(sample.dueDateType.rawValue)
            chore.dueDate        = sample.dueDateType == .none
                                    ? nil
                                    : Calendar.current.date(byAdding: .day, value: index, to: Date())
            chore.repeatInterval = Int16(RepeatInterval.none.rawValue)
            chore.isCompleted    = false
            chore.createdAt      = Date()
            chore.sortOrder      = Int32(index)
            chore.category       = categories[sample.catIndex]
        }

        // ── Sample shopping items ──────────────────────────────────────────────
        let sampleItems: [(name: String, store: String?, type: String?, qty: String?)] = [
            ("Paper Towels",   "Costco",     "Household",    "2"),
            ("Milk",           "Target",     "Food",         "1 gal"),
            ("Light Bulbs",    "Home Depot", "Maintenance",  "4-pack"),
            ("Chicken Breast", "Costco",     "Food",         "3 lbs"),
            ("Shampoo",        "Target",     "Personal Care", nil),
        ]
        for (index, sample) in sampleItems.enumerated() {
            let item = ShoppingItem(context: context)
            item.id          = UUID()
            item.name        = sample.name
            item.store       = sample.store
            item.itemType    = sample.type
            item.quantity    = sample.qty
            item.assignedTo  = 0
            item.isPurchased = false
            item.createdAt   = Date()
            item.sortOrder   = Int32(index)
        }

        try? context.save()
        return categories
    }
}
