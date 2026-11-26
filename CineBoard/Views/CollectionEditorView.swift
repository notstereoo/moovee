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
                ThemeSection(model: model)
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

/// Выбор цвета карточки: предпросмотр, свои сохранённые цвета, готовые темы и свой градиент.
private struct ThemeSection: View {
    @Bindable var model: CollectionEditorViewModel
    private let columns = [GridItem(.adaptive(minimum: 54), spacing: 12)]

    var body: some View {
        Section {
            preview
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)
        }

        if !model.savedThemes.isEmpty {
            Section("My colors") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.savedThemes, id: \.self) { code in
                        if let colors = CollectionTheme.parseCustom(code) {
                            let theme = CollectionTheme.custom(top: colors.top, bottom: colors.bottom)
                            swatch(theme, selected: model.themeID == theme.id) { model.useSaved(code) }
                                .contextMenu {
                                    Button("Remove", systemImage: "trash", role: .destructive) {
                                        model.removeSaved(code)
                                    }
                                }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }

        Section {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(CollectionTheme.all) { theme in
                    swatch(theme, selected: model.themeID == theme.id) { model.select(theme) }
                }
                customSwatch
            }
            .padding(.vertical, 6)
        } header: {
            Text("Color")
        } footer: {
            Text("The same gradient looks brighter in light mode and calmer in dark mode. Others see your color too.")
        }

        if model.isCustom {
            Section("Your gradient") {
                ColorPicker("Top color", selection: $model.customTop, supportsOpacity: false)
                    .onChange(of: model.customTop) { model.customColorsChanged() }
                ColorPicker("Bottom color", selection: $model.customBottom, supportsOpacity: false)
                    .onChange(of: model.customBottom) { model.customColorsChanged() }
                Button("Save to my colors", systemImage: "plus.circle") { model.saveCustomToPalette() }
                    .disabled(!model.canSaveCustom)
            }
        }
    }

    private var preview: some View {
        ZStack(alignment: .leading) {
            AnimatedThemeBackground(theme: model.currentTheme, seed: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
            Text(model.title.isEmpty ? "Preview" : model.title)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, 18)
        }
        .frame(height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)
    }

    private func swatch(_ theme: CollectionTheme, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(
                    LinearGradient(colors: [theme.top, theme.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 46, height: 46)
                .overlay {
                    if selected {
                        Image(systemName: "checkmark").font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                    }
                }
                .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                .overlay(
                    Circle().stroke(Color.primary.opacity(selected ? 0.85 : 0), lineWidth: 2).padding(-4))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var customSwatch: some View {
        Button {
            model.selectCustom()
        } label: {
            Circle()
                .fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red], center: .center))
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: model.isCustom ? "checkmark" : "paintpalette.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
                .overlay(
                    Circle().stroke(Color.primary.opacity(model.isCustom ? 0.85 : 0), lineWidth: 2).padding(-4))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Custom colors")
        .accessibilityAddTraits(model.isCustom ? .isSelected : [])
    }
}
