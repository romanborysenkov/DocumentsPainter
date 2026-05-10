import SwiftUI
import Foundation

struct AppLanguage: Identifiable, Hashable {
    let id: String
    let title: String
}

struct BibleTranslationSeed: Identifiable, Hashable, Codable {
    let id: String
    let languageId: String
    let title: String
    let abbreviation: String
    let sourceURL: String
}

enum BibleLibraryCatalog {
    private static let customTranslationsKey = "settings.customBibleTranslations"
    private static let discoveredTranslationsKey = "settings.discoveredBibleTranslations"
    private static let discoveredLanguageTitlesKey = "settings.discoveredBibleLanguageTitles"
    private static let allowedLanguageIds: Set<String> = ["uk", "en"]

    static let supportedLanguages: [AppLanguage] = [
        AppLanguage(id: "uk", title: "Українська"),
        AppLanguage(id: "en", title: "English")
    ]

    static var availableTranslations: [BibleTranslationSeed] {
        deduplicatedTranslations(
            (supportedLanguages.flatMap { defaultTranslations(for: $0.id) }
            + discoveredTranslations()
            + customTranslations())
            .filter { allowedLanguageIds.contains($0.languageId) }
        )
    }

    static func languageTitle(for id: String) -> String {
        if let native = supportedLanguages.first(where: { $0.id == id })?.title {
            return native
        }
        if let discovered = discoveredLanguageTitles()[id], !discovered.isEmpty {
            return discovered
        }
        return id.uppercased()
    }

    static var translationLanguageIds: [String] {
        let ids = Set(availableTranslations.map(\.languageId))
        return ids.sorted()
    }

    static func translations(for languageId: String) -> [BibleTranslationSeed] {
        guard allowedLanguageIds.contains(languageId) else { return [] }
        return deduplicatedTranslations(
            defaultTranslations(for: languageId)
            + discoveredTranslations().filter { $0.languageId == languageId }
            + customTranslations().filter { $0.languageId == languageId }
        )
    }

    static func customTranslations() -> [BibleTranslationSeed] {
        guard let data = UserDefaults.standard.data(forKey: customTranslationsKey),
              let decoded = try? JSONDecoder().decode([BibleTranslationSeed].self, from: data) else {
            return []
        }
        return decoded.filter { allowedLanguageIds.contains($0.languageId) }
    }

    static func discoveredTranslations() -> [BibleTranslationSeed] {
        guard let data = UserDefaults.standard.data(forKey: discoveredTranslationsKey),
              let decoded = try? JSONDecoder().decode([BibleTranslationSeed].self, from: data) else {
            return []
        }
        return decoded.filter { allowedLanguageIds.contains($0.languageId) }
    }

