import SwiftUI

struct CollectionsView: View {
    var body: some View {
        ViewModelHost(make: { $0.makeCollectionsViewModel() }) { CollectionsContent(model: $0) }
    }
}

private struct CollectionsContent: View {
    @Bindable var model: CollectionsViewModel
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Раздел", selection: $model.scope) {
                        ForEach(CollectionsViewModel.Scope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    let list = model.visible
                    if list.isEmpty {
                        emptyState.padding(.top, 40)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 16) {
                            ForEach(list) { c in
                                NavigationLink(value: c) {
                                    CollectionCard(collection: c, showOwner: model.scope == .discover)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
            .navigationTitle("Подборки")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Новая подборка", systemImage: "plus") { showEditor = true }
                }
            }
            .sheet(isPresented: $showEditor) { CollectionEditorView() }
            .appDestinations()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.scope == .mine {
            ContentUnavailableView {
                Label("Пока нет подборок", systemImage: "rectangle.stack.badge.plus")
            } description: {
                Text("Создайте первую подборку и сохраняйте в неё фильмы из ленты и поиска.")
            } actions: {
                Button("Создать подборку") { showEditor = true }.buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView(
                "Пока нечего показать", systemImage: "globe",
                description: Text("Публичные подборки других пользователей появятся здесь."))
        }
    }
}

struct CollectionCard: View {
    let collection: MovieCollection
    var showOwner = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(path: collection.coverPath, title: collection.title, size: .w342, ratio: 1.2)
            Text(collection.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            HStack(spacing: 4) {
                if !collection.isPublic { Image(systemName: "lock.fill") }
                Text(filmsText(collection.items.count))
                if showOwner, let owner = collection.owner { Text("· @\(owner.username)").lineLimit(1) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
