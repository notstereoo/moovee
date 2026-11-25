import SwiftUI

struct CollectionDetailView: View {
    let collection: MovieCollection

    var body: some View {
        ViewModelHost(make: { $0.makeCollectionDetailViewModel(collection) }) { CollectionDetailContent(model: $0) }
    }
}

private struct CollectionDetailContent: View {
    @Bindable var model: CollectionDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var showReorder = false
    @State private var confirmDelete = false
    @State private var movieToSave: Movie?

    private var collection: MovieCollection { model.collection }

    var body: some View {
        switch model.availability {
        case .removed:
            ContentUnavailableView("Collection unavailable", systemImage: "eye.slash")
        case .privateToViewer:
            ContentUnavailableView(
                "Collection unavailable", systemImage: "lock.fill",
                description: Text("The author made this collection private."))
        case .available:
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if collection.items.isEmpty {
                    ContentUnavailableView(
                        "Nothing here yet", systemImage: "film.stack",
                        description: Text(
                            model.isOwner
                                ? "Add movies from the feed and search with the bookmark button."
                                : "This collection has no movies yet."))
                } else if model.movies.isEmpty {
                    ContentUnavailableView.search(text: model.query)
                } else {
                    MovieMasonry(
                        movies: model.movies,
                        onSave: { movieToSave = $0 },
                        actions: ownerActions)
                }
                TMDBAttribution()
            }
        }
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.query, prompt: "Search in collection")
        .toolbar {
            if !collection.items.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort", selection: $model.sort) {
                            ForEach(CollectionSort.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                    .accessibilityLabel("Sort")
                    .accessibilityValue(model.sort.title)
                }
            }
            if model.isOwner {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Edit", systemImage: "pencil") { showEdit = true }
                        if collection.items.count > 1 {
                            Button("Reorder", systemImage: "arrow.up.and.down.text.horizontal") {
                                showReorder = true
                            }
                        }
                        Button("Delete collection", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Collection actions")
                }
            }
        }
        .sheet(isPresented: $showReorder) { ReorderItemsView(model: model) }
        .sheet(isPresented: $showEdit) { CollectionEditorView(collection: collection) }
        .sheet(item: $movieToSave) { SaveToCollectionSheet(movie: $0) }
        .confirmationDialog(
            "Delete collection \"\(collection.title)\"?", isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { if model.delete() { dismiss() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Movies in the catalog are unaffected, but the collection will be gone for good.")
        }
        .errorAlert($model.errorMessage)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(
                    collection.isPublic ? "Public" : "Private",
                    systemImage: collection.isPublic ? "globe" : "lock.fill")
                Text("·")
                Text(filmsText(collection.items.count))
            }
            .font(.caption).foregroundStyle(.secondary)

            if !collection.details.isEmpty { Text(collection.details) }

            if let owner = collection.owner {
                NavigationLink(value: owner) {
                    HStack(spacing: 8) {
                        AvatarView(user: owner, size: 28)
                        Text(owner.shownName).font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open author profile \(owner.shownName)")
            }

            socialRow
        }
        .padding(.horizontal)
    }

    /// Лайк и сохранение — только для чужих подборок; владелец видит число лайков.
    @ViewBuilder
    private var socialRow: some View {
        if model.canInteract {
            HStack(spacing: 10) {
                Button {
                    model.toggleLike()
                } label: {
                    Label("\(model.likeCount)", systemImage: model.isLiked ? "heart.fill" : "heart")
                }
                .tint(model.isLiked ? .pink : .accentColor)
                .accessibilityLabel(model.isLiked ? "Unlike" : "Like")
                .accessibilityValue("\(model.likeCount)")

                Button {
                    model.toggleSave()
                } label: {
                    Label(model.isSaved ? "Saved" : "Save", systemImage: model.isSaved ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(model.isSaved ? "Remove from saved collections" : "Save collection")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .padding(.top, 4)
        } else {
            Label("\(model.likeCount)", systemImage: "heart.fill")
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityLabel("Likes")
                .accessibilityValue("\(model.likeCount)")
        }
    }

    private func ownerActions(for movie: Movie) -> [CardAction] {
        guard model.isOwner else { return [] }
        return [
            CardAction(title: "Make cover", systemImage: "photo") { model.setCover(movieID: movie.id) },
            CardAction(title: "Remove from collection", systemImage: "trash", isDestructive: true) {
                model.remove(movieID: movie.id)
            },
        ]
    }
}

private struct ReorderItemsView: View {
    let model: CollectionDetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.manualOrder) { item in
                    HStack(spacing: 12) {
                        PosterImage(path: item.posterPath, title: item.title, size: .w185, ratio: 1.0).frame(width: 44)
                        VStack(alignment: .leading) {
                            Text(item.title)
                            if let y = item.year { Text(y).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                .onMove { model.moveItems(from: $0, to: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Movie order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
