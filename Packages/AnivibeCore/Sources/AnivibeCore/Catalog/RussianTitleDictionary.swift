import Foundation

/// Встроенный словарь русских названий популярных тайтлов (официальные, разговорные и альтернативные написания).
/// Ключ — MAL ID (= Shikimori ID), поэтому записи точно сопоставляются с AniList через `idMal`.
/// Данные — в `RussianTitleDictionary+Data.swift`; работает офлайн, не требует сети.
public enum RussianTitleDictionary {
    public struct Entry: Hashable, Sendable {
        public let malID: Int
        public let russian: String
        public let romaji: String
        public let english: [String]
        /// Разговорные названия, синонимы Shikimori, сокращения (в том числе латиницей).
        public let aliases: [String]

        /// Все названия в порядке приоритета: русское, ромадзи, английские, алиасы.
        public var allNames: [String] {
            var seen = Set<String>()
            return ([russian, romaji] + english + aliases).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        }
        /// Только кириллические названия (для поиска по русским запросам).
        public var russianNames: [String] { allNames.filter(RussianTitleTranslator.containsCyrillic) }
    }

    private struct Index: Sendable {
        let entries: [Entry]
        let byMalID: [Int: Entry]
        /// Нормализованное название → запись (точное совпадение любого варианта).
        let byName: [String: Entry]
        /// Для префиксного поиска франшизы: (нормализованный ромадзи/english, запись), от длинных к коротким.
        let prefixes: [(String, Entry)]
        /// Для скоринга: (свёрнутая форма названия, запись).
        let searchable: [(folded: String, entry: Entry)]
    }

    private static let index: Index = {
        var entries: [Entry] = []
        for line in rawData.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 5, let malID = Int(parts[0]) else { continue }
            let list: (String) -> [String] = { $0.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            entries.append(Entry(malID: malID, russian: parts[1], romaji: parts[2], english: list(parts[3]), aliases: list(parts[4])))
        }
        var byMalID: [Int: Entry] = [:]
        var byName: [String: Entry] = [:]
        var prefixes: [(String, Entry)] = []
        var searchable: [(folded: String, entry: Entry)] = []
        for entry in entries {
            byMalID[entry.malID] = entry
            for name in entry.allNames {
                let key = fold(name)
                guard !key.isEmpty else { continue }
                if byName[key] == nil { byName[key] = entry }
                searchable.append((key, entry))
            }
            for name in [entry.romaji] + entry.english {
                let key = TitleMatcher.normalize(name)
                if key.count >= 4 { prefixes.append((key, entry)) }
            }
        }
        prefixes.sort { $0.0.count > $1.0.count }
        return Index(entries: entries, byMalID: byMalID, byName: byName, prefixes: prefixes, searchable: searchable)
    }()

    public static var entries: [Entry] { index.entries }
    public static var count: Int { index.entries.count }

    public static func entry(malID: Int) -> Entry? { index.byMalID[malID] }

    /// Запись, одно из названий которой совпадает с `title` (без учёта регистра, пунктуации, ё/е, э/е, й/и).
    public static func entry(title: String) -> Entry? {
        let key = fold(title)
        guard !key.isEmpty else { return nil }
        return index.byName[key]
    }

    /// Самая длинная запись, чьё ромадзи/английское название — начало `title` по границе слова.
    /// Возвращает запись и остаток названия («Season 2», «: Part 2»).
    public static func franchisePrefix(of title: String) -> (entry: Entry, rest: String)? {
        let normalized = TitleMatcher.normalize(title)
        guard !normalized.isEmpty else { return nil }
        for (prefix, entry) in index.prefixes where normalized == prefix || normalized.hasPrefix(prefix + " ") {
            if normalized == prefix { return (entry, "") }
            let prefixWords = prefix.split(separator: " ").count
            var wordIndex = 0, inWord = false
            var cut: String.UnicodeScalarView.Index?
            let scalars = title.unicodeScalars
            for position in scalars.indices {
                let isWord = CharacterSet.alphanumerics.contains(scalars[position])
                if isWord && !inWord { wordIndex += 1 }
                if !isWord && inWord && wordIndex == prefixWords { cut = position; break }
                inWord = isWord
            }
            guard let cut else { return (entry, "") }
            return (entry, String(scalars[cut...]).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// Записи, подходящие под запрос пользователя, с оценкой релевантности (по убыванию).
    /// Понимает кириллицу, латиницу, транслит русского («vanpanchmen») и ё/е, э/е, й/и.
    public static func matches(query: String, limit: Int = 10) -> [(entry: Entry, score: Int)] {
        let q = fold(query)
        guard q.count >= 2 else { return [] }
        let latin = TitleMatcher.normalize(CatalogSearchRanking.transliterate(q))
        var best: [Int: (Entry, Int)] = [:]
        for item in index.searchable {
            let score = CatalogSearchRanking.score(query: q, transliterated: latin, title: item.folded, exact: 900)
            guard score > 0 else { continue }
            if let current = best[item.entry.malID], current.1 >= score { continue }
            best[item.entry.malID] = (item.entry, score)
        }
        return best.values.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.malID < $1.0.malID }.prefix(limit).map { ($0.0, $0.1) }
    }

    /// Оценка совпадения запроса с названиями конкретной записи словаря (0, если записи нет).
    public static func score(query: String, malID: Int) -> Int {
        guard let entry = index.byMalID[malID] else { return 0 }
        let q = fold(query)
        guard q.count >= 2 else { return 0 }
        let latin = TitleMatcher.normalize(CatalogSearchRanking.transliterate(q))
        return entry.allNames.reduce(0) { best, name in
            max(best, CatalogSearchRanking.score(query: q, transliterated: latin, title: fold(name), exact: 790))
        }
    }

    /// Нормализация для сравнения русских названий: регистр, пунктуация, ё→е, э→е, й→и, ь/ъ убираются.
    public static func fold(_ text: String) -> String {
        let normalized = TitleMatcher.normalize(text)
        var out = ""
        out.reserveCapacity(normalized.count)
        for character in normalized {
            switch character {
            case "ё": out.append("е")
            case "э": out.append("е")
            case "й": out.append("и")
            case "ь", "ъ": continue
            default: out.append(character)
            }
        }
        return out
    }
}
