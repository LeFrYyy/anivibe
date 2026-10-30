import SwiftUI
import AnivibeCore

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppSettings.self) private var settings
    @State private var providers: [ProviderInfo] = []
    @State private var cacheCleared = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Оформление") {
                Picker("Тема", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Основной цвет") {
                HStack {
                    ForEach(["8467FF", "2563EB", "0F766E", "BE185D", "B45309"], id: \.self) { hex in
                        Button { settings.accentHex = hex } label: {
                            Circle().fill(Color(UIColor(hexString: hex)!)).frame(width: 36, height: 36)
                                .overlay { if settings.accentHex == hex { Image(systemName: "checkmark").foregroundStyle(Theme.onAccent) } }
                        }.frame(minWidth: 44, minHeight: 44).buttonStyle(.plain).accessibilityLabel("Цвет \(hex)")
                    }
                }
                ColorPicker("Свой цвет", selection: Binding(get: { Theme.accent }, set: { color in
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
                    settings.accentHex = String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
                }), supportsOpacity: false)
                Text("Предварительный просмотр").padding().frame(maxWidth: .infinity)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(Theme.onAccent)
                Button("Вернуть стандартный фиолетовый") { settings.accentHex = nil }
                NavigationLink("Пользовательский фон") { BackgroundSettingsView() }
                Toggle("Библиотека на главной", isOn: $settings.libraryPinned)
                Text("Оформление сохраняется на устройстве. Папки, их содержимое и порядок синхронизируются в аккаунте вместе с библиотекой.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            Section("Воспроизведение") {
                Toggle("Автоматически включать следующую серию", isOn: $settings.autoplayNextEpisode)
            }
            Section {
                Toggle("Anilibria (русская озвучка)", isOn: Binding(get: { settings.anilibriaEnabled },
                                                       set: { env.setAnilibriaEnabled($0); Task { await reloadProviders() } }))
                Toggle("Тестовые потоки", isOn: Binding(get: { settings.testStreamsEnabled },
                                                       set: { env.setTestStreamsEnabled($0); Task { await reloadProviders() } }))
                LabeledContent("Kodik (озвучки онлайн)", value: env.kodik != nil ? "подключён" : "выключен")
                ForEach(providers) { p in
                    LabeledContent(p.name, value: p.isEnabled ? "включён" : "выключен")
                }
                if env.configuration.manifestURL == nil {
                    Text("Собственный источник не настроен (ANIVIBE_MANIFEST_URL).").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            } header: {
                Text("Источники видео")
            } footer: {
                Text("Anilibria — публичный API одноимённой студии озвучки: реальные серии с русской озвучкой в родном плеере. Выбор тайтлов и доступность — на стороне сервиса; правовой статус контента студии оценивайте сами. Тестовые потоки — демонстрационные видео Apple и Blender Foundation для проверки плеера, это не серии аниме.")
            }
            Section("Экспериментальные функции") {
                Toggle("Манга", isOn: $settings.mangaExperimentalEnabled)
            } header: {
                Text("Экспериментальные функции")
            } footer: {
                Text("Добавляет вкладку «Манга» и блок на главной. Метаданные — Shikimori, главы на русском и обложки — MangaDex. Функция в разработке: переводы могут быть неполными.")
            }
            Section("Каталог") {
                LabeledContent("Источник метаданных", value: env.catalog.name)
                Button(cacheCleared ? "Кэш очищен" : "Очистить кэш метаданных") {
                    Task { await env.cache.removeAll(); cacheCleared = true }
                }
                .disabled(cacheCleared)
            }
            if !env.configuration.warnings.isEmpty {
                Section("Предупреждения конфигурации") {
                    ForEach(env.configuration.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.danger) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Настройки")
        .task { await reloadProviders() }
    }

    private func reloadProviders() async {
        // Небольшая задержка, чтобы реестр успел применить переключатель.
        try? await Task.sleep(nanoseconds: 100_000_000)
        providers = await env.registry.allProviders()
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                HStack(spacing: Theme.Spacing.l) {
                    AnivibeMark().frame(width: 56, height: 56)
                    VStack(alignment: .leading) {
                        Text("Anivibe").font(.title2.bold())
                        Text("Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (сборка \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Section("Данные и материалы") {
                Text("Метаданные, постеры и описания предоставляются AniList (anilist.co). Права на изображения принадлежат их правообладателям.")
                Text("Anivibe не является официальным приложением AniList.")
                Text("Тестовые потоки: Apple HLS examples; «Big Buck Bunny» © Blender Foundation, CC BY 3.0.")
            }
            .font(.footnote)
        }
        .navigationTitle("О приложении")
    }
}
