import SwiftUI
import AnivibeCore

enum LibrarySection: Hashable, CaseIterable, Identifiable {
    case list(LibraryStatus), favorites, history

    static var allCases: [LibrarySection] {
        [.list(.watching), .list(.planned), .list(.onHold), .list(.completed), .favorites, .history]
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
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @State private var section: LibrarySection = .list(.watching)
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(LibrarySection.allCases) { s in
                            Button { withAnimation(.easeInOut(duration: 0.15)) { section = s } } label: {
                                Text("\(s.title) \(count(s))")
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(section == s ? Theme.accent : Theme.surfaceElevated, in: Capsule())
                                    .foregroundStyle(section == s ? Theme.onAccent : Theme.textPrimary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(section == s ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.s)
                }
                content
            }
            .screenBackground()
            .navigationTitle("Библиотека")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HistoryItem.self) { AnimeDetailsView(snapshot: $0.anime, history: $0) }
            .navigationDestination(for: AnimeSnapshot.self) { AnimeDetailsView(snapshot: $0) }
            .navigationDestination(for: Anime.self) { AnimeDetailsView(anime: $0) }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Библиотека").font(.headline).contextMenu {
                        Button(settings.libraryPinned ? "Открепить от главной" : "Закрепить на главной") { settings.libraryPinned.toggle() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if section == .history && !library.snapshot.history.isEmpty {
                    Button("Очистить") { confirmClear = true }
                    }
                }
            }
            .confirmationDialog("Очистить историю просмотров?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Очистить", role: .destructive) { Task { await library.clearHistory() } }
            }
        }
    }

    private func count(_ s: LibrarySection) -> String {
        let n: Int
        switch s {
        case .list(let status): n = library.snapshot.entries(in: status).count
        case .favorites: n = library.snapshot.favorites.count
        case .history: n = library.snapshot.history.count
        }
        return n > 0 ? "· \(n)" : ""
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
                            Button("Удалить", role: .destructive) { Task { await library.remove(entry.id) } }
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
                    NavigationLink(value: item) {
                        HStack(spacing: Theme.Spacing.m) {
                            PosterImage(url: item.anime.coverURL).frame(width: 44, height: 66)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.anime.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text("Серия \(item.episode) · \(item.watchedAt.formatted(.relative(presentation: .named)))")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                                if item.sourceKey != nil { Text("Нумерация источника · выберите эту озвучку для продолжения").font(.caption2).foregroundStyle(Theme.textSecondary) }
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
    @Environment(AppSettings.self) private var settings
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
                    let p = library.progress(entry.id, episode: last)
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
