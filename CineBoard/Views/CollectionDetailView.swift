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
            ContentUnavailableView("Подборка недоступна", systemImage: "eye.slash")
        case .privateToViewer:
            ContentUnavailableView(
                "Подборка недоступна", systemImage: "lock.fill",
                description: Text("Автор сделал эту подборку приватной."))
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
                        "Здесь пока пусто", systemImage: "film.stack",
                        description: Text(
                            model.isOwner
                                ? "Добавляйте фильмы из ленты и поиска кнопкой с закладкой."
                                : "В этой подборке пока нет фильмов."))
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
        .searchable(text: $model.query, prompt: "Поиск в подборке")
        .toolbar {
            if !collection.items.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Сортировка", selection: $model.sort) {
                            ForEach(CollectionSort.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                    .accessibilityLabel("Сортировка")
                    .accessibilityValue(model.sort.title)
                }
            }
            if model.isOwner {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Редактировать", systemImage: "pencil") { showEdit = true }
                        if collection.items.count > 1 {
                            Button("Изменить порядок", systemImage: "arrow.up.and.down.text.horizontal") {
                                showReorder = true
                            }
                        }
                        Button("Удалить подборку", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Действия с подборкой")
                }
            }
        }
        .sheet(isPresented: $showReorder) { ReorderItemsView(model: model) }
        .sheet(isPresented: $showEdit) { CollectionEditorView(collection: collection) }
        .sheet(item: $movieToSave) { SaveToCollectionSheet(movie: $0) }
        .confirmationDialog(
            "Удалить подборку «\(collection.title)»?", isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) { if model.delete() { dismiss() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Фильмы из каталога не пострадают, но подборка пропадёт безвозвратно.")
        }
        .errorAlert($model.errorMessage)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(
                    collection.isPublic ? "Публичная" : "Приватная",
                    systemImage: collection.isPublic ? "globe" : "lock.fill")
                Text("·")
                Text(filmsText(collection.items.count))
            }
            .font(.caption).foregroundStyle(.secondary)

            if !collection.details.isEmpty { Text(collection.details) }

            if let owner = collection.owner {
                NavigationLink(value: owner) {
                    HStack(spacing: 8) {
                        AvatarView(name: owner.username, size: 28)
                        Text("@\(owner.username)").font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Открыть профиль автора @\(owner.username)")
            }
        }
        .padding(.horizontal)
    }

    private func ownerActions(for movie: Movie) -> [CardAction] {
        guard model.isOwner else { return [] }
        return [
            CardAction(title: "Сделать обложкой", systemImage: "photo") { model.setCover(movieID: movie.id) },
            CardAction(title: "Убрать из подборки", systemImage: "trash", isDestructive: true) {
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
            .navigationTitle("Порядок фильмов")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}