    static func discoveredLanguageTitles() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: discoveredLanguageTitlesKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded.filter { allowedLanguageIds.contains($0.key) }
    }

    static func refreshDiscoverableTranslations() async {
        guard let url = URL(string: "https://bible.helloao.org/api/available_translations.json") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            guard let decoded = try? JSONDecoder().decode(HelloAOAvailableTranslationsResponse.self, from: data) else { return }

            var languageTitles: [String: String] = discoveredLanguageTitles()
            var discovered: [BibleTranslationSeed] = []
            for item in decoded.translations {
                guard let link = item.completeTranslationApiLink else { continue }
                let normalizedLanguage = normalizedLanguageId(item.language)
                guard allowedLanguageIds.contains(normalizedLanguage) else { continue }
                let languageTitle = (item.languageName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                     ? item.languageName!
                                     : (item.languageEnglishName ?? normalizedLanguage))
                languageTitles[normalizedLanguage] = languageTitle

                discovered.append(
                    BibleTranslationSeed(
                        id: "helloao_\(item.id)",
                        languageId: normalizedLanguage,
                        title: item.englishName.isEmpty ? item.name : item.englishName,
                        abbreviation: item.shortName.isEmpty ? item.id.uppercased() : item.shortName.uppercased(),
                        sourceURL: absoluteHelloAOURL(link)
                    )
                )
            }

            let deduped = deduplicatedTranslations(discovered)
            if let translationsData = try? JSONEncoder().encode(deduped) {
                UserDefaults.standard.set(translationsData, forKey: discoveredTranslationsKey)
            }
            if let languagesData = try? JSONEncoder().encode(languageTitles) {
                UserDefaults.standard.set(languagesData, forKey: discoveredLanguageTitlesKey)
            }
        } catch {
            return
        }
    }

    @discardableResult
    static func addCustomTranslation(languageId: String, title: String, abbreviation: String, sourceURL: String) -> BibleTranslationSeed? {
        let normalizedLanguage = languageId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard allowedLanguageIds.contains(normalizedLanguage) else { return nil }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAbbreviation = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedURL = URL(string: normalizedURL)
        guard !normalizedLanguage.isEmpty, !normalizedTitle.isEmpty, !normalizedAbbreviation.isEmpty,
              let parsedURL,
              parsedURL.host == "bible.helloao.org",
              parsedURL.path.hasPrefix("/api/"),
              parsedURL.path.hasSuffix("/complete.json") else { return nil }

        let newSeed = BibleTranslationSeed(
            id: "custom_\(normalizedLanguage)_\(normalizedAbbreviation)_\(abs(normalizedURL.hashValue))",
            languageId: normalizedLanguage,
            title: normalizedTitle,
            abbreviation: normalizedAbbreviation,
            sourceURL: normalizedURL
        )

        var all = customTranslations()
        guard !all.contains(where: { $0.id == newSeed.id || $0.sourceURL == newSeed.sourceURL }) else { return nil }
        all.append(newSeed)
        guard let encoded = try? JSONEncoder().encode(all) else { return nil }
        UserDefaults.standard.set(encoded, forKey: customTranslationsKey)
        return newSeed
    }

    fileprivate static func defaultTranslations(for languageId: String) -> [BibleTranslationSeed] {
        switch languageId {
        case "en":
            return [
                BibleTranslationSeed(
                    id: "en_bsb",
                    languageId: "en",
                    title: "Berean Standard Bible",
                    abbreviation: "BSB",
                    sourceURL: "https://bible.helloao.org/api/BSB/complete.json"
                ),
                BibleTranslationSeed(
                    id: "en_bbe",
                    languageId: "en",
                    title: "Bible in Basic English",
                    abbreviation: "BBE",
                    sourceURL: "https://bible.helloao.org/api/eng_bbe/complete.json"
                )
            ]
        case "uk":
            return [
                BibleTranslationSeed(
                    id: "uk_1996",
                    languageId: "uk",
                    title: "Ukrainian Bible (BJU 1996)",
                    abbreviation: "UKR96",
                    sourceURL: "https://bible.helloao.org/api/ukr_1996/complete.json"
                )
            ]
        case "ru":
            return [
                BibleTranslationSeed(
                    id: "ru_synodal",
                    languageId: "ru",
                    title: "Синодальный перевод",
                    abbreviation: "SYNO",
                    sourceURL: "https://bible.helloao.org/api/rus_syn/complete.json"
                )
            ]
        case "es":
            return [
                BibleTranslationSeed(
                    id: "es_rvr",
                    languageId: "es",
                    title: "Reina-Valera",
                    abbreviation: "RVR",
                    sourceURL: "https://bible.helloao.org/api/spa_r09/complete.json"
                )
            ]
        case "pt":
            return [
                BibleTranslationSeed(
                    id: "pt_aa",
                    languageId: "pt",
                    title: "Portuguese Biblia Livre",
                    abbreviation: "BLJ",
                    sourceURL: "https://bible.helloao.org/api/por_blj/complete.json"
                )
            ]
        default:
            return []
        }
    }

    private static func deduplicatedTranslations(_ translations: [BibleTranslationSeed]) -> [BibleTranslationSeed] {
        var byID: [String: BibleTranslationSeed] = [:]
        for translation in translations {
            byID[translation.id] = translation
        }
        return byID.values.sorted {
            if $0.languageId == $1.languageId {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.languageId < $1.languageId
        }
    }

    private static func absoluteHelloAOURL(_ pathOrURL: String) -> String {
        if pathOrURL.hasPrefix("http://") || pathOrURL.hasPrefix("https://") {
            return pathOrURL
        }
        return "https://bible.helloao.org\(pathOrURL)"
    }

    private static func normalizedLanguageId(_ language: String) -> String {
        switch language.lowercased() {
        case "eng": return "en"
        case "ukr": return "uk"
        default: return language.lowercased()
        }
    }
}

