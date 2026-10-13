import SwiftUI
import AnivibeCore

struct FilterSheet: View {
    @Binding var query: CatalogQuery
    let genres: [String]
    let apply: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CatalogQuery()

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: Date()) + 1
        return Array((1960...current).reversed())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Сортировка") {
                    Picker("Сортировка", selection: $draft.sort) {
                        ForEach(CatalogSort.userSelectable, id: \.self) { Text($0.localizedName).tag($0) }
                    }
                }
                Section("Статус и год") {
                    Picker("Статус", selection: $draft.status) {
                        Text("Любой").tag(AiringStatus?.none)
                        ForEach(AiringStatus.filterable, id: \.self) { Text($0.localizedName).tag(Optional($0)) }
                    }
                    Picker("Год выпуска", selection: $draft.year) {
                        Text("Любой").tag(Int?.none)
                        ForEach(years, id: \.self) { Text(String($0)).tag(Optional($0)) }
                    }
                }
                Section("Формат") {
                    ForEach([AnimeFormat.tv, .movie, .ona, .ova, .special, .tvShort], id: \.self) { f in
                        Toggle(f.localizedName, isOn: Binding(
                            get: { draft.formats.contains(f) },
                            set: { on in if on { draft.formats.insert(f) } else { draft.formats.remove(f) } }))
                    }
                }
                Section {
                    if genres.isEmpty {
                        Text("Список жанров загружается…").foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(genres, id: \.self) { g in
                        Toggle(CatalogLocalization.genre(g), isOn: Binding(
                            get: { draft.genres.contains(g) },
                            set: { on in if on { draft.genres.insert(g) } else { draft.genres.remove(g) } }))
                    }
                } header: {
                    Text("Жанры")
                } footer: {
                    Text("Выбранные жанры должны присутствовать все одновременно.")
                }
            }
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Сбросить") {
                        draft.genres = []; draft.year = nil; draft.status = nil; draft.formats = []; draft.sort = .popularity
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        let search = query.search
                        query = draft
                        query.search = search
                        apply()
                        dismiss()
                    }
                }
            }
        }
        .onAppear { draft = query }
    }
}
