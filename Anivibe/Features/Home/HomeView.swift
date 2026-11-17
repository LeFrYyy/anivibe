import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AnivibeCore

struct HomeView: View {
    let openCatalog: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(LibraryStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = HomeViewModel()
    @State private var path = NavigationPath()
    @State private var openedFolder: UUID?
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var editingFolders = false
    @State private var draggedFolder: String?
    @State private var deleteFolderID: UUID?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if env.catalog.isDemo {
                        DemoBanner()
                    }
                    if env.settings.foldersEnabled, let error = env.collections.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(Theme.danger).padding(.horizontal, 16)
                    }
                    if env.settings.foldersEnabled { foldersSection }
                    continueSection
                    recentEpisodesSection
                    feedSections
                    favoritesSection
                    catalogShortcut
                }
                .padding(.vertical, Theme.Spacing.l)
            }
            .screenBackground()
            .navigationTitle("Anivibe")
            .toolbar {
                if env.settings.foldersEnabled {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            newFolderName = ""
                            showNewFolder = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.body.weight(.semibold))
                        }
                        .accessibilityLabel("Создать папку")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openCatalog) {
                        Image(systemName: "magnifyingglass")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Поиск в каталоге")
                }
            }
            .alert("Новая папка", isPresented: $showNewFolder) {
                TextField("Название", text: $newFolderName)
                Button("Создать") {
                    let id = env.collections.create(name: newFolderName)
                    guard env.collections.collection(id) != nil else { return }
                    openedFolder = id
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Собирайте аниме в папки — как приложения на экране «Домой».")
            }
            .navigationDestination(for: Anime.self) { AnimeDetailsView(anime: $0) }
            .navigationDestination(for: AnimeSnapshot.self) { AnimeDetailsView(snapshot: $0) }
            .refreshable {
                async let feed: Void = model.load(catalog: env.catalog, force: true)
                async let recent: Void = model.loadRecentEpisodes(catalog: env.catalog, force: true)
                _ = await (feed, recent)
            }
            .onChange(of: env.collections.activeAccountID) { _, _ in
                openedFolder = nil; path = NavigationPath(); editingFolders = false; draggedFolder = nil
                showNewFolder = false; deleteFolderID = nil
            }
            .onChange(of: env.settings.foldersEnabled) { _, enabled in
                guard !enabled else { return }
                openedFolder = nil; editingFolders = false; draggedFolder = nil
                showNewFolder = false; deleteFolderID = nil
            }
            .task { await model.load(catalog: env.catalog) }
            .task { await model.loadRecentEpisodes(catalog: env.catalog) }
            .task(id: library.continueWatching.first?.anime.id) {
                await model.loadRecommendations(catalog: env.catalog, basedOn: library.continueWatching.first)
            }
        }
        .allowsHitTesting(openedFolder == nil)
        .accessibilityHidden(openedFolder != nil)
        .overlay {
            // The backdrop only fades; only the panel moves. Scaling the material
            // together with the grid caused a double zoom and unnecessary compositing.
            ZStack {
                if let id = openedFolder {
                    FolderBackdrop(close: closeFolder)
                        .transition(.opacity)
                    FolderOverlay(collectionID: id, close: closeFolder) { anime in
                        closeFolder()
                        path.append(anime)
                    }
                    .id(id)
                    .transition(AppMotion.panelTransition(reduceMotion: reduceMotion))
                    .zIndex(1)
                }
            }
            .animation(AppMotion.panel(reduceMotion: reduceMotion), value: openedFolder)
            .allowsHitTesting(openedFolder != nil)
        }
        .confirmationDialog("Удалить папку?", isPresented: Binding(get: { deleteFolderID != nil }, set: { if !$0 { deleteFolderID = nil } }), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { if let id = deleteFolderID { env.collections.delete(id) }; deleteFolderID = nil }
        }
    }

    private func closeFolder() {
        openedFolder = nil
    }

    // MARK: Папки

    @ViewBuilder private var foldersSection: some View {
        let folders = env.collections.collections
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                SectionHeader(title: "Мои папки")
                Spacer()
                if editingFolders { Button("Готово") { editingFolders = false; draggedFolder = nil }.padding(.trailing, Theme.Spacing.l) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Spacing.l) {
                    ForEach(folders) { folder in
                        Button {
                            guard !editingFolders else { return }
                            openedFolder = folder.id
                        } label: {
                            FolderTile(collection: folder)
                        }
                        .buttonStyle(FolderPressStyle())
                        .scaleEffect(!reduceMotion && draggedFolder == folder.id.uuidString ? 1.03 : 1)
                        .animation(AppMotion.press(reduceMotion: reduceMotion), value: draggedFolder)
                        .onDrag {
                            editingFolders = true; draggedFolder = folder.id.uuidString
                            return NSItemProvider(object: folder.id.uuidString as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: CollectionDropDelegate(targetID: folder.id.uuidString, draggedID: $draggedFolder, reduceMotion: reduceMotion) { from, to in
                            if let source = UUID(uuidString: from), let target = UUID(uuidString: to) { env.collections.reorder(source, to: target) }
                        })
                        .contextMenu {
                            Button("Переставить папки") { editingFolders = true }
                            Button { openedFolder = folder.id } label: { Label("Открыть", systemImage: "folder") }
                            Button(role: .destructive) { deleteFolderID = folder.id } label: {
                                Label("Удалить папку", systemImage: "trash")
                            }
                        }
                    }
                    Button {
                        newFolderName = ""
                        showNewFolder = true
                    } label: {
                        NewFolderTile(isFirst: folders.isEmpty)
                    }
                    .buttonStyle(FolderPressStyle())
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder private var continueSection: some View {
        if let item = library.continueWatching.first {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: library.continueWatching.count > 1 ? "Продолжить просмотр" : "Смотреть дальше")
                ContinueWatchingCard(
                    title: item.anime.title,
                    subtitle: continueSubtitle(item.resume),
                    artworkURL: item.anime.coverURL,
                    progress: item.resume.isNextEpisode ? nil : item.resume.fraction
                ) { path.append(item.anime) }
                .folderMenu(item.anime)
                .padding(.horizontal, Theme.Spacing.l)

                if library.continueWatching.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                            ForEach(library.continueWatching.dropFirst()) { item in
                                NavigationLink(value: item.anime) {
                                    PosterCard(title: item.anime.title, coverURL: item.anime.coverURL,
                                               subtitle: continueSubtitle(item.resume),
                                               progress: item.resume.isNextEpisode ? nil : item.resume.fraction)
                                    .frame(width: 124)
                                }
                                .buttonStyle(PosterPressStyle())
                                .folderMenu(item.anime)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.l)
                    }
                }
            }
        }
    }

    private func continueSubtitle(_ resume: ResumePoint) -> String {
        if resume.isFinishedSourceEpisode { return "Серия \(resume.episode) просмотрена" }
        if resume.isNextEpisode { return "Далее: серия \(resume.episode)" }
        return "Серия \(resume.episode) · \(Int(resume.fraction * 100))%"
    }

    @ViewBuilder private var recentEpisodesSection: some View {
        if !model.recentEpisodes.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeaderLink(title: "Недавно вышедшие") {
                    RecentEpisodesView(items: model.recentEpisodes)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(model.recentEpisodes.prefix(50)) { item in
                            NavigationLink(value: item.anime) {
                                PosterCard(title: item.anime.title.preferred, coverURL: item.anime.coverURL,
                                           colorHex: item.anime.coverColorHex,
                                           subtitle: "Серия \(item.episode) · \(RecentEpisodesView.relative(item.airedAt))")
                                    .frame(width: 124)
                            }
                            .buttonStyle(PosterPressStyle())
                            .folderMenu(item.anime.snapshot)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                }
            }
        }
    }

    @ViewBuilder private var feedSections: some View {
        switch model.state {
        case .idle, .loading:
            ForEach(["Популярное", "Новинки сезона"], id: \.self) { title in
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader(title: title)
                    PosterRowSkeleton()
                }
            }
        case .failed(let message):
            ErrorStateView(message: message) { Task { await model.load(catalog: env.catalog, force: true) } }
        case .loaded(let feed):
            PosterRow(title: "Популярное", items: feed.popular)
            PosterRow(title: "Новинки · \(feed.seasonLabel)", items: feed.seasonal)
            if !model.recommendations.isEmpty, let basis = model.recommendationsBasis {
                PosterRow(title: "Рекомендации", subtitle: "Похоже на «\(basis)»", items: model.recommendations)
            } else {
                PosterRow(title: "Рекомендации", subtitle: "Сейчас в тренде", items: feed.trending)
            }
            PosterRow(title: "Недавно добавленные", items: feed.recentlyAdded)
        }
    }

    @ViewBuilder private var favoritesSection: some View {
        let favorites = library.snapshot.favorites
        if !favorites.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "Избранное")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(favorites) { entry in
                            NavigationLink(value: entry.anime) {
                                PosterCard(title: entry.anime.title, coverURL: entry.anime.coverURL)
                                    .frame(width: PosterCard.standardWidth)
                            }
                            .buttonStyle(PosterPressStyle())
                            .folderMenu(entry.anime)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                }
            }
        }
    }

    private var catalogShortcut: some View {
        Button(action: openCatalog) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "square.grid.2x2")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text("Открыть каталог").fontWeight(.semibold).foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.Spacing.l)
            .frame(minHeight: 44)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            }
        }
        .buttonStyle(PosterPressStyle())
        .padding(.horizontal, Theme.Spacing.l)
    }
}