enum BibleLibrarySeeder {
    private static let seededLanguagePrefix = "settings.bibleSeededLanguage."
    private static let seededTranslationPrefix = "settings.bibleSeededTranslation."

    static func ensureSeededIfNeeded(languageId: String, store: CanvasProjectStore = .shared) async {
        let seedKey = seededLanguagePrefix + languageId
        let translations = BibleLibraryCatalog.defaultTranslations(for: languageId)
        guard !translations.isEmpty else { return }

        for translation in translations {
            let translationSeedKey = seededTranslationPrefix + translation.id
            if UserDefaults.standard.bool(forKey: translationSeedKey) {
                continue
            }
            guard let payload = await downloadTranslation(translation) else { continue }
            let folderTitle = "\(AppLocalization.t("Біблія", "Bible")) • \(translation.abbreviation)"
            let folderId = existingFolderId(named: folderTitle, in: store) ?? store.createFolder(title: folderTitle)
            guard let folderId else { continue }
            createMissingBookCanvases(payload: payload, folderId: folderId, store: store)
            UserDefaults.standard.set(true, forKey: translationSeedKey)
        }

        UserDefaults.standard.set(true, forKey: seedKey)
    }

    static func ensureSeeded(translation: BibleTranslationSeed, store: CanvasProjectStore = .shared) async throws -> BibleSeedImportResult {
        let payload = try await downloadTranslationDetailed(translation)
        let translationSeedKey = seededTranslationPrefix + translation.id
        UserDefaults.standard.set(true, forKey: translationSeedKey)
        return BibleSeedImportResult(importedBooksCount: payload.books.count)
    }

    static func isAddedToCanvases(translation: BibleTranslationSeed, store: CanvasProjectStore = .shared) -> Bool {
        let translationSeedKey = seededTranslationPrefix + translation.id
        return UserDefaults.standard.bool(forKey: translationSeedKey)
    }

    static func removeFromCanvases(translation: BibleTranslationSeed, store: CanvasProjectStore = .shared) -> Bool {
        let translationSeedKey = seededTranslationPrefix + translation.id
        UserDefaults.standard.removeObject(forKey: translationSeedKey)
        let folderTitle = "\(AppLocalization.t("Біблія", "Bible")) • \(translation.abbreviation)"
        if let folderId = existingFolderId(named: folderTitle, in: store) {
            store.deleteFolder(id: folderId)
        }
        return true
    }

    static func ensureBookCanvas(
        translation: BibleTranslationSeed,
        bookIndex: Int,
        store: CanvasProjectStore = .shared
    ) async throws -> UUID {
        let payload = try await downloadTranslationDetailed(translation)
        guard payload.books.indices.contains(bookIndex) else {
            throw BibleSeedImportError.emptyPayload
        }
        let book = payload.books[bookIndex]
        let folderTitle = "\(AppLocalization.t("Біблія", "Bible")) • \(translation.abbreviation)"
        let folderId = existingFolderId(named: folderTitle, in: store) ?? store.createFolder(title: folderTitle)
        guard let folderId else { throw BibleSeedImportError.folderCreationFailed }

        if let existing = store.projects(in: folderId).first(where: { $0.title == book.name }) {
            return existing.id
        }

        let id = store.createProject(title: book.name, folderID: folderId)
        if let data = initialCanvasData(text: book.fullText) {
            store.writeCanvasData(id: id, data: data)
        }
        store.reload()
        return id
    }

    private static func existingFolderId(named title: String, in store: CanvasProjectStore) -> UUID? {
        store.folders.first(where: { $0.title == title })?.id
    }

