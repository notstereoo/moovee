import SwiftUI

/// Список подписчиков или подписок пользователя.
struct FollowListView: View {
    let user: UserAccount
    let kind: FollowListViewModel.Kind

    var body: some View {
        ViewModelHost(make: { $0.makeFollowListViewModel(user: user, kind: kind) }) { FollowListContent(model: $0) }
    }
}

private struct FollowListContent: View {
    let model: FollowListViewModel

    var body: some View {
        let users = model.users
        Group {
            if users.isEmpty {
                ContentUnavailableView(
                    model.kind == .followers ? "No followers yet" : "Not following anyone yet",
                    systemImage: "person.2")
            } else {
                List(users) { user in
                    NavigationLink(value: user) {
                        HStack(spacing: 12) {
                            AvatarView(user: user, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.shownName).font(.body.weight(.semibold))
                                Text("@\(user.username)").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(Text(model.kind.title))
        .navigationBarTitleDisplayMode(.inline)
    }
}
