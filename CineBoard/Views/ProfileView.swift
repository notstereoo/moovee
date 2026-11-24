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
    @State private var showFavoritesEditor = false
    @State private var showDeleteAccount = false
    @State private var confirmLogout = false
    @ScaledMetric(relativeTo: .caption) private var posterWidth: CGFloat = 110

    private var user: UserAccount { model.user }

    var body: some View {
        if !model.isAvailable {
            ContentUnavailableView("Профиль недоступен", systemImage: "person.slash")
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if model.isContentHidden {
                    closedNotice
                } else {
                    favoritesSection
                    collectionsSection
                    reviewsSection
                }
            }
            .padding()
        }
        .navigationTitle(model.isMe ? "Профиль" : "@\(user.username)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.isMe {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Редактировать профиль", systemImage: "pencil") { showEditProfile = true }
                        Button("Удалить аккаунт…", systemImage: "person.crop.circle.badge.minus", role: .destructive) {
                            showDeleteAccount = true
                        }
                        Button("Выйти", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            confirmLogout = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Меню профиля")
                }
            }
        }
        .sheet(isPresented: $showEditProfile) { EditProfileView() }
        .sheet(isPresented: $showDeleteAccount) { DeleteAccountView() }
        .sheet(isPresented: $showFavoritesEditor) { FavoritesEditorView(model: model) }
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { session.logout() }
            Button("Отмена", role: .cancel) {}
        }
        .errorAlert($model.errorMessage)
    }

    // MARK: Секции

    private var header: some View {
        VStack(spacing: 8) {
            AvatarView(name: user.username, size: 88)
            Text("@\(user.username)").font(.title2.bold())
            if user.isDemo {
                Text("Демо-профиль").font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
            }
            if !user.bio.isEmpty {
                Text(user.bio).multilineTextAlignment(.center).foregroundStyle(.secondary)
            } else if model.isMe {
                Text("Добавьте описание профиля через меню ⋯").foregroundStyle(.tertiary).font(.footnote)
            }
            if !model.isContentHidden {
                // На крупном шрифте счётчики встают в столбик, а не рвут слова.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { stats }
                    VStack(spacing: 8) { stats }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var stats: some View {
        stat(model.favorites.count, "любимых")
        stat(model.collections.count, "подборок")
        stat(model.reviews.count, "отзывов")
    }

    private var closedNotice: some View {
        ContentUnavailableView(
            "Профиль закрыт", systemImage: "lock.fill",
            description: Text("Пользователь скрыл свои подборки, любимые фильмы и список отзывов."))
    }

    private func stat(_ value: Int, _ title: LocalizedStringKey) -> some View {
        VStack(spacing: 0) {
            Text("\(value)").font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private func sectionHeader(_ title: String, action: (title: String, run: () -> Void)? = nil) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if let action { Button(action.title, action: action.run).font(.subheadline) }
        }
    }

    private var favoritesSection: some View {
        let list = model.favorites
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                "Любимые фильмы",
                action: model.isMe && !list.isEmpty ? ("Изменить", { showFavoritesEditor = true }) : nil)
            if list.isEmpty {
                Text(
                    model.isMe
                        ? "Добавляйте фильмы сердечком на экране фильма — они появятся здесь."
                        : "Пока не выбраны."
                )
                .foregroundStyle(.secondary).font(.subheadline)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(list) { fav in
                            NavigationLink(value: Movie(favorite: fav)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    PosterImage(path: fav.posterPath, title: fav.title, size: .w342, ratio: 1.5)
                                        .frame(width: posterWidth)
                                    Text(fav.title).font(.caption.weight(.medium)).lineLimit(3)
                                        .frame(width: posterWidth, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var collectionsSection: some View {
        let list = model.collections
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(model.isMe ? "Мои подборки" : "Публичные подборки")
            if list.isEmpty {
                Text(
                    model.isMe
                        ? "Создайте первую подборку на вкладке «Подборки»."
                        : "Этот пользователь пока ничем не поделился."
                )
                .foregroundStyle(.secondary).font(.subheadline)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 16) {
                    ForEach(list) { c in
                        NavigationLink(value: c) { CollectionCard(collection: c) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var reviewsSection: some View {
        let list = model.reviews
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(model.isMe ? "Мои отзывы" : "Отзывы")
            if list.isEmpty {
                Text(
                    model.isMe
                        ? "Оценивайте фильмы и пишите отзывы на их страницах."
                        : "Пока нет отзывов."
                )
                .foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(list) { ReviewRow(review: $0, showMovie: true) }
            }
        }
    }
}

// MARK: - Редактор любимых

private struct FavoritesEditorView: View {
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
            .navigationTitle("Любимые фильмы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .overlay {
                if model.favorites.isEmpty {
                    ContentUnavailableView("Список пуст", systemImage: "heart")
                }
            }
            .errorAlert(Binding(get: { model.errorMessage }, set: { model.errorMessage = $0 }))
        }
    }
}

struct EditProfileView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var bio = ""
    @State private var isPrivate = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("О себе") {
                    TextField("Пара слов о ваших вкусах", text: $bio, axis: .vertical).lineLimit(3...6)
                }
                Section { Text("\(bio.count)/160").foregroundStyle(.secondary).font(.footnote) }
                Section {
                    Toggle("Закрытый профиль", isOn: $isPrivate)
                } footer: {
                    Text(
                        "Другие пользователи не увидят ваши подборки, любимые фильмы и список отзывов. Отзывы под фильмами остаются видны всем."
                    )
                }
            }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        do {
                            try session.updateBio(bio)
                            try session.setProfilePrivate(isPrivate)
                            dismiss()
                        } catch { errorMessage = userMessage(for: error) }
                    }
                    .disabled(bio.count > 160)
                }
            }
            .onAppear {
                bio = session.currentUser?.bio ?? ""
                isPrivate = session.currentUser?.isProfilePrivate ?? false
            }
            .errorAlert($errorMessage)
        }
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
                        "Профиль, подборки, отзывы и любимые фильмы будут удалены с этого устройства безвозвратно. Восстановить их не получится."
                    )
                }
                Section("Подтвердите паролем") {
                    SecureField("Пароль", text: $password).textContentType(.password)
                }
                Section {
                    Button("Удалить аккаунт и все данные", role: .destructive) {
                        do {
                            try session.deleteAccount(password: password)
                            dismiss()
                        } catch { errorMessage = userMessage(for: error) }
                    }
                    .disabled(password.isEmpty)
                }
            }
            .navigationTitle("Удаление аккаунта")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
            .errorAlert($errorMessage)
        }
    }
}
