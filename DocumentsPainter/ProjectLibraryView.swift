import SwiftUI

struct ProjectLibraryView: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                Section("На цьому iPad") {
                    Label("Мої малюнки", systemImage: "folder.fill")
                }
            }
            .navigationTitle("DocumentsPainter")
        } detail: {
            NavigationStack(path: $navigationPath) {
                ProjectGridView(navigationPath: $navigationPath)
            }
            .onChange(of: navigationPath.count) { _, count in
                columnVisibility = count > 0 ? .detailOnly : .all
            }
        }
    }
}

private struct ProjectGridView: View {
    @ObservedObject private var store = CanvasProjectStore.shared
    @Binding var navigationPath: NavigationPath

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 280), spacing: 16)
    ]

    var body: some View {
        Group {
            if store.projects.isEmpty {
                ContentUnavailableView(
                    "Немає малюнків",
                    systemImage: "square.dashed",
                    description: Text("Натисни «Новий малюнок», щоб створити перший проєкт.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(store.projects) { project in
                            NavigationLink(value: project.id) {
                                ProjectCardView(project: project)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
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
        .navigationTitle("Мої малюнки")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: UUID.self) { id in
            ContentView(projectId: id)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let n = store.projects.count + 1
                    let id = store.createProject(title: "Малюнок \(n)")
                    navigationPath.append(id)
                } label: {
                    Label("Новий малюнок", systemImage: "plus")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                let n = store.projects.count + 1
                let id = store.createProject(title: "Малюнок \(n)")
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
