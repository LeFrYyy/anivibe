import SwiftUI
import UIKit
import AnivibeCore

/// Вертикальная читалка главы: страницы грузятся через ImagePipeline
/// (для uploads.mangadex.org выставляется Referer автоматически).
struct MangaReaderView: View {
    let chapter: MangaChapter
    let allChapters: [MangaChapter]
    /// ID манги (Shikimori) — прочитанные главы пишутся в `mangaLibrary`.
    let mangaID: Int
    @Environment(AppEnvironment.self) private var env
    @State private var model = MangaReaderViewModel()
    @State private var currentChapter: MangaChapter

    init(chapter: MangaChapter, allChapters: [MangaChapter], mangaID: Int) {
        self.chapter = chapter
        self.allChapters = allChapters
        self.mangaID = mangaID
        _currentChapter = State(initialValue: chapter)
    }

    private var currentIndex: Int? { allChapters.firstIndex { $0.id == currentChapter.id } }
    private var previousChapter: MangaChapter? { currentIndex.flatMap { $0 > 0 ? allChapters[$0 - 1] : nil } }
    private var nextChapter: MangaChapter? { currentIndex.flatMap { $0 < allChapters.count - 1 ? allChapters[$0 + 1] : nil } }

    var body: some View {
        ZoomableScrollView {
            LazyVStack(spacing: 0) {
                if model.loading && model.pages.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 80)
                }
                if let error = model.error, model.pages.isEmpty {
                    ErrorStateView(message: error) {
                        Task { await model.load(chapterID: currentChapter.id, service: env.manga) }
                    }
                    .padding(.top, 80)
                }
                ForEach(Array(model.pages.enumerated()), id: \.offset) { index, url in
                    MangaPageImage(url: url)
                        .accessibilityLabel("Страница \(index + 1)")
                }
                if !model.pages.isEmpty {
                    navigationBar
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(currentChapter.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: currentChapter.id) {
            await model.load(chapterID: currentChapter.id, service: env.manga)
            if !model.pages.isEmpty {
                env.mangaLibrary.markChapterRead(mangaID, chapter: currentChapter)
            }
        }
    }

    private var navigationBar: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let previous = previousChapter {
                Button { switchChapter(previous) } label: { navButton("Глава \(previous.number.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String($0) } ?? "назад")", systemImage: "chevron.left") }
            }
            Spacer()
            if let next = nextChapter {
                Button { switchChapter(next) } label: { navButton("Глава \(next.number.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String($0) } ?? "вперёд")", systemImage: "chevron.right") }
            }
        }
        .padding(Theme.Spacing.l)
    }

    private func navButton(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.surfaceElevated, in: Capsule())
            .foregroundStyle(Theme.textPrimary)
    }

    private func switchChapter(_ chapter: MangaChapter) {
        currentChapter = chapter
        model = MangaReaderViewModel()
    }
}

/// Страница манги на всю ширину экрана, высота по пропорциям картинки.
private struct MangaPageImage: View {
    let url: URL
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Theme.surfaceElevated
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .overlay {
                        if failed {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.textSecondary)
                        } else {
                            ProgressView()
                        }
                    }
            }
        }
        .task {
            guard image == nil, !failed else { return }
            do { image = try await ImagePipeline.shared.image(for: url) }
            catch { failed = true }
        }
    }
}
