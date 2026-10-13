import SwiftUI
import AnivibeCore

struct VideoSettingsSheet: View {
    @Bindable var model: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if model.phase == .preparing { Section { ProgressView("Загружаем видео и восстанавливаем позицию…") } }
                if case .failed(let message) = model.phase {
                    Section("Ошибка воспроизведения") {
                        Text(message)
                        Button("Повторить загрузку") { model.retry() }
                    }
                }
                if !model.qualities.isEmpty {
                    Section("Качество") {
                        ForEach(model.qualities.sorted { $0.height > $1.height }) { quality in
                            choice(quality.label, selected: quality.height == model.currentQualityHeight) { model.selectQuality(quality) }
                                .disabled(model.phase != .ready)
                        }
                    }
                }
                else {
                    Section("Качество") {
                        Text("Источник не предоставил отдельные варианты разрешения. Для адаптивного HLS качество выбирается автоматически.").font(.footnote)
                    }
                }
                if !model.voices.isEmpty {
                    Section("Озвучка") {
                        ForEach(model.voices, id: \.self) { voice in
                            choice(voice, selected: voice == model.selectedVoice) { model.selectVoice(voice) }
                        }
                    }
                }
                Section("Скорость") {
                    ForEach(PlayerViewModel.speeds, id: \.self) { speed in
                        choice(KodikPlayerScreen.speedLabel(speed), selected: speed == model.playbackSpeed) { model.setSpeed(speed) }
                    }
                }
                Section("Аудиодорожки") {
                    if model.audioOptions.isEmpty { Text("Поток не сообщает об аудиодорожках") }
                    ForEach(model.audioOptions) { option in
                        choice(option.name, selected: option.id == model.selectedAudioID) { model.selectAudio(option) }
                    }
                }
                Section("Субтитры") {
                    if model.subtitleOptions.isEmpty { Text("В потоке нет субтитров") }
                    ForEach(model.subtitleOptions) { option in
                        choice(option.name, selected: option.id == model.selectedSubtitleID) { model.selectSubtitle(option) }
                    }
                }
            }
            .navigationTitle("Настройки видео")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); if selected { Image(systemName: "checkmark") } }
        }
    }
}
