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
        Group {
            if !model.pages.isEmpty {
                // Нативный UIScrollView-зум: pinch до 4x, панорамирование, двойной тап.
                MangaPagesZoomView(pages: model.pages, footer: AnyView(navigationBar))
            } else if let error = model.error {
                ErrorStateView(message: error) {
                    Task { await model.load(chapterID: currentChapter.id, service: env.manga) }
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
