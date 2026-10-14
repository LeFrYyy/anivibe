import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AnivibeCore

struct HomeView: View {
    let openCatalog: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(LibraryStore.self) private var library
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
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { openedFolder = id }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Собирайте аниме в папки — как приложения на экране «Домой».")
            }
            .navigationDestination(for: Anime.self) { AnimeDetailsView(anime: $0) }
            .navigationDestination(for: AnimeSnapshot.self) { AnimeDetailsView(snapshot: $0) }
            .refreshable {
                await model.load(catalog: env.catalog, force: true)
                await model.loadRecentEpisodes(catalog: env.catalog)
            }
            .onChange(of: env.collections.activeAccountID) { _, _ in
                openedFolder = nil; path = NavigationPath(); editingFolders = false; draggedFolder = nil
                showNewFolder = false; deleteFolderID = nil
            }
            .task { await model.load(catalog: env.catalog) }
            .task { await model.loadRecentEpisodes(catalog: env.catalog) }
            .task(id: library.continueWatching.first?.anime.id) {
                await model.loadRecommendations(catalog: env.catalog, basedOn: library.continueWatching.first)
            }
        }
        .overlay {
            if let id = openedFolder {
                FolderOverlay(collectionID: id, close: closeFolder) { anime in
                    closeFolder()
                    path.append(anime)
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.86)),
                        removal: .opacity.combined(with: .scale(scale: 0.92))
                    )
                )
                .zIndex(100)
            }
        }
        .confirmationDialog("Удалить папку?", isPresented: Binding(get: { deleteFolderID != nil }, set: { if !$0 { deleteFolderID = nil } }), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { if let id = deleteFolderID { env.collections.delete(id) }; deleteFolderID = nil }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: openedFolder)
    }

    private func closeFolder() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { openedFolder = nil }
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
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { openedFolder = folder.id }
                        } label: {
                            FolderTile(collection: folder)
                        }
                        .buttonStyle(FolderPressStyle())
                        .scaleEffect(draggedFolder == folder.id.uuidString ? 1.05 : 1)
                        .onDrag {
                            editingFolders = true; draggedFolder = folder.id.uuidString
                            return NSItemProvider(object: folder.id.uuidString as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: CollectionDropDelegate(targetID: folder.id.uuidString, draggedID: $draggedFolder) { from, to in
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
                                           subtitle: item.resume.isNextEpisode ? "Далее: серия \(item.resume.episode)" : "Серия \(item.resume.episode) · \(Int(item.resume.fraction * 100))%",
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
    var size: CGFloat = 104

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            ZStack {
                FolderBackground(cornerRadius: size * 0.25)
                let cell = (size - 14 * 2 - 6 * 2) / 3
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 6), count: 3), spacing: 6) {
                    ForEach(0..<9, id: \.self) { index in
                        if index < collection.items.count {
                            PosterImage(url: collection.items[index].coverURL, cornerRadius: cell * 0.24)
                                .frame(width: cell, height: cell)
                                .clipShape(RoundedRectangle(cornerRadius: cell * 0.24, style: .continuous))
                                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        } else {
                            RoundedRectangle(cornerRadius: cell * 0.24, style: .continuous)
                                .fill(.white.opacity(0.08))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
                .padding(14)
            }
            .frame(width: size, height: size)

            VStack(spacing: 1) {
                Text(collection.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
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

/// Фон папки: матовое стекло с лёгким фирменным переливом и бликом по краю.
struct FolderBackground: View {
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay(
                shape.fill(LinearGradient(colors: [Theme.accent.opacity(0.32), Theme.secondaryAccent.opacity(0.16)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.08)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            .shadow(color: Theme.accent.opacity(0.2), radius: 14, y: 4)
    }
}

/// Плитка «Новая папка» в конце ряда.
struct NewFolderTile: View {
    var isFirst: Bool
    var size: CGFloat = 104

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .background(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(Theme.accent.opacity(0.06)))
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

/// Открытая папка: размытый фон, крупное название, сетка обложек, «+» и режим правки.
struct FolderOverlay: View {
    @Environment(AppEnvironment.self) private var env
    let collectionID: UUID
    let close: () -> Void
    let open: (AnimeSnapshot) -> Void

    @State private var name = ""
    @State private var editing = false
    @State private var draggedItem: String?
    @State private var showSearch = false
    @State private var confirmDelete = false
    @State private var isVisible = false
    @FocusState private var nameFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.m), count: 3)

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.35))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { finish() }

            if let collection = env.collections.collection(collectionID) {
                VStack(spacing: Theme.Spacing.l) {
                    TextField("Название папки", text: $name)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { env.collections.rename(collectionID, to: name) }
                        .padding(.horizontal, Theme.Spacing.xl)
                        .opacity(isVisible ? 1 : 0)
                        .offset(y: isVisible ? 0 : -8)

                    panel(collection)
                        .scaleEffect(isVisible ? 1.0 : 0.93)
                        .opacity(isVisible ? 1 : 0)

                    HStack(spacing: Theme.Spacing.m) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { editing.toggle() }
                        } label: {
                            Label(editing ? "Готово" : "Изменить", systemImage: editing ? "checkmark" : "pencil")
                        }
                        .buttonStyle(GlassCapsuleStyle())
                        Button { showSearch = true } label: {
                            Label("Добавить", systemImage: "plus")
                        }
                        .buttonStyle(GlassCapsuleStyle(prominent: true))
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(GlassCapsuleStyle())
                        .accessibilityLabel("Удалить папку")
                    }
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 8)
                }
                .padding(.horizontal, Theme.Spacing.l)
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            name = env.collections.collection(collectionID)?.name ?? ""
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                isVisible = true
            }
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

    private func finish() {
        if nameFocused { nameFocused = false }
        env.collections.rename(collectionID, to: name)
        close()
    }

    private func panel(_ collection: AnimeCollection) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                ForEach(Array(collection.items.enumerated()), id: \.element.id) { index, anime in
                    FolderItemView(anime: anime, index: index, editing: editing) {
                        if editing { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        env.collections.rename(collectionID, to: name)
                        open(anime)
                    } remove: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            env.collections.remove(anime.id, from: collectionID)
                        }
                    }
                    .onDrag {
                        editing = true; draggedItem = String(anime.id)
                        return NSItemProvider(object: String(anime.id) as NSString)
                    }
                    .onDrop(of: [UTType.text], delegate: CollectionDropDelegate(targetID: String(anime.id), draggedID: $draggedItem) { from, to in
                        if let source = Int(from), let target = Int(to) { env.collections.reorderItem(source, in: collectionID, to: target) }
                    })
                }
                Button { showSearch = true } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                            .aspectRatio(Theme.posterAspect, contentMode: .fit)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        Text("Добавить")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .buttonStyle(FolderPressStyle())
                .accessibilityLabel("Добавить аниме через поиск")
            }
            .padding(Theme.Spacing.l)
        }
        .frame(maxHeight: 460)
        .fixedSize(horizontal: false, vertical: collection.items.count < 4)
        .background(FolderBackground(cornerRadius: 34))
    }
}