    private static func createMissingBookCanvases(payload: DownloadedBibleTranslation, folderId: UUID, store: CanvasProjectStore) -> Int {
        let existingTitles = Set(store.projects(in: folderId).map(\.title))
        let maxBooks = min(payload.books.count, 66)
        let books = Array(payload.books.prefix(maxBooks))
        var importedCount = 0
        for book in books {
            let title = book.name
            if existingTitles.contains(title) { continue }
            let id = store.createProject(title: title, folderID: folderId)
            if let data = initialCanvasData(text: book.fullText) {
                store.writeCanvasData(id: id, data: data)
            }
            importedCount += 1
        }
        store.reload()
        return importedCount
    }

    private static func downloadTranslation(_ translation: BibleTranslationSeed) async -> DownloadedBibleTranslation? {
        try? await downloadTranslationDetailed(translation)
    }

    fileprivate static func downloadTranslationDetailed(_ translation: BibleTranslationSeed) async throws -> DownloadedBibleTranslation {
        if let cached = loadCachedTranslation(for: translation.id) {
            return cached
        }
        guard let url = URL(string: translation.sourceURL) else {
            throw BibleSeedImportError.invalidSourceURL(translation.sourceURL)
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw BibleSeedImportError.invalidServerResponse
            }
            guard (200...299).contains(http.statusCode) else {
                throw BibleSeedImportError.httpStatus(http.statusCode)
            }

            let helloAODecoded: HelloAOCompleteDTO
            do {
                helloAODecoded = try JSONDecoder().decode(HelloAOCompleteDTO.self, from: data)
            } catch {
                throw BibleSeedImportError.decodeFailed(error.localizedDescription)
            }

            let books = helloAODecoded.books.compactMap { bookDTO in
                let primaryName = bookDTO.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackName = bookDTO.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = (primaryName?.isEmpty == false ? primaryName : fallbackName) ?? "Book"
                let chapters = (bookDTO.chapters ?? []).map { chapterDTO in
                    flattenHelloAOChapterText(chapterDTO.chapter.content)
                }
                return DownloadedBibleBook(
                    name: name,
                    fullText: buildBookText(name: name, chapters: chapters, languageId: translation.languageId),
                    chapters: chapters
                )
            }
            guard !books.isEmpty else {
                throw BibleSeedImportError.emptyPayload
            }
            let payload = DownloadedBibleTranslation(translationId: translation.id, books: books)
            saveCachedTranslation(payload, for: translation.id)
            return payload
        } catch let error as BibleSeedImportError {
            throw error
        } catch let error as URLError {
            throw BibleSeedImportError.network(error)
        } catch {
            throw BibleSeedImportError.unknown(error.localizedDescription)
        }
    }

    private static func flattenHelloAOChapterText(_ content: [HelloAOContentItem]) -> [String] {
        var versesByNumber: [Int: String] = [:]
        var order: [Int] = []

        for item in content {
            guard item.type == "verse", let number = item.number else { continue }
            let verseText = item.content
                .compactMap { entry -> String? in
                    if let text = entry.stringValue {
                        return text
                    }
                    if let object = entry.objectValue {
                        return object.text
                    }
                    return nil
                }
                .joined()
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !verseText.isEmpty else { continue }
            if versesByNumber[number] == nil {
                order.append(number)
                versesByNumber[number] = verseText
            } else {
                versesByNumber[number]? += " " + verseText
            }
        }

        return order.sorted().compactMap { versesByNumber[$0] }
    }

    private static func buildBookText(name: String, chapters: [[String]], languageId: String) -> String {
        var chunks: [String] = [name]
        let chapterTitle = chapterLabel(for: languageId)
        for (chapterIndex, verses) in chapters.enumerated() {
            chunks.append("")
            chunks.append("\(chapterTitle) \(chapterIndex + 1)")
            for (verseIndex, verse) in verses.enumerated() {
                let cleanVerse = verse.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                chunks.append("\(verseIndex + 1). \(cleanVerse)")
            }
        }
        return chunks.joined(separator: "\n")
    }

    private static func chapterLabel(for languageId: String) -> String {
        switch languageId {
        case "uk": return AppLocalization.t("Розділ", "Chapter")
        case "ru": return "Глава"
        case "es": return "Capítulo"
        case "pt": return "Capítulo"
        default: return "Chapter"
        }
    }

    private static func cacheFileURL(for translationId: String) -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let base = appSupport
            .appendingPathComponent("DocumentsPainter", isDirectory: true)
            .appendingPathComponent("BibleCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("\(translationId).json")
    }

    private static func loadCachedTranslation(for translationId: String) -> DownloadedBibleTranslation? {
        guard let url = cacheFileURL(for: translationId),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DownloadedBibleTranslation.self, from: data)
    }

    private static func saveCachedTranslation(_ payload: DownloadedBibleTranslation, for translationId: String) {
        guard let url = cacheFileURL(for: translationId),
              let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func initialCanvasData(text: String) -> Data? {
        let layerId = UUID()
        let wrappedLines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .flatMap { line -> [String] in
                let normalized = line
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { return [""] }
                return wrapCanvasTextLine(normalized, maxChars: 64)
            }
        let lines = wrappedLines
            .enumerated()
            .map { idx, line in
                ImportedTextLine(
                    documentId: UUID(),
                    groupId: UUID(),
                    order: idx,
                    layerId: layerId,
                    text: line,
                    position: CGPoint(x: 24, y: 120 + CGFloat(idx) * 24),
                    fontSize: 18,
                    color: .black
                )
            }

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
            artLayers: [CanvasArtLayerDTO(CanvasArtLayer(id: layerId, name: AppLocalization.t("Шар 1", "Layer 1")))],
            activeLayerId: layerId,
            hiddenArtLayerIds: []
        )
        return try? JSONEncoder().encode(state)
    }

    private static func wrapCanvasTextLine(_ text: String, maxChars: Int) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }

        var result: [String] = []
        var current = ""
        for word in words {
            if current.isEmpty {
                current = word
                continue
            }
            if current.count + 1 + word.count <= maxChars {
                current += " " + word
            } else {
                result.append(current)
                current = word
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}

struct BibleSeedImportResult {
    let importedBooksCount: Int
}

struct BibleBookOption: Identifiable, Hashable {
    let id: String
    let title: String
    let chapterCount: Int
}

struct BibleVerseOption: Identifiable, Hashable {
    let id: Int
    let number: Int
    let text: String
}

struct BiblePassageResolved {
    let title: String
    let lines: [String]
}

enum BibleSeedImportError: LocalizedError {
    case invalidSourceURL(String)
    case invalidServerResponse
    case httpStatus(Int)
    case decodeFailed(String)
    case emptyPayload
    case network(URLError)
    case folderCreationFailed
    case seedMarkedButFolderMissing
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidSourceURL(let url):
            return AppLocalization.isUkrainian
                ? "Некоректне джерело перекладу: \(url)"
                : "Invalid translation source: \(url)"
        case .invalidServerResponse:
            return AppLocalization.t("Сервер повернув некоректну відповідь.", "Server returned an invalid response.")
        case .httpStatus(let code):
            return AppLocalization.isUkrainian
                ? "Сервер повернув помилку HTTP \(code)."
                : "Server returned HTTP error \(code)."
        case .decodeFailed(let details):
            return "Не вдалося розпізнати дані перекладу (\(details))."
        case .emptyPayload:
            return "Переклад завантажено, але в ньому немає книг."
        case .network(let urlError):
            return "Помилка мережі: \(urlError.localizedDescription)"
        case .folderCreationFailed:
            return "Не вдалося створити папку для перекладу."
        case .seedMarkedButFolderMissing:
            return "Переклад позначений як імпортований, але папку не знайдено."
        case .unknown(let details):
            return "Невідома помилка: \(details)"
        }
    }
}

