import SwiftUI
import AnivibeCore

/// Корень композиции: создаёт сервисы из конфигурации и раздаёт их экранам.
@Observable
@MainActor
final class AppEnvironment {
    let configuration: AppConfiguration
    let catalog: CatalogService
    let registry: ProviderRegistry
    let library: LibraryStore
    let session: SessionStore
    let settings: AppSettings
    let cache: MetadataCache
    let socialService: SupabaseSocialService?
    let communityService: SupabaseCommunityService?
    let community = CommunityStore()
    /// Клиент Kodik (веб-плеер с озвучками). `nil`, если токен не задан в конфигурации.
    let kodik: KodikClient?
    /// Пользовательские папки с аниме на главной.
    let collections: CollectionsStore
    /// Каталог и читалка манги (экспериментальная функция, гейтится настройкой).
    let manga: MangaService
    @ObservationIgnored private var started = false

    init(configuration: AppConfiguration, catalog: CatalogService, registry: ProviderRegistry, library: LibraryStore,
         session: SessionStore, settings: AppSettings, cache: MetadataCache, kodik: KodikClient? = nil, socialService: SupabaseSocialService? = nil, communityService: SupabaseCommunityService? = nil, manga: MangaService) {
        self.configuration = configuration
        self.catalog = catalog
        self.manga = manga
        self.registry = registry
        self.library = library
        self.session = session
        self.collections = session.collections
        self.settings = settings
        self.cache = cache
        self.kodik = kodik
        self.socialService = socialService
        self.communityService = communityService
    }

    static func live(bundle: Bundle = .main) -> AppEnvironment {
        let config = AppConfiguration.from(infoDictionary: bundle.infoDictionary ?? [:])
        let transport = RetryingTransport(base: URLSessionTransport.standard())
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AnivibeMetadata", isDirectory: true)
        let cache = MetadataCache(directory: cachesDir)

        let catalog: CatalogService = config.demoCatalog
            ? DemoCatalogService()
            : RussianCatalogService(catalog: AniListCatalogService(transport: transport, cache: cache),
                metadata: RussianMetadataService(transport: transport, cache: cache), cache: cache)

        // Видеопровайдеры: реальные (если настроены) + легальные тестовые потоки.
        var providers: [VideoSourceProvider] = []
        if let manifestURL = config.manifestURL {
            providers.append(ManifestProvider(manifestURL: manifestURL, transport: transport))
        }
        // Kodik — основной источник (десятки озвучек, качество и скорость в плеере).
        // Anilibria остаётся запасным: только если у Kodik нет тайтла/серии.
        let kodik = config.kodikToken.map { KodikClient(token: $0, transport: transport) }
        if let kodik {
            providers.insert(KodikProvider(
                client: kodik,
                preferredVoice: { UserDefaults.standard.string(forKey: KodikPreferences.voiceKey) },
                preferredQuality: {
                    let q = UserDefaults.standard.integer(forKey: KodikPreferences.qualityKey)
                    return q > 0 ? q : nil
                }), at: 0)
        }
        providers.append(AnilibriaProvider(transport: transport))
        providers.append(TestStreamProvider(transport: transport))
        // Kodik отвечает объёмными JSON (все серии всех озвучек) — даём больше времени.
        let registry = ProviderRegistry(providers: providers, timeout: 25)

        let persistence: LibraryPersistence
        if let file = try? FileLibraryPersistence.defaultLocation() {
            persistence = file
        } else {
            persistence = InMemoryLibraryPersistence()
        }
        let repository = LibraryRepository(persistence: persistence)
        let library = LibraryStore(repository: repository)

        var auth: SupabaseAuthClient?
        var sync: SupabaseSyncService?
        var socialService: SupabaseSocialService?
        var communityService: SupabaseCommunityService?
        if let supa = config.supabase {
            let client = SupabaseAuthClient(config: supa, transport: transport, store: KeychainTokenStore())
            auth = client
            socialService = SupabaseSocialService(config: supa, auth: client, transport: transport)
            communityService = SupabaseCommunityService(config: supa, auth: client, transport: transport)
            sync = SupabaseSyncService(config: supa, transport: transport, auth: client, library: repository)
        }
        let session = SessionStore(auth: auth, sync: sync, library: library, collections: CollectionsStore())
        let settings = AppSettings(testStreamsDefault: config.testStreamsEnabledByDefault)


        let manga: MangaService = MangaHub(
            catalog: ShikimoriMangaService(transport: transport, cache: cache),
            reader: MangaDexService(transport: transport, cache: cache),
            cache: cache)

        return AppEnvironment(configuration: config, catalog: catalog, registry: registry, library: library,
                              session: session, settings: settings, cache: cache, kodik: kodik, socialService: socialService, communityService: communityService, manga: manga)
    }

