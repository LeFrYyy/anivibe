import XCTest
@testable import AnivibeCore

final class RussianTitleDictionaryTests: XCTestCase {
    func testDictionaryIsLoadedAndKeyedByMALID() {
        XCTAssertGreaterThan(RussianTitleDictionary.count, 400)
        let aot = RussianTitleDictionary.entry(malID: 16498)
        XCTAssertEqual(aot?.russian, "Атака титанов")
        XCTAssertEqual(aot?.romaji, "Shingeki no Kyojin")
        XCTAssertTrue(aot?.aliases.contains("СнК") == true)
        XCTAssertTrue(aot?.aliases.contains("Вторжение гигантов") == true)
        XCTAssertNil(RussianTitleDictionary.entry(malID: -1))
    }

    func testOfficialAndColloquialRussianQueriesFindTheSameTitle() {
        for query in ["Атака титанов", "атака титанов", "Вторжение титанов", "Вторжение гигантов", "СнК", "снк", "AoT", "атака тит", "Атака  титанов!"] {
            XCTAssertEqual(RussianTitleDictionary.matches(query: query).first?.entry.malID, 16498, query)
        }
        XCTAssertEqual(RussianTitleDictionary.matches(query: "Тетрадь смерти").first?.entry.malID, 1535)
        XCTAssertEqual(RussianTitleDictionary.matches(query: "Дэс ноут").first?.entry.malID, 1535)
        XCTAssertEqual(RussianTitleDictionary.matches(query: "Магическая битва").first?.entry.malID, 40748)
        XCTAssertEqual(RussianTitleDictionary.matches(query: "Ванпанчмен").first?.entry.malID, 30276)
        XCTAssertEqual(RussianTitleDictionary.matches(query: "Человек одного удара").first?.entry.malID, 30276)
    }

    func testYoAndTypoToleranceAndTransliteration() {
        XCTAssertEqual(RussianTitleDictionary.fold("Звёздное дитя"), RussianTitleDictionary.fold("Звездное дитя"))
        XCTAssertEqual(RussianTitleDictionary.matches(query: "Тетрад смерти").first?.entry.malID, 1535, "опечатка")
        XCTAssertEqual(RussianTitleDictionary.matches(query: "Тетрадь смерты").first?.entry.malID, 1535, "опечатка")
        XCTAssertEqual(RussianTitleDictionary.matches(query: "Шингеки но Кёджин").first?.entry.malID, 16498, "транслит ромадзи")
        XCTAssertEqual(RussianTitleDictionary.matches(query: "vanpanchmen").first?.entry.malID, 30276, "латиница от русского")
    }

    func testSeasonsAreNotConfused() {
        XCTAssertEqual(RussianTitleDictionary.matches(query: "Атака титанов 2 сезон").first?.entry.malID, 25777)
        XCTAssertEqual(RussianTitleDictionary.matches(query: "Магическая битва 2").first?.entry.malID, 51009)
        XCTAssertEqual(RussianTitleDictionary.entry(title: "Shingeki no Kyojin Season 3")?.malID, 35760)
    }

    func testFranchisePrefixReturnsLongestMatchAndRemainder() throws {
        let hit = try XCTUnwrap(RussianTitleDictionary.franchisePrefix(of: "Shingeki no Kyojin Season 9"))
        XCTAssertEqual(hit.entry.malID, 16498)
        XCTAssertEqual(hit.rest, "Season 9")
        let movie = try XCTUnwrap(RussianTitleDictionary.franchisePrefix(of: "Kimetsu no Yaiba: Hashira Geiko-hen Part 2"))
        XCTAssertEqual(movie.entry.malID, 55701)
        XCTAssertEqual(movie.rest, "Part 2")
        XCTAssertNil(RussianTitleDictionary.franchisePrefix(of: "Narutomaki Cooking"), "префикс только по границе слова")
        XCTAssertEqual(RussianTitleDictionary.franchisePrefix(of: "attack on titan")?.rest, "")
    }

    func testEmptyAndShortQueriesReturnNothing() {
        XCTAssertTrue(RussianTitleDictionary.matches(query: "").isEmpty)
        XCTAssertTrue(RussianTitleDictionary.matches(query: "а").isEmpty)
        XCTAssertTrue(RussianTitleDictionary.matches(query: "!!!").isEmpty)
    }
}

final class RussianTitleTranslatorTests: XCTestCase {
    func testStructuralSuffixesAreTranslated() {
        XCTAssertEqual(RussianTitleTranslator.translate(AnimeTitle(romaji: "Shingeki no Kyojin Season 9")), "Атака титанов 9 сезон")
        XCTAssertEqual(RussianTitleTranslator.translate(AnimeTitle(english: "Attack on Titan 9th Season")), "Атака титанов 9 сезон")
        XCTAssertEqual(RussianTitleTranslator.translate(AnimeTitle(romaji: "Jujutsu Kaisen 3rd Season Part 2")), "Магическая битва 3 сезон Часть 2")
        XCTAssertEqual(RussianTitleTranslator.translate(AnimeTitle(romaji: "Kimetsu no Yaiba: Hashira Geiko-hen Part 2")),
                       "Клинок, рассекающий демонов: Тренировка столпов Часть 2")
        XCTAssertEqual(RussianTitleTranslator.translate(AnimeTitle(english: "Death Note: The Movie")), "Тетрадь смерти: Фильм")
        XCTAssertEqual(RussianTitleTranslator.translate(AnimeTitle(romaji: "Death Note Recap")), "Тетрадь смерти Рекап")
    }

