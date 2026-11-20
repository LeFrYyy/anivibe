import SwiftUI
import AnivibeCore

enum LibrarySection: Hashable, CaseIterable, Identifiable {
    case all, list(LibraryStatus), favorites, history

    static var allCases: [LibrarySection] {
        [.all, .list(.watching), .list(.completed), .list(.planned), .list(.onHold), .list(.dropped), .favorites, .history]
    }

    var id: String {
        switch self {
        case .all: return "all"
        case .list(let s): return s.rawValue
        case .favorites: return "favorites"
        case .history: return "history"
        }
    }

    var title: String {
        switch self {
        case .all: return "Все"
        case .list(let s): return s.localizedName
        case .favorites: return "Избранное"
        case .history: return "История"
        }
    }
}

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace
    @State private var section: LibrarySection = .list(.watching)
    @State private var confirmClear = false
    @State private var undoMessage: String?
    @State private var undoRestore: (() async -> Void)?
    @State private var undoTicket = 0

    private let embedded: Bool
    /// Переход в каталог из пустого состояния. `nil` — кнопка не показывается.
    private let onOpenCatalog: (() -> Void)?

    init(initialSection: LibrarySection = .list(.watching), embedded: Bool = false,
         onOpenCatalog: (() -> Void)? = nil) {
        _section = State(initialValue: initialSection)
        self.embedded = embedded
        self.onOpenCatalog = onOpenCatalog
    }

    var body: some View {
        if embedded { libraryContent }
        else {
            NavigationStack {
                libraryContent
                    .navigationDestination(for: AnimeSnapshot.self) { AnimeDetailsView(snapshot: $0) }
                    .navigationDestination(for: Anime.self) { AnimeDetailsView(anime: $0) }
            }
        }
    }

    private var libraryContent: some View {
        let counts = sectionCounts
        return Group {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(LibrarySection.allCases) { s in
                            Button {
                                section = s
                            } label: {
                                Text("\(s.title) (\(counts[s, default: 0]))")
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 14).frame(minHeight: 44)
                                    .background {
                                        Capsule().fill(Theme.surfaceElevated)
                                        if section == s {
                                            Capsule().fill(Theme.accent)
                                                .matchedGeometryEffect(id: "library.selection", in: selectionNamespace)
                                        }
                                    }
                                    .foregroundStyle(section == s ? Theme.onAccent : Theme.textPrimary)
                            }
                            .buttonStyle(PosterPressStyle())
                            .accessibilityAddTraits(section == s ? .isSelected : [])
                        }
                    }
                    .animation(AppMotion.selection(reduceMotion: reduceMotion), value: section)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.s)
                }
                content
                    .animation(AppMotion.fade(reduceMotion: reduceMotion), value: section)
            }
            .refreshable { await library.refresh() }
            .screenBackground()
            .navigationTitle("Библиотека")
            // Лёгкий отклик на любую правку библиотеки: добавление, оценку,
            // избранное. Триггер — счётчик в сторе, поэтому вызывается один раз
            // на мутацию, а не из каждой кнопки.
            .sensoryFeedback(trigger: library.changeFeedback) { _, _ in
                library.lastChangeKind == .success ? .success : .impact(weight: .light)
            }
            .overlay(alignment: .bottom) {
                if let undoMessage {
                    UndoBanner(message: undoMessage) {
                        let restore = undoRestore
                        dismissUndo()
                        Task { await restore?() }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.bottom, Theme.Spacing.l)
                    .transition(AppMotion.panelTransition(reduceMotion: reduceMotion))
                }
            }
            .animation(AppMotion.panel(reduceMotion: reduceMotion), value: undoMessage)
            .toolbar {
                if section == .history && !library.snapshot.history.isEmpty {
                    Button("Очистить") { confirmClear = true }
                }
            }
            .confirmationDialog("Очистить историю просмотров?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Очистить", role: .destructive) { Task { await library.clearHistory() } }
            }
        }
    }

    /// One pass per body evaluation, not one full scan for every status chip.
    private var sectionCounts: [LibrarySection: Int] {
        var result: [LibrarySection: Int] = [.history: library.snapshot.history.count, .all: 0]
        for entry in library.snapshot.entries where !entry.isDeleted && !entry.isEmpty {
            result[.all, default: 0] += 1
            if let status = entry.status { result[.list(status), default: 0] += 1 }
            if entry.isFavorite { result[.favorites, default: 0] += 1 }
        }
        return result
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .all: entriesList(library.snapshot.allListEntries, for: .all)
        case .history: historyList
        case .favorites: entriesList(library.snapshot.favorites, for: .favorites)
        case .list(let status): entriesList(library.snapshot.entries(in: status), for: .list(status))
        }
    }

    private func emptyMeta(for section: LibrarySection) -> (icon: String, title: String, message: String) {
        switch section {
        case .all:
            return ("books.vertical", "Библиотека пуста", "Добавляйте тайтлы со страницы аниме — кнопки «В список» и «В избранное».")
        case .favorites:
            return ("heart", "В избранном пока пусто", "Нажмите на сердце на странице тайтла, чтобы сохранить его сюда.")
        case .history:
            return ("clock", "История пуста", "Здесь появятся просмотренные серии.")
        case .list(let status):
            switch status {
            case .watching:
                return (status.systemImage, "В «Смотрю» пока пусто", "Отмечайте тайтлы, которые смотрите сейчас.")
            case .completed:
                return (status.systemImage, "В «Просмотрено» пока пусто", "Завершённые аниме попадут в этот раздел.")
            case .planned:
                return (status.systemImage, "В «В планах» пока пусто", "Отложите сюда тайтлы, которые хотите посмотреть позже.")
            case .onHold:
                return (status.systemImage, "В «Отложено» пока пусто", "Пауза в просмотре — добавьте сюда поставленные на паузу тайтлы.")
            case .dropped:
                return (status.systemImage, "В «Брошено» пока пусто", "Сюда можно перенести тайтлы, которые вы решили не досматривать.")
            }
        }
    }

    @ViewBuilder private func entriesList(_ entries: [LibraryEntry], for currentSection: LibrarySection) -> some View {
        if entries.isEmpty {
            let empty = emptyMeta(for: currentSection)
            EmptyStateView(systemImage: empty.icon, title: empty.title, message: empty.message,
                           actionTitle: "Перейти в каталог") {
                onOpenCatalog?()
            }
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(entries) { entry in
                    NavigationLink(value: entry.anime) { LibraryRow(entry: entry) }
                        .swipeActions {
                            let removingFavorite = currentSection == .favorites || entry.status == nil
                            Button(removingFavorite ? "Убрать из избранного" : "Убрать из списка", role: .destructive) {
                                Task {
                                    if removingFavorite { await library.setFavorite(false, for: entry.anime) }
                                    else { await library.setStatus(nil, for: entry.anime) }
                                }
                            }
                        }
                        .contextMenu {
                            ForEach(LibraryStatus.allCases, id: \.self) { status in
                                Button(status.localizedName) { Task { await library.setStatus(status, for: entry.anime) } }
                            }
                            Button(entry.isFavorite ? "Убрать из избранного" : "В избранное") {
                                Task { await library.toggleFavorite(entry.anime) }
                            }
                            Button("Удалить из библиотеки", role: .destructive) {
                                Task { await deleteWithUndo(entry) }
                            }
                        }
                        .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    /// Удаляет запись и показывает плашку отката на ~4 секунды.
    private func deleteWithUndo(_ entry: LibraryEntry) async {
        guard let restore = await library.removeWithUndo(entry.id) else { return }
        undoRestore = restore
        undoMessage = "«\(entry.anime.title)» удалено"
        undoTicket &+= 1
        let ticket = undoTicket
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        // Плашку убираем только если её не сменило другое удаление.
        if undoTicket == ticket { dismissUndo() }
    }

    private func dismissUndo() {
        undoMessage = nil
        undoRestore = nil
    }

    @ViewBuilder private var historyList: some View {
        let history = library.snapshot.history
        if history.isEmpty {
            EmptyStateView(systemImage: "clock", title: "История пуста", message: "Здесь появятся просмотренные серии.",
                           actionTitle: "Перейти в каталог") {
                onOpenCatalog?()
            }
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(history) { item in
                    NavigationLink(value: item.anime) {
                        HStack(spacing: Theme.Spacing.m) {
                            PosterImage(url: item.anime.coverURL).frame(width: 44, height: 66)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.anime.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text("Серия \(item.episode) · \(item.watchedAt.formatted(.relative(presentation: .named)))")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                                if let p = library.progress(item.anime.id, episode: item.episode, sourceKey: item.sourceKey) {
                                    Text(p.isFinished ? "Просмотрено" : "Просмотрено \(p.percent)%")
                                        .font(.caption2).foregroundStyle(p.isFinished ? Theme.success : Theme.textSecondary)
                                }
                            }
                        }
                    }
                    .swipeActions {
                        Button("Удалить", role: .destructive) { Task { await library.removeHistoryItem(item.id) } }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct LibraryRow: View {
    let entry: LibraryEntry
    @Environment(LibraryStore.self) private var library

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            PosterImage(url: entry.anime.coverURL).frame(width: 52, height: 78)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.anime.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    if let status = entry.status { Text(status.localizedName) }
                    if entry.isFavorite { Image(systemName: "heart.fill").foregroundStyle(Theme.accent) }
                }
                .font(.caption).foregroundStyle(Theme.textSecondary)
                if let last = entry.lastEpisode {
                    let p = library.snapshot.latestProgress(animeId: entry.id, episode: last)
                    Text("Серия \(last)" + (entry.anime.episodeCount.map { " из \($0)" } ?? "") + (p.map { $0.isFinished ? " · просмотрена" : " · \($0.percent)%" } ?? ""))
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    if let total = entry.anime.episodeCount, total > 0 {
                        let watched = Double(last - ((p?.isFinished ?? false) ? 0 : 1)) + ((p?.isFinished ?? false) ? 0 : (p?.fraction ?? 0))
                        ProgressBar(value: watched / Double(total)).frame(height: 3).frame(maxWidth: 160)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
