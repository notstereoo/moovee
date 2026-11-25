import Foundation

@MainActor @Observable
final class ProfileEditorViewModel {
    var displayName: String
    var bio: String
    var isPrivate: Bool
    var errorMessage: String?
    /// Что показывать в предпросмотре (текущее значение или выбранное, ещё не сохранённое).
    private(set) var avatarPreview: Data?
    private(set) var bannerPreview: Data?
    private(set) var avatarChange: ImageChange = .keep
    private(set) var bannerChange: ImageChange = .keep
    let username: String
    private let session: AppSession

    init(session: AppSession) {
        self.session = session
        let user = session.currentUser
        username = user?.username ?? ""
        displayName = user?.displayName ?? ""
        bio = user?.bio ?? ""
        isPrivate = user?.isProfilePrivate ?? false
        avatarPreview = user?.avatarData
        bannerPreview = user?.bannerData
    }

    var nameRemaining: Int { ProfileRules.maxNameLength - displayName.count }
    var bioRemaining: Int { ProfileRules.maxBioLength - bio.count }
    var canSave: Bool { nameRemaining >= 0 && bioRemaining >= 0 }
    var hasAvatar: Bool { avatarPreview != nil }
    var hasBanner: Bool { bannerPreview != nil }

    /// `false`, если файл не удалось прочитать как изображение.
    @discardableResult
    func setAvatar(from raw: Data) -> Bool {
        guard let data = ImageProcessing.avatarJPEG(from: raw) else {
            errorMessage = String(localized: "Could not read this image.")
            return false
        }
        avatarPreview = data
        avatarChange = .set(data)
        return true
    }

    @discardableResult
    func setBanner(from raw: Data) -> Bool {
        guard let data = ImageProcessing.bannerJPEG(from: raw) else {
            errorMessage = String(localized: "Could not read this image.")
            return false
        }
        bannerPreview = data
        bannerChange = .set(data)
        return true
    }

    /// Уже кадрированный пользователем JPEG.
    func applyAvatar(jpeg: Data) {
        avatarPreview = jpeg
        avatarChange = .set(jpeg)
    }

    func applyBanner(jpeg: Data) {
        bannerPreview = jpeg
        bannerChange = .set(jpeg)
    }

    func removeAvatar() {
        avatarPreview = nil
        avatarChange = .remove
    }

    func removeBanner() {
        bannerPreview = nil
        bannerChange = .remove
    }

    func save() -> Bool {
        let edit = ProfileEdit(
            displayName: displayName, bio: bio, isPrivate: isPrivate, avatar: avatarChange, banner: bannerChange)
        do {
            try session.updateProfile(edit)
            return true
        } catch {
            errorMessage = userMessage(for: error)
            return false
        }
    }
}
