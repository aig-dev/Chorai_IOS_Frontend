import Foundation

struct NoteCard: Identifiable, Equatable {
    let id: Int
    let title: String
    let description: String
    let isPublic: Bool
    let username: String
    let avatarUrl: String?
}