    func testExactDictionaryTitleWins() {
        XCTAssertEqual(RussianTitleTranslator.translate(AnimeTitle(romaji: "Shingeki no Kyojin Season 2")), "Атака титанов 2")
        XCTAssertEqual(RussianTitleTranslator.translate(AnimeTitle(english: "Attack on Titan")), "Атака титанов")
    }

    func testRomajiIsTranscribedByPolivanov() {
        XCTAssertEqual(RussianTitleTranslator.transcribe("Hikari no Niwa"), "Хикари но Нива")
        XCTAssertEqual(RussianTitleTranslator.transcribe("Shinsekai yori"), "Синсэкай ёри")
        XCTAssertEqual(RussianTitleTranslator.transcribe("Sensei Oniisan"), "Сэнсэй Ониисан")
        XCTAssertEqual(RussianTitleTranslator.transcribe("Toukyou Juushin"), "Токё Дзюсин")
        XCTAssertEqual(RussianTitleTranslator.transcribe("Nekketsu Shounen"), "Нэккэцу Сёнэн")
        XCTAssertEqual(RussianTitleTranslator.transcribe("Chi-chan"), "Ти-тян")
        XCTAssertEqual(RussianTitleTranslator.translate(AnimeTitle(romaji: "Hikari no Niwa")), "Хикари но Нива")
    }

    func testEnglishWordsAndAbbreviationsAreNotTranscribed() {
        XCTAssertNil(RussianTitleTranslator.transcribeWord("Blue"))
        XCTAssertNil(RussianTitleTranslator.transcribeWord("Lock"))
        XCTAssertNil(RussianTitleTranslator.transcribeWord("OVA"))
        XCTAssertNil(RussianTitleTranslator.transcribeWord("TV"))
        XCTAssertNil(RussianTitleTranslator.transcribeWord("xxx"))
        XCTAssertEqual(RussianTitleTranslator.transcribe("Blue Lock vs OVA"), "Blue Lock vs OVA")
        XCTAssertNil(RussianTitleTranslator.translate(AnimeTitle(romaji: "Quartz Velvet Club", english: "Quartz Velvet Club")))
        XCTAssertEqual(RussianTitleTranslator.translate(AnimeTitle(romaji: "Blue Lock")), "Синяя тюрьма: Блю Лок", "английское название из словаря")
        XCTAssertNil(RussianTitleTranslator.translate(AnimeTitle()))
    }

    func testLocalizeUsesDictionaryAndKeepsOfficialNames() {
        var anime = Anime(id: 1, title: AnimeTitle(romaji: "Shingeki no Kyojin", english: "Attack on Titan"))
        anime.malID = 16498
        let localized = RussianTitleTranslator.localize(anime)
        XCTAssertEqual(localized.title.russian, "Атака титанов")
        XCTAssertEqual(localized.title.russianSource, .dictionary)
        XCTAssertTrue(localized.searchAliases?.contains("СнК") == true)
        XCTAssertTrue(localized.allTitles.contains("Атака титанов"), "название из словаря — официальное, годится источникам")
        XCTAssertFalse(localized.allTitles.contains("СнК"), "разговорные варианты не идут в сопоставление с источниками")
        XCTAssertTrue(localized.searchableTitles.contains("СнК"))

        anime.title.russian = "Официальное"
        anime.title.russianSource = .shikimori
        let kept = RussianTitleTranslator.localize(anime)
        XCTAssertEqual(kept.title.russian, "Официальное")
        XCTAssertTrue(kept.searchAliases?.contains("Атака титанов") == true, "словарное название остаётся как вариант для поиска")
    }

    func testAutomaticTranslationIsDisplayedButNotUsedForProviders() {
        let anime = Anime(id: 2, title: AnimeTitle(romaji: "Hikari no Niwa"))
        let localized = RussianTitleTranslator.localize(anime)
        XCTAssertEqual(localized.title.russian, "Хикари но Нива")
        XCTAssertEqual(localized.title.russianSource, .automatic)
        XCTAssertTrue(localized.title.isRussianAutomatic)
        XCTAssertEqual(localized.title.preferred, "Хикари но Нива")
        XCTAssertEqual(localized.allTitles, ["Hikari no Niwa"])
        XCTAssertTrue(localized.searchableTitles.contains("Хикари но Нива"))
        XCTAssertGreaterThan(CatalogSearchRanking.score(query: "хикари но нива", anime: localized), 0)
    }

