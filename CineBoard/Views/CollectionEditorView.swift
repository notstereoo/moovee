import SwiftUI

struct CollectionEditorView: View {
    var collection: MovieCollection?
    var onSaved: ((MovieCollection) -> Void)?

    var body: some View {
        ViewModelHost(make: { $0.makeEditorViewModel(collection: collection) }) {
            CollectionEditorContent(model: $0, onSaved: onSaved)
        }
    }
}

private struct CollectionEditorContent: View {
    @Bindable var model: CollectionEditorViewModel
    var onSaved: ((MovieCollection) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") { TextField("e.g. \"Movies for a rainy evening\"", text: $model.title) }
                Section("Description") {
                    TextField("What is this collection about", text: $model.details, axis: .vertical).lineLimit(3...6)
                }
                Section {
                    ThemePicker(selection: $model.themeID)
                } header: {
                    Text("Color")
                } footer: {
                    Text("The card on your profile is painted with this gradient.")
                }
                Section {
                    Toggle("Public collection", isOn: $model.isPublic)
                } footer: {
                    Text(model.isPublic ? "Other users will see it on your profile." : "Visible only to you.")
                }
            }
            .navigationTitle(model.collection == nil ? "New collection" : "Editing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let saved = model.save() {
                            onSaved?(saved)
                            dismiss()
                        }
                    }
                    .disabled(!model.canSave)
                }
            }
            .errorAlert($model.errorMessage)
        }
    }
}

/// Выбор цветовой темы подборки.
private struct ThemePicker: View {
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(CollectionTheme.all) { theme in
                    Button {
                        selection = theme.id
                    } label: {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [theme.top, theme.bottom], startPoint: .topLeading,
                                    endPoint: .bottomTrailing)
                            )
                            .frame(width: 46, height: 46)
                            .overlay {
                                if selection == theme.id {
                                    Image(systemName: "checkmark").font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay(
                                Circle().stroke(Color.primary.opacity(selection == theme.id ? 0.9 : 0), lineWidth: 2)
                                    .padding(-4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.name)
                    .accessibilityAddTraits(selection == theme.id ? .isSelected : [])
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        }
    }
}
