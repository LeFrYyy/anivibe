import Foundation

/// Откуда взято русское название тайтла.
public enum RussianTitleSource: String, Codable, Sendable {
    /// Официальное название из Shikimori.
    case shikimori
    /// Встроенный словарь популярных тайтлов.
    case dictionary
    /// Автоматический перевод/транскрипция (не официальное название).
    case automatic
}

/// Автоматический перевод названий на русский, когда официального перевода нет.
/// Порядок: словарь по MAL ID → словарь по началу названия (франшиза + «Season 2»)
/// → транскрипция японского (Хэпбёрн → Поливанов) с переводом служебных слов.
/// Результат помечается как `.automatic` и не используется для сопоставления с видеоисточниками.
public enum RussianTitleTranslator {
    /// Добавляет русское название (если его нет) и разговорные варианты из словаря.
    /// Официальное название Shikimori никогда не перезаписывается.
    public static func localize(_ anime: Anime) -> Anime {
        var result = anime
        if let malID = anime.malID, let entry = RussianTitleDictionary.entry(malID: malID) {
            var aliases = entry.aliases
            if result.title.russian?.nilIfBlank == nil {
                result.title.russian = entry.russian
                result.title.russianSource = .dictionary
            } else if RussianTitleDictionary.fold(result.title.russian ?? "") != RussianTitleDictionary.fold(entry.russian) {
                aliases.append(entry.russian)
            }
            result.searchAliases = merge(result.searchAliases ?? [], aliases, excluding: result.allTitles)
            return result
        }
        guard result.title.russian?.nilIfBlank == nil, let translated = translate(anime.title) else { return result }
        result.title.russian = translated
        result.title.russianSource = .automatic
        return result
    }

    public static func localize(_ items: [Anime]) -> [Anime] { items.map(localize) }

