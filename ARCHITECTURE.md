# AniVibe — карта проекта (читать первым в каждой сессии)

Нативное iOS-приложение: Swift + SwiftUI, мин. iOS 17, SPM-пакет ядра. Сборка IPA — GitHub Actions `ios.yml` (push → `main`), артефакт `Anivibe-unsigned-ipa-rNN`.

## Дерево

- `Anivibe.xcodeproj` — проект Xcode (file-system-synchronized, новые .swift подхватываются сами).
- `Anivibe/` — приложение (SwiftUI, `@Observable`, `@MainActor` сторы, `NavigationStack`).
  - `App/`
    - `AnivibeApp.swift` — точка входа, окружение.
    - `AppEnvironment.swift` — корень композиции: сервисы, сторы, `CollectionsStore` также тут (в конце файла).
    - `RootView.swift` — TabView: home / catalog / library / profile + splash + community-поллинг.
    - `AppSettings.swift` — настройки пользователя в UserDefaults (тема, акцент `accentHex` → `Theme.palette.hex`, toggles, `foldersEnabled`).
    - `AppFeatures.swift` — фичефлаги (community и пр.).
  - `Core/` — сторы состояния
    - `LibraryStore.swift` — обёртка над `LibraryRepository`, `onLocalChange` для синка.
    - `SessionStore.swift` — авторизация + orchestration sync (библиотека, папки, тир-лист), файлы per-account.
    - `SocialStore.swift` — друзья/поиск + `SocialProfileStore` (чужой профиль с пагинацией).
    - `TierListStore.swift` — тир-листы (TierListSet, до 5 списков): локальный JSON + sync-документ.
    - `ImagePipeline.swift`, `KeychainTokenStore.swift`, `GoogleOAuthCoordinator.swift`, `CommunityStore.swift`.
  - `DesignSystem/`
    - `Theme.swift` — цвета/отступы/радиусы, `palette.hex` (пользовательский акцент), `screenBackground`, `profilePanel`, `UIColor(hexString:)`.
    - `AppMotion.swift` — анимации с учётом Reduce Motion.
    - `Components/` — `PosterImage` (async-картинка с фолбэком), `PosterCard`, `StateViews` (EmptyStateView и пр.).
  - `Features/`
    - `Home/HomeView.swift` (+Model) — лента, «Недавно вышедшие», ПАПКИ (FolderTile/FolderOverlay/NewFolderTile, drag-reorder).
    - `Catalog/` — каталог AniList, фильтры.
    - `Library/LibraryView.swift` — вкладки списков (Все/Смотрю/Просмотрено/В планах/Отложено/Брошено/Избранное/История), `CollectionDropDelegate.swift`, `FolderSelectionSheet.swift`.
    - `AnimeDetails/` — карточка тайтла, серии, комментарии.
    - `Player/` — `PlayerScreen` (оверлей плеера), `PlayerViewModel` (AVPlayer), `PlayerControlsView` (контролы + `VideoTimelineSlider` + sheets: Sources/Episodes), `PlayerLayerView`, `SpeedBoostIndicator`, `VideoSettingsSheet`.
    - `Online/` — `KodikPlayerView` (веб-плеер), `OnlineSourcesSection`.
    - `Profile/` — `ProfileView` (профиль + «Мои списки» + статистика), `FriendsView` (друзья, `PublicProfileView`, `SocialActivityList`), `ProfileEditorView`, `ProfileAvatarView`, `TierListView` (BETA: карточка, конструктор, селектор списков), `TierListSheets` (assign/customize/manager шиты), `TierListAutoScroll` (плавный автоскролл при драге), `PublicTierListView` (чужой список).
    - `Settings/` — `SettingsView` (тема, акцент, toggles, источники), `BackgroundSettings`.
    - `Community/` — совместный просмотр/монеты.
