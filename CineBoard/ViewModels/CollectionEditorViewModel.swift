import SwiftUI

@MainActor @Observable
final class CollectionEditorViewModel {
    let collection: MovieCollection?
    var title: String
    var details: String
    var isPublic: Bool
    /// Идентификатор цветовой темы карточки.
    var themeID: String
    /// Два цвета для «своей» темы (редактируются палитрой).
    var customTop: Color
    var customBottom: Color
    /// Личная палитра: сохранённые свои цвета.
    private(set) var savedThemes: [String]
    var errorMessage: String?
    private let repository: any CollectionRepository
    private let session: AppSession

    init(collection: MovieCollection?, repository: any CollectionRepository, session: AppSession) {
        self.collection = collection
        self.repository = repository
        self.session = session
        title = collection?.title ?? ""
        details = collection?.details ?? ""
        isPublic = collection?.isPublic ?? true
        let theme = collection.map { CollectionTheme.resolve(for: $0) } ?? CollectionTheme.all[2]
        themeID = theme.id
        customTop = Color(hex: theme.baseTop)
        customBottom = Color(hex: theme.baseBottom)
        savedThemes = session.currentUser?.savedThemeCodes ?? []
    }

    // MARK: Цвет подборки

    var isCustom: Bool { CollectionTheme.isCustom(themeID) }

    /// Тема, которая сейчас выбрана (для предпросмотра).
    var currentTheme: CollectionTheme {
        if let colors = CollectionTheme.parseCustom(themeID), isCustom {
            return .custom(top: colors.top, bottom: colors.bottom)
        }
        return CollectionTheme.theme(withID: themeID) ?? CollectionTheme.all[2]
    }

    func select(_ theme: CollectionTheme) {
        themeID = theme.id
        customTop = Color(hex: theme.baseTop)
        customBottom = Color(hex: theme.baseBottom)
    }

    /// Переключает на «свои цвета», начиная с текущих.
    func selectCustom() {
        let theme = currentTheme
        customTop = Color(hex: theme.baseTop)
        customBottom = Color(hex: theme.baseBottom)
        customColorsChanged()
    }

    func customColorsChanged() {
        themeID = CollectionTheme.customCode(top: UIColor(customTop).rgbHex, bottom: UIColor(customBottom).rgbHex)
    }

    /// Код текущих своих цветов (`RRGGBB-RRGGBB`).
    private var currentCustomCode: String {
        String(format: "%06X-%06X", UIColor(customTop).rgbHex, UIColor(customBottom).rgbHex)
    }

    var canSaveCustom: Bool {
        isCustom && !savedThemes.contains(currentCustomCode) && savedThemes.count < CollectionRules.savedThemesLimit
    }

    func saveCustomToPalette() {
        guard canSaveCustom else { return }
        updateSaved(savedThemes + [currentCustomCode])
    }

    func removeSaved(_ code: String) { updateSaved(savedThemes.filter { $0 != code }) }

    func useSaved(_ code: String) {
        guard let colors = CollectionTheme.parseCustom(code) else { return }
        customTop = Color(hex: colors.top)
        customBottom = Color(hex: colors.bottom)
        themeID = CollectionTheme.customPrefix + code
    }

    private func updateSaved(_ codes: [String]) {
        do {
            try session.setSavedThemes(codes)
            savedThemes = session.currentUser?.savedThemeCodes ?? codes
        } catch { errorMessage = userMessage(for: error) }
    }

    var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Возвращает сохранённую подборку или `nil` (причина — в `errorMessage`).
    func save() -> MovieCollection? {
        guard let user = session.currentUser else { return nil }
        do {
            if let collection {
                try repository.update(collection, title: title, details: details, isPublic: isPublic, as: user)
                try repository.setTheme(themeID, of: collection, as: user)
                return collection
            }
            let created = try repository.create(title: title, details: details, isPublic: isPublic, as: user)
            try repository.setTheme(themeID, of: created, as: user)
            return created
        } catch {
            errorMessage = userMessage(for: error)
            return nil
        }
    }
}
