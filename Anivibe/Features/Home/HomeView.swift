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
                    if let error = env.collections.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(Theme.danger).padding(.horizontal, 16)
                    }
                    foldersSection
                    continueSection
                    recentEpisodesSection
                    mangaSection
                    feedSections
                    favoritesSection
                    catalogShortcut
                }
                .padding(.vertical, Theme.Spacing.l)
            }
            .screenBackground()
            .navigationTitle("Anivibe")
            .toolbar {
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
            .navigationDestination(for: MangaLink.self) { MangaDetailsView(link: $0) }
            .refreshable {
                async let feed: Void = model.load(catalog: env.catalog, force: true)
                async let recent: Void = model.loadRecentEpisodes(catalog: env.catalog, force: true)
                _ = await (feed, recent)
            }
            .onChange(of: env.collections.activeAccountID) { _, _ in
                openedFolder = nil; path = NavigationPath(); editingFolders = false; draggedFolder = nil
                showNewFolder = false; deleteFolderID = nil
            }
            .task { await model.load(catalog: env.catalog) }
            .task { await model.loadRecentEpisodes(catalog: env.catalog) }
            .task(id: env.settings.mangaExperimentalEnabled) {
                await model.loadManga(service: env.manga, enabled: env.settings.mangaExperimentalEnabled)
            }
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
        if !library.continueWatching.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "Продолжить просмотр")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(library.continueWatching) { item in
                            NavigationLink(value: item.anime) {
                                PosterCard(title: item.anime.title, coverURL: item.anime.coverURL,
                                           subtitle: item.resume.isFinishedSourceEpisode ? "Серия \(item.resume.episode) просмотрена" :
                                               (item.resume.isNextEpisode ? "Далее: серия \(item.resume.episode)" : "Серия \(item.resume.episode) · \(Int(item.resume.fraction * 100))%"),
                                           progress: item.resume.isNextEpisode ? nil : item.resume.fraction)
                                .frame(width: 130)
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

    @ViewBuilder private var recentEpisodesSection: some View {
        if !model.recentEpisodes.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    SectionHeader(title: "Недавно вышедшие")
                    Spacer()
                    NavigationLink {
                        RecentEpisodesView(items: model.recentEpisodes)
                    } label: {
                        Text("Все").font(.subheadline.weight(.medium))
                    }
                    .padding(.trailing, Theme.Spacing.l)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(model.recentEpisodes.prefix(20)) { item in
                            NavigationLink(value: item.anime) {
                                PosterCard(title: item.anime.title.preferred, coverURL: item.anime.coverURL,
                                           colorHex: item.anime.coverColorHex,
                                           subtitle: "Серия \(item.episode) · \(RecentEpisodesView.relative(item.airedAt))")
                                    .frame(width: 120)
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

    @ViewBuilder private var mangaSection: some View {
        let manga = model.mangaRow
        if env.settings.mangaExperimentalEnabled, !manga.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "Популярная манга")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(manga) { entry in
                            NavigationLink(value: MangaLink(entry)) {
                                PosterCard(title: entry.title.preferred, coverURL: entry.coverURL,
                                           subtitle: entry.metaLine, badge: "Манга")
                                .frame(width: 120)
                            }
                            .buttonStyle(PosterPressStyle())
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
                                PosterCard(title: entry.anime.title, coverURL: entry.anime.coverURL).frame(width: 120)
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
            HStack {
                Image(systemName: "square.grid.2x2")
                Text("Открыть каталог").fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.Spacing.l)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        }
        .buttonStyle(PosterPressStyle())
        .padding(.horizontal, Theme.Spacing.l)
    }
}

struct PosterRow: View {
    let title: String
    var subtitle: String?
    let items: [Anime]

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
                                PosterCard(anime: anime).frame(width: 120)
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
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
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
        .navigationTitle("Недавно вышедшие")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Папки (как папки приложений в iOS)

/// Плитка папки: «стеклянный» скруглённый квадрат с мини-обложками 3×3.
struct FolderTile: View {
    let collection: AnimeCollection
    var size: CGFloat = Theme.Folder.tileSize

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            ZStack {
                FolderBackground(cornerRadius: Theme.Folder.tileRadius)
                let cell = (size - Theme.Folder.tileInset * 2 - Theme.Folder.slotSpacing * 2) / 3
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: Theme.Folder.slotSpacing), count: 3), spacing: Theme.Folder.slotSpacing) {
                    ForEach(0..<9, id: \.self) { index in
                        if index < collection.items.count {
                            PosterImage(url: collection.items[index].coverURL, cornerRadius: Theme.Folder.slotRadius)
                                .frame(width: cell, height: cell)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Folder.slotRadius, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: Theme.Folder.slotRadius, style: .continuous)
                                .fill(Theme.Folder.placeholder)
                                .frame(width: cell, height: cell)
                        }
                    }
                }
                .padding(Theme.Folder.tileInset)
            }
            .frame(width: size, height: size)

            VStack(spacing: 1) {
                Text(collection.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(Self.countLabel(collection.items.count))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(width: size + 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Папка «\(collection.name)», \(Self.countLabel(collection.items.count))")
    }

    static func countLabel(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        let word: String
        if mod10 == 1 && mod100 != 11 { word = "тайтл" }
        else if (2...4).contains(mod10) && !(12...14).contains(mod100) { word = "тайтла" }
        else { word = "тайтлов" }
        return n == 0 ? "Пусто" : "\(n) \(word)"
    }
}

/// Сплошная поверхность папки с тонкой адаптивной границей.
struct FolderBackground: View {
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.Folder.background)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.Folder.border, lineWidth: Theme.Folder.borderWidth)
            }
    }
}

