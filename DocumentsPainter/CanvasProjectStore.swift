import Foundation
import Combine

final class CanvasProjectStore: ObservableObject {
    static let shared = CanvasProjectStore()

    private static let legacyCanvasUserDefaultsKey = "canvas.state.v1"
    private static let projectsFolderName = "Projects"
    private static let foldersFileName = "folders.json"
    private static let metaFileName = "meta.json"
    private static let canvasFileName = "canvas.json"
    private static let previewFileName = "preview.png"

    @Published private(set) var projects: [CanvasProjectMetadata] = []
    @Published private(set) var folders: [CanvasFolderMetadata] = []

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        ensureProjectsRootExists()
        reload()
        migrateLegacyCanvasIfNeeded()
        reload()
    }

    private var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DocumentsPainter", isDirectory: true)
    }

    private var projectsRoot: URL {
        applicationSupportDirectory.appendingPathComponent(Self.projectsFolderName, isDirectory: true)
    }

    func projectDirectory(for id: UUID) -> URL {
        projectsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func canvasFileURL(for id: UUID) -> URL {
        projectDirectory(for: id).appendingPathComponent(Self.canvasFileName)
    }

    func metaFileURL(for id: UUID) -> URL {
        projectDirectory(for: id).appendingPathComponent(Self.metaFileName)
    }

    func previewFileURL(for id: UUID) -> URL {
        projectDirectory(for: id).appendingPathComponent(Self.previewFileName)
    }

    func metadata(for id: UUID) -> CanvasProjectMetadata? {
        projects.first { $0.id == id }
    }

    func reload() {
        folders = loadFolders()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            projects = []
            return
        }

        var loaded: [CanvasProjectMetadata] = []
        for url in contents {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let metaURL = url.appendingPathComponent(Self.metaFileName)
            guard let data = try? Data(contentsOf: metaURL),
                  let meta = try? decoder.decode(CanvasProjectMetadata.self, from: data) else { continue }
            loaded.append(meta)
        }
        loaded.sort { $0.modifiedAt > $1.modifiedAt }
        projects = loaded
    }

    @discardableResult
    func createProject(title: String, folderID: UUID? = nil) -> UUID {
        let id = UUID()
        let now = Date()
        let meta = CanvasProjectMetadata(id: id, title: title, createdAt: now, modifiedAt: now, folderID: folderID)
        try? FileManager.default.createDirectory(at: projectDirectory(for: id), withIntermediateDirectories: true)
        saveMetadata(meta)
        reload()
        return id
    }

    func saveMetadata(_ meta: CanvasProjectMetadata) {
        guard let data = try? encoder.encode(meta) else { return }
        let dir = projectDirectory(for: meta.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: metaFileURL(for: meta.id), options: .atomic)
    }

    func renameProject(id: UUID, title: String) {
        guard var meta = metadata(for: id) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.title = trimmed.isEmpty ? meta.title : trimmed
        meta.modifiedAt = Date()
        saveMetadata(meta)
        reload()
    }

    func moveProject(id: UUID, to folderID: UUID?) {
        guard var meta = metadata(for: id) else { return }
        meta.folderID = folderID
        meta.modifiedAt = Date()
        saveMetadata(meta)
        reload()
    }

    @discardableResult
    func copyProject(id: UUID, to folderID: UUID?) -> UUID? {
        guard let sourceMeta = metadata(for: id) else { return nil }

        let newID = UUID()
        let sourceDir = projectDirectory(for: id)
        let destinationDir = projectDirectory(for: newID)

        do {
            try FileManager.default.copyItem(at: sourceDir, to: destinationDir)
        } catch {
            return nil
        }

        let now = Date()
        var copiedMeta = sourceMeta
        copiedMeta.id = newID
        copiedMeta.title = copyTitle(for: sourceMeta.title, in: folderID)
        copiedMeta.folderID = folderID
        copiedMeta.createdAt = now
        copiedMeta.modifiedAt = now
        saveMetadata(copiedMeta)
        reload()
        return newID
    }

    func touchModified(id: UUID) {
        guard var meta = metadata(for: id) else { return }
        meta.modifiedAt = Date()
        saveMetadata(meta)
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx] = meta
            projects.sort { $0.modifiedAt > $1.modifiedAt }
        } else {
            reload()
        }
    }

    func deleteProject(id: UUID) {
        try? FileManager.default.removeItem(at: projectDirectory(for: id))
        reload()
    }

    @discardableResult
    func createFolder(title: String) -> UUID? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let now = Date()
        let folder = CanvasFolderMetadata(id: UUID(), title: trimmed, createdAt: now, modifiedAt: now)
        folders.append(folder)
        folders.sort { $0.modifiedAt > $1.modifiedAt }
        saveFolders()
        return folder.id
    }

    func renameFolder(id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[idx].title = trimmed
        folders[idx].modifiedAt = Date()
        folders.sort { $0.modifiedAt > $1.modifiedAt }
        saveFolders()
    }

    func deleteFolder(id: UUID) {
        folders.removeAll { $0.id == id }
        saveFolders()
        for var project in projects where project.folderID == id {
            project.folderID = nil
            project.modifiedAt = Date()
            saveMetadata(project)
        }
        reload()
    }

    func projects(in folderID: UUID?) -> [CanvasProjectMetadata] {
        guard let folderID else { return projects }
        return projects.filter { $0.folderID == folderID }
    }

    private func copyTitle(for baseTitle: String, in folderID: UUID?) -> String {
        let titles = Set(projects(in: folderID).map { $0.title })
        let baseCopyTitle = "\(baseTitle) копія"
        if !titles.contains(baseCopyTitle) {
            return baseCopyTitle
        }

        var idx = 2
        while titles.contains("\(baseTitle) копія \(idx)") {
            idx += 1
        }
        return "\(baseTitle) копія \(idx)"
    }

    func writePreviewPNG(id: UUID, data: Data) {
        let url = previewFileURL(for: id)
        try? data.write(to: url, options: .atomic)
    }

    private func ensureProjectsRootExists() {
        try? FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
    }

    private var foldersFileURL: URL {
        projectsRoot.appendingPathComponent(Self.foldersFileName)
    }

    private func loadFolders() -> [CanvasFolderMetadata] {
        guard let data = try? Data(contentsOf: foldersFileURL),
              let decoded = try? decoder.decode([CanvasFolderMetadata].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func saveFolders() {
        guard let data = try? encoder.encode(folders) else { return }
        try? data.write(to: foldersFileURL, options: .atomic)
    }

    private func migrateLegacyCanvasIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: Self.legacyCanvasUserDefaultsKey), !data.isEmpty else { return }
        if !projects.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.legacyCanvasUserDefaultsKey)
            return
        }
        let title = "Малюнок"
        let id = UUID()
        let now = Date()
        let meta = CanvasProjectMetadata(id: id, title: title, createdAt: now, modifiedAt: now, folderID: nil)
        try? FileManager.default.createDirectory(at: projectDirectory(for: id), withIntermediateDirectories: true)
        try? data.write(to: canvasFileURL(for: id), options: .atomic)
        saveMetadata(meta)
        UserDefaults.standard.removeObject(forKey: Self.legacyCanvasUserDefaultsKey)
    }
}
