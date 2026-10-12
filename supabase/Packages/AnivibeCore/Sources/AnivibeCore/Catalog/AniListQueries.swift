import Foundation

/// GraphQL-запросы к AniList. Поля проверены по схеме https://docs.anilist.co/reference/
enum AniListQueries {
    static let mediaCard = """
    fragment card on Media {
      id
      idMal
      title { romaji english native }
      synonyms
      coverImage { large extraLarge color }
      bannerImage
      seasonYear
      season
      startDate { year }
      genres
      status
      format
      averageScore
      episodes
      duration
      nextAiringEpisode { episode }
      isAdult
    }
    """

    static let search = """
    query ($page: Int, $perPage: Int, $search: String, $genres: [String], $year: Int, $season: MediaSeason, $status: MediaStatus, $formats: [MediaFormat], $sort: [MediaSort]) {
      Page(page: $page, perPage: $perPage) {
        pageInfo { currentPage hasNextPage }
        media(type: ANIME, isAdult: false, search: $search, genre_in: $genres, seasonYear: $year, season: $season, status: $status, format_in: $formats, sort: $sort) { ...card }
      }
    }
    """ + "\n" + mediaCard

    static let details = """
    query ($id: Int) {
      Media(id: $id, type: ANIME) {
        ...card
        description(asHtml: false)
        relations { edges { relationType node { ...card } } }
        streamingEpisodes { title thumbnail url site }
        externalLinks { site url type language }
        studios(isMain: true) { nodes { name } }
        recommendations(perPage: 12, sort: RATING_DESC) { nodes { mediaRecommendation { ...card } } }
      }
    }
    """ + "\n" + mediaCard

    static let home = """
    query ($season: MediaSeason, $seasonYear: Int, $perPage: Int) {
      popular: Page(page: 1, perPage: $perPage) { media(type: ANIME, isAdult: false, sort: [POPULARITY_DESC]) { ...card } }
      seasonal: Page(page: 1, perPage: $perPage) { media(type: ANIME, isAdult: false, season: $season, seasonYear: $seasonYear, sort: [POPULARITY_DESC]) { ...card } }
      trending: Page(page: 1, perPage: $perPage) { media(type: ANIME, isAdult: false, sort: [TRENDING_DESC]) { ...card } }
      recent: Page(page: 1, perPage: $perPage) { media(type: ANIME, isAdult: false, format_in: [TV, MOVIE, ONA, OVA], status_in: [RELEASING, FINISHED, NOT_YET_RELEASED], sort: [ID_DESC]) { ...card } }
    }
    """ + "\n" + mediaCard

    static let genres = "query { GenreCollection }"
}
