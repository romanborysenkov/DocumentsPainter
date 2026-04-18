import SwiftUI

struct ProjectLibraryView: View {
    private enum LibrarySelection: Hashable {
        case all
        case folder(UUID)
    }

    @ObservedObject private var store = CanvasProjectStore.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var navigationPath = NavigationPath()
    @State private var selection: LibrarySelection? = .all
    @State private var showCreateFolderAlert = false
    @State private var newFolderName = ""

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section("На цьому iPad") {
                    NavigationLink(value: LibrarySelection.all) {
                        Label("Мої малюнки", systemImage: "folder.fill")
                    }
                }
                Section("Папки") {
                    ForEach(store.folders) { folder in
                        NavigationLink(value: LibrarySelection.folder(folder.id)) {
                            Label(folder.title, systemImage: "folder")
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                store.deleteFolder(id: folder.id)
                            } label: {
                                Label("Видалити папку", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("DocumentsPainter")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newFolderName = ""
                        showCreateFolderAlert = true
                    } label: {
                        Label("Нова папка", systemImage: "folder.badge.plus")
                    }
                }
            }
            .alert("Нова папка", isPresented: $showCreateFolderAlert) {
                TextField("Назва папки", text: $newFolderName)
                Button("Скасувати", role: .cancel) {}
                Button("Створити") {
                    let id = store.createFolder(title: newFolderName)
                    newFolderName = ""
                    if let id {
                        selection = .folder(id)
                    }
                }
            }
        } detail: {
            NavigationStack(path: $navigationPath) {
                ProjectGridView(
                    selectedFolderID: selectedFolderID,
                    title: selectedTitle,
                    navigationPath: $navigationPath
                )
            }
            .onChange(of: navigationPath.count) { _, count in
                columnVisibility = count > 0 ? .detailOnly : .all
            }
        }
        .onChange(of: store.folders) { _, folders in
            guard case let .folder(id) = selection, !folders.contains(where: { $0.id == id }) else { return }
            selection = .all
        }
    }

    private var selectedFolderID: UUID? {
        guard case let .folder(id) = selection else { return nil }
        return id
    }

    private var selectedTitle: String {
        guard case let .folder(id) = selection else { return "Мої малюнки" }
        return store.folders.first(where: { $0.id == id })?.title ?? "Папка"
    }
}

private struct ProjectGridView: View {
    @ObservedObject private var store = CanvasProjectStore.shared
    let selectedFolderID: UUID?
    let title: String
    @Binding var navigationPath: NavigationPath

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 280), spacing: 16)
    ]

    var body: some View {
        Group {
            if filteredProjects.isEmpty {
                ContentUnavailableView(
                    "Немає малюнків",
                    systemImage: "square.dashed",
                    description: Text(selectedFolderID == nil
                                      ? "Натисни «Новий малюнок», щоб створити перший проєкт."
                                      : "Ця папка порожня. Створи новий малюнок або перемісти існуючий.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(filteredProjects) { project in
                            NavigationLink(value: project.id) {
                                ProjectCardView(project: project)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Menu("Перемістити в папку") {
                                    Button {
                                        store.moveProject(id: project.id, to: nil)
                                    } label: {
                                        Label("Без папки", systemImage: "tray")
                                    }

                                    if !store.folders.isEmpty {
                                        Divider()
                                        ForEach(store.folders) { folder in
                                            Button {
                                                store.moveProject(id: project.id, to: folder.id)
                                            } label: {
                                                Label(folder.title, systemImage: "folder")
                                            }
                                            .disabled(project.folderID == folder.id)
                                        }
                                    }
                                }

                                Menu("Копіювати в папку") {
                                    Button {
                                        _ = store.copyProject(id: project.id, to: nil)
                                    } label: {
                                        Label("Без папки", systemImage: "tray")
                                    }

                                    if !store.folders.isEmpty {
                                        Divider()
                                        ForEach(store.folders) { folder in
                                            Button {
                                                _ = store.copyProject(id: project.id, to: folder.id)
                                            } label: {
                                                Label(folder.title, systemImage: "folder")
                                            }
                                        }
                                    }
                                }

                                Button(role: .destructive) {
                                    store.deleteProject(id: project.id)
                                } label: {
                                    Label("Видалити", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: UUID.self) { id in
            ContentView(projectId: id)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let n = store.projects.count + 1
                    let id = store.createProject(title: "Малюнок \(n)", folderID: selectedFolderID)
                    navigationPath.append(id)
                } label: {
                    Label("Новий малюнок", systemImage: "plus")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                let n = store.projects.count + 1
                let id = store.createProject(title: "Малюнок \(n)", folderID: selectedFolderID)
                navigationPath.append(id)
            } label: {
                Label("Новий малюнок", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .background(.bar)
        }
    }

    private var filteredProjects: [CanvasProjectMetadata] {
        store.projects(in: selectedFolderID)
    }
}

private struct ProjectCardView: View {
    let project: CanvasProjectMetadata
    @ObservedObject private var store = CanvasProjectStore.shared

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemBackground))
                previewContent
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(UIColor.separator).opacity(0.35), lineWidth: 1)
            )

            Text(project.title)
                .font(.headline)
                .lineLimit(2)
                .foregroundStyle(.primary)

            Text(Self.dateFormatter.string(from: project.modifiedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var previewContent: some View {
        let path = store.previewFileURL(for: project.id).path
        if let ui = UIImage(contentsOfFile: path) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            Image(systemName: "scribble.variable")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    ProjectLibraryView()
}
