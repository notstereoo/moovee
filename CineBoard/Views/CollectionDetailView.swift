import SwiftUI
import SwiftData

struct CollectionDetailView: View {
    let collection: MovieCollection
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var movieToSave: Movie?
    @State private var errorMessage: String?

    var body: some View {
        // Проверки защищают от обращения к удалённой модели и от доступа к чужой приватной подборке.
        if collection.modelContext == nil || collection.isDeleted {
            ContentUnavailableView("Подборка недоступна", systemImage: "eye.slash")
        } else if !collection.isVisible(to: session.currentUser) {
            ContentUnavailableView(
                "Подборка недоступна", systemImage: "lock.fill",
                description: Text("Автор сделал эту подборку приватной."))
        } else {
            content
        }
    }

    private var isOwner: Bool {
        guard let me = session.currentUser else { return false }
        return collection.owner?.id == me.id
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if collection.items.isEmpty {
                    ContentUnavailableView(
                        "Здесь пока пусто", systemImage: "film.stack",
                        description: Text(
                            isOwner
                                ? "Добавляйте фильмы из ленты и поиска кнопкой с закладкой."
                                : "В этой подборке пока нет фильмов."))
                } else {
                    MovieMasonry(
                        movies: collection.sortedItems.map(Movie.init(item:)),
                        onSave: { movieToSave = $0 },
                        actions: ownerActions)
                }
                TMDBAttribution()
            }
        }
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Редактировать", systemImage: "pencil") { showEdit = true }
                        Button("Удалить подборку", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Действия с подборкой")
                }
            }
        }
        .sheet(isPresented: $showEdit) { CollectionEditorView(collection: collection) }
        .sheet(item: $movieToSave) { SaveToCollectionSheet(movie: $0) }
        .confirmationDialog(
            "Удалить подборку «\(collection.title)»?", isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive, action: deleteCollection)
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Фильмы из каталога не пострадают, но подборка пропадёт безвозвратно.")
        }
        .errorAlert($errorMessage)
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
        guard isOwner else { return [] }
        return [
            CardAction(title: "Сделать обложкой", systemImage: "photo") {
                run { try $0.setCover(of: collection, movieID: movie.id) }
            },
            CardAction(title: "Убрать из подборки", systemImage: "trash", isDestructive: true) {
                run { try $0.remove(movieID: movie.id, from: collection) }
            },
        ]
    }

    private func run(_ op: (CollectionService) throws -> Void) {
        guard let user = session.currentUser else { return }
        do { try op(CollectionService(context: context, user: user)) } catch { errorMessage = userMessage(for: error) }
    }

    private func deleteCollection() {
        guard let user = session.currentUser else { return }
        do {
            try CollectionService(context: context, user: user).delete(collection)
            dismiss()
        } catch { errorMessage = userMessage(for: error) }
    }
}
