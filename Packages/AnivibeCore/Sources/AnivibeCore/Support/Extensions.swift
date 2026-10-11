import Foundation

extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

extension Calendar {
    public static var utcGregorian: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }
}

/// Стабильный (между запусками) хэш FNV-1a для ключей кэша.
enum StableHash {
    static func fnv1a(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

/// Превращает HTML-описание из каталога в обычный текст.
public enum HTMLText {
    public static func plainText(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "<br\\s*/?>[ \\t]*\\r?\\n?", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#039;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "[ \\t]+\n", with: "\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
