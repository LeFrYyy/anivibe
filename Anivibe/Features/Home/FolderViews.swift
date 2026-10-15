import SwiftUI
import UniformTypeIdentifiers
import AnivibeCore

/// A folder is a collection, not a miniature copy of the Home screen.
/// Its name and count are readable without opening it.
struct FolderTile: View {
    let collection: AnimeCollection
    var width: CGFloat = 184

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Image(systemName: "folder")
                    .font(.system(size: 20, weight: .regular))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.textSecondary)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(collection.name)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(Self.countLabel(collection.items.count))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.l)
        .frame(width: width, alignment: .leading)
        .background(FolderBackground(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
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

/// One opaque surface and a hairline. No decorative tint or costly compositing.
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

struct NewFolderTile: View {
    var isFirst: Bool
    var width: CGFloat = 184

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Новая папка")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2, reservesSpace: true)
                Text(isFirst ? "Добавьте аниме" : "Создать")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.l)
        .frame(width: width, alignment: .leading)
        .background(FolderBackground(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Создать папку")
    }
}

/// Quiet opacity feedback, without magnification or a springy icon effect.
struct FolderPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(AppMotion.fade(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

struct FolderBackdrop: View {
    let close: () -> Void

    var body: some View {
        Color.black.opacity(0.48)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: close)
            .accessibilityHidden(true)
    }
}

/// A conventional collection panel: stable header, scrollable covers and two actions.
/// It follows the system color scheme and always stays within the available bounds.
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
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 160 : 96,
                            maximum: dynamicTypeSize.isAccessibilitySize ? 220 : 144),
                  spacing: Theme.Spacing.l, alignment: .top)]
    }

    var body: some View {
        GeometryReader { geometry in
            if let collection = env.collections.collection(collectionID) {
                VStack(spacing: 0) {
                    header(collection)
                    Divider().overlay(Theme.separator)
                    contents(collection)
                    if let error = env.collections.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(Theme.danger)
                            .padding(.horizontal, Theme.Spacing.l)
                            .padding(.bottom, Theme.Spacing.s)
                    }
                    Divider().overlay(Theme.separator)
                    actions
                }
                .frame(width: max(0, min(640, geometry.size.width - 32)),
                       height: max(0, geometry.size.height - 32))
                .background(FolderBackground(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .onAppear {
            presentedAccountID = env.collections.activeAccountID
            name = env.collections.collection(collectionID)?.name ?? ""
        }
        .onDisappear {
            // A backdrop tap also commits the name, but never to a different account.
            if env.collections.activeAccountID == presentedAccountID {
                env.collections.rename(collectionID, to: name)
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
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Сами аниме останутся в каталоге и библиотеке.")
        }
    }

    private func header(_ collection: AnimeCollection) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if editing {
                    TextField("Название папки", text: $name)
                        .font(.title3.weight(.semibold))
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit(finishEditing)
                        .accessibilityLabel("Название папки")
                } else {
                    Text(collection.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(FolderTile.countLabel(collection.items.count))
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button("Переименовать", systemImage: "pencil") {
                    editing = true
                    nameFocused = true
                }
                Button("Удалить папку", systemImage: "trash", role: .destructive) {
                    confirmDelete = true
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
            }
            .foregroundStyle(Theme.textSecondary)
            .accessibilityLabel("Действия с папкой")
            Button(action: close) {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .foregroundStyle(Theme.textSecondary)
            .accessibilityLabel("Закрыть папку")
        }
        .padding(Theme.Spacing.l)
    }

    private func contents(_ collection: AnimeCollection) -> some View {
        ScrollView {
            if collection.items.isEmpty {
                VStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "folder")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                    Text("В папке пока пусто").font(.headline)
                    Text("Добавьте аниме из каталога.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 220)
                .padding(Theme.Spacing.l)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.xl) {
                    ForEach(collection.items) { anime in
                        FolderItemView(anime: anime, editing: editing) {
                            guard !editing else { return }
                            env.collections.rename(collectionID, to: name)
                            open(anime)
                        } remove: {
                            withAnimation(AppMotion.selection(reduceMotion: reduceMotion)) {
                                env.collections.remove(anime.id, from: collectionID)
                            }
                        }
                        .onDrag {
                            editing = true
                            nameFocused = false
                            draggedItem = String(anime.id)
                            return NSItemProvider(object: String(anime.id) as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: CollectionDropDelegate(targetID: String(anime.id), draggedID: $draggedItem, reduceMotion: reduceMotion) { from, to in
                            if let source = Int(from), let target = Int(to) {
                                env.collections.reorderItem(source, in: collectionID, to: target)
                            }
                        })
                    }
                }
                .padding(Theme.Spacing.l)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button(editing ? "Готово" : "Изменить") {
                if editing { finishEditing() }
                else {
                    editing = true
                    draggedItem = nil
                }
            }
            .buttonStyle(FolderActionStyle())
            Spacer(minLength: Theme.Spacing.s)
            Button { showSearch = true } label: {
                Label("Добавить", systemImage: "plus")
            }
            .buttonStyle(FolderActionStyle(prominent: true))
        }
        .padding(Theme.Spacing.l)
    }

    private func finishEditing() {
        env.collections.rename(collectionID, to: name)
        nameFocused = false
        editing = false
        draggedItem = nil
    }
}

struct FolderItemView: View {
    let anime: AnimeSnapshot
    let editing: Bool
    let tap: () -> Void
    let remove: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                PosterImage(url: anime.coverURL, cornerRadius: 8)
                    .aspectRatio(Theme.posterAspect, contentMode: .fit)
                Text(anime.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(FolderPressStyle())
        .overlay(alignment: .topTrailing) {
            if editing {
                Button(action: remove) {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(width: 32, height: 32)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.separator, lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Убрать «\(anime.title)» из папки")
            }
        }
        .contextMenu {
            Button(role: .destructive, action: remove) {
                Label("Убрать из папки", systemImage: "folder.badge.minus")
            }
        }
    }
}

struct FolderActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Theme.onAccent : Theme.textPrimary)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: 44)
            .background(prominent ? Theme.accent : Theme.surfaceElevated,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(prominent ? Color.clear : Theme.separator, lineWidth: 1)
            }
            .opacity(!isEnabled ? 0.45 : (configuration.isPressed ? 0.9 : 1))
            .animation(AppMotion.fade(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}