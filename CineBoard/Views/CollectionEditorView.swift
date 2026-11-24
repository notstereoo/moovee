import SwiftUI
import SwiftData

struct CollectionEditorView: View {
    let collection: MovieCollection?
    var onSaved: ((MovieCollection) -> Void)?

    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var details: String
    @State private var isPublic: Bool
    @State private var errorMessage: String?

    init(collection: MovieCollection? = nil, onSaved: ((MovieCollection) -> Void)? = nil) {
        self.collection = collection
        self.onSaved = onSaved
        _title = State(initialValue: collection?.title ?? "")
        _details = State(initialValue: collection?.details ?? "")
        _isPublic = State(initialValue: collection?.isPublic ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") { TextField("Например, «Фильмы на дождливый вечер»", text: $title) }
                Section("Описание") { TextField("О чём эта подборка", text: $details, axis: .vertical).lineLimit(3...6) }
                Section {
                    Toggle("Публичная подборка", isOn: $isPublic)
                } footer: {
                    Text(isPublic ? "Её увидят другие пользователи в вашем профиле." : "Видна только вам.")
                }
            }
            .navigationTitle(collection == nil ? "Новая подборка" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .errorAlert($errorMessage)
        }
    }

    private func save() {
        guard let user = session.currentUser else { return }
        let service = CollectionService(context: context, user: user)
        do {
            let result: MovieCollection
            if let collection {
                try service.update(collection, title: title, details: details, isPublic: isPublic)
                result = collection
            } else {
                result = try service.create(title: title, details: details, isPublic: isPublic)
            }
            onSaved?(result)
            dismiss()
        } catch {
            errorMessage = userMessage(for: error)
        }
    }
}
