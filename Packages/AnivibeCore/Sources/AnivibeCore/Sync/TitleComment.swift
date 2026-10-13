import Foundation
public struct TitleComment: Decodable, Sendable, Identifiable {
    public let id: String
    public let authorID: String
    public let authorName: String
    public let body: String
    public let createdAt: String
    public let likes: Int
    public let dislikes: Int
    public let myReaction: Int
    enum CodingKeys: String, CodingKey {
        case id, body, likes, dislikes
        case authorID = "author_id", authorName = "author_name", createdAt = "created_at", myReaction = "my_reaction"
    }
}
struct AvatarLink: Decodable { let url: URL? }
