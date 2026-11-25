import SwiftUI

/// Любимые фильмы пользователя: сетка постеров. Владелец может менять список и порядок.
struct FavoritesView: View {
    let user: UserAccount

    var body: some View {
        ViewModelHost(make: { $0.makeProfileViewModel(user: user) }) { FavoritesContent(model: $0) }
    }
}

private struct FavoritesContent: View {
    let model: ProfileViewModel
    @State private var showEditor = false

    var body: some View {
        let list = model.favorites
        ScrollView {
            if list.isEmpty {
                ContentUnavailableView(
                    "No favorite movies yet", systemImage: "heart",
                    description: Text(
                        model.isMe
                            ? "Tap the heart on a movie page to add it here."
                            : "This user hasn't picked any favorites yet.")
                )
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 16) {
                    ForEach(list) { fav in
                        NavigationLink(value: Movie(favorite: fav)) {
                            VStack(alignment: .leading, spacing: 6) {
                                PosterImage(path: fav.posterPath, title: fav.title, size: .w342, ratio: 1.5)
                                Text(fav.title).font(.caption.weight(.semibold)).lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(model.isMe ? "My favorites" : "\(model.user.shownName)'s favorites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.isMe && !list.isEmpty {
                ToolbarItem(placement: .primaryAction) { Button("Edit") { showEditor = true } }
            }
        }
        .sheet(isPresented: $showEditor) { FavoritesEditorView(model: model) }
    }
}

struct FavoritesEditorView: View {
    let model: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.favorites) { fav in
                    HStack(spacing: 12) {
                        PosterImage(path: fav.posterPath, title: fav.title, size: .w185, ratio: 1.0).frame(width: 44)
                        VStack(alignment: .leading) {
                            Text(fav.title)
                            if let y = fav.year { Text(y).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { model.favorites[$0].movieID }
                    ids.forEach { model.removeFavorite(movieID: $0) }
                }
                .onMove { model.moveFavorites(from: $0, to: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Favorite movies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .overlay {
                if model.favorites.isEmpty {
                    ContentUnavailableView("The list is empty", systemImage: "heart")
                }
            }
            .errorAlert(Binding(get: { model.errorMessage }, set: { model.errorMessage = $0 }))
        }
    }
}
