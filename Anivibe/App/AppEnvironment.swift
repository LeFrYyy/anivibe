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
