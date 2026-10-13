import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import ImageIO

@Observable
final class BackgroundStore {
    static let shared = BackgroundStore()
    private(set) var image: UIImage?
    var position: Int = UserDefaults.standard.integer(forKey: "settings.backgroundPosition")
    var dimming: Double = (UserDefaults.standard.object(forKey: "settings.backgroundDimming") as? Double) ?? 0.65
    var errorMessage: String?
    private let fileURL: URL?
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Anivibe")
        fileURL = directory?.appendingPathComponent("background.jpg")
        if let url = fileURL { image = UIImage(contentsOfFile: url.path) }
    }
    func save(_ image: UIImage, position: Int, dimming: Double) -> Bool {
        guard let fileURL, let data = image.jpegData(compressionQuality: 0.75), data.count <= 4 * 1024 * 1024 else {
            errorMessage = "Не удалось подготовить фон (максимум 4 МБ)."; return false
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            self.image = image; self.position = position; self.dimming = dimming
            UserDefaults.standard.set(position, forKey: "settings.backgroundPosition")
            UserDefaults.standard.set(dimming, forKey: "settings.backgroundDimming")
            errorMessage = nil; return true
        } catch { errorMessage = "Не удалось сохранить фон."; return false }
    }
    func remove() {
        do { if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }; image = nil; errorMessage = nil }
        catch { errorMessage = "Не удалось удалить фон." }
    }
    static func thumbnail(url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048, kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
}

struct BackgroundPhoto: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: target)
            return Self(url: target)
        }
    }
}

struct AppScreenBackground: View {
    var body: some View {
        BackgroundPreview(image: BackgroundStore.shared.image, position: BackgroundStore.shared.position,
                          dimming: BackgroundStore.shared.dimming)
    }
}
struct BackgroundPreview: View {
    let image: UIImage?
    let position: Int
    let dimming: Double
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.background
                if let image {
                    let size = image.size
                    let scale = max(proxy.size.width / max(1, size.width), proxy.size.height / max(1, size.height))
                    let overflow = max(0, size.height * scale - proxy.size.height)
                    Image(uiImage: image).resizable()
                        .frame(width: size.width * scale, height: size.height * scale)
                        .position(x: proxy.size.width / 2, y: size.height * scale / 2 - overflow * CGFloat(position) / 2)
                    Theme.background.opacity(dimming)
                }
            }.clipped().allowsHitTesting(false)
        }
    }
}
struct BackgroundSettingsView: View {
    @State private var selected: PhotosPickerItem?
    @State private var draft: UIImage?
    @State private var position = BackgroundStore.shared.position
    @State private var dimming = BackgroundStore.shared.dimming
    @State private var isLoading = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section("Предварительный просмотр") {
                ZStack {
                    BackgroundPreview(image: draft ?? BackgroundStore.shared.image, position: position, dimming: dimming)
                    VStack { Text("Anivibe").font(.title.bold()); Text("Проверка читаемости текста").font(.subheadline) }
                        .foregroundStyle(Theme.textPrimary)
                }.frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 12))
                PhotosPicker(selection: $selected, matching: .images, photoLibrary: .shared()) {
                    Label("Выбрать изображение", systemImage: "photo")
                }.disabled(isLoading)
                if isLoading { ProgressView("Подготавливаем изображение…") }
            }
            Section("Положение и читаемость") {
                Picker("Положение", selection: $position) {
                    Text("Сверху").tag(0); Text("По центру").tag(1); Text("Снизу").tag(2)
                }
                Slider(value: $dimming, in: 0.45...0.9) { Text("Затемнение фона") }
                    .accessibilityLabel("Подложка под текстом")
            }
            Section {
                Button("Сохранить фон") {
                    if let image = draft ?? BackgroundStore.shared.image,
                       BackgroundStore.shared.save(image, position: position, dimming: dimming) { dismiss() }
                }.disabled((draft == nil && BackgroundStore.shared.image == nil) || isLoading)
                Button("Удалить фон", role: .destructive) { BackgroundStore.shared.remove(); draft = nil }
            }
            if let message = error ?? BackgroundStore.shared.errorMessage { Text(message).foregroundStyle(Theme.danger) }
            Text("Фон хранится только на устройстве. Используется уменьшенная копия до 2048 пикселей; на сервер изображение не отправляется.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
        .navigationTitle("Пользовательский фон")
        .task(id: selected) {
            guard let selected else { return }
            isLoading = true; defer { isLoading = false }
            do {
                guard let photo = try await selected.loadTransferable(type: BackgroundPhoto.self) else { throw CocoaError(.fileReadCorruptFile) }
                defer { try? FileManager.default.removeItem(at: photo.url) }
                let image = await Task.detached(priority: .userInitiated) { BackgroundStore.thumbnail(url: photo.url) }.value
                guard !Task.isCancelled else { return }
                guard let image else { throw CocoaError(.fileReadCorruptFile) }
                draft = image; error = nil
            } catch { if !Task.isCancelled { self.error = "Не удалось прочитать изображение. Попробуйте другой файл." } }
        }
    }
}