    static func merge(_ existing: [String], _ added: [String], excluding: [String]) -> [String] {
        var seen = Set(excluding.map { $0.lowercased() })
        return (existing + added).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Русское название для набора оригинальных названий или `nil`, если перевести нечего
    /// (например, полностью английское название без известного прототипа).
    public static func translate(_ title: AnimeTitle) -> String? {
        for candidate in [title.romaji, title.english].compactMap({ $0?.nilIfBlank }) {
            if let exact = RussianTitleDictionary.entry(title: candidate) { return exact.russian }
        }
        for candidate in [title.romaji, title.english].compactMap({ $0?.nilIfBlank }) {
            if let (entry, rest) = RussianTitleDictionary.franchisePrefix(of: candidate) {
                let suffix = translateSuffix(rest)
                return suffix.isEmpty ? entry.russian : entry.russian + separator(before: rest) + suffix
            }
        }
        if let romaji = title.romaji?.nilIfBlank {
            let transcribed = transcribe(romaji)
            if transcribed != romaji, containsCyrillic(transcribed) { return transcribed }
        }
        if let english = title.english?.nilIfBlank {
            let translated = translateSuffix(english)
            if translated != english, containsCyrillic(translated) { return translated }
        }
        return nil
    }

    static func containsCyrillic(_ text: String) -> Bool {
        text.range(of: #"[А-Яа-яЁё]"#, options: .regularExpression) != nil
    }

    private static func separator(before rest: String) -> String {
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        if let first = trimmed.first, ":;,.-–—!?".contains(first) { return "" }
        return " "
    }

    // MARK: - Служебные слова английских/ромадзи названий

    private static let structuralPatterns: [(String, String)] = [
        (#"(?i)\bthe\s+final\s+season\b"#, "Финальный сезон"),
        (#"(?i)\bfinal\s+season\b"#, "Финальный сезон"),
        (#"(?i)\b(\d{1,2})(?:st|nd|rd|th)\s+season\b"#, "$1 сезон"),
        (#"(?i)\bseason\s+(\d{1,2})\b"#, "$1 сезон"),
        (#"(?i)\bpart\s+(\d{1,2})\b"#, "Часть $1"),
        (#"(?i)\bcour\s+(\d{1,2})\b"#, "Часть $1"),
        (#"(?i)\bthe\s+movie\b"#, "Фильм"),
        (#"(?i)\bmovie\s+(\d{1,2})\b"#, "Фильм $1"),
        (#"(?i)\bmovie\b"#, "Фильм"),
        (#"(?i)\bfilm\b"#, "Фильм"),
        (#"(?i)\bthe\s+final\s+chapter\b"#, "Финальная глава"),
        (#"(?i)\bfinal\s+chapter\b"#, "Финальная глава"),
        (#"(?i)\bfinal\s+arc\b"#, "Финальная арка"),
        (#"(?i)\barc\b"#, "Арка"),
        (#"(?i)\bspecials?\b"#, "Спешл"),
        (#"(?i)\brecap\b"#, "Рекап"),
        (#"(?i)\bprologue\b"#, "Пролог"),
        (#"(?i)\bepilogue\b"#, "Эпилог"),
        (#"(?i)\bchapter\s+(\d{1,2})\b"#, "Глава $1"),
        (#"(?i)\bepisode\s+(\d{1,3})\b"#, "Серия $1"),
        (#"(?i)\bvolume\s+(\d{1,2})\b"#, "Том $1"),
        (#"(?i)\bthe\s+beginning\b"#, "Начало"),
        (#"(?i)\bthe\s+end\b"#, "Конец"),
        (#"(?i)\bthe\s+last\b"#, "Последний"),
        (#"(?i)\bthe\s+first\b"#, "Первый"),
        (#"(?i)\bthe\s+second\b"#, "Второй"),
        (#"(?i)\bthe\s+third\b"#, "Третий"),
        (#"(?i)\bsecond\s+act\b"#, "Второй акт"),
        (#"(?i)\bfirst\s+act\b"#, "Первый акт"),
        (#"(?i)\bact\s+(\d{1,2})\b"#, "Акт $1"),
        (#"(?i)\bshou\b"#, "Глава"),
        (#"(?i)\bhen\b"#, "Глава"),
        (#"(?i)\bkanketsu-?hen\b"#, "Финальная глава"),
        (#"(?i)\bsaishuushou\b"#, "Финальный сезон"),
        (#"(?i)\bsaishuu\s+shou\b"#, "Финальный сезон"),
        (#"(?i)\bsaishuu\s+sho\b"#, "Финальный сезон"),
        (#"(?i)\b(\d{1,2})(?:nd|rd|th|st)?\s*ki\b"#, "$1 сезон"),
        (#"(?i)\bzoku\s+hen\b"#, "Продолжение"),
        (#"(?i)\bzoku\b"#, "Продолжение"),
        (#"(?i)\bsoushuuhen\b"#, "Рекап"),
        (#"(?i)\bgekijouban\b"#, "Фильм"),
        (#"(?i)\bgekijou-?ban\b"#, "Фильм"),
        (#"(?i)\bova\b"#, "OVA"),
        (#"(?i)\bona\b"#, "ONA"),
        (#"(?i)\btv\b"#, "ТВ")
    ]

    /// Переводит служебные слова («Season 2», «Part 2», «The Movie») и транскрибирует японские слова.
    static func translateSuffix(_ text: String) -> String {
        var result = text
        for (pattern, replacement) in structuralPatterns {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        result = transcribe(result)
        return result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Транскрипция Хэпбёрн → Поливанов

    private static let syllables: [String: String] = [
        "a": "а", "i": "и", "u": "у", "e": "э", "o": "о",
        "ka": "ка", "ki": "ки", "ku": "ку", "ke": "кэ", "ko": "ко",
        "sa": "са", "shi": "си", "su": "су", "se": "сэ", "so": "со", "si": "си",
        "ta": "та", "chi": "ти", "tsu": "цу", "te": "тэ", "to": "то", "ti": "ти", "tu": "цу",
        "na": "на", "ni": "ни", "nu": "ну", "ne": "нэ", "no": "но",
        "ha": "ха", "hi": "хи", "fu": "фу", "he": "хэ", "ho": "хо", "hu": "фу",
        "ma": "ма", "mi": "ми", "mu": "му", "me": "мэ", "mo": "мо",
        "ya": "я", "yu": "ю", "yo": "ё", "ye": "е",
        "ra": "ра", "ri": "ри", "ru": "ру", "re": "рэ", "ro": "ро",
        "wa": "ва", "wo": "о", "wi": "ви", "we": "вэ",
        "ga": "га", "gi": "ги", "gu": "гу", "ge": "гэ", "go": "го",
        "za": "дза", "ji": "дзи", "zu": "дзу", "ze": "дзэ", "zo": "дзо", "zi": "дзи", "dzu": "дзу",
        "da": "да", "di": "дзи", "du": "дзу", "de": "дэ", "do": "до",
        "ba": "ба", "bi": "би", "bu": "бу", "be": "бэ", "bo": "бо",
        "pa": "па", "pi": "пи", "pu": "пу", "pe": "пэ", "po": "по",
        "kya": "кя", "kyu": "кю", "kyo": "кё", "kye": "кье",
        "sha": "ся", "shu": "сю", "sho": "сё", "she": "се", "sya": "ся", "syu": "сю", "syo": "сё",
        "cha": "тя", "chu": "тю", "cho": "тё", "che": "те", "tya": "тя", "tyu": "тю", "tyo": "тё",
        "nya": "ня", "nyu": "ню", "nyo": "нё",
        "hya": "хя", "hyu": "хю", "hyo": "хё",
        "mya": "мя", "myu": "мю", "myo": "мё",
        "rya": "ря", "ryu": "рю", "ryo": "рё",
        "gya": "гя", "gyu": "гю", "gyo": "гё",
        "ja": "дзя", "ju": "дзю", "jo": "дзё", "je": "дзе", "jya": "дзя", "jyu": "дзю", "jyo": "дзё", "zya": "дзя", "zyu": "дзю", "zyo": "дзё",
        "bya": "бя", "byu": "бю", "byo": "бё",
        "pya": "пя", "pyu": "пю", "pyo": "пё",
        "fa": "фа", "fi": "фи", "fe": "фэ", "fo": "фо",
        "va": "ва", "vi": "ви", "vu": "ву", "ve": "вэ", "vo": "во",
        "tsa": "ца", "tsi": "ци", "tse": "цэ", "tso": "цо",
        "n": "н", "m": "м"
    ]

    /// Переводит каждое слово-ромадзи в кириллицу по системе Поливанова; остальные слова не трогает.
    static func transcribe(_ text: String) -> String {
        guard !containsCyrillic(text) else { return text }
        var output = ""
        var word = ""
        func flush() {
            guard !word.isEmpty else { return }
            output += transcribeWord(word) ?? word
            word = ""
        }
        for character in text {
            if character.isLetter, character.isASCII || "āīūēō".contains(character.lowercased()) {
                word.append(character)
            } else {
                flush()
                output.append(character)
            }
        }
        flush()
        return output
    }

    private static let englishStopWords: Set<String> = [
        "the", "of", "and", "in", "on", "at", "to", "a", "an", "is", "my", "vs", "x", "re", "no", "wa", "ga", "to", "de",
        "ni", "mo", "e", "o", "yo", "ka", "kara", "made", "demo", "zero", "code", "one", "two", "three", "four"
    ]
    private static let keepLatin: Set<String> = ["x", "vs", "re", "ii", "iii", "iv", "ova", "ona", "tv", "op", "ed", "oad", "dx"]

    /// `nil`, если слово не разбирается на японские слоги (английское, аббревиатура и т.п.).
    static func transcribeWord(_ word: String) -> String? {
        let lower = word.lowercased()
            .replacingOccurrences(of: "ā", with: "aa").replacingOccurrences(of: "ī", with: "ii")
            .replacingOccurrences(of: "ū", with: "uu").replacingOccurrences(of: "ē", with: "ee")
            .replacingOccurrences(of: "ō", with: "ou")
        guard !keepLatin.contains(lower), lower.count >= 2 || "aioue".contains(lower) else { return nil }
        if lower.rangeOfCharacter(from: CharacterSet(charactersIn: "lqxvc")) != nil {
            // "c" допустима только в "ch"/"tch".
            let withoutCh = lower.replacingOccurrences(of: "ch", with: "")
            if withoutCh.rangeOfCharacter(from: CharacterSet(charactersIn: "lqxvc")) != nil { return nil }
        }
        if lower.allSatisfy({ $0 == lower.first }) && lower.count > 1 { return nil }
        let chars = Array(lower)
        var index = 0
        var result = ""
        var previousVowel: Character?
        while index < chars.count {
            // Удвоенная согласная (kk, ss, tt, pp, tch, ssh) → удвоенная кириллическая.
            if index + 1 < chars.count, chars[index] == chars[index + 1], "kstpgdbzhmr".contains(chars[index]) {
                if let next = lookup(chars, from: index + 1) {
                    result += String(next.value.first!)
                    index += 1
                    continue
                }
                return nil
            }
            if chars[index] == "t", index + 2 < chars.count, chars[index + 1] == "c", chars[index + 2] == "h" {
                result += "т"
                index += 1
                continue
            }
            if chars[index] == "n", index + 1 < chars.count, chars[index + 1] == "'" { result += "н"; index += 2; continue }
            guard let match = lookup(chars, from: index) else { return nil }
            var value = match.value
            // Долгие гласные: ou → о, uu → у, oo → о, aa → а, ee → э; дифтонги ai/ei/ui/oi → «й».
            if let previousVowel, match.key.count == 1, let only = match.key.first, "aiueo".contains(only) {
                if (previousVowel == "o" && (only == "u" || only == "o")) || (previousVowel == "u" && only == "u")
                    || (previousVowel == "a" && only == "a") || (previousVowel == "e" && only == "e") {
                    value = ""
                } else if only == "i", previousVowel != "i" {
                    value = "й"
                }
            }
            if match.key == "n", index + 1 < chars.count, "aiueoy".contains(chars[index + 1]) {
                // Слоговое «н» перед гласной (например, shin'ichi без апострофа) — редкий случай, оставляем «н».
            }
            result += value
            previousVowel = match.key.last.flatMap { "aiueo".contains($0) ? $0 : nil }
            if match.key == "n" || match.key == "m" { previousVowel = nil }
            index += match.key.count
        }
        guard !result.isEmpty else { return nil }
        var transcribed = result
        if let first = word.first, first.isUppercase, let firstCyrillic = transcribed.first {
            transcribed = String(firstCyrillic).uppercased() + transcribed.dropFirst()
        }
        return transcribed
    }

    private static func lookup(_ chars: [Character], from index: Int) -> (key: String, value: String)? {
        for length in stride(from: min(3, chars.count - index), through: 1, by: -1) {
            let key = String(chars[index..<index + length])
            if let value = syllables[key] {
                // Одиночные n/m — только если дальше нет гласной (иначе это слог na/ni/ma...).
                if length == 1, key == "n" || key == "m" {
                    if index + 1 < chars.count, "aiueo".contains(chars[index + 1]) { continue }
                    if key == "m" { if index + 1 < chars.count, "bpm".contains(chars[index + 1]) { return (key, value) } else { return nil } }
                }
                return (key, value)
            }
        }
        return nil
    }
}
