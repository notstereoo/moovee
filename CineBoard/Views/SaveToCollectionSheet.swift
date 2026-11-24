import SwiftUI

/// Выбор одной или нескольких собственных подборок для фильма.
struct SaveToCollectionSheet: View {
    let movie: Movie

    var body: some View {
        ViewModelHost(make: { $0.makeSaveViewModel(movie: movie) }) { SaveToCollectionContent(model: $0) }
    }
}

private struct SaveToCollectionContent: View {
    @Bindable var model: SaveToCollectionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            Group {
                let mine = model.mine
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
                        Button {
                            model.toggle(c)
                        } label: {
                            HStack(spacing: 12) {
                                PosterImage(path: c.coverPath, title: c.title, size: .w185, ratio: 1.0).frame(width: 48)
                                VStack(alignment: .leading) {
                                    Text(c.title).foregroundStyle(.primary)
                                    Text("\(filmsText(c.items.count)) · \(c.isPublic ? "публичная" : "приватная")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: model.contains(c) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.contains(c) ? Color.accentColor : .secondary)
                            }
                        }
                        .accessibilityValue(model.contains(c) ? "Добавлен" : "Не добавлен")
                    }
                }
            }
            .navigationTitle("Сохранить в подборку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Новая подборка", systemImage: "plus") { showNew = true }
                }
            }
            .sheet(isPresented: $showNew) {
                CollectionEditorView(onSaved: { model.addToNew($0) })
            }
            .errorAlert($model.errorMessage)
        }
        .presentationDetents([.medium, .large])
    }
}
