# PROJECT_HISTORY — последние 8 изменений (новые сверху)

---

## 2026-11-19 · Откат визуального редизайна к r70 (41b562c) + скелетоны загрузки

**Направление:** вернуть внешний вид релиза r70. Откатан только визуал; невизуальные
фиксы из диапазона редизайна перенесены заново.

**Файлы:**
- `Anivibe/**` — всё дерево восстановлено из `41b562c` (`git checkout 41b562c -- Anivibe/`).
- `Anivibe/DesignSystem/Components/ContinueWatchingCard.swift` — **удалён** (файл редизайна, в r70 не существовал).
- `Anivibe/Features/Home/FolderViews.swift` — **удалён**; папки снова живут внутри `HomeView.swift` (FolderTile/NewFolderTile/FolderOverlay/FolderBackground), как в r70.
- `.github/workflows/ios.yml` — восстановлен из `41b562c`: прогон `test_flat_design.py` из CI убран (на старом визуале контракты снова красные — это исходное состояние).
- `scripts/test_motion_performance.py`, `scripts/test_update_20261025.py` — восстановлены из `41b562c` (указатели на `HomeView.swift` после удаления `FolderViews.swift`).
- `Anivibe/Features/Home/HomeView.swift` — заново применён фикс `0cd1df9`: процент в подписи «Продолжить просмотр» считается от безопасного числа (`continueSubtitle(_:)`, `isFinite` + clamp `0...1`), иначе `Int(fraction * 100)` падал на NaN.
- `Anivibe/Features/Catalog/CatalogView.swift` — заново применён невизуальный фикс из `bce4207`: рамка строки-подсказки больше не хардкод `Color.white` (на светлой теме пропадала), а `Theme.separator.opacity(0.7)`; геометрия строки оставлена как в r70 (40 pt).
- `Anivibe/DesignSystem/Components/StateViews.swift` — **нов.** `PosterGridSkeleton` (сетка каталога, повторяет адаптивные колонки) и `TextBlockSkeleton` (текстовый блок деталей).
- `Anivibe/Features/Catalog/CatalogView.swift` — вместо голого `LoadingStateView` на пустой выдаче показан `PosterGridSkeleton`; у CatalogView уже был `.animation(AppMotion.fade, value: phase)`, поэтому выдача проявляется без скачка раскладки.
- `Anivibe/Features/AnimeDetails/AnimeDetailsView.swift` — вместо спиннера `TextBlockSkeleton(lines: 4)`; заголовок и действия и так видны во время загрузки.

**БД/API/стейт:** без изменений. `Packages/AnivibeCore` не тронут, тир-листы — только UI, манга не добавлялась.

**Нюансы:**
- Градиент-затемнение постера в `AnimeDetailsView` оставлен как в r70.
- `test_motion_performance.py` жёстко держит ровно один `.sensoryFeedback(` на всё приложение (boost 2× в `PlayerScreen.swift`), а `AppMotion.swift` — ровно 4 вхождения `reduceMotion ? nil`. Поэтому **дополнительные haptics не добавлялись**: контракт r70 прямо запрещает рутинные вибрации (`AppMotion.swift:4`, `PosterCard.swift:96`), и любая новая вибрация красит тест. Пустой/скелетонный слой и контекстные меню в r70 уже были покрыты (`PosterRowSkeleton`, `EmptyStateView` во всех разделах, `folderMenu`/`contextMenu` на карточках) — переделывать было нечего.
- Скелетоны не создают собственный `ScrollView` — встраиваются в существующий контейнер (без вложенного скролла).
- Проверки локально: `python3 scripts/check_project.py` + все `scripts/test_*.py` — 0 ошибок (на Windows нужен `PYTHONUTF8=1`: скрипты читают файлы без явной кодировки, а локальная cp1251 не декодирует UTF-8; в CI на Linux проблемы нет). Swift локально не компилируется — сборка через `ios.yml`.

---

