import SwiftUI
import AnivibeCore

func tierColor(_ hex: String) -> Color {
    UIColor(hexString: hex).map(Color.init(uiColor:)) ?? .gray
}

struct TierBetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.accent.opacity(0.14), in: Capsule())
    }
}

/// Карточка входа в персональный тир-лист в профиле владельца.
struct TierListProfileCard: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let set = env.tierList.set
        let active = set.activeList
        let tierList = active?.list ?? .empty
        NavigationLink {
            TierListEditorView()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.3x1.below.line.grid.1x2")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                    Text(active?.name ?? "Тир-лист")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    TierBetaBadge()
                    Spacer()
                    Label(tierList.visibility.shortTitle,
                          systemImage: tierList.visibility == .publicList ? "globe" : "lock")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }

                if set.lists.isEmpty {
                    Text("Создайте до \(TierListSet.maxLists) тир-листов и распределите любимые аниме по рангам S–D.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if tierList.isEmpty {
                    Text(set.lists.count > 1
                         ? "Списков: \(set.lists.count)/\(TierListSet.maxLists). Активный пока пуст — распределите аниме по рангам."
                         : "Распределите любимые аниме по рангам S–D из ваших списков.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                        ForEach(tierList.tiers) { row in
                            HStack(spacing: 4) {
                                Text(row.key.rawValue)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(tierColor(row.colorHex), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                Text("\(row.items.count)")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 5)
                            .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    Text("Всего распределено: \(tierList.totalAssignedCount)\(set.lists.count > 1 ? " · Списков: \(set.lists.count)/\(TierListSet.maxLists)" : "")")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .profilePanel()
        }
        .buttonStyle(.plain)
    }
}

private struct SelectedTierAnime: Identifiable {
    let snapshot: AnimeSnapshot
    var id: Int { snapshot.id }
}

/// Конструктор персональных тир-листов (Beta): до `TierListSet.maxLists` именованных списков.
struct TierListEditorView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(LibraryStore.self) private var library
    @State private var includeAllStatuses = false
    @State private var selectedAnime: SelectedTierAnime?
    @State private var editingTier: TierRowData?
    @State private var targetedTier: TierKey?
    @State private var isPoolTargeted = false
    @State private var showingManager = false
    @State private var scroller = TierListAutoScroller()
    @State private var scrollPosition = ScrollPosition(edge: .top)

    private var set: TierListSet { env.tierList.set }
    private var tierList: TierList { env.tierList.tierList }

    private var poolEntries: [LibraryEntry] {
        tierList.unassignedPool(from: library.snapshot, includeAllStatuses: includeAllStatuses)
    }

    private func snapshot(forAnimeID id: Int) -> AnimeSnapshot? {
        if let entry = library.snapshot.entry(for: id) {
            return entry.anime
        }
        for row in tierList.tiers {
            if let found = row.items.first(where: { $0.id == id }) {
                return found
            }
        }
        return nil
    }

    var body: some View {
        Group {
            if set.lists.isEmpty {
                emptyState
            } else {
                editorScroll
            }
        }
        .screenBackground()
        .navigationTitle(set.activeList?.name ?? "Тир-лист")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text(set.activeList?.name ?? "Тир-лист").font(.headline).lineLimit(1)
                    TierBetaBadge()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingManager = true
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .accessibilityLabel("Управление тир-листами")
            }
        }
        .sheet(isPresented: $showingManager) {
            TierListManagerSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedAnime) { selection in
            TierAssignSheet(
                anime: selection.snapshot,
                tiers: tierList.tiers,
                currentTier: tierList.tier(for: selection.snapshot.id),
                onSelectTier: { key in
                    env.tierList.assign(selection.snapshot, to: key)
                    selectedAnime = nil
                },
                onRemove: {
                    env.tierList.remove(selection.snapshot.id)
                    selectedAnime = nil
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(item: $editingTier) { row in
            TierCustomizeSheet(row: row) { title, hex in
                env.tierList.updateTier(row.key, title: title, colorHex: hex)
            }
            .presentationDetents([.medium])
        }
        .onChange(of: set.activeListID) { _, _ in scroller.cancel() }
        .onDisappear { scroller.cancel() }
    }

    /// Пустое состояние: ни одного списка ещё не создано.
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: "square.grid.3x1.below.line.grid.1x2")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text("Тир-листов пока нет")
                .font(.title3.bold())
            Text("Создайте до \(TierListSet.maxLists) именованных списков и разложите любимые аниме по рангам S–D.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                _ = env.tierList.createList()
            } label: {
                Label("Создать тир-лист", systemImage: "plus")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            Spacer()
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
    }

    private var editorScroll: some View {
        GeometryReader { geo in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    listSelector
                    visibilityPanel

                    if let error = env.tierList.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                            .profilePanel()
                    }

                    tiersSection
                    unassignedPoolSection
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.l)
                .background(
                    GeometryReader { inner in
                        Color.clear.preference(
                            key: TierScrollOffsetKey.self,
                            value: -inner.frame(in: .named("tierEditorScroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "tierEditorScroll")
            .scrollPosition($scrollPosition)
            .onPreferenceChange(TierScrollOffsetKey.self) { scroller.updateOffset($0) }
            .onAppear {
                scroller.updateContainer(height: geo.size.height)
                scroller.applyScroll = { y in scrollPosition.scrollTo(y: y) }
            }
            .onChange(of: geo.size.height) { _, h in scroller.updateContainer(height: h) }
            .onDrop(of: [.text], delegate: TierListAutoScrollDelegate(scroller: scroller))
        }
    }

    /// Переключатель между именованными списками + счётчик X/5.
    private var listSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Мои тир-листы")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(set.lists.count)/\(TierListSet.maxLists)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(set.lists) { named in
                        let isActive = named.id == set.activeList?.id
                        Button {
                            env.tierList.selectList(named.id)
                        } label: {
                            Text(named.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .foregroundStyle(isActive ? Theme.onAccent : Theme.textPrimary)
                                .background(isActive ? Theme.accent : Theme.surfaceElevated, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Тир-лист \(named.name)")
                    }
                    Button {
                        showingManager = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.bold))
                            .frame(minWidth: 36, minHeight: 36)
                            .foregroundStyle(Theme.accent)
                            .background(Theme.accent.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Управление списками")
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var visibilityPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Видимость тир-листа", systemImage: tierList.visibility == .publicList ? "globe" : "lock")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                TierBetaBadge()
            }
            Picker("Видимость", selection: Binding(
                get: { tierList.visibility },
                set: { env.tierList.setVisibility($0) }
            )) {
                ForEach(TierListVisibility.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(tierList.visibility == .publicList
                 ? "Публичный: этот список видят все, кто может открыть ваш профиль."
                 : "Приватный: этот список виден только вам.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .profilePanel()
    }

    private var tiersSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text("Ранги (S–D)").font(.title3.bold())
                Spacer()
                Text("Тап или перетаскивание")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(tierList.tiers) { row in
                tierRowView(row)
            }
        }
    }

    private func tierRowView(_ row: TierRowData) -> some View {
        let isTargeted = targetedTier == row.key
        return HStack(alignment: .top, spacing: 10) {
            Button {
                editingTier = row
            } label: {
                VStack(spacing: 4) {
                    Text(row.key.rawValue)
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(.white)
                    Text(row.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 72)
                .frame(minHeight: 88)
                .padding(.horizontal, 4)
                .background(tierColor(row.colorHex), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Тир \(row.key.rawValue) — \(row.title). Нажмите, чтобы изменить.")

            if row.items.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "plus.square.dashed")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Перетащите сюда или выберите снизу")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 88)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 8) {
                        ForEach(row.items, id: \.id) { anime in
                            tierPosterTile(anime)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 88)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(isTargeted ? Theme.accent : Theme.separator.opacity(0.7), lineWidth: isTargeted ? 2 : 0.5)
        }
        .dropDestination(for: String.self) { items, _ in
            scroller.dragEnded()
            guard let raw = items.first, let id = Int(raw), let item = snapshot(forAnimeID: id) else { return false }
            env.tierList.assign(item, to: row.key)
            return true
        } isTargeted: { targeted in
            targetedTier = targeted ? row.key : (targetedTier == row.key ? nil : targetedTier)
        }
    }

    private func tierPosterTile(_ anime: AnimeSnapshot) -> some View {
        Button {
            selectedAnime = SelectedTierAnime(snapshot: anime)
        } label: {
            VStack(spacing: 4) {
                PosterImage(url: anime.coverURL, cornerRadius: 8)
                    .frame(width: 56, height: 84)
                Text(anime.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 60)
            }
        }
        .buttonStyle(PosterPressStyle())
        .draggable(String(anime.id))
    }

    private var unassignedPoolSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Нераспределённые (\(poolEntries.count))")
                    .font(.title3.bold())
                Spacer()
            }
            Picker("Источник списка", selection: $includeAllStatuses) {
                Text("Просмотрено / смотрю").tag(false)
                Text("Вся библиотека").tag(true)
            }
            .pickerStyle(.segmented)

            if poolEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: library.snapshot.allListEntries.isEmpty ? "books.vertical" : "checkmark.seal")
                        .font(.title2)
                        .foregroundStyle(Theme.textSecondary)
                    Text(library.snapshot.allListEntries.isEmpty
                         ? "В библиотеке пока нет тайтлов"
                         : (includeAllStatuses ? "Все тайтлы из списков уже распределены!" : "Все тайтлы из «Просмотрено» и «Смотрю» распределены."))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .profilePanel()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 112), spacing: 10, alignment: .top)], spacing: 12) {
                    ForEach(poolEntries) { entry in
                        Button {
                            selectedAnime = SelectedTierAnime(snapshot: entry.anime)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                PosterImage(url: entry.anime.coverURL, cornerRadius: 10)
                                    .aspectRatio(Theme.posterAspect, contentMode: .fit)
                                Text(entry.anime.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(2, reservesSpace: true)
                                    .multilineTextAlignment(.leading)
                                if let status = entry.status {
                                    Text(status.localizedName)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(PosterPressStyle())
                        .draggable(String(entry.anime.id))
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .fill(isPoolTargeted ? Theme.accent.opacity(0.08) : Color.clear)
        )
        .overlay {
            if isPoolTargeted {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            scroller.dragEnded()
            guard let raw = items.first, let id = Int(raw) else { return false }
            env.tierList.remove(id)
            return true
        } isTargeted: { targeted in
            isPoolTargeted = targeted
        }
    }
}