    func start() async {
        guard !started else { return }
        started = true
        await registry.setEnabled(settings.testStreamsEnabled, for: TestStreamProvider.providerID)
        await registry.setEnabled(settings.anilibriaEnabled, for: AnilibriaProvider.providerID)
        await library.load()
        await session.restore()
    }

    func setTestStreamsEnabled(_ enabled: Bool) {
        settings.testStreamsEnabled = enabled
        Task { await registry.setEnabled(enabled, for: TestStreamProvider.providerID) }
    }

    func setAnilibriaEnabled(_ enabled: Bool) {
        settings.anilibriaEnabled = enabled
        Task { await registry.setEnabled(enabled, for: AnilibriaProvider.providerID) }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Task { await library.refresh(); await session.syncIfNeeded(reason: .foreground) }
        case .background:
            NotificationCenter.default.post(name: .anivibeWillResignActive, object: nil)
            Task { await session.syncIfNeeded(reason: .background) }
        default:
            break
        }
    }
}

extension Notification.Name {
    /// Плеер сохраняет позицию, когда приложение уходит в фон.
    static let anivibeWillResignActive = Notification.Name("anivibe.willResignActive")
}

/// Общие настройки Kodik (используются и плеером приложения, и разделом озвучек).
enum KodikPreferences {
    static let voiceKey = "kodik.preferredVoice"
    static let qualityKey = "kodik.preferredQuality"
    static let speedKey = "kodik.playbackSpeed"
}


