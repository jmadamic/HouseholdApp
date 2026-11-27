// PhotoViews.swift
// Photo strip for forms and detail screens, full-screen viewer, camera.
// Storage, limits and the free-plan guard are in Firebase/PhotoStore.swift.

import SwiftUI
import PhotosUI

// MARK: - Draft

/// The photo list being edited for one item.
///
/// Form mode (`start(ids:householdId:)`): photos upload as soon as they're
/// picked, so errors show at once, but the item only changes on Save:
/// `commit()` returns the final IDs and deletes the ones removed. If the form
/// is dismissed without saving, photos uploaded meanwhile are deleted when
/// the draft goes away, so a cancelled form never leaves counted orphans.
///
/// Live mode (`saveLive` set, for screens without a Save button): each add or
/// removal is written to the item straight away through that closure.
@MainActor
final class PhotoDraft: ObservableObject {
    @Published private(set) var ids: [String] = []
    @Published private(set) var uploading = 0
    @Published var errorMessage: String?
    private(set) var householdId = ""

    private var original: [String] = []
    private var uploaded: Set<String> = []
    private var missing: Set<String> = []
    private var started = false
    private var committed = false
    private var saveLive: (([String]) -> Void)?
    /// Form-mode uploads not yet saved to the item, readable from deinit.
    private let unsaved = UnsavedUploads()

    var isUploading: Bool { uploading > 0 }
    var remaining: Int { max(0, PhotoStore.perItemLimit - ids.count - uploading) }

    func start(ids: [String]?, householdId: String, saveLive: (([String]) -> Void)? = nil) {
        guard !started else { return }
        started = true
        self.ids = ids ?? []
        original = self.ids
        self.householdId = householdId
        self.saveLive = saveLive
    }

    /// Live mode: follow the item when another phone changes its photos.
    func follow(_ ids: [String]?) {
        guard saveLive != nil, uploading == 0 else { return }
        let next = (ids ?? []).filter { !missing.contains($0) }
        if next != self.ids { self.ids = next; original = next }
    }

    func add(_ images: [UIImage]) async {
        errorMessage = nil
        for image in images.prefix(remaining) {
            uploading += 1
            do {
                let id = try await PhotoStore.upload(image, householdId: householdId)
                uploading -= 1
                ids.append(id)
                if let saveLive {
                    saveLive(ids); original = ids
                } else {
                    uploaded.insert(id); unsaved.set(uploaded, householdId: householdId)
                }
            } catch {
                uploading -= 1
                errorMessage = error.localizedDescription
                return
            }
        }
    }

    func remove(_ id: String) {
        ids.removeAll { $0 == id }
        if let saveLive {
            saveLive(ids)
            original = ids
            PhotoStore.delete(ids: [id], householdId: householdId)
        }
    }

    /// The server says this photo doesn't exist. Hide it; Save drops the ID.
    func markMissing(_ id: String) {
        missing.insert(id)
        ids.removeAll { $0 == id }
    }

    /// Form mode: the IDs to store on the item. Deletes removed photos.
    func commit() -> [String]? {
        committed = true
        unsaved.set([], householdId: householdId)
        let gone = Set(original).union(uploaded).subtracting(ids).subtracting(missing)
        PhotoStore.delete(ids: Array(gone), householdId: householdId)
        return ids.isEmpty ? nil : ids
    }

    deinit {
        // Dismissed without Save: photos uploaded for this form go too.
        unsaved.deleteAll()
    }
}

/// Thread-safe holder so the draft's deinit (not on the main actor) can
/// delete uploads the form never saved.
private final class UnsavedUploads: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<String> = []
    private var householdId = ""

    func set(_ ids: Set<String>, householdId: String) {
        lock.lock(); defer { lock.unlock() }
        self.ids = ids
        self.householdId = householdId
    }

    func deleteAll() {
        lock.lock(); let ids = self.ids, householdId = self.householdId; self.ids = []; lock.unlock()
        if !ids.isEmpty { PhotoStore.delete(ids: Array(ids), householdId: householdId) }
    }
}

// MARK: - Section

/// "Photos" section for a Form or List: thumbnails, an add menu (camera or
/// library), tap to view full screen.
struct PhotoSection: View {
    @ObservedObject var draft: PhotoDraft
    var footer: String? = nil

    @State private var showingLibrary = false
    @State private var showingCamera  = false
    @State private var picks: [PhotosPickerItem] = []
    @State private var viewing: ViewingPhoto?