enum BiblePassageService {
    static func books(for translation: BibleTranslationSeed) async throws -> [BibleBookOption] {
        let payload = try await BibleLibrarySeeder.downloadTranslationDetailed(translation)
        return payload.books.enumerated().map { index, book in
            BibleBookOption(
                id: "\(index)",
                title: book.name,
                chapterCount: max(0, book.chapters.count)
            )
        }
    }

    static func resolvePassage(
        translation: BibleTranslationSeed,
        bookIndex: Int,
        chapterNumber: Int,
        verseStart: Int,
        verseEnd: Int?
    ) async throws -> BiblePassageResolved {
        let payload = try await BibleLibrarySeeder.downloadTranslationDetailed(translation)
        guard payload.books.indices.contains(bookIndex) else {
            throw BibleSeedImportError.emptyPayload
        }
        let book = payload.books[bookIndex]
        guard chapterNumber > 0, chapterNumber <= book.chapters.count else {
            throw BibleSeedImportError.emptyPayload
        }

        let verses = book.chapters[chapterNumber - 1]
        guard !verses.isEmpty else { throw BibleSeedImportError.emptyPayload }
        let start = max(1, verseStart)
        let computedEnd = min(max(start, verseEnd ?? start), verses.count)
        guard start <= computedEnd else { throw BibleSeedImportError.emptyPayload }

        var lines: [String] = []
        for idx in (start - 1)...(computedEnd - 1) {
            lines.append("\(idx + 1). \(verses[idx])")
        }

        let title: String
        if start == computedEnd {
            title = "\(book.name) \(chapterNumber):\(start)"
        } else {
            title = "\(book.name) \(chapterNumber):\(start)-\(computedEnd)"
        }
        return BiblePassageResolved(title: title, lines: lines)
    }

