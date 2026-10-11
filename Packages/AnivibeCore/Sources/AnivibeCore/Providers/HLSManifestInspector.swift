import Foundation

/// Читает мастер-плейлист HLS (RFC 8216) и извлекает объявленные аудиодорожки и субтитры.
/// Используется только для информации/проверки: фактический выбор дорожек делает AVPlayer.
public enum HLSManifestInspector {
    public struct Info: Equatable, Sendable {
        public let isValid: Bool
        public let isMaster: Bool
        public let audio: [MediaTrackInfo]
        public let subtitles: [MediaTrackInfo]
        public let variantCount: Int
    }

    public static func inspect(_ text: String) -> Info {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.first?.hasPrefix("#EXTM3U") == true else {
            return Info(isValid: false, isMaster: false, audio: [], subtitles: [], variantCount: 0)
        }
        var audio: [MediaTrackInfo] = [], subs: [MediaTrackInfo] = []
        var variants = 0
        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF") { variants += 1 }
            guard line.hasPrefix("#EXT-X-MEDIA:") else { continue }
            let attrs = attributes(String(line.dropFirst("#EXT-X-MEDIA:".count)))
            let track = MediaTrackInfo(name: attrs["NAME"] ?? attrs["LANGUAGE"] ?? "Без названия",
                                       language: attrs["LANGUAGE"],
                                       isDefault: attrs["DEFAULT"] == "YES",
                                       isForced: attrs["FORCED"] == "YES")
            switch attrs["TYPE"] {
            case "AUDIO": if !audio.contains(track) { audio.append(track) }
            case "SUBTITLES": if !subs.contains(track) { subs.append(track) }
            default: break
            }
        }
        return Info(isValid: true, isMaster: variants > 0, audio: audio, subtitles: subs, variantCount: variants)
    }

    /// Разбор списка атрибутов `KEY=VALUE,KEY="quoted,value"`.
    static func attributes(_ s: String) -> [String: String] {
        var result: [String: String] = [:]
        var key = "", value = "", inKey = true, inQuotes = false
        func flush() {
            if !key.isEmpty { result[key.trimmingCharacters(in: .whitespaces)] = value }
            key = ""; value = ""; inKey = true
        }
        for ch in s {
            if inKey {
                if ch == "=" { inKey = false } else if ch != "," { key.append(ch) }
            } else if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                flush()
            } else {
                value.append(ch)
            }
        }
        flush()
        return result
    }
}
