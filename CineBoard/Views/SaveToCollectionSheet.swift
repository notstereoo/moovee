import SwiftUI
import SwiftData

/// Выбор одной или нескольких собственных подборок для фильма.
struct SaveToCollectionSheet: View {
    let movie: Movie
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MovieCollection.createdAt, order: .reverse) private var all: [MovieCollection]
    @State private var showNew = false
    @State private var errorMessage: String?

    private var mine: [MovieCollection] { all.filter { $0.owner?.id == session.currentUser?.id } }

    var body: some View {
        NavigationStack {
            Group {
                if mine.isEmpty {
                    ContentUnavailableView {
                        Label("Пока нет подборок", systemImage: "rectangle.stack.badge.plus")
                    } description: {
                        Text("Создайте первую подборку — и фильм сразу попадёт в неё.")
                    } actions: {
                        Button("Создать подборку") { showNew = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List(mine) { c in
                        Button { toggle(c) } label: {
                            HStack(spacing: 12) {
                                PosterImage(path: c.coverPath, title: c.title, size: .w185, ratio: 1.0).frame(width: 48)
                                VStack(alignment: .leading) {
                                    Text(c.title).foregroundStyle(.primary)
                                    Text("\(filmsText(c.items.count)) · \(c.isPublic ? "публичная" : "приватная")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: contains(c) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(contains(c) ? Color.accentColor : .secondary)
                            }
                        }
                        .accessibilityValue(contains(c) ? "Добавлен" : "Не добавлен")
                    }
                }
            }
            .navigationTitle("Сохранить в подборку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
                ToolbarItem(placement: .secondaryAction) { Button("Новая подборка", systemImage: "plus") { showNew = true } }
            }
            .sheet(isPresented: $showNew) {
                CollectionEditorView(onSaved: { created in
                    guard let user = session.currentUser else { return }
                    do { try CollectionService(context: context, user: user).add(movie, to: created) }
                    catch { errorMessage = userMessage(for: error) }
                })
            }
            .errorAlert($errorMessage)
        }
        .presentationDetents([.medium, .large])
    }

    private func contains(_ c: MovieCollection) -> Bool { c.items.contains { $0.movieID == movie.id } }

    private func toggle(_ c: MovieCollection) {
        guard let user = session.currentUser else { return }
        let service = CollectionService(context: context, user: user)
        do {
            if contains(c) { try service.remove(movieID: movie.id, from: c) }
            else { try service.add(movie, to: c) }
        } catch { errorMessage = userMessage(for: error) }
    }
}
