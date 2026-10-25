import SwiftUI
import AnivibeCore

enum LibrarySection: Hashable, CaseIterable, Identifiable {
    case list(LibraryStatus), favorites, history

    static var allCases: [LibrarySection] {
        [.list(.watching), .list(.planned), .list(.onHold), .list(.completed), .list(.dropped), .favorites, .history]
    }

    var id: String {
        switch self {
        case .list(let s): return s.rawValue
        case .favorites: return "favorites"
        case .history: return "history"
        }
    }

    var title: String {
        switch self {
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

    private let embedded: Bool

    init(initialSection: LibrarySection = .list(.watching), embedded: Bool = false) {
        _section = State(initialValue: initialSection)
        self.embedded = embedded
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
                                Text("\(s.title) \(countLabel(counts[s, default: 0]))")
                                    .font(.subheadline.weight(.medium))
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
            .screenBackground()
            .navigationTitle("Библиотека")
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
        var result: [LibrarySection: Int] = [.history: library.snapshot.history.count]
        for entry in library.snapshot.entries where !entry.isDeleted {
            if let status = entry.status { result[.list(status), default: 0] += 1 }
            if entry.isFavorite { result[.favorites, default: 0] += 1 }
        }
        return result
    }

    private func countLabel(_ value: Int) -> String {
        value > 0 ? "· \(value)" : ""
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .history: historyList
        case .favorites: entriesList(library.snapshot.favorites)
        case .list(let status): entriesList(library.snapshot.entries(in: status))
        }
    }

    @ViewBuilder private func entriesList(_ entries: [LibraryEntry]) -> some View {
        if entries.isEmpty {
            EmptyStateView(systemImage: "tray", title: "Список пуст",
                           message: "Добавляйте тайтлы со страницы аниме — кнопки «В список» и «В избранное».")
                .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(entries) { entry in
                    NavigationLink(value: entry.anime) { LibraryRow(entry: entry) }
                        .swipeActions {
                            Button(section == .favorites ? "Убрать из избранного" : "Убрать из списка", role: .destructive) {
                                let removingFavorite = section == .favorites
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
                            Button("Удалить из библиотеки", role: .destructive) { Task { await library.remove(entry.id) } }
                        }
                        .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder private var historyList: some View {
        let history = library.snapshot.history
        if history.isEmpty {
            EmptyStateView(systemImage: "clock", title: "История пуста", message: "Здесь появятся просмотренные серии.")
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
