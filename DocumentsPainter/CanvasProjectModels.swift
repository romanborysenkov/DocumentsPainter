import Foundation

struct CanvasProjectMetadata: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
}
