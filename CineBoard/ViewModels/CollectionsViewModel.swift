import Foundation

/// Вкладка «Подборки»: свои подборки и публичные подборки других.
@MainActor @Observable
final class CollectionsViewModel {
    enum Scope: String, CaseIterable, Identifiable {
        case mine, discover
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .mine: "Mine"
            case .discover: "Discover"
            }
        }
    }

    var scope: Scope = .mine
    private let repository: any CollectionRepository
    private let session: AppSession

    init(repository: any CollectionRepository, session: AppSession) {
        self.repository = repository
        self.session = session
    }

    var mine: [MovieCollection] {
        _ = repository.revision
        guard let me = session.currentUser else { return [] }
        return repository.collections(ownedBy: me)
    }

    var others: [MovieCollection] {
        _ = repository.revision
        return repository.publicCollections(excluding: session.currentUser)
    }

    var visible: [MovieCollection] { scope == .mine ? mine : others }
}