    static func chapterVerses(
        translation: BibleTranslationSeed,
        bookIndex: Int,
        chapterNumber: Int
    ) async throws -> [BibleVerseOption] {
        let payload = try await BibleLibrarySeeder.downloadTranslationDetailed(translation)
        guard payload.books.indices.contains(bookIndex) else {
            throw BibleSeedImportError.emptyPayload
        }
        let book = payload.books[bookIndex]
        guard chapterNumber > 0, chapterNumber <= book.chapters.count else {
            throw BibleSeedImportError.emptyPayload
        }
        let verses = book.chapters[chapterNumber - 1]
        guard !verses.isEmpty else { throw BibleSeedImportError.emptyPayload }
        return verses.enumerated().map { index, verse in
            BibleVerseOption(id: index + 1, number: index + 1, text: verse)
        }
    }
}

private struct DownloadedBibleTranslation: Codable {
    let translationId: String
    let books: [DownloadedBibleBook]
}

private struct DownloadedBibleBook: Codable {
    let name: String
    let fullText: String
    let chapters: [[String]]

    init(name: String, fullText: String, chapters: [[String]]) {
        self.name = name
        self.fullText = fullText
        self.chapters = chapters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? "Book"
        fullText = (try? container.decode(String.self, forKey: .fullText)) ?? ""
        chapters = (try? container.decode([[String]].self, forKey: .chapters)) ?? []
    }
}

private struct HelloAOCompleteDTO: Codable {
    let books: [HelloAOBookDTO]
}

private struct HelloAOAvailableTranslationsResponse: Codable {
    let translations: [HelloAOAvailableTranslationDTO]
}

private struct HelloAOAvailableTranslationDTO: Codable {
    let id: String
    let name: String
    let shortName: String
    let englishName: String
    let language: String
    let languageName: String?
    let languageEnglishName: String?
    let completeTranslationApiLink: String?
}

private struct HelloAOBookDTO: Codable {
    let name: String?
    let title: String?
    let chapters: [HelloAOChapterDTO]?
}

private struct HelloAOChapterDTO: Codable {
    let chapter: HelloAOChapterContentDTO

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chapter = (try? container.decode(HelloAOChapterContentDTO.self, forKey: .chapter))
            ?? HelloAOChapterContentDTO(content: [])
    }
}

private struct HelloAOChapterContentDTO: Codable {
    let content: [HelloAOContentItem]
}

private struct HelloAOContentItem: Codable {
    let type: String
    let number: Int?
    let content: [HelloAOContentEntry]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decode(String.self, forKey: .type)) ?? ""
        number = try? container.decode(Int.self, forKey: .number)
        content = (try? container.decode([HelloAOContentEntry].self, forKey: .content)) ?? []
    }
}

private struct HelloAOContentObject: Codable {
    let text: String?
}

private enum HelloAOContentEntry: Codable {
    case string(String)
    case object(HelloAOContentObject)

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var objectValue: HelloAOContentObject? {
        if case let .object(value) = self { return value }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        self = .object(try container.decode(HelloAOContentObject.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}
