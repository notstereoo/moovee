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
                Section("Название") { TextField("Например, «Фильмы на дождливый вечер»", text: $model.title) }
                Section("Описание") {
                    TextField("О чём эта подборка", text: $model.details, axis: .vertical).lineLimit(3...6)
                }
                Section {
                    Toggle("Публичная подборка", isOn: $model.isPublic)
                } footer: {
                    Text(model.isPublic ? "Её увидят другие пользователи в вашем профиле." : "Видна только вам.")
                }
            }
            .navigationTitle(model.collection == nil ? "Новая подборка" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
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
