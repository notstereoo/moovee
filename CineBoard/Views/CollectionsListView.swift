import SwiftUI

/// Все подборки пользователя карточками. Владелец может выбрать, какие показывать в профиле.
struct CollectionsListView: View {
    let user: UserAccount

    var body: some View {
        ViewModelHost(make: { $0.makeProfileViewModel(user: user) }) { CollectionsListContent(model: $0) }
    }
}

private struct CollectionsListContent: View {
    let model: ProfileViewModel
    @State private var showPinEditor = false

    var body: some View {
        let list = model.collections
        ScrollView {
            if list.isEmpty {
                ContentUnavailableView(
                    "No collections yet", systemImage: "rectangle.stack",
                    description: Text(
                        model.isMe
                            ? "Create your first collection on the Collections tab."
                            : "This user hasn't shared anything yet.")
                )
                .padding(.top, 60)
            } else {
                ShowcaseList(model: model, collections: list).padding(16)
            }
        }
        .navigationTitle(model.isMe ? "My collections" : "\(model.user.shownName)'s collections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.isMe && !list.isEmpty {
                ToolbarItem(placement: .primaryAction) { Button("Pin") { showPinEditor = true } }
            }
        }
        .sheet(isPresented: $showPinEditor) { FeaturedCollectionsEditor(model: model) }
        .errorAlert(Binding(get: { model.errorMessage }, set: { model.errorMessage = $0 }))
    }
}

/// Все отзывы пользователя.
struct ReviewsListView: View {
    let user: UserAccount

    var body: some View {
        ViewModelHost(make: { $0.makeProfileViewModel(user: user) }) { ReviewsListContent(model: $0) }
    }
}

private struct ReviewsListContent: View {
    let model: ProfileViewModel

    var body: some View {
        let list = model.reviews
        ScrollView {
            if list.isEmpty {
                ContentUnavailableView(
                    "No reviews yet", systemImage: "star.bubble",
                    description: Text(
                        model.isMe ? "Rate movies and write reviews on their pages." : "No reviews yet.")
                )
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(list) { ReviewRow(review: $0, showMovie: true) }
                }
                .padding(16)
            }
        }
        .navigationTitle(model.isMe ? "My reviews" : "\(model.user.shownName)'s reviews")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Выбор подборок для профиля: закреплённые (до трёх, с порядком) и остальные.
struct FeaturedCollectionsEditor: View {
    let model: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            let pinned = model.pinnedCollections
            List {
                Section {
                    if pinned.isEmpty {
                        Text("Nothing pinned — your newest \(CollectionRules.profileLimit) collections are shown.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(pinned) { c in
                        row(c, pinned: true)
                    }
                    .onMove { model.movePinned(from: $0, to: $1) }
                } header: {
                    Text("Shown on your profile")
                } footer: {
                    Text("Up to \(CollectionRules.profileLimit). Drag to change the order.")
                }

                Section("Other collections") {
                    ForEach(model.unpinnedCollections) { c in
                        row(c, pinned: false)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Profile collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .errorAlert(Binding(get: { model.errorMessage }, set: { model.errorMessage = $0 }))
        }
    }

    private func row(_ c: MovieCollection, pinned: Bool) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [CollectionTheme.resolve(for: c).top, CollectionTheme.resolve(for: c).bottom],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title).lineLimit(1)
                Text(filmsText(c.items.count)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if pinned { model.unpin(c) } else { model.pin(c) }
            } label: {
                Image(systemName: pinned ? "pin.slash" : "pin")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(pinned ? "Unpin" : "Pin to profile")
        }
    }
}
