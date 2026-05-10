import SwiftUI
import UniformTypeIdentifiers

struct ProjectLibraryView: View {
    private enum LibrarySelection: Hashable {
        case all
        case folder(UUID)
        case bibleBook(translationId: String, bookIndex: Int, bookTitle: String)
        case importedDocument(UUID)
    }

    @ObservedObject private var store = CanvasProjectStore.shared
    @AppStorage("settings.nativeLanguage") private var nativeLanguage = "en"
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var navigationPath = NavigationPath()
    @State private var selection: LibrarySelection? = .all
    @State private var showCreateFolderAlert = false
    @State private var newFolderName = ""
    @State private var showAddTranslationSheet = false
    @State private var selectedTranslationLanguage = "uk"
    @State private var importingTranslationId: String?
    @State private var processingTranslationRemovalId: String?
    @State private var addTranslationError: String?
    @State private var discoverableReloadToken = UUID()
    @State private var isLanguageDropdownExpanded = false
    @State private var expandedTranslationIds: Set<String> = []
    @State private var booksByTranslationId: [String: [BibleBookOption]] = [:]
    @State private var loadingBooksTranslationIds: Set<String> = []
    @State private var showDocxImporter = false
    @State private var documentImportError: String?
    @State private var importingDocument = false

    private static var importedDocumentsFolderTitle: String {
        AppLocalization.t("Імпортовані документи", "Imported documents")
    }
    private static let docxUTType: UTType = UTType("org.openxmlformats.wordprocessingml.document")
        ?? UTType(filenameExtension: "docx")
        ?? .data

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section(AppLocalization.t("На цьому iPad", "On this iPad")) {
                    NavigationLink(value: LibrarySelection.all) {
                        Label(AppLocalization.t("Мої дослідження", "My researches"), systemImage: "folder.fill")
                    }
                }
                Section(AppLocalization.t("Переклади Біблії", "Bible translations")) {
                    if addedTranslations.isEmpty {
                        Text(AppLocalization.t("Немає доданих перекладів", "No translations added"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(addedTranslations) { translation in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedTranslationIds.contains(translation.id) },
                                    set: { newValue in
                                        if newValue {
                                            expandedTranslationIds.insert(translation.id)
                                            loadBooksIfNeeded(for: translation)
                                        } else {
                                            expandedTranslationIds.remove(translation.id)
                                        }
                                    }
                                )
                            ) {
                                let books = booksByTranslationId[translation.id] ?? []
                                if loadingBooksTranslationIds.contains(translation.id) && books.isEmpty {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text(AppLocalization.t("Завантаження книг...", "Loading books..."))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else if books.isEmpty {
                                    Text(AppLocalization.t("Книги не знайдено", "Books not found"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                                        NavigationLink(
                                            value: LibrarySelection.bibleBook(
                                                translationId: translation.id,
                                                bookIndex: index,
                                                bookTitle: book.title
                                            )
                                        ) {
                                            Label(book.title, systemImage: "doc.text")
                                        }
                                    }
                                }
                            } label: {
                                Label("Біблія • \(translation.abbreviation)", systemImage: "books.vertical")
                            }
                        }
                    }
                }
                Section(AppLocalization.t("Імпортовані документи", "Imported documents")) {
                    if importedDocumentProjects.isEmpty {
                        Text(AppLocalization.t("Ще немає імпортованих документів", "No imported documents yet"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(importedDocumentProjects) { project in
                            NavigationLink(value: LibrarySelection.importedDocument(project.id)) {
                                Label(project.title, systemImage: "doc.text")
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.deleteProject(id: project.id)
                                } label: {
                                    Label(AppLocalization.t("Видалити документ", "Delete document"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("DocumentsPainter")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            newFolderName = ""
                            showCreateFolderAlert = true
                        } label: {
                            Label(AppLocalization.t("Нова папка", "New folder"), systemImage: "folder.badge.plus")
                        }
                        Button {
                            let allLanguageIds = BibleLibraryCatalog.translationLanguageIds
                            if allLanguageIds.contains(nativeLanguage) {
                                selectedTranslationLanguage = nativeLanguage
                            } else {
                                selectedTranslationLanguage = allLanguageIds.first ?? "en"
                            }
                            isLanguageDropdownExpanded = false
                            addTranslationError = nil
                            importingTranslationId = nil
                            processingTranslationRemovalId = nil
                            showAddTranslationSheet = true
                        } label: {
                            Label(AppLocalization.t("Додати переклад Біблії", "Add Bible translation"), systemImage: "books.vertical")
                        }
                        Button {
                            showDocxImporter = true
                        } label: {
                            Label(AppLocalization.t("Імпортувати документ DOCX", "Import DOCX document"), systemImage: "doc.badge.plus")
                        }
                    } label: {
                        Label(AppLocalization.t("Дії", "Actions"), systemImage: "plus")
                    }
                }
            }
            .alert(AppLocalization.t("Нова папка", "New folder"), isPresented: $showCreateFolderAlert) {
                TextField(AppLocalization.t("Назва папки", "Folder name"), text: $newFolderName)
                Button(AppLocalization.t("Скасувати", "Cancel"), role: .cancel) {}
                Button(AppLocalization.t("Створити", "Create")) {
                    let id = store.createFolder(title: newFolderName)
                    newFolderName = ""
                    if let id {
                        selection = .folder(id)
                    }
                }
            }
            .fileImporter(
                isPresented: $showDocxImporter,
                allowedContentTypes: [Self.docxUTType],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                importDocumentCanvas(from: url)
            }
            .alert(AppLocalization.t("Імпорт документа не вдався", "Document import failed"), isPresented: Binding(
                get: { documentImportError != nil },
                set: { if !$0 { documentImportError = nil } }
            )) {
                Button("OK", role: .cancel) { documentImportError = nil }
            } message: {
                Text(documentImportError ?? AppLocalization.t("Спробуй ще раз.", "Try again."))
            }
            .sheet(isPresented: $showAddTranslationSheet) {
                NavigationStack {
                    ZStack {
                        Color(UIColor.systemGroupedBackground)
                            .ignoresSafeArea()

                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(AppLocalization.t("Оберіть мову", "Choose language"))
                                        .font(.headline)

                                    TranslationLanguageDropdown(
                                        languageIds: translationLanguageIds,
                                        selectedLanguageId: $selectedTranslationLanguage,
                                        isExpanded: $isLanguageDropdownExpanded
                                    )
                                }
                                .padding(16)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14))

                                VStack(alignment: .leading, spacing: 12) {
                                    Text(AppLocalization.t("Доступні переклади", "Available translations"))
                                        .font(.headline)

                                    let options = availableTranslationsForSelectedLanguage
                                    if options.isEmpty {
                                        ContentUnavailableView(
                                            AppLocalization.t("Немає перекладів", "No translations"),
                                            systemImage: "books.vertical",
                                            description: Text(AppLocalization.t("Для цієї мови ще немає доступних перекладів.", "No translations are available for this language yet."))
                                        )
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 20)
                                    } else {
                                        ForEach(options) { translation in
                                            BibleTranslationCard(
                                                translation: translation,
                                                isAddedToCanvases: BibleLibrarySeeder.isAddedToCanvases(translation: translation, store: store),
                                                isLoading: importingTranslationId == translation.id,
                                                isRemoving: processingTranslationRemovalId == translation.id
                                            ) {
                                                toggleTranslationPresence(translation)
                                            }
                                        }
                                    }
                                }
                                .padding(16)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14))

                                if let importingTranslationId,
                                   let active = availableTranslationsForSelectedLanguage.first(where: { $0.id == importingTranslationId }) {
                                    HStack(spacing: 10) {
                                        ProgressView()
                                        Text(
                                            AppLocalization.isUkrainian
                                            ? "Імпортую \(active.abbreviation)..."
                                            : "Importing \(active.abbreviation)..."
                                        )
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(Color(UIColor.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                if let processingTranslationRemovalId,
                                   let active = availableTranslationsForSelectedLanguage.first(where: { $0.id == processingTranslationRemovalId }) {
                                    HStack(spacing: 10) {
                                        ProgressView()
                                        Text(
                                            AppLocalization.isUkrainian
                                            ? "Прибираю \(active.abbreviation) з канв..."
                                            : "Removing \(active.abbreviation) from canvases..."
                                        )
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(Color(UIColor.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }

                                if let addTranslationError, !addTranslationError.isEmpty {
                                    Text(addTranslationError)
                                        .foregroundStyle(.red)
                                        .font(.footnote)
                                        .padding(14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.red.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }

                                Text(AppLocalization.t("Джерело: bible.helloao.org", "Source: bible.helloao.org"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .padding(16)
                        }
                    }
                    .navigationTitle(AppLocalization.t("Новий переклад", "New translation"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(AppLocalization.t("Скасувати", "Cancel")) { showAddTranslationSheet = false }
                        }
                    }
                }
                .presentationDetents([.large])
                .task {
                    await BibleLibraryCatalog.refreshDiscoverableTranslations()
                    await MainActor.run {
                        discoverableReloadToken = UUID()
                    }
                }
            }
        } detail: {
            Group {
                if case let .bibleBook(translationId, bookIndex, bookTitle) = selection,
                   let translation = addedTranslations.first(where: { $0.id == translationId }) {
                    NavigationStack {
                        BibleBookCanvasLoaderView(
                            translation: translation,
                            bookIndex: bookIndex,
                            bookTitle: bookTitle
                        )
                        .navigationTitle(bookTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    selection = .all
                                    columnVisibility = .all
                                } label: {
                                    Label(AppLocalization.t("Назад", "Back"), systemImage: "chevron.backward")
                                }
                            }
                        }
                    }
                    .onAppear {
                        columnVisibility = .detailOnly
                    }
                } else if case let .importedDocument(projectId) = selection {
                    NavigationStack {
                        ContentView(projectId: projectId)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button {
                                        selection = .all
                                        columnVisibility = .all
                                    } label: {
                                        Label(AppLocalization.t("Назад", "Back"), systemImage: "chevron.backward")
                                    }
                                }
                            }
                    }
                    .onAppear {
                        columnVisibility = .detailOnly
                    }
                } else {
                    NavigationStack(path: $navigationPath) {
                        ProjectGridView(
                            selectedFolderID: selectedFolderID,
                            title: selectedTitle,
                            excludedFolderIDs: selectedFolderID == nil ? excludedFolderIDsForMainLibrary : [],
                            navigationPath: $navigationPath
                        )
                    }
                    .onChange(of: navigationPath.count) { _, count in
                        columnVisibility = count > 0 ? .detailOnly : .all
                    }
                }
            }
        }
        .onChange(of: store.folders) { _, folders in
            guard case let .folder(id) = selection, !folders.contains(where: { $0.id == id }) else { return }
            selection = .all
        }
        .onChange(of: store.projects) { _, projects in
            guard case let .importedDocument(id) = selection else { return }
            if !projects.contains(where: { $0.id == id }) {
                selection = .all
            }
        }
    }

    private var selectedFolderID: UUID? {
        guard case let .folder(id) = selection else { return nil }
        return id
    }

    private var selectedTitle: String {
        guard case let .folder(id) = selection else { return AppLocalization.t("Мої дослідження", "My researches") }
        return store.folders.first(where: { $0.id == id })?.title ?? AppLocalization.t("Папка", "Folder")
    }

    private var otherFolders: [CanvasFolderMetadata] {
        store.folders.filter {
            !$0.title.hasPrefix("Біблія • ")
            && $0.title != Self.importedDocumentsFolderTitle
        }
    }

    private var importedDocumentsFolderId: UUID? {
        store.folders.first(where: { $0.title == Self.importedDocumentsFolderTitle })?.id
    }

    private var importedDocumentProjects: [CanvasProjectMetadata] {
        guard let folderId = importedDocumentsFolderId else { return [] }
        return store.projects(in: folderId).sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private var excludedFolderIDsForMainLibrary: [UUID] {
        let bibleFolderIds = store.folders
            .filter { $0.title.hasPrefix("Біблія • ") }
            .map(\.id)
        var ids = bibleFolderIds
        if let importedDocumentsFolderId {
            ids.append(importedDocumentsFolderId)
        }
        return ids
    }

    private var addedTranslations: [BibleTranslationSeed] {
        _ = discoverableReloadToken
        return BibleLibraryCatalog.availableTranslations
            .filter { BibleLibrarySeeder.isAddedToCanvases(translation: $0, store: store) }
            .sorted { $0.title < $1.title }
    }

    private var availableTranslationsForSelectedLanguage: [BibleTranslationSeed] {
        _ = discoverableReloadToken
        return BibleLibraryCatalog.availableTranslations
            .filter { $0.languageId == selectedTranslationLanguage }
            .sorted { $0.title < $1.title }
    }

    private var translationLanguageIds: [String] {
        _ = discoverableReloadToken
        return BibleLibraryCatalog.translationLanguageIds
    }

    private func addPredefinedTranslationAndSeed(_ seed: BibleTranslationSeed) {
        guard importingTranslationId == nil, processingTranslationRemovalId == nil else { return }
        addTranslationError = nil
        importingTranslationId = seed.id
        Task {
            await MainActor.run {
                addTranslationError = nil
            }

            do {
                _ = try await BibleLibrarySeeder.ensureSeeded(translation: seed, store: store)
                await MainActor.run {
                    importingTranslationId = nil
                    expandedTranslationIds.insert(seed.id)
                    loadBooksIfNeeded(for: seed)
                    showAddTranslationSheet = false
                }
            } catch {
                await MainActor.run {
                    importingTranslationId = nil
                    if let detailed = (error as? BibleSeedImportError)?.errorDescription {
                        addTranslationError = detailed
                    } else {
                        addTranslationError = "Неможливо завантажити переклад: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func removeTranslationFromCanvases(_ seed: BibleTranslationSeed) {
        guard importingTranslationId == nil, processingTranslationRemovalId == nil else { return }
        addTranslationError = nil
        processingTranslationRemovalId = seed.id
        Task {
            let removed = await MainActor.run {
                BibleLibrarySeeder.removeFromCanvases(translation: seed, store: store)
            }
            await MainActor.run {
                processingTranslationRemovalId = nil
                if removed {
                    if case let .bibleBook(translationId, _, _) = selection, translationId == seed.id {
                        selection = .all
                    } else if case .folder = selection {
                        selection = .all
                    }
                    expandedTranslationIds.remove(seed.id)
                    booksByTranslationId.removeValue(forKey: seed.id)
                } else {
                    addTranslationError = "Не вдалося прибрати переклад з канв."
                }
            }
        }
    }

    private func toggleTranslationPresence(_ seed: BibleTranslationSeed) {
        let added = BibleLibrarySeeder.isAddedToCanvases(translation: seed, store: store)
        if added {
            removeTranslationFromCanvases(seed)
        } else {
            addPredefinedTranslationAndSeed(seed)
        }
    }

    private func loadBooksIfNeeded(for translation: BibleTranslationSeed) {
        if booksByTranslationId[translation.id] != nil || loadingBooksTranslationIds.contains(translation.id) {
            return
        }
        loadingBooksTranslationIds.insert(translation.id)
        Task {
            do {
                let books = try await BiblePassageService.books(for: translation)
                await MainActor.run {
                    booksByTranslationId[translation.id] = books
                    loadingBooksTranslationIds.remove(translation.id)
                }
            } catch {
                await MainActor.run {
                    booksByTranslationId[translation.id] = []
                    loadingBooksTranslationIds.remove(translation.id)
                    addTranslationError = "Не вдалося завантажити список книг: \(error.localizedDescription)"
                }
            }
        }
    }

    private func importDocumentCanvas(from url: URL) {
        guard !importingDocument else { return }
        importingDocument = true
        defer { importingDocument = false }

        guard url.startAccessingSecurityScopedResource() else {
            documentImportError = "Немає доступу до файлу."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let paragraphs = try? DocxPlainTextParser.parseParagraphs(from: url), !paragraphs.isEmpty else {
            documentImportError = "Не вдалося прочитати текст DOCX або документ порожній."
            return
        }

        guard let data = makeCanvasData(fromParagraphs: paragraphs) else {
            documentImportError = "Не вдалося згенерувати канву з документа."
            return
        }

        let folderId = importedDocumentsFolderId ?? store.createFolder(title: Self.importedDocumentsFolderTitle)
        guard let folderId else {
            documentImportError = "Не вдалося створити папку для імпортованих документів."
            return
        }

        let titleBase = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = titleBase.isEmpty ? AppLocalization.t("Імпортований документ", "Imported document") : titleBase
        let projectId = store.createProject(title: title, folderID: folderId)
        store.writeCanvasData(id: projectId, data: data)
        store.touchModified(id: projectId)
        selection = .importedDocument(projectId)
    }

    private func makeCanvasData(fromParagraphs paragraphs: [String]) -> Data? {
        let layerId = UUID()
        let lines: [ImportedTextLine] = paragraphs
            .flatMap { wrapText($0, maxChars: 64) + [""] }
            .enumerated()
            .map { index, text in
                ImportedTextLine(
                    documentId: UUID(),
                    groupId: UUID(),
                    order: index,
                    layerId: layerId,
                    text: text,
                    position: CGPoint(x: 24, y: 120 + CGFloat(index) * 24),
                    fontSize: 18,
                    color: .black
                )
            }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !lines.isEmpty else { return nil }
        let state = CanvasStateDTO(
            scale: 1,
            offsetX: 0,
            offsetY: 0,
            strokes: [],
            hiddenStrokeIds: [],
            importedTextLines: lines.map(ImportedTextLineDTO.init),
            hiddenTextLineIds: [],
            importedImageItems: [],
            hiddenImageItemIds: [],
            layerGroups: [],
            customLayerNames: [:],
            toolDockPlacement: nil,
            canvasBackground: CanvasBackgroundKind.dots.rawValue,
            artLayers: [CanvasArtLayerDTO(CanvasArtLayer(id: layerId, name: "Шар 1"))],
            activeLayerId: layerId,
            hiddenArtLayerIds: []
        )
        return try? JSONEncoder().encode(state)
    }

    private func wrapText(_ text: String, maxChars: Int) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var lines: [String] = []
        var current = ""
        for word in words {
            if current.isEmpty {
                current = word
                continue
            }
            if current.count + 1 + word.count <= maxChars {
                current += " " + word
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }
}

private struct BibleBookCanvasLoaderView: View {
    let translation: BibleTranslationSeed
    let bookIndex: Int
    let bookTitle: String

    @ObservedObject private var store = CanvasProjectStore.shared
    @State private var projectId: UUID?
    @State private var loadingError: String?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let projectId {
                ContentView(projectId: projectId)
            } else if isLoading {
                ProgressView("Відкриваю \(bookTitle)...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadingError {
                ContentUnavailableView(
                    "Не вдалося відкрити книгу",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadingError)
                )
            } else {
                ProgressView("Підготовка...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .task(id: "\(translation.id)-\(bookIndex)") {
            isLoading = true
            loadingError = nil
            do {
                let id = try await BibleLibrarySeeder.ensureBookCanvas(
                    translation: translation,
                    bookIndex: bookIndex,
                    store: store
                )
                await MainActor.run {
                    projectId = id
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    loadingError = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

private struct TranslationLanguageDropdown: View {
    let languageIds: [String]
    @Binding var selectedLanguageId: String
    @Binding var isExpanded: Bool
    @State private var searchQuery = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BibleLibraryCatalog.languageTitle(for: selectedLanguageId))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(selectedLanguageId.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(AppLocalization.t("Пошук мови", "Search language"), text: $searchQuery)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(filteredLanguageIds, id: \.self) { languageId in
                                let isSelected = languageId == selectedLanguageId
                                Button {
                                    selectedLanguageId = languageId
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        isExpanded = false
                                    }
                                } label: {
                                    HStack {
                                        Text(BibleLibraryCatalog.languageTitle(for: languageId))
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 9)
                                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 190)
                }
                .padding(10)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .onChange(of: languageIds) { _, ids in
            guard !ids.isEmpty else { return }
            if !ids.contains(selectedLanguageId) {
                selectedLanguageId = ids[0]
            }
        }
    }

    private var filteredLanguageIds: [String] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return languageIds
        }
        return languageIds.filter { languageId in
            let title = BibleLibraryCatalog.languageTitle(for: languageId).lowercased()
            return title.contains(query) || languageId.lowercased().contains(query)
        }
    }
}

private struct BibleTranslationCard: View {
    let translation: BibleTranslationSeed
    let isAddedToCanvases: Bool
    let isLoading: Bool
    let isRemoving: Bool
    let onImport: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "book.closed")
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(translation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(translation.abbreviation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isLoading || isRemoving {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(
                        isRemoving
                        ? AppLocalization.t("Видалення...", "Removing...")
                        : AppLocalization.t("Імпорт...", "Importing...")
                    )
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(UIColor.systemGray5))
                .clipShape(Capsule())
                .foregroundStyle(.secondary)
            } else {
                if isAddedToCanvases {
                    Button(AppLocalization.t("Видалити", "Delete"), action: onImport)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Button(AppLocalization.t("Додати", "Add"), action: onImport)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .saturation((isLoading || isRemoving) ? 0 : 1)
        .opacity((isLoading || isRemoving) ? 0.72 : 1)
    }
}

private struct ProjectGridView: View {
    @ObservedObject private var store = CanvasProjectStore.shared
    @AppStorage("settings.appLanguage") private var appLanguage = "en"
    let selectedFolderID: UUID?
    let title: String
    let excludedFolderIDs: [UUID]
    @Binding var navigationPath: NavigationPath
    @State private var bookSearchQuery = ""
    @State private var showLibrarySettings = false

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 280), spacing: 16)
    ]

    var body: some View {
        Group {
            if filteredProjects.isEmpty {
                ContentUnavailableView(
                    isBibleTranslationFolder && !bookSearchQueryTrimmed.isEmpty
                        ? AppLocalization.t("Книгу не знайдено", "Book not found")
                        : AppLocalization.t("Немає малюнків", "No drawings"),
                    systemImage: "square.dashed",
                    description: Text(emptyStateDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        if isBibleTranslationFolder {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField(AppLocalization.t("Пошук книги", "Search books"), text: $bookSearchQuery)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                if !bookSearchQuery.isEmpty {
                                    Button {
                                        bookSearchQuery = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        }

                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(filteredProjects) { project in
                                NavigationLink(value: project.id) {
                                    ProjectCardView(project: project)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Menu(AppLocalization.t("Перемістити в папку", "Move to folder")) {
                                        Button {
                                            store.moveProject(id: project.id, to: nil)
                                        } label: {
                                            Label(AppLocalization.t("Без папки", "No folder"), systemImage: "tray")
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

                                    Menu(AppLocalization.t("Копіювати в папку", "Copy to folder")) {
                                        Button {
                                            _ = store.copyProject(id: project.id, to: nil)
                                        } label: {
                                            Label(AppLocalization.t("Без папки", "No folder"), systemImage: "tray")
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
                                        Label(AppLocalization.t("Видалити", "Delete"), systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: UUID.self) { id in
            ContentView(projectId: id)
        }
        .onChange(of: selectedFolderID) { _, _ in
            bookSearchQuery = ""
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showLibrarySettings = true
                } label: {
                    Label(AppLocalization.t("Налаштування", "Settings"), systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showLibrarySettings) {
            NavigationStack {
                Form {
                    Section(AppLocalization.t("Мова інтерфейсу", "Interface language")) {
                        HStack(spacing: 12) {
                            languageOptionButton(id: "en", shortTitle: "ENG", subtitle: "English")
                            languageOptionButton(id: "uk", shortTitle: "UA", subtitle: "Українська")
                        }
                        .padding(.vertical, 4)
                    }
                }
                .navigationTitle(AppLocalization.t("Налаштування", "Settings"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(AppLocalization.t("Готово", "Done")) { showLibrarySettings = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                let n = store.projects.count + 1
                let id = store.createProject(
                    title: AppLocalization.isUkrainian ? "Дослідження \(n)" : "Research \(n)",
                    folderID: selectedFolderID
                )
                navigationPath.append(id)
            } label: {
                Label(AppLocalization.t("Нове дослідження", "New research"), systemImage: "plus.circle.fill")
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
        let source = store.projects(in: selectedFolderID).filter { project in
            guard selectedFolderID == nil else { return true }
            guard let folderID = project.folderID else { return true }
            return !excludedFolderIDs.contains(folderID)
        }
        let searched: [CanvasProjectMetadata]
        if isBibleTranslationFolder, !bookSearchQueryTrimmed.isEmpty {
            searched = source.filter { $0.title.localizedCaseInsensitiveContains(bookSearchQueryTrimmed) }
        } else {
            searched = source
        }
        guard isBibleTranslationFolder else { return searched }
        return searched.sorted(by: canonicalBibleOrderSort)
    }

    private var isBibleTranslationFolder: Bool {
        title.hasPrefix(AppLocalization.t("Біблія • ", "Bible • "))
    }

    private var bookSearchQueryTrimmed: String {
        bookSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emptyStateDescription: String {
        if isBibleTranslationFolder && !bookSearchQueryTrimmed.isEmpty {
            return AppLocalization.t("Спробуй іншу назву книги або очисть пошук.", "Try another book name or clear the search.")
        }
        if selectedFolderID == nil {
            return AppLocalization.t("Натисни «Нове дослідження, щоб створити перший проєкт.", "Tap \"New drawing\" to create your first project.")
        }
        return AppLocalization.t("Ця папка порожня. Створи нове дослідження або перемісти існуюче.", "This folder is empty. Create a new research or move an existing one.")
    }

    private func languageOptionButton(id: String, shortTitle: String, subtitle: String) -> some View {
        let isSelected = appLanguage == id
        return Button {
            appLanguage = id
        } label: {
            VStack(spacing: 7) {
                Text(shortTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .frame(width: 62, height: 62)
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.82))
                    .background(
                        Circle()
                            .fill(isSelected ? Color(UIColor.systemBackground) : Color(UIColor.tertiarySystemBackground))
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                isSelected ? Color.primary : Color(UIColor.separator).opacity(0.5),
                                lineWidth: isSelected ? 2.2 : 1
                            )
                    )

                Text(subtitle)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 92)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subtitle)
    }

    private func canonicalBibleOrderSort(_ lhs: CanvasProjectMetadata, _ rhs: CanvasProjectMetadata) -> Bool {
        let leftIndex = canonicalBookIndex(for: lhs.title) ?? Int.max
        let rightIndex = canonicalBookIndex(for: rhs.title) ?? Int.max
        if leftIndex != rightIndex {
            return leftIndex < rightIndex
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func canonicalBookIndex(for title: String) -> Int? {
        let normalized = normalizeBookTitle(title)
        return Self.canonicalBookAliases.firstIndex { aliases in
            aliases.contains(normalized)
        }
    }

    private func normalizeBookTitle(_ title: String) -> String {
        let lowered = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scalarFiltered = lowered.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        return String(String.UnicodeScalarView(scalarFiltered))
    }

    private static let canonicalBookAliases: [[String]] = [
        ["буття", "genesis"],
        ["вихід", "exodus"],
        ["левит", "leviticus"],
        ["числа", "numbers"],
        ["повтореннязакону", "deuteronomy"],
        ["ісуснавин", "joshua"],
        ["судді", "judges"],
        ["рут", "ruth"],
        ["1самуїлова", "1samuel"],
        ["2самуїлова", "2samuel"],
        ["1царів", "1kings"],
        ["2царів", "2kings"],
        ["1хронік", "1chronicles"],
        ["2хронік", "2chronicles"],
        ["ездри", "ezra"],
        ["неемії", "nehemiah"],
        ["естери", "esther"],
        ["йова", "job"],
        ["псалми", "псалом", "psalms", "psalm"],
        ["приповісті", "proverbs"],
        ["екклезіяст", "ecclesiastes"],
        ["піснянадпіснями", "songofsongs", "songofsolomon"],
        ["ісая", "isaiah"],
        ["єремії", "jeremiah"],
        ["плачєремії", "lamentations"],
        ["єзекіїля", "ezekiel"],
        ["даниїла", "daniel"],
        ["осії", "hosea"],
        ["йоіла", "joel"],
        ["амоса", "amos"],
        ["овдія", "obadiah"],
        ["йони", "jonah"],
        ["михея", "micah"],
        ["наума", "nahum"],
        ["авакума", "habakkuk"],
        ["софонії", "zephaniah"],
        ["аггея", "haggai"],
        ["захарії", "zechariah"],
        ["малахії", "malachi"],
        ["відматвія", "матвія", "matthew"],
        ["відмарка", "марка", "mark"],
        ["відлуки", "луки", "luke"],
        ["відівана", "івана", "john"],
        ["діїсвятихапостолів", "діїапостолів", "acts"],
        ["до римлян", "римлян", "romans", "rom"], 
        ["1коринтян", "1corinthians"],
        ["2коринтян", "2corinthians"],
        ["галатів", "galatians"],
        ["ефесян", "ephesians"],
        ["филипян", "philippians"],
        ["колосян", "colossians"],
        ["1солунян", "1thessalonians"],
        ["2солунян", "2thessalonians"],
        ["1тимофія", "1timothy"],
        ["2тимофія", "2timothy"],
        ["тита", "titus"],
        ["филимона", "philemon"],
        ["євреїв", "hebrews"],
        ["якова", "james"],
        ["1петра", "1peter"],
        ["2петра", "2peter"],
        ["1івана", "1john"],
        ["2івана", "2john"],
        ["3івана", "3john"],
        ["юди", "jude"],
        ["обявлення", "обʼявлення", "одкровення", "revelation"]
    ].map { $0.map { alias in
        let scalarFiltered = alias.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        return String(String.UnicodeScalarView(scalarFiltered))
    }}
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
