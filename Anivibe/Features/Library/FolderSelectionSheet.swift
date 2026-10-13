import SwiftUI
import AnivibeCore

struct FolderSelectionSheet: View {
    let anime: AnimeSnapshot
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Добавить в папки") {
                    if env.collections.collections.isEmpty { Text("Создайте первую папку ниже") }
                    ForEach(env.collections.collections) { folder in
                        Toggle(folder.name, isOn: Binding(get: { env.collections.collection(folder.id)?.contains(anime.id) == true },
                            set: { checked in
                                if checked { env.collections.add(anime, to: folder.id) }
                                else { env.collections.remove(anime.id, from: folder.id) }
                            }))
                    }
                }
                Section("Новая папка") {
                    TextField("Название", text: $newName)
                    Button("Создать и добавить тайтл") {
                        _ = env.collections.create(name: newName, with: anime)
                        newName = ""
                    }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error = env.collections.errorMessage { Text(error).foregroundStyle(Theme.danger) }
            }
            .navigationTitle("Папки")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}