/// Плитка «Новая папка» в конце ряда.
struct NewFolderTile: View {
    var isFirst: Bool
    var size: CGFloat = Theme.Folder.tileSize

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            RoundedRectangle(cornerRadius: Theme.Folder.tileRadius, style: .continuous)
                .strokeBorder(Theme.Folder.border, lineWidth: Theme.Folder.borderWidth)
                .background(RoundedRectangle(cornerRadius: Theme.Folder.tileRadius, style: .continuous).fill(Theme.Folder.background))
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: size, height: size)
            VStack(spacing: 1) {
                Text("Новая папка")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(isFirst ? "Соберите свою" : " ")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(width: size + 8)
        }
    }
}

/// Пружинистое нажатие, как у иконок на «Домой».
struct FolderPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(AppMotion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

private struct FolderBackdrop: View {
    let close: () -> Void

    var body: some View {
        Rectangle()
            .fill(Theme.Folder.scrim)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: close)
            .accessibilityHidden(true)
    }
}

/// Flat, theme-aware folder panel with a height limited by the available screen.
struct FolderOverlay: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let collectionID: UUID
    let close: () -> Void
    let open: (AnimeSnapshot) -> Void

    @State private var name = ""
    @State private var editing = false
    @State private var draggedItem: String?
    @State private var showSearch = false
    @State private var confirmDelete = false
    @State private var presentedAccountID: String?
    @FocusState private var nameFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.m), count: 3)

    var body: some View {
        GeometryReader { geometry in
            let panelHeight = min(Theme.Folder.panelMaxHeight, max(96, geometry.size.height - 180))
            ZStack {
                if let collection = env.collections.collection(collectionID) {
                    VStack(spacing: Theme.Spacing.l) {
                        TextField("Название папки", text: $name)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.textPrimary)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit { commitName() }
                            .padding(.horizontal, Theme.Spacing.xl)
                        panel(collection, maxHeight: panelHeight)

                        HStack(spacing: Theme.Spacing.m) {
                            Button {
                                withAnimation(AppMotion.selection(reduceMotion: reduceMotion)) {
                                    editing.toggle()
                                    draggedItem = nil
                                }
                            } label: {
                                Label(editing ? "Готово" : "Изменить", systemImage: editing ? "checkmark" : "pencil")
                            }
                            .buttonStyle(FolderCapsuleButtonStyle())
                            Button { showSearch = true } label: {
                                Label("Добавить", systemImage: "plus")
                            }
                            .buttonStyle(FolderCapsuleButtonStyle(prominent: true))
                            Button(role: .destructive) { confirmDelete = true } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(FolderCapsuleButtonStyle(destructive: true))
                            .accessibilityLabel("Удалить папку")
                        }
                    }
                    .padding(Theme.Spacing.l)
                    .frame(maxWidth: Theme.Folder.panelMaxWidth)
                    .background(FolderBackground(cornerRadius: Theme.Folder.panelRadius))
                }
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .onAppear {
            presentedAccountID = env.collections.activeAccountID
            name = env.collections.collection(collectionID)?.name ?? ""
        }
        .onDisappear {
            // A backdrop tap also commits the name, but never to a different account.
            commitName()
        }
        .sheet(isPresented: $showSearch) {
            AddToFolderSheet(collectionID: collectionID)
        }
        .confirmationDialog("Удалить папку «\(name)»?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить папку", role: .destructive) {
                close()
                env.collections.delete(collectionID)
            }
        } message: {
            Text("Сами аниме останутся в каталоге и библиотеке.")
        }
    }

    private func commitName() {
        guard env.collections.activeAccountID == presentedAccountID,
              let collection = env.collections.collection(collectionID) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Clearing the field is not a request to discard the existing name.
        if trimmed.isEmpty { name = collection.name }
        else { env.collections.rename(collectionID, to: trimmed) }
    }

    private func panel(_ collection: AnimeCollection, maxHeight: CGFloat) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                ForEach(Array(collection.items.enumerated()), id: \.element.id) { index, anime in
                    FolderItemView(anime: anime, index: index, editing: editing) {
                        if editing { return }
                        commitName()
                        open(anime)
                    } remove: {
                        withAnimation(AppMotion.selection(reduceMotion: reduceMotion)) {
                            env.collections.remove(anime.id, from: collectionID)
                        }
                    }
                    .onDrag {
                        editing = true; draggedItem = String(anime.id)
                        return NSItemProvider(object: String(anime.id) as NSString)
                    }
                    .onDrop(of: [UTType.text], delegate: CollectionDropDelegate(targetID: String(anime.id), draggedID: $draggedItem, reduceMotion: reduceMotion) { from, to in
                        if let source = Int(from), let target = Int(to) { env.collections.reorderItem(source, in: collectionID, to: target) }
                    })
                }
                Button { showSearch = true } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: Theme.Folder.posterRadius, style: .continuous)
                            .strokeBorder(Theme.Folder.border, lineWidth: Theme.Folder.borderWidth)
                            .aspectRatio(Theme.posterAspect, contentMode: .fit)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        Text("Добавить")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .buttonStyle(FolderPressStyle())
                .accessibilityLabel("Добавить аниме через поиск")
            }
            .padding(Theme.Spacing.l)
        }
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: collection.items.count < 4)
        .background(FolderBackground(cornerRadius: Theme.Folder.posterRadius))
    }
}

