import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AnivibeCore

// MARK: - Плитки на главной

/// Плитка папки: одна плоская поверхность, иконка, название и счётчик.
/// Никаких мини-обложек и стекла — папка читается как папка.
struct FolderTile: View {
    let collection: AnimeCollection
    var size: CGFloat = Theme.Folder.tileSize

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            FolderBackground(cornerRadius: Theme.Folder.tileRadius)
                .overlay {
                    Image(systemName: "folder")
                        .font(.system(size: size * 0.30, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: size, height: size)
            VStack(spacing: 1) {
                Text(collection.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2, reservesSpace: true)
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
            .fill(Theme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
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
                .strokeBorder(Theme.separator, lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: Theme.Folder.tileRadius, style: .continuous).fill(Theme.surface))
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
        .accessibilityLabel("Создать папку")
    }
}

/// Плоское нажатие: приглушение вместо масштабирования, чтобы сетка не «дышала».
struct FolderPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(AppMotion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// Затемнение под панелью папки. Отдельный слой, чтобы двигалась только панель.
struct FolderBackdrop: View {
    let close: () -> Void

    var body: some View {
        Rectangle()
            .fill(Theme.scrim)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: close)
            .accessibilityHidden(true)
    }
}

// MARK: - Панель папки

/// Плоская панель папки: высота ограничена экраном, сетка адаптивная.
struct FolderOverlay: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 140 : 96, maximum: 180),
                  spacing: Theme.Spacing.m, alignment: .top)]
    }

    var body: some View {
        GeometryReader { geometry in
            let panelHeight = min(Theme.Folder.panelMaxHeight, max(96, geometry.size.height - 32))
            ZStack {
                if let collection = env.collections.collection(collectionID) {
                    VStack(spacing: Theme.Spacing.l) {
                        HStack {
                            Spacer()
                            Button(action: close) {
                                Image(systemName: "xmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(Theme.surfaceElevated))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Закрыть папку")
                        }
                        TextField("Название папки", text: $name)
                            .font(.title3.weight(.bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.textPrimary)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit { commitName() }
                            .padding(.horizontal, Theme.Spacing.xl)
                        panel(collection, maxHeight: panelHeight)

                        HStack(spacing: Theme.Spacing.s) {
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
                            Spacer(minLength: 0)
                            Button(role: .destructive) { confirmDelete = true } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(FolderCapsuleButtonStyle(destructive: true))
                            .accessibilityLabel("Удалить папку")
                        }
                        .frame(minHeight: 44)
                    }
                    .padding(Theme.Spacing.l)
                    .frame(maxWidth: min(640, geometry.size.width - 32))
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

    @ViewBuilder
    private func panel(_ collection: AnimeCollection, maxHeight: CGFloat) -> some View {
        if collection.items.isEmpty {
            emptyFolderPanel(cornerRadius: Theme.Folder.posterRadius)
                .frame(height: min(maxHeight, 260))
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                    ForEach(collection.items, id: \.id) { anime in
                        FolderItemView(anime: anime, editing: editing) {
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
                    addTile
                }
                .padding(Theme.Spacing.l)
            }
            .frame(maxHeight: maxHeight)
            .background(FolderBackground(cornerRadius: Theme.Folder.posterRadius))
        }
    }

    private var addTile: some View {
        Button { showSearch = true } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: Theme.Folder.posterRadius, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
                    .aspectRatio(Theme.posterAspect, contentMode: .fit)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                Label("Добавить", systemImage: "plus")
                    .labelStyle(.titleOnly)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .buttonStyle(FolderPressStyle())
        .accessibilityLabel("Добавить аниме через поиск")
    }

    /// Пустая папка — понятный текст и одно действие, а не пустая сетка.
    private func emptyFolderPanel(cornerRadius: CGFloat) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "folder")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
            Text("В папке пока пусто")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Найдите тайтл в каталоге и добавьте его сюда.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button { showSearch = true } label: {
                Label("Добавить", systemImage: "plus")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(FolderCapsuleButtonStyle(prominent: true))
            .frame(width: 148, height: 44)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FolderBackground(cornerRadius: cornerRadius))
    }
}

/// Карточка тайтла внутри папки: постер, название и кнопка «убрать» в режиме правки.
struct FolderItemView: View {
    let anime: AnimeSnapshot
    let editing: Bool
    let tap: () -> Void
    let remove: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(spacing: 6) {
                PosterImage(url: anime.coverURL, cornerRadius: Theme.Folder.posterRadius)
                    .aspectRatio(Theme.posterAspect, contentMode: .fit)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Folder.posterRadius, style: .continuous)
                            .strokeBorder(Theme.separator, lineWidth: 1)
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
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.onAccent)
                        .background(Circle().fill(Theme.accent).frame(width: 26, height: 26))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(-10)
                .transition(.opacity)
                .accessibilityLabel("Убрать «\(anime.title)» из папки")
            }
        }
        .contextMenu {
            Button(role: .destructive, action: remove) { Label("Убрать из папки", systemImage: "folder.badge.minus") }
        }
    }
}

/// Плоские капсулы: одно действие акцентом, удаление — семантическим цветом.
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
            .background(Capsule().fill(prominent ? Theme.accent : Theme.surfaceElevated))
            .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: prominent ? 0 : 1))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(AppMotion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

// MARK: - Добавление аниме в папку

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
            .scrollContentBackground(.hidden)
            .background(Theme.background)
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
            .frame(minHeight: 44)
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
