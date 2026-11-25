import PhotosUI
import SwiftUI

/// Редактирование профиля: аватар, баннер, имя, описание, приватность.
struct ProfileEditorView: View {
    var body: some View {
        ViewModelHost(make: { $0.makeProfileEditorViewModel() }) { ProfileEditorContent(model: $0) }
    }
}

private struct ProfileEditorContent: View {
    @Bindable var model: ProfileEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var avatarItem: PhotosPickerItem?
    @State private var bannerItem: PhotosPickerItem?

    private let bannerHeight: CGFloat = 130
    private let avatarSize: CGFloat = 84

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    photoHeader
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if model.hasAvatar || model.hasBanner {
                    Section { photoActions }
                }

                Section {
                    TextField("Name", text: $model.displayName)
                        .textInputAutocapitalization(.words)
                        .textContentType(.name)
                } header: {
                    Text("Name")
                } footer: {
                    Text(
                        "Shown on your profile. Names don't have to be unique. Your @\(model.username) username can't be changed."
                    )
                        + Text("  \(model.nameRemaining) characters left")
                        .foregroundStyle(model.nameRemaining < 0 ? .red : .secondary)
                }

                Section {
                    TextField("A few words about your taste", text: $model.bio, axis: .vertical).lineLimit(3...6)
                } header: {
                    Text("About me")
                } footer: {
                    Text("\(model.bioRemaining) characters left")
                        .foregroundStyle(model.bioRemaining < 0 ? .red : .secondary)
                }

                Section {
                    Toggle("Private profile", isOn: $model.isPrivate)
                } footer: {
                    Text(
                        "Other users won't see your collections, favorite movies and review list. Reviews on movie pages remain visible to everyone."
                    )
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if model.save() { dismiss() } }.disabled(!model.canSave)
                }
            }
            .onChange(of: avatarItem) { _, item in load(item) { model.setAvatar(from: $0) } }
            .onChange(of: bannerItem) { _, item in load(item) { model.setBanner(from: $0) } }
            .errorAlert($model.errorMessage)
        }
    }

    private func load(_ item: PhotosPickerItem?, apply: @escaping (Data) -> Void) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) { apply(data) }
        }
    }

    // MARK: Баннер и аватар

    private var photoHeader: some View {
        ZStack(alignment: .bottomLeading) {
            PhotosPicker(selection: $bannerItem, matching: .images) {
                ZStack(alignment: .topTrailing) {
                    bannerImage
                    Label("Banner", systemImage: "camera.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change banner")

            PhotosPicker(selection: $avatarItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(
                        name: model.displayName.isEmpty ? model.username : model.displayName,
                        imageData: model.avatarPreview, size: avatarSize
                    )
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 4))
                    Image(systemName: "camera.fill")
                        .font(.caption)
                        .padding(7)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .offset(y: avatarSize / 2)
            .accessibilityLabel("Change profile photo")
        }
        .padding(.bottom, avatarSize / 2 + 8)
    }

    private var bannerImage: some View {
        ProfileBanner(imageData: model.bannerPreview, seed: model.username, height: bannerHeight)
    }

    @ViewBuilder
    private var photoActions: some View {
        if model.hasAvatar {
            Button("Remove profile photo", role: .destructive) {
                avatarItem = nil
                model.removeAvatar()
            }
        }
        if model.hasBanner {
            Button("Remove banner", role: .destructive) {
                bannerItem = nil
                model.removeBanner()
            }
        }
    }
}
