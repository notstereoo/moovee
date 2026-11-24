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
    @Environment(AppSession.self) private var session
    @State private var showEditProfile = false
    @State private var confirmLogout = false

    private var isMe: Bool { session.currentUser?.id == user.id }

    var body: some View {
        if user.modelContext == nil {
            ContentUnavailableView("Профиль недоступен", systemImage: "person.slash")
        } else {
            content
        }
    }

    private var content: some View {
        // Для чужого профиля — только публичные подборки; для своего — все.
        let list = user.collections(visibleTo: session.currentUser)
        return ScrollView {
            VStack(spacing: 16) {
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
                    } else if isMe {
                        Text("Добавьте описание профиля через меню ⋯").foregroundStyle(.tertiary).font(.footnote)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack {
                    Text(isMe ? "Мои подборки" : "Публичные подборки").font(.headline)
                    Spacer()
                }

                if list.isEmpty {
                    ContentUnavailableView(
                        isMe ? "Пока нет подборок" : "Нет публичных подборок",
                        systemImage: "rectangle.stack",
                        description: Text(isMe ? "Создайте первую подборку на вкладке «Подборки»."
                                               : "Этот пользователь пока ничем не поделился."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 16) {
                        ForEach(list) { c in
                            NavigationLink(value: c) { CollectionCard(collection: c) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(isMe ? "Профиль" : "@\(user.username)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isMe {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Редактировать профиль", systemImage: "pencil") { showEditProfile = true }
                        Button("Выйти", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmLogout = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Меню профиля")
                }
            }
        }
        .sheet(isPresented: $showEditProfile) { EditProfileView() }
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { session.logout() }
            Button("Отмена", role: .cancel) {}
        }
    }
}

struct EditProfileView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var bio = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("О себе") { TextField("Пара слов о ваших вкусах", text: $bio, axis: .vertical).lineLimit(3...6) }
                Section { Text("\(bio.count)/160").foregroundStyle(.secondary).font(.footnote) }
            }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        do { try session.updateBio(bio); dismiss() }
                        catch { errorMessage = userMessage(for: error) }
                    }
                    .disabled(bio.count > 160)
                }
            }
            .onAppear { bio = session.currentUser?.bio ?? "" }
            .errorAlert($errorMessage)
        }
    }
}