/// Separate local files per account; guest collections.json is preserved and only
/// copied to an account by the explicit import action. Cloud data stays own-only.
@Observable
@MainActor
final class CollectionsStore {
    private(set) var state = AnimeCollections()
    private(set) var activeAccountID: String?
    private(set) var errorMessage: String?
    private(set) var importMessage: String?
    @ObservationIgnored var onLocalChange: (@MainActor () -> Void)?
    @ObservationIgnored private var document = CollectionsSyncState()
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var canSave = true
    @ObservationIgnored private let directory: URL?
    var collections: [AnimeCollection] { state.collections }

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Anivibe", isDirectory: true)
        if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        do { activate(try prepareAccount(nil), userID: nil) }
        catch { canSave = false; errorMessage = "Файл папок не удалось открыть. Исходный файл сохранён без изменений." }
    }
    struct Prepared { let document: CollectionsSyncState; let url: URL }
    func prepareAccount(_ userID: String?) throws -> Prepared {
        guard let directory else { throw APIError.badRequest("Хранилище папок недоступно") }
        let filename: String
        if let userID {
            guard UUID(uuidString: userID) != nil else { throw APIError.badRequest("Некорректный ID аккаунта") }
            filename = "collections-user-" + userID.lowercased() + ".json"
        } else { filename = "collections.json" }
        let url = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return Prepared(document: CollectionsSyncState(), url: url) }
        let data = try Data(contentsOf: url)
        if let document = try? JSONDecoder().decode(CollectionsSyncState.self, from: data) {
            return Prepared(document: document, url: url)
        }
        // Original guest JSON remains readable; conversion never auto-uploads it.
        let legacy = try JSONDecoder().decode(AnimeCollections.self, from: data)
        var migrated = CollectionsSyncState(); migrated.capture(legacy)
        return Prepared(document: migrated, url: url)
    }
    func activate(_ prepared: Prepared, userID: String?) {
        activeAccountID = userID; fileURL = prepared.url; document = prepared.document
        state = document.visible; canSave = true; errorMessage = nil; importMessage = nil
    }
    func clearVisibleOnAccountFailure() {
        activeAccountID = nil; state = AnimeCollections(); document = CollectionsSyncState(); canSave = false
        errorMessage = "Папки не удалось открыть. Исходные файлы сохранены."
    }
    func collection(_ id: UUID) -> AnimeCollection? { state.collection(id) }
    @discardableResult func create(name: String, with first: AnimeSnapshot? = nil) -> UUID {
        guard canSave else { return UUID() }
        let id = state.create(name: String(name.prefix(100)), with: first); saveLocal(); return id
    }
    func reorder(_ id: UUID, to target: UUID) { mutate { $0.moveCollection(id, to: target) } }
    func reorderItem(_ animeID: Int, in id: UUID, to target: Int) { mutate { $0.moveItem(animeID, in: id, to: target) } }
    func rename(_ id: UUID, to name: String) { mutate { $0.rename(id, to: String(name.prefix(120))) } }
    func delete(_ id: UUID) { mutate { $0.delete(id) } }
    func add(_ anime: AnimeSnapshot, to id: UUID) { mutate { $0.add(anime, to: id) } }
    func remove(_ animeID: Int, from id: UUID) { mutate { $0.remove(animeID, from: id) } }
    func toggle(_ anime: AnimeSnapshot, in id: UUID) { mutate { $0.toggle(anime, in: id) } }
    func move(in id: UUID, from source: IndexSet, to destination: Int) { mutate { $0.moveItems(in: id, from: source, to: destination) } }
    private func mutate(_ work: (inout AnimeCollections) -> Void) {
        guard canSave else { return }
        var next = state
        work(&next)
        // Closing an unchanged folder or adding an existing item needs no disk write.
        // Retry a failed save even if the visible state did not change.
        guard next != state || errorMessage != nil else { return }
        if next != state { state = next }
        saveLocal()
    }
    private func saveLocal() {
        document.capture(state)
        do { try persist(); onLocalChange?() }
        catch { errorMessage = "Папки не удалось сохранить. Не закрывайте приложение и повторите действие." }
    }
    private func persist() throws {
        guard canSave, let fileURL else { throw APIError.badRequest("Хранилище папок недоступно") }
        try JSONEncoder().encode(document).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        errorMessage = nil
    }
    func recordsForSync(accountID: String) throws -> [CollectionSyncRecord] {
        guard activeAccountID == accountID, canSave, errorMessage == nil else { throw APIError.badRequest("Папки не готовы к синхронизации") }
        return document.recordsToUpload
    }
    func mergeRemote(_ records: [CollectionSyncRecord], accountID: String) throws {
        guard activeAccountID == accountID, canSave else { throw AuthError.notSignedIn }
        // Merge into current document, not the snapshot taken before network await.
        let previous = document
        document.merge(records)
        do { try persist(); state = document.visible }
        catch { document = previous; errorMessage = "Не удалось сохранить полученные папки."; throw error }
    }
    func importGuestFolders() {
        guard activeAccountID != nil, canSave else { return }
        do {
            let guest = try prepareAccount(nil).document.visible.collections
            let copied = guest.map { AnimeCollection(name: String($0.name.prefix(120)), items: $0.items, createdAt: $0.createdAt) }
            state = AnimeCollections(collections: state.collections + copied)
            saveLocal()
            if errorMessage == nil { importMessage = "Скопировано папок: \(copied.count). Локальный оригинал сохранён." }
        } catch { errorMessage = "Локальные папки не удалось прочитать. Исходный файл сохранён." }
    }
}