/// Обложка внутри открытой папки; в режиме правки «дрожит» и показывает кнопку удаления.
struct FolderItemView: View {
    let anime: AnimeSnapshot
    let index: Int
    let editing: Bool
    let tap: () -> Void
    let remove: () -> Void

    @State private var wiggle = false

    private var wiggleAngle: Double {
        guard editing else { return 0 }
        let direction: Double = index.isMultiple(of: 2) ? 1 : -1
        return (wiggle ? 1.6 : -1.6) * direction
    }

    var body: some View {
        Button(action: tap) {
            VStack(spacing: 6) {
                PosterImage(url: anime.coverURL, cornerRadius: 14)
                    .aspectRatio(Theme.posterAspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                Text(anime.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
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
                        .foregroundStyle(.black)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white))
                        .shadow(radius: 2)
                }
                .offset(x: -8, y: -8)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Убрать «\(anime.title)» из папки")
            }
        }
        .rotationEffect(.degrees(wiggleAngle))
        .onChange(of: editing) { _, isEditing in
            if isEditing {
                withAnimation(.easeInOut(duration: 0.14).repeatForever(autoreverses: true)) { wiggle = true }
            } else {
                withAnimation(.easeOut(duration: 0.1)) { wiggle = false }
            }
        }
        .contextMenu {
            Button(role: .destructive, action: remove) { Label("Убрать из папки", systemImage: "folder.badge.minus") }
        }
    }
}

/// Капсульные «стеклянные» кнопки под открытой папкой.
struct GlassCapsuleStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background {
                if prominent {
                    Capsule().fill(LinearGradient(colors: [Theme.accent, Theme.secondaryAccent],
                                                  startPoint: .leading, endPoint: .trailing))
                        .shadow(color: Theme.accent.opacity(0.4), radius: 8, y: 3)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

/// Поиск по каталогу для добавления аниме в папку. Без запроса — популярное.
struct AddToFolderSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let collectionID: UUID

    @State private var query = ""
    @State private var results: [Anime] = []
    @State private var isLoading = false
    @State private var errorText: String?

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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(added ? "Убрать «\(anime.title.preferred)» из папки" : "Добавить «\(anime.title.preferred)» в папку")
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            // Небольшая пауза: не дёргаем каталог на каждую букву.
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await env.catalog.search(CatalogQuery(search: text, perPage: 30))
            guard !Task.isCancelled else { return }
            results = page.items
            errorText = page.items.isEmpty ? "Ничего не нашлось" : nil
        } catch {
            if !Task.isCancelled { errorText = "Не удалось выполнить поиск. Потяните, чтобы повторить." }
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
