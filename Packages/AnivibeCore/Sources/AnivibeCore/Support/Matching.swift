import Foundation

/// Разбор номера серии/сезона из строк вида «Episode 3 - Title», «S2E05», «Серия 7», «第5話».
public enum EpisodeNumberParser {
    public struct Result: Equatable, Sendable {
        public let season: Int?
        public let number: Int
        public let title: String?
    }

    private static let patterns: [(String, Bool)] = [
        // (regex, hasSeasonGroup)
        (#"(?i)\bS(\d{1,2})\s*E(\d{1,4})\b"#, true),
        (#"(?i)\b(?:episode|ep\.?|серия|эпизод)\s*#?\s*(\d{1,4})\b"#, false),
        (#"第\s*(\d{1,4})\s*[話话集]"#, false),
        (#"^\s*#?(\d{1,4})(?:\s*[-–—:.]\s*|\s*$)"#, false)
    ]

    public static func parse(_ raw: String) -> Result? {
        for (pattern, hasSeason) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = raw as NSString
            guard let m = regex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) else { continue }
            let season = hasSeason ? Int(ns.substring(with: m.range(at: 1))) : nil
            guard let number = Int(ns.substring(with: m.range(at: hasSeason ? 2 : 1))), number > 0 else { continue }
            let rest = ns.substring(from: m.range.location + m.range.length)
            let title = rest.trimmingCharacters(in: CharacterSet(charactersIn: " -–—:.|").union(.whitespacesAndNewlines))
            return Result(season: season, number: number, title: title.isEmpty ? nil : title)
        }
        return nil
    }
}

/// Нормализация и нечёткое сравнение названий (для поиска по альтернативным названиям
/// и сопоставления тайтла каталога с тайтлом у видеопровайдера).
public enum TitleMatcher {
    public static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        var out = ""
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Номер сезона из названия: «Season 2», «2nd Season», «Part 2» не считается сезоном, «II», «第2期», «2 сезон».
    public static func seasonNumber(in title: String) -> Int? {
        let patterns = [
            #"(?i)\bseason\s*(\d{1,2})\b"#,
            #"(?i)\b(\d{1,2})(?:st|nd|rd|th)\s+season\b"#,
            #"(?i)\b(\d{1,2})\s*(?:-?й\s*)?сезон\b"#,
            #"(?i)\bсезон\s*(\d{1,2})\b"#,
            #"第\s*(\d{1,2})\s*期"#,
            // Суффикс в конце названия: «Код Гиасс: Восставший Лелуш R1», «…R2».
            #"(?i)\sR(\d{1,2})$"#
        ]
        let ns = title as NSString
        for p in patterns {
            if let r = try? NSRegularExpression(pattern: p),
               let m = r.firstMatch(in: title, range: NSRange(location: 0, length: ns.length)),
               let n = Int(ns.substring(with: m.range(at: 1))) { return n }
        }
        let roman = ["II": 2, "III": 3, "IV": 4, "V": 5]
        if let last = title.split(separator: " ").last, let n = roman[String(last)] { return n }
        return nil
    }

    /// Сходство 0...1 по множествам слов (коэффициент Дайса) с бонусом за точное совпадение.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let na = normalize(a), nb = normalize(b)
        if na.isEmpty || nb.isEmpty { return 0 }
        if na == nb { return 1 }
        let ta = Set(na.split(separator: " ")), tb = Set(nb.split(separator: " "))
        let inter = Double(ta.intersection(tb).count)
        return (2 * inter) / Double(ta.count + tb.count)
    }

    /// Совпадает ли запрос с одним из названий (подстрока после нормализации).
    public static func matches(query: String, titles: [String]) -> Bool {
        let q = normalize(query)
        guard !q.isEmpty else { return true }
        return titles.contains { normalize($0).contains(q) }
    }

    /// Лучшее совпадение среди кандидатов. Порог по умолчанию консервативный,
    /// чтобы не подставить серию чужого тайтла. Сезон в названии должен совпадать.
    public static func bestMatch<C>(for titles: [String], among candidates: [C], titlesOf: (C) -> [String], threshold: Double = 0.8) -> C? {
        let wantedSeason = titles.compactMap(seasonNumber(in:)).first ?? 1
        var best: (C, Double)?
        for candidate in candidates {
            let ctitles = titlesOf(candidate)
            let cSeason = ctitles.compactMap(seasonNumber(in:)).first ?? 1
            guard cSeason == wantedSeason else { continue }
            let score = titles.flatMap { t in ctitles.map { similarity(t, $0) } }.max() ?? 0
            if score >= threshold, score > (best?.1 ?? 0) { best = (candidate, score) }
        }
        return best?.0
    }
}
