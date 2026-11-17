# PROJECT_HISTORY — последние 8 изменений (новые сверху)

---

## 2026-11-17 · Обновление: тогл папок, плеер без градиентов, мульти-листы (≤5), автоскролл

**Файлы:**
- `AppSettings.swift`, `SettingsView.swift` — персистентный тогл «Система папок» (`settings.foldersEnabled`, default ON).
- `HomeView.swift`, `ProfileView.swift`, `AnimeDetailsView.swift` — гейт `foldersEnabled` на секции/кнопки/метрику/импорт папок; данные `CollectionsStore` не трогаются — тайтлы из папок остаются в общей библиотеке.
- `PlayerControlsView.swift` — убраны все `LinearGradient` (фон контролов, оверлей, прогресс); заливка прогресса и бегунок → `Theme.accent` (выбранный акцент темы).
- `AnivibeCore/Models/TierList.swift` — `NamedTierList` + `TierListSet` (≤`maxLists`=5, имена ≤40, `create/rename/delete/select/mutateActive`); legacy-декод: одиночный `TierList` и doc `{tierList:…}` → именованный «Тир-лист 1».
- `Core/TierListStore.swift` — `set` вместо одиночного списка; `tierList` (активный) для совместимости; `selectList` — локально без выгрузки.
- `SupabaseSyncService.swift` — `syncTierList`/`TierListRow.data` → `TierListSet`; `visibility` = «public» если хоть один список публичный.
- `SupabaseSocialService.swift` — `PublicTierList` + `SocialProfileDetails.tierLists` (legacy `tierList` сохранён).
- `supabase/migrations/20261117000000_multi_tier_lists.sql` (нов.) — CHECK `lists` ≤5 + RPC отдаёт `tier_lists[]` (владельцу все, гостю только public по `list.visibility`).
- `TierListView.swift` — селектор списков (чипсы) + счётчик X/5 + empty-state «нет списков»; `tierColor` теперь internal.
- `TierListSheets.swift` (нов.) — `TierAssignSheet`, `TierCustomizeSheet`, `TierListManagerSheet` (создание/выбор/переименование/удаление, X/5, блокировка при лимите).
- `PublicTierListView.swift` (нов.) — `PublicTierListSection` с именем списка; `FriendsView` рендерит все видимые списки.
- `TierListAutoScroll.swift` (нов.) — `TierListAutoScroller` (зоны 110pt, таймер 30 Гц, квадратичный разгон к краю) + `TierListAutoScrollDelegate` (DropDelegate на ScrollView, `performDrop`→false) + `TierScrollOffsetKey`.
- `SessionStore.swift`, `AppEnvironment.swift` — фикс MainActor-дефолта `TierListStore()` (прошлый пад CI-рана 43956219803).
- `FeatureUpdate202611Tests.swift` — +тест `testTierListSetCrudLimitAndLegacyDecode` (CRUD, лимит 5, legacy-декод, roundtrip).

**БД/API/стейт:** CHECK `jsonb_array_length(data->'lists') <= 5`; RPC возвращает и `tier_list` (старый ключ), и `tier_lists[]`. `selectList` — без выгрузки; остальные мутации — LWW по `updatedAt`+`mutationID`.

**Нюансы:** видимость — per-list (`list.visibility`), владелец видит всё; старые remote-строки `data={tiers…}` декодируются в `TierListSet` автоматически (затем перезаписываются новым форматом при аплоаде). Автоскролл: `scrollPosition.scrollTo(y:)` iOS 17; таймер гасится на drop/exit/disappear/смене списка.

---

## 2026-11-17 · Этап 0: защита контекста и память проекта

**Файлы:**
- `.cursorignore` — исключены из индексации медиа, патчи, фикстуры, локи, сборочные каталоги.
- `.cursorrules` — правила агента: чтение ARCHITECTURE/HISTORY перед стартом, экономия токенов, правило 300 строк, запись истории, сборка только через GH Actions.
- `.agent/skills/project-memory.md` — протокол памяти и декомпозиции.
- `ARCHITECTURE.md` — компактная карта проекта (дерево, БД, тема/плеер/тир-листы).

**БД/API/стейт:** без изменений.
**Нюансы:** `*.patch` и `docs/*-results/` в репо — вечнозелёные артефакты, не читать и не трогать.

---

## 2026-11-16 · Фиче-обновление: фильтры списков, «Недавно вышедшие» 7 дней, тир-лист Beta

**Файлы:**
- `AnivibeCore/Models/Library.swift` — `allListEntries`, `statusCounts`, «В планах».
- `LibraryView.swift` — вкладка «Все», счётчики `Название (N)`, Empty State по категориям.
- `ProfileView.swift` — «Мои списки»: табы со счётчиками, превью 6 шт., фильтры.
- `FriendsView.swift` — `SocialActivityList` фильтры по статусам; `PublicTierListSection` в `PublicProfileView`.
- `AniListQueries/DTO/CatalogService` — окно 7 дней (168ч), пагинация до 5 стр. ×50, dedup, сортировка новые→старые.
- `RussianCatalogService` — локализация recentEpisodes.
- `HomeView.swift` — главная до 50 карточек; `RecentEpisodesView` «· 7 дней».
- `AnivibeCore/Models/TierList.swift` (нов.) — TierKey S–D, TierRowData, TierList, TierListSyncDocument.
- `Core/TierListStore.swift` (нов.) — локальный JSON per-account + sync payload/merge.
- `Features/Profile/TierListView.swift` (нов.) — конструктор (tap-sheet + drag&drop), BETA, приватность.
- `SessionStore`, `AppEnvironment` — проводка TierListStore (init с явным `tierList:` — default-аргумент MainActor-сторов в init'ах запрещён!).
- `SupabaseSyncService` — `syncTierList` (upsert `tier_lists`, изолирован от остального синка).
- `SupabaseSocialService` — `SocialProfileDetails.tierList` (опциональный, `try?`).
- `PosterImage` — фолбэк-заглушка при битых URL.
- `supabase/migrations/20261116000000_tier_lists.sql` (нов.) — таблица `tier_lists` (1 строка/user, LWW, RLS) + `tier_list` в `anivibe_social_profile`.
- `Packages/AnivibeCore/Tests/.../FeatureUpdate202611Tests.swift` (нов.) — тесты всего вышеперечисленного.

**БД/API/стейт:** новая таблица `tier_lists`; соц-RPC отдаёт `tier_list`.
**Нюансы:** `LibraryEntry` init — `isDeleted:` ПОСЛЕ `updatedAt:`; миграцию tier_lists нужно накатить на прод-Supabase для публичного режима.
