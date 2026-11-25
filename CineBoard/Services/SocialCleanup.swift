import Foundation
import SwiftData

/// Связи (подписки, лайки, сохранения) хранятся по идентификаторам, поэтому при удалении
/// пользователя или подборки их нужно убирать вручную.
@MainActor
enum SocialCleanup {
    /// Всё, что связано с пользователем: его подписки и подписчики, его лайки/сохранения,
    /// а также лайки и сохранения его подборок другими.
    static func removeData(of user: UserAccount, in context: ModelContext) {
        let id = user.id
        let collectionIDs = user.collections.map(\.id)
        try? context.delete(model: Follow.self, where: #Predicate { $0.followerID == id || $0.followeeID == id })
        try? context.delete(
            model: CollectionLike.self, where: #Predicate { $0.userID == id || collectionIDs.contains($0.collectionID) })
        try? context.delete(
            model: SavedCollection.self,
            where: #Predicate { $0.userID == id || collectionIDs.contains($0.collectionID) })
    }

    static func removeData(ofCollection collectionID: UUID, in context: ModelContext) {
        try? context.delete(model: CollectionLike.self, where: #Predicate { $0.collectionID == collectionID })
        try? context.delete(model: SavedCollection.self, where: #Predicate { $0.collectionID == collectionID })
    }
}
