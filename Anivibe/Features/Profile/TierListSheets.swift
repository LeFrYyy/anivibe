import SwiftUI
import AnivibeCore

/// Sheet распределения тайтла по тирам (tap-альтернатива перетаскиванию).
struct TierAssignSheet: View {
    let anime: AnimeSnapshot
    let tiers: [TierRowData]
    let currentTier: TierKey?
    let onSelectTier: (TierKey) -> Void
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    HStack(spacing: Theme.Spacing.m) {
                        PosterImage(url: anime.coverURL, cornerRadius: 10)
                            .frame(width: 56, height: 84)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(anime.title)
                                .font(.headline)
                                .lineLimit(3)
                            Text(currentTier.map { "Сейчас в тире: \($0.rawValue)" } ?? "Не распределён")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }

                    Text("Выберите тир")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(tiers) { row in
                            let selected = currentTier == row.key
                            Button {
                                onSelectTier(row.key)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(row.key.rawValue)
                                        .font(.headline.weight(.heavy))
                                        .foregroundStyle(.white)
                                        .frame(width: 34, height: 34)
                                        .background(tierColor(row.colorHex), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    Text(row.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.85)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    if selected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                .padding(10)
                                .frame(minHeight: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Theme.surfaceElevated)
                                )
                                .overlay {
                                    if selected {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Theme.accent, lineWidth: 1.5)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if currentTier != nil {
                        Button(role: .destructive, action: onRemove) {
                            Label("Убрать в пул нераспределённых", systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }

                    NavigationLink(value: anime) {
                        Label("Открыть страницу аниме", systemImage: "info.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(Theme.Spacing.l)
            }
            .screenBackground()
            .navigationTitle("Распределение")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AnimeSnapshot.self) { AnimeDetailsView(snapshot: $0) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }
}

/// Sheet настройки названия и цвета тира.
struct TierCustomizeSheet: View {
    let row: TierRowData
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var colorHex: String

    private let palette = ["E5534B", "E0823D", "C9A227", "2E9B63", "2B86C5", "7B5CE6", "6E7687"]

    init(row: TierRowData, onSave: @escaping (String, String) -> Void) {
        self.row = row
        self.onSave = onSave
        _title = State(initialValue: row.title)
        _colorHex = State(initialValue: row.colorHex)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название тира \(row.key.rawValue)") {
                    TextField("Название", text: $title)
                    Button("Сбросить по умолчанию («\(row.key.defaultTitle)»)") {
                        title = row.key.defaultTitle
                        colorHex = row.key.defaultColorHex
                    }
                }
                Section("Цвет плашки") {
                    HStack(spacing: 12) {
                        ForEach(palette, id: \.self) { hex in
                            Button {
                                colorHex = hex
                            } label: {
                                Circle()
                                    .fill(tierColor(hex))
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if colorHex == hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Тир \(row.key.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        onSave(title, colorHex)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Sheet управления именованными тир-листами: создание, переименование, удаление (лимит — `TierListSet.maxLists`).
struct TierListManagerSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var newListName = ""
    @State private var deleteTarget: NamedTierList?

    private var set: TierListSet { get { env.tierList.set } }
    private var atLimit: Bool { get { set.lists.count >= TierListSet.maxLists } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        TextField("Название нового списка", text: $newListName)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .onSubmit(createList)
                        Button("Создать", action: createList)
                            .disabled(atLimit)
                    }
                    .frame(minHeight: 44)
                } header: {
                    Text("Новый тир-лист · \(set.lists.count)/\(TierListSet.maxLists)")
                } footer: {
                    Text(atLimit
                         ? "Достигнут лимит — максимум \(TierListSet.maxLists) тир-листов на аккаунт. Удалите ненужный, чтобы создать новый."
                         : "Можно создать до \(TierListSet.maxLists) тир-листов, например «Сёнэны» или «Топ 2025».")
                }

                Section("Мои тир-листы") {
                    ForEach(set.lists) { named in
                        HStack(spacing: 10) {
                            Button {
                                env.tierList.selectList(named.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: named.id == set.activeList?.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(named.id == set.activeList?.id ? Theme.accent : Theme.textSecondary)
                                    Text(named.name)
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Выбрать список \(named.name)")
                            Button {
                                deleteTarget = named
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(Theme.danger)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Удалить список \(named.name)")
                        }
                        .frame(minHeight: 44)
                    }
                } footer: {
                    Text("Отмеченный список открыт в конструкторе. Переименование — в поле ниже или долгим нажатием на имя.")
                }

                if let active = set.activeList {
                    Section("Переименовать «\(active.name)»") {
                        RenameListRow(name: active.name) { newName in
                            env.tierList.renameList(active.id, name: newName)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Тир-листы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .confirmationDialog("Удалить тир-лист?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let target = deleteTarget { env.tierList.deleteList(target.id) }
                    deleteTarget = nil
                }
                Button("Отмена", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("«\(deleteTarget?.name ?? "")» будет удалён вместе с расстановкой тайтлов. Сами аниме останутся в библиотеке.")
            }
        }
    }

    private func createList() {
        guard env.tierList.createList(name: newListName) else { return }
        newListName = ""
    }
}

private struct RenameListRow: View {
    @State private var draft: String
    let onCommit: (String) -> Void

    init(name: String, onCommit: @escaping (String) -> Void) {
        _draft = State(initialValue: name)
        self.onCommit = onCommit
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField("Название списка", text: $draft)
                .submitLabel(.done)
                .onSubmit { onCommit(draft) }
            Button("Сохранить") { onCommit(draft) }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(minHeight: 44)
    }
}
