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