- `Packages/AnivibeCore/` — ядро без UI-зависимостей от приложения
  - `Models/` — `Anime`/`AnimeSnapshot`, `Library` (`LibraryStatus`, `LibraryEntry`, `LibrarySnapshot`: `entries(in:)`, `allListEntries`, `statusCounts`), `AnimeCollection`, `TierList` (`TierKey` S–D, `TierRowData`, `TierList`, `NamedTierList`, `TierListSet` ≤5 списков + legacy-декод, `TierListSyncDocument`), `CatalogQuery` (`AiredEpisode`), `Episode`, `Playback*`.
  - `Catalog/` — `CatalogService` протокол, `AniListCatalogService` (`recentEpisodes`: окно 7 дней, до 5 стр. ×50, dedup по anime.id), `AniListQueries/DTO`, `RussianCatalogService` (русские названия), `RussianMetadataService`.
  - `Providers/` — `VideoSourceProvider`, `KodikProvider`, `AnilibriaProvider`, `ManifestProvider`, `TestStreamProvider`, `ProviderRegistry`.
  - `Online/` — `KodikClient/Streams/Models`.
  - `Library/` — `LibraryRepository` (файлы per-account в Application Support), `LibraryPersistence`.
  - `Sync/` — `SupabaseAuthClient`, `SupabaseSyncService` (`syncTierList` upsert 1 строка/user), `SupabaseSocialService` (`anivibe_social_profile` RPC → `SocialProfileDetails`, `tierList` опционально).
  - `Networking/`, `Support/`, `Config/AppConfiguration` (секреты из Info.plist).
- `supabase/migrations/` — PostgreSQL миграции (RLS, RPC). Новые — только новыми файлами.
- `supabase/tests/`, `scripts/` — CI-проверки (запускаются в `ios.yml`).
- `android/` — Android-версия (в этой задаче не трогаем).

## Хранилище данных

### Локальное (Application Support/Anivibe/)
- `library(-user-<uuid>).json` — `LibrarySnapshot`: entries(status/isFavorite/lastEpisode/updatedAt/isDeleted), progress, history, historyTombstones, lastSyncAt.
- `collections(-user-<uuid>).json` — `CollectionsSyncState` (папки).
- `tierlist(-user-<uuid>).json` — `TierListSyncDocument` { set: TierListSet, acknowledgedMutationID } (legacy-ключ `tierList` читается).
- UserDefaults — `settings.*` (accentHex, appearance, libraryPinned, foldersEnabled, autoplay, providers).

### Supabase (PostgreSQL, RLS own-only)
- `library_entries`, `watch_progress`, `watch_history`, `profiles` (friends/history/library_visibility), `friendships`, `account_collections`.
- `tier_lists` — 1 строка/user: `visibility`, `data jsonb` (TierListSet {lists ≤5, activeListID,...}; CHECK ограничивает ≤5), `updated_at`, `mutation_id`, LWW-триггер.
- RPC `anivibe_social_profile(target, offsets)` → профиль + friends/history/library по видимости + `tier_list` (legacy-ключ) + `tier_lists[]` (NamedTierList[]: владельцу все, гостю только public) + `stats` + `*_has_more`.

## Где что лежит (быстрый поиск)

- Тема/акцент: `DesignSystem/Theme.swift` (`Theme.accent` читает `palette.hex`; палитра и кастом-цвет — `SettingsView`).
- Стейт пользователя/синк: `Core/SessionStore.swift`; видимый стейт библиотеки — `Core/LibraryStore.swift`.
- Видеоплеер: `Features/Player/PlayerControlsView.swift` (UI), `PlayerViewModel.swift` (логика AVPlayer).
- Тир-листы: модель `AnivibeCore/Models/TierList.swift` (TierListSet, ≤5 именованных), стор `Core/TierListStore.swift`, UI `Features/Profile/TierList{View,Sheets,AutoScroll}.swift` + `PublicTierListView.swift`, синк `SupabaseSyncService.syncTierList`, миграции `20261116000000_tier_lists.sql` + `20261117000000_multi_tier_lists.sql`.
- Папки: тогл `settings.foldersEnabled` (только скрывает UI, данные не трогает); модель `AnivibeCore/Models/AnimeCollection.swift`, стор `CollectionsStore` (в `AppEnvironment.swift`), UI на `HomeView` (foldersSection + оверлей), sheet `Library/FolderSelectionSheet.swift`, кнопка в `AnimeDetailsView`, метрика/импорт в `ProfileView`.