struct PosterRow: View {
    let title: String
    var subtitle: String?
    let items: [Anime]
    /// Один шаг размера карточки на все ряды — сетка экрана читается ровно.
    var cardWidth: CGFloat = PosterCard.standardWidth

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionHeader(title: title)
                    if let subtitle {
                        Text(subtitle).font(.footnote).foregroundStyle(Theme.textSecondary).padding(.horizontal, Theme.Spacing.l)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(items) { anime in
                            NavigationLink(value: anime) {
                                PosterCard(anime: anime).frame(width: cardWidth)
                            }
                            .buttonStyle(PosterPressStyle())
                            .folderMenu(anime.snapshot)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                }
            }
        }
    }
}

struct DemoBanner: View {
    var body: some View {
        Label("Демо-каталог: вымышленные данные режима разработки", systemImage: "hammer")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.secondaryAccent)
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            }
            .padding(.horizontal, Theme.Spacing.l)
    }
}

/// Полный список недавно вышедших серий.
struct RecentEpisodesView: View {
    let items: [AiredEpisode]

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.unitsStyle = .short
        return f
    }()

    static func relative(_ date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyStateView(systemImage: "sparkles.tv", title: "Пока пусто",
                               message: "За последние 7 дней новых серий не найдено.")
            } else {
                List(items) { item in
                    NavigationLink(value: item.anime) {
                        HStack(spacing: Theme.Spacing.m) {
                            PosterImage(url: item.anime.coverURL, placeholderColorHex: item.anime.coverColorHex)
                                .frame(width: 50, height: 50 / Theme.posterAspect)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.anime.title.preferred)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2)
                                Text("Серия \(item.episode)")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.accent)
                                Text(Self.relative(item.airedAt))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Недавно вышедшие · 7 дней")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Меню «В папку»
struct FolderMenuModifier: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    let anime: AnimeSnapshot

    @State private var askName = false
    @State private var newName = ""

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Menu {
                    ForEach(env.collections.collections) { folder in
                        Button {
                            env.collections.toggle(anime, in: folder.id)
                        } label: {
                            if folder.contains(anime.id) {
                                Label(folder.name, systemImage: "checkmark")
                            } else {
                                Label(folder.name, systemImage: "folder")
                            }
                        }
                    }
                    if !env.collections.collections.isEmpty { Divider() }
                    Button {
                        newName = ""
                        askName = true
                    } label: {
                        Label("Новая папка…", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("В папку", systemImage: "folder")
                }
            }
            .alert("Новая папка", isPresented: $askName) {
                TextField("Название", text: $newName)
                Button("Создать") { _ = env.collections.create(name: newName, with: anime) }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("«\(anime.title)» сразу окажется в ней.")
            }
    }
}

extension View {
    /// Добавляет в контекстное меню обложки пункт «В папку».
    func folderMenu(_ anime: AnimeSnapshot) -> some View {
        modifier(FolderMenuModifier(anime: anime))
    }
}
