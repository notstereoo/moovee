import SwiftUI

/// Вкладка «Профиль»: собственный профиль в своём NavigationStack.
struct ProfileTab: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        NavigationStack {
            if let me = session.currentUser {
                ProfileView(user: me).appDestinations()
            }
        }
    }
}

struct ProfileView: View {
    let user: UserAccount

    var body: some View {
        ViewModelHost(make: { $0.makeProfileViewModel(user: user) }) { ProfileContent(model: $0) }
    }
}

private struct ProfileContent: View {
    @Bindable var model: ProfileViewModel
    @Environment(AppSession.self) private var session
    @State private var showEditProfile = false
    @State private var showDeleteAccount = false
    @State private var confirmLogout = false

    private var user: UserAccount { model.user }
    private let bannerHeight: CGFloat = 200
    private let avatarSize: CGFloat = 88

    var body: some View {
        if !model.isAvailable {
            ContentUnavailableView("Profile unavailable", systemImage: "person.slash")
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                banner
                VStack(alignment: .leading, spacing: 14) {
                    header
                    bio
                    statsRow
                    followButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if model.isMe { tabBar.padding(.top, 18) } else { Divider().padding(.top, 18) }

                VStack(alignment: .leading, spacing: 24) {
                    if model.isContentHidden {
                        closedNotice
                    } else if model.isMe && model.tab == .saved {
                        savedList
                    } else {
                        homeContent
                    }
                }
                .padding(16)
            }
        }
        .coordinateSpace(name: ProfileBanner.scrollSpace)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if model.isMe {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Edit profile", systemImage: "pencil") { showEditProfile = true }
                        Button("Delete account…", systemImage: "person.crop.circle.badge.minus", role: .destructive) {
                            showDeleteAccount = true
                        }
                        Button("Log out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            confirmLogout = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Profile menu")
                }
            }
        }
        .sheet(isPresented: $showEditProfile) { ProfileEditorView() }
        .sheet(isPresented: $showDeleteAccount) { DeleteAccountView() }
        .confirmationDialog("Log out of your account?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { session.logout() }
            Button("Cancel", role: .cancel) {}
        }
        .errorAlert($model.errorMessage)
    }

    // MARK: Шапка

    private var banner: some View {
        ProfileBanner(imageData: user.bannerData, seed: user.username, height: bannerHeight, stretches: true)
    }

    /// Слева аватар (наполовину на баннере) и под ним @никнейм; справа имя, выровненное по нижней половине аватара.
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                AvatarView(user: user, size: avatarSize)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 4))
                    .padding(.top, -avatarSize / 2)
                Text("@\(user.username)")
                    .font(.footnote)
                    .foregroundStyle(.secondary.opacity(0.85))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 6) {
                Text(user.shownName)
                    .font(.title2.bold())
                    .lineLimit(2)
                    .frame(minHeight: avatarSize / 2, alignment: .center)
                if user.isDemo || model.isFriend {
                    HStack(spacing: 6) {
                        if user.isDemo { badge("Demo profile", systemImage: "sparkles") }
                        if model.isFriend { badge("Friends", systemImage: "person.2.fill") }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func badge(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
    }

    @ViewBuilder
    private var bio: some View {
        if !user.bio.isEmpty {
            Text(user.bio)
        } else if model.isMe {
            Text("Add a bio in Edit profile").foregroundStyle(.tertiary).font(.footnote)
        }
    }

    private var statsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { stats }
            VStack(alignment: .leading, spacing: 6) { stats }
        }
    }

    @ViewBuilder
    private var stats: some View {
        NavigationLink(value: ProfileRoute.followList(user, .followers)) {
            stat(model.followersCount, "Followers")
        }
        .buttonStyle(.plain)
        NavigationLink(value: ProfileRoute.followList(user, .following)) {
            stat(model.followingCount, "Following")
        }
        .buttonStyle(.plain)
        HStack(spacing: 4) {
            Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink)
            stat(model.totalLikes, "Likes")
        }
    }

    private func stat(_ value: Int, _ title: LocalizedStringKey) -> some View {
        (Text("\(value)").font(.subheadline.weight(.bold)) + Text(" ") + Text(title).foregroundStyle(.secondary))
            .font(.subheadline)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .combine)
    }

    /// Редактирование своего профиля — только через меню справа сверху; здесь лишь подписка на чужой профиль.
    @ViewBuilder
    private var followButton: some View {
        if !model.isMe && model.canFollow {
            Button {
                model.toggleFollow()
            } label: {
                Text(model.isFollowing ? "Following" : "Follow").font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .modifier(FollowButtonStyle(isFollowing: model.isFollowing))
        }
    }

    // MARK: Вкладки

    private var tabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(ProfileViewModel.Tab.allCases) { tab in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { model.tab = tab }
                    } label: {
                        Text(tab.title)
                            .font(.subheadline.weight(model.tab == tab ? .bold : .medium))
                            .foregroundStyle(model.tab == tab ? Color.primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay(alignment: .bottom) {
                                if model.tab == tab { Capsule().fill(Color.primary).frame(width: 44, height: 3) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
                }
            }
            Divider()
        }
    }

    // MARK: Главная

    @ViewBuilder
    private var homeContent: some View {
        favoritesButton
        collectionsSection
        reviewsSection
    }

    private var favoritesButton: some View {
        let list = model.favorites
        return NavigationLink(value: ProfileRoute.favorites(user)) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill").font(.title3).foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Favorite movies").font(.headline)
                    Text(favoritesSubtitle(list)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: -14) {
                    ForEach(Array(list.prefix(3).enumerated()), id: \.element.id) { index, fav in
                        PosterImage(path: fav.posterPath, title: fav.title, size: .w185, ratio: 1.0)
                            .frame(width: 34)
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                            .clipShape(Circle())
                            .zIndex(Double(3 - index))
                    }
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private func favoritesSubtitle(_ list: [FavoriteMovie]) -> String {
        if list.isEmpty {
            return model.isMe
                ? String(localized: "Add movies with the heart on a movie page")
                : String(localized: "Nothing here yet")
        }
        return list.prefix(3).map(\.title).joined(separator: ", ") + (list.count > 3 ? "…" : "")
    }

    private var collectionsSection: some View {
        let featured = model.featuredCollections
        return VStack(alignment: .leading, spacing: 16) {
            SectionLink(title: model.isMe ? "My collections" : "Collections", route: .collections(user))
            if featured.isEmpty {
                Text(
                    model.isMe
                        ? "Create your first collection on the Collections tab."
                        : "This user hasn't shared anything yet."
                )
                .foregroundStyle(.secondary).font(.subheadline)
            } else {
                ShowcaseList(model: model, collections: featured)
            }
        }
    }

    private var reviewsSection: some View {
        let list = model.featuredReviews
        return VStack(alignment: .leading, spacing: 12) {
            SectionLink(title: model.isMe ? "My reviews" : "Reviews", route: .reviews(user))
            if list.isEmpty {
                Text(model.isMe ? "Rate movies and write reviews on their pages." : "No reviews yet.")
                    .foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(list) { ReviewRow(review: $0, showMovie: true) }
            }
        }
    }

    // MARK: Сохранённые

    @ViewBuilder
    private var savedList: some View {
        let list = model.savedCollections
        if list.isEmpty {
            ContentUnavailableView(
                "No saved collections", systemImage: "bookmark",
                description: Text("Tap the bookmark on other people's collections to keep them here."))
        } else {
            LazyVStack(spacing: 16) {
                ForEach(list) { SavedCollectionRow(collection: $0) }
            }
        }
    }

    private var closedNotice: some View {
        ContentUnavailableView(
            "This profile is private", systemImage: "lock.fill",
            description: Text("This user has hidden their collections, favorite movies and reviews."))
    }
}

/// Кнопка подписки: «Follow» — заметная, «Following» — спокойная.
private struct FollowButtonStyle: ViewModifier {
    let isFollowing: Bool

    func body(content: Content) -> some View {
        if isFollowing {
            content.buttonStyle(.bordered)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

/// Строка сохранённой подборки: обложка слева, справа название, автор, число фильмов и описание.
private struct SavedCollectionRow: View {
    let collection: MovieCollection

    var body: some View {
        NavigationLink(value: collection) {
            HStack(alignment: .top, spacing: 14) {
                PosterImage(path: collection.coverPath, title: collection.title, size: .w342, ratio: 1.35)
                    .frame(width: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.title).font(.headline).lineLimit(2)
                    if let owner = collection.owner {
                        Text("by \(owner.shownName)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(filmsText(collection.items.count)).font(.caption).foregroundStyle(.secondary)
                    if !collection.details.isEmpty {
                        Text(collection.details).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// Необратимое удаление аккаунта: подтверждается паролем.
struct DeleteAccountView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Your profile, collections, reviews and favorites will be permanently deleted from this device. This cannot be undone."
                    )
                }
                Section("Confirm with your password") {
                    SecureField("Password", text: $password).textContentType(.password)
                }
                Section {
                    Button("Delete account and all data", role: .destructive) {
                        do {
                            try session.deleteAccount(password: password)
                            dismiss()
                        } catch { errorMessage = userMessage(for: error) }
                    }
                    .disabled(password.isEmpty)
                }
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .errorAlert($errorMessage)
        }
    }
}

/// Заголовок раздела со стрелкой: нажатие открывает экран со всем списком.
struct SectionLink: View {
    let title: LocalizedStringKey
    let route: ProfileRoute

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 5) {
                Text(title).font(.headline)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint("Shows all")
    }
}

/// Подборки карточками, одна под другой; всё выровнено по левому краю.
struct ShowcaseList: View {
    let model: ProfileViewModel
    let collections: [MovieCollection]

    var body: some View {
        LazyVStack(spacing: 18) {
            ForEach(collections) { c in
                CollectionShowcaseCard(
                    collection: c, likes: model.likeCount(of: c), saves: model.saveCount(of: c),
                    showsSave: model.canSave(c), isSaved: model.isSaved(c), onToggleSave: { model.toggleSave(c) })
            }
        }
    }
}
