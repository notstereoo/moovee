import SwiftUI

struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        if session.currentUser != nil {
            MainTabView()
        } else {
            AuthView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            FeedView().tabItem { Label("Лента", systemImage: "square.grid.2x2") }
            SearchView().tabItem { Label("Поиск", systemImage: "magnifyingglass") }
            CollectionsView().tabItem { Label("Подборки", systemImage: "rectangle.stack") }
            ProfileTab().tabItem { Label("Профиль", systemImage: "person.crop.circle") }
        }
    }
}

struct AuthView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case login, register
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .login: "Вход"
            case .register: "Регистрация"
            }
        }
    }

    @Environment(AppSession.self) private var session
    @State private var mode: Mode = .login
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?

    /// В UI-тестах подсказка «надёжный пароль» перехватывает фокус и ломает ввод.
    private var passwordContentType: UITextContentType? {
        #if DEBUG
            if UITestSupport.isActive { return nil }
        #endif
        return mode == .login ? .password : .newPassword
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "film.stack").font(.system(size: 56)).foregroundStyle(.tint).padding(.top, 40)
                Text("CineBoard").font(.largeTitle.bold())
                Text("Находите фильмы и собирайте подборки")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)

                Picker("Режим", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { errorMessage = nil }

                VStack(spacing: 12) {
                    TextField("Имя пользователя", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .textFieldStyle(.roundedBorder)
                    SecureField(mode == .register ? "Пароль (от 8 символов)" : "Пароль", text: $password)
                        .textContentType(passwordContentType)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submit)
                }

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }

                Button(action: submit) {
                    Text(mode == .login ? "Войти" : "Создать аккаунт").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)

                Text("Аккаунты хранятся только на этом устройстве.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
    }

    private func submit() {
        do {
            switch mode {
            case .login: try session.login(username: username, password: password)
            case .register: try session.register(username: username, password: password)
            }
        } catch {
            errorMessage = userMessage(for: error)
        }
    }
}