## 2026-11-18 · Редизайн визуального слоя: плоская система, восстановление папок, контракты в CI

**Направление:** спокойный нативный стиль на непрозрачных поверхностях — один цвет действия
(пользовательский акцент), нейтральные фоны, тонкие границы вместо стекла и теней.
Градиентов, материалов и декоративных теней в приложении не осталось.

**Файлы:**
- `DesignSystem/Theme.swift` — нейтральная палитра (bg/surface/surfaceElevated/separator/textPrimary/textSecondary), `Theme.scrim`, радиусы 12/16/8, `secondaryAccent` → тот же акцент; `profilePanel` без `regularMaterial`; `Theme.Folder` сокращён до геометрии (цвета — из общей палитры).
- `Resources/Assets.xcassets/AccentColor.colorset` — выровнен с `Theme.accent` (0x275D8C / 0x9CBADD); контраст AA проверен тестом.
- `DesignSystem/Components/`: `PosterCard` (бейдж и прогресс на плоских заливках, `standardWidth`), `StateViews` (чипы-капсулы, `SectionHeaderLink`), **`ContinueWatchingCard.swift` (нов.)** — крупная карточка продолжения просмотра.
- `Features/Home/FolderViews.swift` (**восстановлен**) — плитки папок, панель, `AddToFolderSheet`, `FolderMenuModifier`; плоские поверхности, `FolderPressStyle` без масштаба, empty-state и кнопка закрытия с зонами 44 pt.
- `Features/Home/HomeView.swift` — папки вынесены в `FolderViews.swift` (удалены до-v4 дубли, которые ломали сборку), главная перестроена: одна крупная карточка «Продолжить просмотр», секции с `SectionHeaderLink`, единая ширина карточек.
- `Features/Catalog/`: `CatalogView` — активные фильтры-пилюли + «Сбросить», центрированный прогресс догрузки; `FilterSheet`, строки подсказок на токенах темы.
- `Features/Library/LibraryView.swift` — невыбранные табы получили ту же границу, что и чипы.
- `Features/Player/`: `PlayerControlsView` — плоские подложки `Color.black.opacity(0.76)`, белая кнопка play, `ViewThatFits` + `.labelStyle(.iconOnly)` для узкого экрана, зоны 44 pt; `PlayerScreen`, `SpeedBoostIndicator` — без материалов.
- `Features/AnimeDetails/AnimeDetailsView.swift` — баннер отдельным блоком над текстом вместо подложки под ним (без градиентной шторки).
- `Features/Settings/SettingsView.swift` — «Вернуть стандартный цвет».
- `App/SplashView.swift` — без тени и rounded-шрифта.
- `scripts/test_flat_design.py` — **подключён в `.github/workflows/ios.yml`** (раньше не запускался: поэтому папки и разошлись с контрактами).
- `scripts/test_motion_performance.py`, `scripts/test_update_20261025.py` — указатели на `FolderViews.swift` после переноса.

**БД/API/стейт:** без изменений. Тир-листы (`TierListView/Sheets/Store`) и плеер (Kodik/AVPlayer) не тронуты функционально — только визуальные правки.

**Фиксы по пути:**
- Восстановлен удалённый `FolderViews.swift` (коммит `acc3675` удалил его, посчитав дубликатом `HomeView.swift`; на деле в `HomeView` оставались до-v4 копии).
- `Int(resume.fraction * 100)` в подписи продолжения падал на NaN — теперь клампится, как в `ProgressBar`.
- `ProgressBar`/`ContinueWatchingCard` защищены от NaN и нефинитной ширины.
- В `CatalogView` убран хардкод `Color.white` (пропадал в светлой теме).

**Нюансы:** `test_flat_design.py` теперь в CI — палитра, градиенты и материалы проверяются на каждом пуше. Проверки локально: `python3 scripts/check_project.py` + все `scripts/test_*.py` — 0 ошибок. Swift локально не компилируется (Windows), сборка — через `ios.yml`.

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
