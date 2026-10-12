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
    /// Клиент Kodik (веб-плеер с озвучками). `nil`, если токен не задан в конфигурации.
    let kodik: KodikClient?
    /// Пользовательские папки с аниме на главной.
    let collections = CollectionsStore()
    @ObservationIgnored private var started = false

    init(configuration: AppConfiguration, catalog: CatalogService, registry: ProviderRegistry, library: LibraryStore,
         session: SessionStore, settings: AppSettings, cache: MetadataCache, kodik: KodikClient? = nil) {
        self.configuration = configuration
        self.catalog = catalog
        self.registry = registry
        self.library = library
        self.session = session
        self.settings = settings
        self.cache = cache
        self.kodik = kodik
    }

    static func live(bundle: Bundle = .main) -> AppEnvironment {
        let config = AppConfiguration.from(infoDictionary: bundle.infoDictionary ?? [:])
        let transport = URLSessionTransport.standard()
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AnivibeMetadata", isDirectory: true)
        let cache = MetadataCache(directory: cachesDir)

        let catalog: CatalogService = config.demoCatalog
            ? DemoCatalogService()
            : AniListCatalogService(transport: transport, cache: cache)

        // Видеопровайдеры: реальные (если настроены) + легальные тестовые потоки.
        var providers: [VideoSourceProvider] = []
        if let manifestURL = config.manifestURL {
            providers.append(ManifestProvider(manifestURL: manifestURL, transport: transport))
        }
        // Kodik — основной источник (десятки озвучек, качество и скорость в плеере).
        // Anilibria остаётся запасным: только если у Kodik нет тайтла/серии.
        let kodikToken = config.kodikToken ?? KodikClient.defaultToken
        let kodik = KodikClient(token: kodikToken, transport: transport)
        providers.insert(KodikProvider(
            client: kodik,
            preferredVoice: { UserDefaults.standard.string(forKey: KodikPreferences.voiceKey) },
            preferredQuality: {
                let q = UserDefaults.standard.integer(forKey: KodikPreferences.qualityKey)
                return q > 0 ? q : nil
            }), at: 0)
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
        if let supa = config.supabase {
            let client = SupabaseAuthClient(config: supa, transport: transport, store: KeychainTokenStore())
            auth = client
            sync = SupabaseSyncService(config: supa, transport: transport, auth: client, library: repository)
        }
        let session = SessionStore(auth: auth, sync: sync, library: library)
        let settings = AppSettings(testStreamsDefault: config.testStreamsEnabledByDefault)


        return AppEnvironment(configuration: config, catalog: catalog, registry: registry, library: library,
                              session: session, settings: settings, cache: cache, kodik: kodik)
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


/// Хранилище папок: состояние + сохранение в JSON (Application Support/collections.json).
@Observable
@MainActor
final class CollectionsStore {
    private(set) var state: AnimeCollections
    @ObservationIgnored private let fileURL: URL?

    var collections: [AnimeCollection] { state.collections }

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Anivibe", isDirectory: true)
        if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        fileURL = dir?.appendingPathComponent("collections.json")
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AnimeCollections.self, from: data) {
            state = decoded
        } else {
            state = AnimeCollections()
        }
    }

    func collection(_ id: UUID) -> AnimeCollection? { state.collection(id) }

    @discardableResult
    func create(name: String, with first: AnimeSnapshot? = nil) -> UUID {
        let id = state.create(name: name, with: first)
        save()
        return id
    }

    func rename(_ id: UUID, to name: String) { state.rename(id, to: name); save() }
    func delete(_ id: UUID) { state.delete(id); save() }
    func add(_ anime: AnimeSnapshot, to id: UUID) { state.add(anime, to: id); save() }
    func remove(_ animeID: Int, from id: UUID) { state.remove(animeID, from: id); save() }
    func toggle(_ anime: AnimeSnapshot, in id: UUID) { state.toggle(anime, in: id); save() }
    func move(in id: UUID, from source: IndexSet, to destination: Int) {
        state.moveItems(in: id, from: source, to: destination); save()
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