    var body: some View {
        Section {
            // One row view, so the presentation modifiers below attach once
            // (on a Section they'd be copied onto every row and not present).
            VStack(alignment: .leading, spacing: 6) {
                rowContent
                if let message = draft.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
            .photosPicker(isPresented: $showingLibrary, selection: $picks,
                          maxSelectionCount: max(1, draft.remaining), matching: .images)
            .onChange(of: picks) { _, items in
                guard !items.isEmpty else { return }
                picks = []
                Task {
                    var images: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) { images.append(image) }
                    }
                    if images.count < items.count { draft.errorMessage = PhotoStore.PhotoError.unreadable.localizedDescription }
                    await draft.add(images)
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in Task { await draft.add([image]) } }
                    .ignoresSafeArea()
            }
            .fullScreenCover(item: $viewing) { start in
                PhotoViewer(draft: draft, startId: start.id)
            }
        } header: {
            Text("Photos")
        } footer: {
            if let footer { Text(footer) }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        if draft.ids.isEmpty && !draft.isUploading {
            addMenu { Label("Add Photo", systemImage: "camera") }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(draft.ids.enumerated()), id: \.element) { index, id in
                        Button { viewing = ViewingPhoto(id: id) } label: {
                            PhotoThumbnail(id: id, householdId: draft.householdId) {
                                draft.markMissing(id)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo \(index + 1) of \(draft.ids.count)")
                        .accessibilityHint("Opens full screen")
                    }
                    ForEach(0..<draft.uploading, id: \.self) { _ in
                        ProgressView()
                            .frame(width: PhotoThumbnail.side, height: PhotoThumbnail.side)
                            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("Uploading photo")
                    }
                    if draft.remaining > 0 {
                        addMenu {
                            Image(systemName: "plus")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: PhotoThumbnail.side, height: PhotoThumbnail.side)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .accessibilityLabel("Add photo")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func addMenu<L: View>(@ViewBuilder label: () -> L) -> some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showingCamera = true } label: { Label("Take Photo", systemImage: "camera") }
            }
            Button { showingLibrary = true } label: { Label("Choose from Library", systemImage: "photo.on.rectangle") }
        } label: {
            label()
        }
    }
}

private struct ViewingPhoto: Identifiable { let id: String }

// MARK: - Thumbnail

struct PhotoThumbnail: View {
    static let side: CGFloat = 72

    let id: String
    let householdId: String
    var onMissing: () -> Void = {}

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color(.secondarySystemFill)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                Image(systemName: "photo").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: id) {
            switch await PhotoStore.image(id: id, householdId: householdId) {
            case .image(let loaded): image = loaded
            case .missing:           onMissing()
            case .failed:            failed = true
            }
        }
    }
}

// MARK: - Viewer

/// Full-screen pager over the item's photos, with Delete.
struct PhotoViewer: View {
    @ObservedObject var draft: PhotoDraft
    @Environment(\.dismiss) private var dismiss
    @State private var current: String
    @State private var confirmingDelete = false

    init(draft: PhotoDraft, startId: String) {
        self.draft = draft
        _current = State(initialValue: startId)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $current) {
                ForEach(draft.ids, id: \.self) { id in
                    FullPhoto(id: id, householdId: draft.householdId).tag(id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: draft.ids.count > 1 ? .automatic : .never))
            .background(Color.black.ignoresSafeArea())
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete Photo", systemImage: "trash")
                    }
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Photo", role: .destructive) {
                    let index = draft.ids.firstIndex(of: current) ?? 0
                    draft.remove(current)
                    if draft.ids.isEmpty { dismiss() } else { current = draft.ids[min(index, draft.ids.count - 1)] }
                }
            }
        }
    }
}

private struct FullPhoto: View {
    let id: String
    let householdId: String
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .accessibilityLabel("Photo")
            } else if failed {
                ContentUnavailableView("Photo unavailable", systemImage: "photo",
                                       description: Text("Connect to the internet to load it."))
                    .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: id) {
            if case .image(let loaded) = await PhotoStore.image(id: id, householdId: householdId) {
                image = loaded
            } else {
                failed = true
            }
        }
    }
}

// MARK: - Camera

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Row badge

/// Small glyph beside a row's name when the item has photos.
struct PhotoBadge: View {
    let ids: [String]?

    var body: some View {
        if let count = ids?.count, count > 0 {
            Image(systemName: "photo")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel(count == 1 ? "Has a photo" : "Has \(count) photos")
        }
    }
}
