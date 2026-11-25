import Foundation

@MainActor @Observable
final class FollowListViewModel {
    enum Kind: Hashable {
        case followers, following

        var title: LocalizedStringResource {
            switch self {
            case .followers: "Followers"
            case .following: "Following"
            }
        }
    }

    let user: UserAccount
    let kind: Kind
    private let social: any SocialRepository

    init(user: UserAccount, kind: Kind, social: any SocialRepository) {
        self.user = user
        self.kind = kind
        self.social = social
    }

    var users: [UserAccount] {
        _ = social.revision
        switch kind {
        case .followers: return social.followers(of: user)
        case .following: return social.following(of: user)
        }
    }
}