    func testShikimoriOfficialNameOverridesButNeverErasesTranslation() {
        var anime = Anime(id: 3, title: AnimeTitle(romaji: "Hikari no Niwa"))
        anime.malID = 999_999_1
        let automatic = RussianTitleTranslator.localize(anime)
        let noRussian = RussianMetadataService.Metadata(id: 999_999_1, name: "Hikari no Niwa", russian: nil, synonyms: [], english: [], description: nil)
        XCTAssertEqual(noRussian.apply(to: automatic).title.russian, "Хикари но Нива")
        let official = RussianMetadataService.Metadata(id: 999_999_1, name: "Hikari no Niwa", russian: "Сад света", synonyms: [], english: [], description: nil)
        let applied = official.apply(to: automatic)
        XCTAssertEqual(applied.title.russian, "Сад света")
        XCTAssertEqual(applied.title.russianSource, .shikimori)
        XCTAssertTrue(applied.allTitles.contains("Сад света"))
    }

    func testOldCacheWithoutNewFieldsStillDecodes() throws {
        let original = Anime(id: 4, title: AnimeTitle(romaji: "Old", russian: "Старое"))
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        object.removeValue(forKey: "searchAliases")
        var title = object["title"] as! [String: Any]
        title.removeValue(forKey: "russianSource")
        object["title"] = title
        let decoded = try JSONDecoder().decode(Anime.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.title.russian, "Старое")
        XCTAssertNil(decoded.title.russianSource)
        XCTAssertNil(decoded.searchAliases)
        XCTAssertFalse(decoded.title.isRussianAutomatic)
    }
}

final class RussianSearchRankingTests: XCTestCase {
    private func anime(_ id: Int, russian: String? = nil, romaji: String, malID: Int? = nil, aliases: [String]? = nil) -> Anime {
        var anime = Anime(id: id, title: AnimeTitle(romaji: romaji, russian: russian))
        anime.malID = malID
        anime.searchAliases = aliases
        return anime
    }

    func testRankingPrefersExactThenPrefixThenContains() {
        let aot = anime(1, russian: "Атака титанов", romaji: "Shingeki no Kyojin", malID: 16498)
        let aot2 = anime(2, russian: "Атака титанов 2", romaji: "Shingeki no Kyojin Season 2", malID: 25777)
        XCTAssertEqual(CatalogSearchRanking.score(query: "Атака титанов", anime: aot), 1000)
        XCTAssertGreaterThan(CatalogSearchRanking.score(query: "Атака титанов", anime: aot), CatalogSearchRanking.score(query: "Атака титанов", anime: aot2))
        XCTAssertGreaterThan(CatalogSearchRanking.score(query: "Атака титанов 2", anime: aot2), CatalogSearchRanking.score(query: "Атака титанов 2", anime: aot))
        XCTAssertGreaterThan(CatalogSearchRanking.score(query: "атака тит", anime: aot), 600)
        XCTAssertGreaterThan(CatalogSearchRanking.score(query: "титанов атака", anime: aot), 0, "слова в другом порядке")
    }

    func testColloquialAliasesAndDictionaryHelpWithoutOfficialAliases() {
        let withAliases = anime(1, russian: "Атака титанов", romaji: "Shingeki no Kyojin", aliases: ["СнК"])
        XCTAssertGreaterThanOrEqual(CatalogSearchRanking.score(query: "снк", anime: withAliases), 800)
        let bare = anime(2, romaji: "Shingeki no Kyojin", malID: 16498)
        XCTAssertGreaterThan(CatalogSearchRanking.score(query: "Вторжение гигантов", anime: bare), 500, "словарь по MAL ID")
        XCTAssertEqual(CatalogSearchRanking.score(query: "Вторжение гигантов", anime: anime(3, romaji: "Other", malID: 1)), 0)
    }

    func testYoTypoAndTransliterationInRanking() {
        let note = anime(1, russian: "Тетрадь смерти", romaji: "Death Note")
        XCTAssertEqual(CatalogSearchRanking.score(query: "тетрадь смерти", anime: note), 1000)
        XCTAssertGreaterThan(CatalogSearchRanking.score(query: "тетрад смерти", anime: note), 0)
        let opm = anime(2, russian: "Ванпанчмен", romaji: "One Punch Man")
        XCTAssertGreaterThan(CatalogSearchRanking.score(query: "vanpanchmen", anime: opm), 700)
        XCTAssertEqual(CatalogSearchRanking.score(query: "", anime: opm), 0)
        XCTAssertEqual(CatalogSearchRanking.score(query: "Совершенно другое", anime: opm), 0)
    }

    func testQueryVariantsUseDictionaryRomajiBeforeTransliteration() {
        let hits = RussianTitleDictionary.matches(query: "Ванпанчмен")
        let variants = RussianCatalogService.queryVariants("Ванпанчмен", hits: hits)
        XCTAssertEqual(variants.first, "One Punch Man")
        XCTAssertEqual(variants.last, "vanpanchmen")
        XCTAssertEqual(RussianCatalogService.queryVariants("Нечто неведомое", hits: []), ["nechto nevedomoe"])
    }
}