/// Edit mode is a quiet, static tilt with a remove button, not an endless wiggle.
struct FolderItemView: View {
    let anime: AnimeSnapshot
    let index: Int
    let editing: Bool
    let tap: () -> Void
    let remove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var editAngle: Double {
        guard editing, !reduceMotion else { return 0 }
        let direction: Double = index.isMultiple(of: 2) ? 1 : -1
        return 0.7 * direction
    }

    var body: some View {
        Button(action: tap) {
            VStack(spacing: 6) {
                PosterImage(url: anime.coverURL, cornerRadius: Theme.Folder.posterRadius)
                    .aspectRatio(Theme.posterAspect, contentMode: .fit)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Folder.posterRadius, style: .continuous)
                            .strokeBorder(Theme.Folder.border, lineWidth: Theme.Folder.borderWidth)
                    }
                Text(anime.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(FolderPressStyle())
        .overlay(alignment: .topLeading) {
            if editing {
                Button(action: remove) {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.accent))
                        .padding(10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: -18, y: -18)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Убрать «\(anime.title)» из папки")
            }
        }
        .rotationEffect(.degrees(editAngle))
        .animation(AppMotion.press(reduceMotion: reduceMotion), value: editing)
        .contextMenu {
            Button(role: .destructive, action: remove) { Label("Убрать из папки", systemImage: "folder.badge.minus") }
        }
    }
}

/// Solid capsule buttons; one accent and a semantic destructive color.
struct FolderCapsuleButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Theme.onAccent : (destructive ? Theme.danger : Theme.textPrimary))
            .padding(.horizontal, Theme.Spacing.l)
            .frame(minHeight: 44)
            .background(Capsule().fill(prominent ? Theme.accent : Theme.Folder.placeholder))
            .overlay(Capsule().strokeBorder(Theme.Folder.border, lineWidth: prominent ? 0 : Theme.Folder.borderWidth))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(AppMotion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// Поиск по каталогу для добавления аниме в папку. Без запроса — популярное.
struct AddToFolderSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let collectionID: UUID

    @State private var query = ""
    @State private var results: [Anime] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var searchRequestID = UUID()

    private var folderName: String { env.collections.collection(collectionID)?.name ?? "папку" }

    var body: some View {
        NavigationStack {
            List {
                if let errorText {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(results) { anime in
                    row(anime)
                }
            }
            .listStyle(.plain)
            .overlay {
                if isLoading && results.isEmpty { ProgressView() }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Найти аниме")
            .autocorrectionDisabled()
            .task(id: query) { await search() }
            .refreshable { await search(debounce: false) }
            .navigationTitle("В «\(folderName)»")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func row(_ anime: Anime) -> some View {
        let added = env.collections.collection(collectionID)?.contains(anime.id) ?? false
        return Button {
            withAnimation(AppMotion.selection(reduceMotion: reduceMotion)) {
                env.collections.toggle(anime.snapshot, in: collectionID)
            }
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                PosterImage(url: anime.coverURL, placeholderColorHex: anime.coverColorHex, cornerRadius: 6)
                    .frame(width: 44, height: 44 / Theme.posterAspect)
                VStack(alignment: .leading, spacing: 3) {
                    Text(anime.title.preferred)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if let year = anime.year {
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(added ? Theme.success : Theme.accent)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(added ? "Убрать «\(anime.title.preferred)» из папки" : "Добавить «\(anime.title.preferred)» в папку")
    }

    @MainActor private func search(debounce: Bool = true) async {
        let requestID = UUID()
        searchRequestID = requestID
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if debounce && !text.isEmpty {
            // Небольшая пауза: не дёргаем каталог на каждую букву.
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
        }
        guard !Task.isCancelled, searchRequestID == requestID else { return }
        isLoading = true
        defer { if searchRequestID == requestID { isLoading = false } }
        do {
            let page = try await env.catalog.search(CatalogQuery(search: text, perPage: 30))
            guard !Task.isCancelled, searchRequestID == requestID else { return }
            results = page.items
            errorText = page.items.isEmpty ? "Ничего не нашлось" : nil
        } catch {
            if !Task.isCancelled, searchRequestID == requestID {
                errorText = "Не удалось выполнить поиск. Потяните, чтобы повторить."
            }
        }
    }
}

/// Долгое нажатие на любую обложку → «В папку» (добавить/убрать, создать новую).
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
