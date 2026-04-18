import Foundation

struct CanvasProjectMetadata: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var folderID: UUID?
}

struct CanvasFolderMetadata: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
}
