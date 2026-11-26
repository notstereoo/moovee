import Foundation
import SwiftData

enum SocialError: LocalizedError, Equatable {
    case cannotFollowSelf, cannotLikeOwn, cannotSaveOwn, collectionUnavailable, saveFailed

    var errorDescription: String? {
        switch self {
        case .cannotFollowSelf: String(localized: "You can't follow yourself.")
        case .cannotLikeOwn: String(localized: "You can only like other people's collections.")
        case .cannotSaveOwn: String(localized: "This is your own collection — it is already on your profile.")
        case .collectionUnavailable: String(localized: "This collection is not available.")
        case .saveFailed: String(localized: "Could not save changes. Please try again.")
        }
    }
}

@MainActor @Observable
final class LocalSocialRepository: SocialRepository {
    private(set) var revision = 0
    @ObservationIgnored private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    // MARK: Подписки

    func isFollowing(_ follower: UserAccount, _ followee: UserAccount) -> Bool {
        let a = follower.id, b = followee.id
        let descriptor = FetchDescriptor<Follow>(predicate: #Predicate { $0.followerID == a && $0.followeeID == b })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    func areFriends(_ a: UserAccount, _ b: UserAccount) -> Bool { isFollowing(a, b) && isFollowing(b, a) }

    func followersCount(of user: UserAccount) -> Int {
        let id = user.id
        return (try? context.fetchCount(FetchDescriptor<Follow>(predicate: #Predicate { $0.followeeID == id }))) ?? 0
    }

    func followingCount(of user: UserAccount) -> Int {
        let id = user.id
        return (try? context.fetchCount(FetchDescriptor<Follow>(predicate: #Predicate { $0.followerID == id }))) ?? 0
    }

    func followers(of user: UserAccount) -> [UserAccount] {
        let id = user.id
        let rows = fetch(FetchDescriptor<Follow>(predicate: #Predicate { $0.followeeID == id }))
        return users(rows.sorted { $0.createdAt > $1.createdAt }.map(\.followerID))
    }

    func following(of user: UserAccount) -> [UserAccount] {
        let id = user.id
        let rows = fetch(FetchDescriptor<Follow>(predicate: #Predicate { $0.followerID == id }))
        return users(rows.sorted { $0.createdAt > $1.createdAt }.map(\.followeeID))
    }

    func follow(_ followee: UserAccount, as user: UserAccount) throws {
        guard followee.id != user.id else { throw SocialError.cannotFollowSelf }
        guard !isFollowing(user, followee) else { return }
        context.insert(Follow(followerID: user.id, followeeID: followee.id))
        try commit()
    }

    func unfollow(_ followee: UserAccount, as user: UserAccount) throws {
        let a = user.id, b = followee.id
        let rows = fetch(FetchDescriptor<Follow>(predicate: #Predicate { $0.followerID == a && $0.followeeID == b }))
        guard !rows.isEmpty else { return }
        rows.forEach(context.delete)
        try commit()
    }

    // MARK: Лайки

    func likeCount(of collection: MovieCollection) -> Int {
        let id = collection.id
        return
            (try? context.fetchCount(FetchDescriptor<CollectionLike>(predicate: #Predicate { $0.collectionID == id })))
            ?? 0
    }

    func totalLikes(ofOwner user: UserAccount) -> Int {
        let ids = user.collections.map(\.id)
        guard !ids.isEmpty else { return 0 }
        return
            (try? context.fetchCount(
                FetchDescriptor<CollectionLike>(predicate: #Predicate { ids.contains($0.collectionID) }))) ?? 0
    }

    func isLiked(_ collection: MovieCollection, by user: UserAccount) -> Bool {
        let u = user.id, c = collection.id
        let descriptor = FetchDescriptor<CollectionLike>(predicate: #Predicate { $0.userID == u && $0.collectionID == c })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    func setLiked(_ liked: Bool, _ collection: MovieCollection, as user: UserAccount) throws {
        let u = user.id, c = collection.id
        if liked {
            guard collection.owner?.id != user.id else { throw SocialError.cannotLikeOwn }
            guard collection.isVisible(to: user) else { throw SocialError.collectionUnavailable }
            guard !isLiked(collection, by: user) else { return }
            context.insert(CollectionLike(userID: u, collectionID: c))
        } else {
            let rows = fetch(
                FetchDescriptor<CollectionLike>(predicate: #Predicate { $0.userID == u && $0.collectionID == c }))
            guard !rows.isEmpty else { return }
            rows.forEach(context.delete)
        }
        try commit()
    }

    // MARK: Сохранённые подборки

    func saveCount(of collection: MovieCollection) -> Int {
        let id = collection.id
        return
            (try? context.fetchCount(FetchDescriptor<SavedCollection>(predicate: #Predicate { $0.collectionID == id })))
            ?? 0
    }

    func isSaved(_ collection: MovieCollection, by user: UserAccount) -> Bool {
        let u = user.id, c = collection.id
        let descriptor = FetchDescriptor<SavedCollection>(
            predicate: #Predicate { $0.userID == u && $0.collectionID == c })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    func setSaved(_ saved: Bool, _ collection: MovieCollection, as user: UserAccount) throws {
        let u = user.id, c = collection.id
        if saved {
            guard collection.owner?.id != user.id else { throw SocialError.cannotSaveOwn }
            guard collection.isVisible(to: user) else { throw SocialError.collectionUnavailable }
            guard !isSaved(collection, by: user) else { return }
            context.insert(SavedCollection(userID: u, collectionID: c))
        } else {
            let rows = fetch(
                FetchDescriptor<SavedCollection>(predicate: #Predicate { $0.userID == u && $0.collectionID == c }))
            guard !rows.isEmpty else { return }
            rows.forEach(context.delete)
        }
        try commit()
    }

    func savedCollections(of user: UserAccount) -> [MovieCollection] {
        let id = user.id
        let rows = fetch(FetchDescriptor<SavedCollection>(predicate: #Predicate { $0.userID == id }))
            .sorted { $0.savedAt > $1.savedAt }
        let ids = rows.map(\.collectionID)
        guard !ids.isEmpty else { return [] }
        let found = fetch(FetchDescriptor<MovieCollection>(predicate: #Predicate { ids.contains($0.id) }))
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }.filter { $0.isVisible(to: user) }
    }

    // MARK: Внутреннее

    private func users(_ ids: [UUID]) -> [UserAccount] {
        guard !ids.isEmpty else { return [] }
        let found = fetch(FetchDescriptor<UserAccount>(predicate: #Predicate { ids.contains($0.id) }))
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }

    private func commit() throws {
        do {
            try context.save()
            revision += 1
        } catch {
            context.rollback()
            throw SocialError.saveFailed
        }
    }
}
