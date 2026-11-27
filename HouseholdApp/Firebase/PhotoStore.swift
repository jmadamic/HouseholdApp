// PhotoStore.swift
// Photos attached to meals, shopping items, plants and Looking For items.
//
// Stored in Firestore itself, at /households/{id}/photos/{photoId} as
// { jpeg: bytes, createdAt }, because Cloud Storage needs the paid Blaze
// plan and this project stays on the free one. Parents hold the IDs in an
// optional `photoIds` array, and photos are fetched one at a time when shown,
// never through a list listener, then cached on disk. Photos are immutable,
// so each phone downloads each photo once.
//
// Free-plan guard: every add and delete moves the project-wide counter at
// /meta/photoUsage by exactly one in the same batch, and the rules refuse a
// photo over 400 KB or a counter over `projectCap`. 2,000 × 400 KB = 800 MB,
// under the free 1 GiB, so photos can't use up the plan even with a buggy
// or hostile client. Adding needs a connection: the counter is read from the
// server first, so the error is immediate instead of a write queued offline
// that the rules would later refuse.

import UIKit
import FirebaseFirestore

enum PhotoStore {
    /// Must match the cap in firestore.rules and scripts/test-firestore-rules.py.
    static let projectCap = 2000
    static let perItemLimit = 6
    /// The rules refuse anything larger; compression aims a little under it.
    static let maxBytes = 400_000
    private static let targetBytes = 350_000

    enum PhotoError: LocalizedError {
        case offline, full, unreadable, refused

        var errorDescription: String? {
            switch self {
            case .offline:    return "Photos can only be added while you're online."
            case .full:       return "Photo storage is full (\(projectCap.formatted()) photos). Delete some photos to add more."
            case .unreadable: return "That photo couldn't be read."
            case .refused:    return "The photo couldn't be saved. Try again."
            }
        }
    }

    enum Loaded {
        case image(UIImage)
        /// The server says it doesn't exist (its item was deleted and restored
        /// with Undo, or an older build deleted it).
        case missing
        /// Offline and not cached, or another error. Try again later.
        case failed
    }

    private static var db: Firestore { Firestore.firestore() }
    private static var usageRef: DocumentReference { db.collection("meta").document("photoUsage") }

    private static func ref(_ id: String, _ householdId: String) -> DocumentReference {
        db.collection("households").document(householdId).collection("photos").document(id)
    }

    /// The counter change the rules require alongside each photo add/delete.
    private static func usageChange(_ id: String, _ householdId: String, _ delta: Int64) -> [String: Any] {
        ["count": FieldValue.increment(delta), "lastHousehold": householdId, "lastPhoto": id]
    }

    /// Photos stored across the whole project, read from the server.
    static func usedCount() async throws -> Int {
        let snap = try await usageRef.getDocument(source: .server)
        return (snap.get("count") as? NSNumber)?.intValue ?? 0
    }

    // MARK: - Add

    /// Compresses and saves one photo; returns its ID once the server has it.
    static func upload(_ image: UIImage, householdId: String) async throws -> String {
        guard !householdId.isEmpty else { throw PhotoError.refused }
        let jpeg = await Task.detached(priority: .userInitiated) { jpegData(for: image) }.value
        guard let jpeg else { throw PhotoError.unreadable }
        let used: Int
        do { used = try await usedCount() } catch { throw PhotoError.offline }
        guard used < projectCap else { throw PhotoError.full }

        let id = UUID().uuidString
        let batch = db.batch()
        batch.setData(["jpeg": jpeg, "createdAt": FieldValue.serverTimestamp()],
                      forDocument: ref(id, householdId))
        batch.setData(usageChange(id, householdId, 1), forDocument: usageRef, merge: true)
        do {
            try await batch.commit()
        } catch {
            // Another phone may have taken the last slot since the check.
            if (error as NSError).code == FirestoreErrorCode.permissionDenied.rawValue,
               (try? await usedCount()) ?? 0 >= projectCap {
                throw PhotoError.full
            }
            throw PhotoError.refused
        }
        PhotoCache.shared.store(jpeg, id: id)
        return id
    }

    /// Longest side 1600 px, stepping size and quality down until it fits.
    static func jpegData(for image: UIImage) -> Data? {
        for side in [1600, 1280, 1024, 800] as [CGFloat] {
            let scaled = image.scaledDown(toFit: side)
            for quality in [0.75, 0.6, 0.45] as [CGFloat] {
                if let data = scaled.jpegData(compressionQuality: quality), data.count <= targetBytes {
                    return data
                }
            }
        }
        return nil
    }

    // MARK: - Delete

    /// Deletes photos, one batch each (the rules allow one counter step per
    /// write). Queued while offline. A photo that's already gone is refused
    /// by the rules, so it can't be uncounted twice.
    static func delete(ids: [String], householdId: String) {
        guard !householdId.isEmpty else { return }
        for id in Set(ids) {
            let batch = db.batch()
            batch.deleteDocument(ref(id, householdId))
            batch.setData(usageChange(id, householdId, -1), forDocument: usageRef, merge: true)
            batch.commit { _ in }
            PhotoCache.shared.remove(id)
        }
    }

    /// Every photo in a household, for deleteHousehold's cascade.
    static func deleteAll(householdId: String) async throws {
        let docs = try await db.collection("households").document(householdId)
            .collection("photos").getDocuments()
        for doc in docs.documents {
            let batch = db.batch()
            batch.deleteDocument(doc.reference)
            batch.setData(usageChange(doc.documentID, householdId, -1), forDocument: usageRef, merge: true)
            try await batch.commit()
            PhotoCache.shared.remove(doc.documentID)
        }
    }

    // MARK: - Load

    static func image(id: String, householdId: String) async -> Loaded {
        if let cached = PhotoCache.shared.image(id) { return .image(cached) }
        guard !householdId.isEmpty else { return .failed }
        do {
            let snap = try await ref(id, householdId).getDocument()
            if !snap.exists { return snap.metadata.isFromCache ? .failed : .missing }
            guard let data = snap.get("jpeg") as? Data, let image = UIImage(data: data) else { return .failed }
            PhotoCache.shared.store(data, id: id)
            return .image(image)
        } catch {
            return .failed
        }
    }
}

/// Memory + disk cache of photo JPEGs by ID. Photos never change, so an
/// entry never goes stale; iOS may clear the Caches folder, which just
/// means one more download.
final class PhotoCache: @unchecked Sendable {
    static let shared = PhotoCache()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL

    private init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 60
    }

    func image(_ id: String) -> UIImage? {
        if let hit = memory.object(forKey: id as NSString) { return hit }
        guard let file = file(id), let data = try? Data(contentsOf: file),
              let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: id as NSString)
        return image
    }

    func store(_ data: Data, id: String) {
        if let file = file(id) { try? data.write(to: file, options: .atomic) }
        if let image = UIImage(data: data) { memory.setObject(image, forKey: id as NSString) }
    }

    func remove(_ id: String) {
        memory.removeObject(forKey: id as NSString)
        if let file = file(id) { try? FileManager.default.removeItem(at: file) }
    }

    /// IDs come from synced documents, so only plain ones become file names.
    private func file(_ id: String) -> URL? {
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return directory.appendingPathComponent(id + ".jpg")
    }
}

extension UIImage {
    /// A copy whose longest side is at most `side` pixels, orientation baked in.
    func scaledDown(toFit side: CGFloat) -> UIImage {
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let factor = min(1, side / max(pixelSize.width, pixelSize.height, 1))
        let target = CGSize(width: (pixelSize.width * factor).rounded(),
                            height: (pixelSize.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
